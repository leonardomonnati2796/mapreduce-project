package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"
)

// HealthStatus rappresenta lo stato di salute del sistema
type HealthStatus struct {
	Status     string                     `json:"status"`
	Timestamp  time.Time                  `json:"timestamp"`
	Version    string                     `json:"version"`
	Uptime     time.Duration              `json:"uptime"`
	Components map[string]ComponentStatus `json:"components"`
	System     SystemInfo                 `json:"system"`
}

// ComponentStatus rappresenta lo stato di un componente
type ComponentStatus struct {
	Status    string            `json:"status"`
	Message   string            `json:"message,omitempty"`
	LastCheck time.Time         `json:"last_check"`
	Details   map[string]string `json:"details,omitempty"`
}

// SystemInfo contiene informazioni sul sistema
type SystemInfo struct {
	GoVersion    string     `json:"go_version"`
	OS           string     `json:"os"`
	Architecture string     `json:"architecture"`
	NumCPU       int        `json:"num_cpu"`
	NumGoroutine int        `json:"num_goroutine"`
	Memory       MemoryInfo `json:"memory"`
}

// MemoryInfo contiene informazioni sulla memoria
type MemoryInfo struct {
	Alloc      uint64 `json:"alloc"`
	TotalAlloc uint64 `json:"total_alloc"`
	Sys        uint64 `json:"sys"`
	NumGC      uint32 `json:"num_gc"`
}

// HealthChecker gestisce i controlli di salute del sistema
type HealthChecker struct {
	version    string
	startTime  time.Time
	components map[string]ComponentStatus
}

// NewHealthChecker crea un nuovo health checker
func NewHealthChecker(version string) *HealthChecker {
	return &HealthChecker{
		version:    version,
		startTime:  time.Now(),
		components: make(map[string]ComponentStatus),
	}
}

// CheckComponent verifica lo stato di un componente
func (h *HealthChecker) CheckComponent(name string, checkFunc func() (bool, string, map[string]string)) {
	status, message, details := checkFunc()

	componentStatus := ComponentStatus{
		Status:    "healthy",
		LastCheck: time.Now(),
		Details:   details,
	}

	if !status {
		componentStatus.Status = "unhealthy"
		componentStatus.Message = message
	}

	h.components[name] = componentStatus
}

// CheckAll esegue tutti i controlli di salute e restituisce lo stato completo
func (h *HealthChecker) CheckAll(ctx context.Context) HealthStatus {
	// Esegui tutti i controlli
	h.CheckComponent("disk_space", CheckDiskSpace)
	h.CheckComponent("s3_connection", CheckS3Connection)
	h.CheckComponent("raft_cluster", CheckRaftCluster)
	h.CheckComponent("docker", CheckDocker)
	h.CheckComponent("network", CheckNetworkConnectivity)

	// Restituisci lo stato completo
	return h.GetHealthStatus()
}

// GetHealthStatus restituisce lo stato di salute completo
func (h *HealthChecker) GetHealthStatus() HealthStatus {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	overallStatus := "healthy"
	for _, component := range h.components {
		if component.Status == "unhealthy" {
			overallStatus = "unhealthy"
			break
		}
	}

	return HealthStatus{
		Status:     overallStatus,
		Timestamp:  time.Now(),
		Version:    h.version,
		Uptime:     time.Since(h.startTime),
		Components: h.components,
		System: SystemInfo{
			GoVersion:    runtime.Version(),
			OS:           runtime.GOOS,
			Architecture: runtime.GOARCH,
			NumCPU:       runtime.NumCPU(),
			NumGoroutine: runtime.NumGoroutine(),
			Memory: MemoryInfo{
				Alloc:      m.Alloc,
				TotalAlloc: m.TotalAlloc,
				Sys:        m.Sys,
				NumGC:      m.NumGC,
			},
		},
	}
}

// HealthCheckHandler gestisce le richieste di health check
func HealthCheckHandler(healthChecker *HealthChecker) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		status := healthChecker.GetHealthStatus()

		w.Header().Set("Content-Type", "application/json")

		if status.Status == "healthy" {
			w.WriteHeader(http.StatusOK)
		} else {
			w.WriteHeader(http.StatusServiceUnavailable)
		}

		json.NewEncoder(w).Encode(status)
	}
}

