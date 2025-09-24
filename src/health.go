package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/hashicorp/raft"
)

// Constants for health check configuration
const (
	// DefaultHealthCheckTimeout represents the default timeout for health checks
	DefaultHealthCheckTimeout = 5 * time.Second
	// DefaultNetworkTimeout represents the default timeout for network checks
	DefaultNetworkTimeout = 2 * time.Second
	// HealthCheckTestFile represents the test file name for storage checks
	HealthCheckTestFile = "health_check_test"
	// DefaultFileMode represents the default file mode for created files
	DefaultFileMode = 0644
	// DefaultDirMode represents the default directory mode for created directories
	DefaultDirMode = 0755
)

// HealthStatus rappresenta lo stato di salute del sistema
type HealthStatus struct {
	Status    string                 `json:"status"`
	Timestamp time.Time              `json:"timestamp"`
	Checks    map[string]CheckResult `json:"checks"`
	Version   string                 `json:"version"`
	Uptime    time.Duration          `json:"uptime"`
}

// CheckResult rappresenta il risultato di un singolo check
type CheckResult struct {
	Status      string        `json:"status"`
	Message     string        `json:"message,omitempty"`
	Duration    time.Duration `json:"duration"`
	LastChecked time.Time     `json:"last_checked"`
}

// WorkerInfo è definito in rpc.go

// HealthChecker gestisce i controlli di salute del sistema
type HealthChecker struct {
	mu        sync.RWMutex
	checks    map[string]HealthCheck
	startTime time.Time
	version   string
}

// HealthCheck definisce un singolo controllo di salute
type HealthCheck interface {
	Name() string
	Check(ctx context.Context) CheckResult
}

// NewHealthChecker crea un nuovo health checker con la versione specificata
// La versione viene utilizzata per identificare la versione del sistema nei report di salute
func NewHealthChecker(version string) *HealthChecker {
	if version == "" {
		version = "unknown"
	}
	return &HealthChecker{
		checks:    make(map[string]HealthCheck),
		startTime: time.Now(),
		version:   version,
	}
}

// RegisterCheck registra un nuovo controllo di salute nel checker
// Se un controllo con lo stesso nome esiste già, viene sostituito
func (hc *HealthChecker) RegisterCheck(check HealthCheck) {
	if check == nil {
		return // Ignora controlli null
	}
	hc.mu.Lock()
	defer hc.mu.Unlock()
	hc.checks[check.Name()] = check
}

// CheckAll esegue tutti i controlli registrati e restituisce lo stato complessivo
// Il metodo è thread-safe e può essere chiamato concorrentemente
func (hc *HealthChecker) CheckAll(ctx context.Context) HealthStatus {
	hc.mu.RLock()
	defer hc.mu.RUnlock()

	results := make(map[string]CheckResult)
	overallStatus := "healthy"

	for name, check := range hc.checks {
		result := check.Check(ctx)
		results[name] = result
		if result.Status != "healthy" {
			overallStatus = "unhealthy"
		}
	}

	return HealthStatus{
		Status:    overallStatus,
		Timestamp: time.Now(),
		Checks:    results,
		Version:   hc.version,
		Uptime:    time.Since(hc.startTime),
	}
}

// HTTPHandler restituisce un handler HTTP per i controlli di salute
func (hc *HealthChecker) HTTPHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), DefaultHealthCheckTimeout)
		defer cancel()

		status := hc.CheckAll(ctx)

		w.Header().Set("Content-Type", "application/json")
		if status.Status != "healthy" {
			w.WriteHeader(http.StatusServiceUnavailable)
		} else {
			w.WriteHeader(http.StatusOK)
		}

		// Serializza la risposta in JSON
		if err := json.NewEncoder(w).Encode(status); err != nil {
			http.Error(w, "Failed to encode health status", http.StatusInternalServerError)
			return
		}
	}
}

// MasterHealthCheck controlla la salute del Master
type MasterHealthCheck struct {
	master *Master
}

// Name restituisce il nome del controllo di salute del Master
func (m *MasterHealthCheck) Name() string {
	return "master"
}

// Check esegue il controllo di salute del Master
// Verifica che il Master sia inizializzato correttamente e che Raft sia funzionante
func (m *MasterHealthCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	if m.master == nil {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Master not initialized",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Controlla se il master è inizializzato
	if m.master.inputFiles == nil || len(m.master.inputFiles) == 0 {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Master not properly initialized",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Controlla lo stato Raft
	if m.master.raft == nil {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Raft not initialized",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	raftState := m.master.raft.State()
	if raftState == raft.Shutdown {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Raft is shutdown",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	return CheckResult{
		Status:      "healthy",
		Message:     fmt.Sprintf("Master is healthy, Raft state: %s", raftState.String()),
		Duration:    time.Since(start),
		LastChecked: time.Now(),
	}
}

// WorkerHealthCheck controlla la salute del Worker
type WorkerHealthCheck struct {
	worker *WorkerInfo
}

// Name restituisce il nome del controllo di salute del Worker
func (w *WorkerHealthCheck) Name() string {
	return "worker"
}

// Check esegue il controllo di salute del Worker
// Verifica che il Worker sia inizializzato e che possa accedere al percorso temporaneo
func (w *WorkerHealthCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	if w.worker == nil {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Worker not initialized",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Controlla se il worker può accedere al temp path
	tempPath := os.Getenv("TMP_PATH")
	if tempPath == "" {
		tempPath = "."
	}

	// Verifica che il path sia accessibile
	if _, err := os.Stat(tempPath); os.IsNotExist(err) {
		return CheckResult{
			Status:      "unhealthy",
			Message:     fmt.Sprintf("Temp path not accessible: %s", tempPath),
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	return CheckResult{
		Status:      "healthy",
		Message:     "Worker is healthy",
		Duration:    time.Since(start),
		LastChecked: time.Now(),
	}
}

// RaftHealthCheck controlla la salute del cluster Raft
type RaftHealthCheck struct {
	master *Master
}

// Name restituisce il nome del controllo di salute di Raft
func (r *RaftHealthCheck) Name() string {
	return "raft"
}

// Check esegue il controllo di salute del cluster Raft
// Verifica che Raft sia inizializzato, non sia in stato di shutdown e che ci sia un leader disponibile
func (r *RaftHealthCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	if r.master == nil || r.master.raft == nil {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Raft not available",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	state := r.master.raft.State()
	if state == raft.Shutdown {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Raft is shutdown",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Controlla se il leader è disponibile
	leader := r.master.raft.Leader()
	if leader == "" && state != raft.Leader {
		return CheckResult{
			Status:      "degraded",
			Message:     "No leader available",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	return CheckResult{
		Status:      "healthy",
		Message:     fmt.Sprintf("Raft is healthy, state: %s, leader: %s", state.String(), leader),
		Duration:    time.Since(start),
		LastChecked: time.Now(),
	}
}

// StorageHealthCheck controlla la salute dello storage
type StorageHealthCheck struct {
	tempPath string
}

// Name restituisce il nome del controllo di salute dello storage
func (s *StorageHealthCheck) Name() string {
	return "storage"
}

// Check esegue il controllo di salute dello storage
// Verifica che il percorso temporaneo sia accessibile e scrivibile
func (s *StorageHealthCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	if s.tempPath == "" {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "Temp path not configured",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Controlla se il path esiste ed è scrivibile
	if err := os.MkdirAll(s.tempPath, DefaultDirMode); err != nil {
		return CheckResult{
			Status:      "unhealthy",
			Message:     fmt.Sprintf("Cannot create temp path: %v", err),
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Test di scrittura
	testFile := filepath.Join(s.tempPath, HealthCheckTestFile)
	if err := os.WriteFile(testFile, []byte("test"), DefaultFileMode); err != nil {
		return CheckResult{
			Status:      "unhealthy",
			Message:     fmt.Sprintf("Cannot write to temp path: %v", err),
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Cleanup - ignora errori di cleanup
	_ = os.Remove(testFile)

	return CheckResult{
		Status:      "healthy",
		Message:     "Storage is healthy",
		Duration:    time.Since(start),
		LastChecked: time.Now(),
	}
}

// NetworkHealthCheck controlla la connettività di rete
type NetworkHealthCheck struct {
	addresses []string
}

// Name restituisce il nome del controllo di salute della rete
func (n *NetworkHealthCheck) Name() string {
	return "network"
}

// Check esegue il controllo di salute della connettività di rete
// Verifica che sia possibile connettersi a tutti gli indirizzi specificati
func (n *NetworkHealthCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	if len(n.addresses) == 0 {
		return CheckResult{
			Status:      "unhealthy",
			Message:     "No addresses to check",
			Duration:    time.Since(start),
			LastChecked: time.Now(),
		}
	}

	// Controlla la connettività a tutti gli indirizzi
	for _, addr := range n.addresses {
		conn, err := net.DialTimeout("tcp", addr, DefaultNetworkTimeout)
		if err != nil {
			return CheckResult{
				Status:      "degraded",
				Message:     fmt.Sprintf("Cannot connect to %s: %v", addr, err),
				Duration:    time.Since(start),
				LastChecked: time.Now(),
			}
		}
		// Chiudi la connessione in modo sicuro
		if closeErr := conn.Close(); closeErr != nil {
			// Log dell'errore ma non fallire il check
			fmt.Printf("Warning: failed to close connection to %s: %v\n", addr, closeErr)
		}
	}

	return CheckResult{
		Status:      "healthy",
		Message:     "Network connectivity is healthy",
		Duration:    time.Since(start),
		LastChecked: time.Now(),
	}
}