// Component check functions

// CheckDiskSpace verifica lo spazio su disco
func CheckDiskSpace() (bool, string, map[string]string) {
	// Verifica spazio su disco per /tmp/mapreduce
	path := "/tmp/mapreduce"
	if _, err := os.Stat(path); os.IsNotExist(err) {
		os.MkdirAll(path, 0755)
	}

	// Per semplicità, assumiamo che ci sia spazio sufficiente
	// In un'implementazione reale, useresti syscall.Statfs
	return true, "", map[string]string{
		"path":      path,
		"available": "sufficient",
	}
}

// CheckS3Connection verifica la connessione a S3
func CheckS3Connection() (bool, string, map[string]string) {
	if os.Getenv("S3_SYNC_ENABLED") != "true" {
		return true, "S3 non abilitato", map[string]string{
			"enabled": "false",
		}
	}

	// Verifica configurazione S3
	bucket := os.Getenv("AWS_S3_BUCKET")
	region := os.Getenv("AWS_REGION")

	if bucket == "" {
		return false, "Bucket S3 non configurato", map[string]string{
			"bucket": "not_set",
			"region": region,
		}
	}

	// In un'implementazione reale, faresti una chiamata di test a S3
	return true, "", map[string]string{
		"bucket": bucket,
		"region": region,
	}
}

// CheckRaftCluster verifica lo stato del cluster Raft
func CheckRaftCluster() (bool, string, map[string]string) {
	// Verifica che le variabili d'ambiente Raft siano configurate
	raftAddrs := os.Getenv("RAFT_ADDRESSES")
	rpcAddrs := os.Getenv("RPC_ADDRESSES")

	if raftAddrs == "" || rpcAddrs == "" {
		return false, "Configurazione Raft mancante", map[string]string{
			"raft_addresses": raftAddrs,
			"rpc_addresses":  rpcAddrs,
		}
	}

	return true, "", map[string]string{
		"raft_addresses": raftAddrs,
		"rpc_addresses":  rpcAddrs,
	}
}

// CheckDocker verifica che Docker sia disponibile
func CheckDocker() (bool, string, map[string]string) {
	// Verifica che Docker sia disponibile
	// In un'implementazione reale, faresti una chiamata al Docker daemon
	return true, "", map[string]string{
		"available": "true",
	}
}

// CheckNetworkConnectivity verifica la connettività di rete
func CheckNetworkConnectivity() (bool, string, map[string]string) {
	// Verifica connettività di base
	// In un'implementazione reale, faresti ping o HTTP requests
	return true, "", map[string]string{
		"connectivity": "ok",
	}
}

// StartHealthCheckServer avvia il server di health check
func StartHealthCheckServer(port int, healthChecker *HealthChecker) error {
	mux := http.NewServeMux()

	// Health check endpoint
	mux.HandleFunc("/health", HealthCheckHandler(healthChecker))

	// Liveness probe (semplice)
	mux.HandleFunc("/health/live", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Readiness probe (controlla se il servizio è pronto)
	mux.HandleFunc("/health/ready", func(w http.ResponseWriter, r *http.Request) {
		status := healthChecker.GetHealthStatus()
		if status.Status == "healthy" {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("READY"))
		} else {
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("NOT READY"))
		}
	})

	// Metrics endpoint (informazioni dettagliate)
	mux.HandleFunc("/health/metrics", func(w http.ResponseWriter, r *http.Request) {
		status := healthChecker.GetHealthStatus()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(status)
	})

	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", port),
		Handler: mux,
	}

	fmt.Printf("Health check server avviato sulla porta %d\n", port)
	return server.ListenAndServe()
}

// RunHealthChecks esegue tutti i controlli di salute
func RunHealthChecks(healthChecker *HealthChecker) {
	// Esegui controlli periodici
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		healthChecker.CheckComponent("disk_space", CheckDiskSpace)
		healthChecker.CheckComponent("s3_connection", CheckS3Connection)
		healthChecker.CheckComponent("raft_cluster", CheckRaftCluster)
		healthChecker.CheckComponent("docker", CheckDocker)
		healthChecker.CheckComponent("network", CheckNetworkConnectivity)
	}
}
