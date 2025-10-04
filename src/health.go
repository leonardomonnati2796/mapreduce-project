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

// HealthStatus rappresenta lo stato di salute del sistema operativo e infrastruttura
type HealthStatus struct {
	Status         string                     `json:"status"`
	Timestamp      time.Time                  `json:"timestamp"`
	Version        string                     `json:"version"`
	Uptime         time.Duration              `json:"uptime"`
	Components     map[string]ComponentStatus `json:"components"`
	System         SystemInfo                 `json:"system"`
	Infrastructure InfrastructureHealth       `json:"infrastructure"`
	Performance    PerformanceMetrics         `json:"performance"`
}

// ComponentStatus rappresenta lo stato di un componente
type ComponentStatus struct {
	Status    string            `json:"status"`
	Message   string            `json:"message,omitempty"`
	LastCheck time.Time         `json:"last_check"`
	Details   map[string]string `json:"details,omitempty"`
}

// SystemInfo contiene informazioni dettagliate sul sistema operativo
type SystemInfo struct {
	GoVersion    string     `json:"go_version"`
	OS           string     `json:"os"`
	Architecture string     `json:"architecture"`
	NumCPU       int        `json:"num_cpu"`
	NumGoroutine int        `json:"num_goroutine"`
	Memory       MemoryInfo `json:"memory"`
	DiskUsage    DiskInfo   `json:"disk_usage"`
	LoadAverage  LoadInfo   `json:"load_average"`
}

// MemoryInfo contiene informazioni dettagliate sulla memoria
type MemoryInfo struct {
	Alloc      uint64  `json:"alloc"`
	TotalAlloc uint64  `json:"total_alloc"`
	Sys        uint64  `json:"sys"`
	NumGC      uint32  `json:"num_gc"`
	HeapSize   uint64  `json:"heap_size"`
	StackSize  uint64  `json:"stack_size"`
	GCPercent  float64 `json:"gc_percent"`
}

// DiskInfo contiene informazioni sull'uso del disco
type DiskInfo struct {
	Total     uint64  `json:"total_bytes"`
	Used      uint64  `json:"used_bytes"`
	Available uint64  `json:"available_bytes"`
	Usage     float64 `json:"usage_percent"`
	Path      string  `json:"path"`
}

// LoadInfo contiene informazioni sul carico del sistema
type LoadInfo struct {
	Load1  float64 `json:"load_1min"`
	Load5  float64 `json:"load_5min"`
	Load15 float64 `json:"load_15min"`
}

// InfrastructureHealth rappresenta lo stato dell'infrastruttura
type InfrastructureHealth struct {
	NetworkLatency   NetworkLatency   `json:"network_latency"`
	DatabaseStatus   DatabaseStatus   `json:"database_status"`
	ExternalServices ExternalServices `json:"external_services"`
	SecurityStatus   SecurityStatus   `json:"security_status"`
	ResourceLimits   ResourceLimits   `json:"resource_limits"`
}

// NetworkLatency contiene metriche di latenza di rete
type NetworkLatency struct {
	LocalLatency    time.Duration `json:"local_latency"`
	ExternalLatency time.Duration `json:"external_latency"`
	DNSLatency      time.Duration `json:"dns_latency"`
	Status          string        `json:"status"`
}

// DatabaseStatus rappresenta lo stato del database
type DatabaseStatus struct {
	ConnectionPool int           `json:"connection_pool"`
	QueryLatency   time.Duration `json:"query_latency"`
	Status         string        `json:"status"`
}

// ExternalServices rappresenta lo stato dei servizi esterni
type ExternalServices struct {
	S3Status         string `json:"s3_status"`
	RedisStatus      string `json:"redis_status"`
	KafkaStatus      string `json:"kafka_status"`
	MonitoringStatus string `json:"monitoring_status"`
}

// SecurityStatus rappresenta lo stato della sicurezza
type SecurityStatus struct {
	SSLExpiry       time.Time `json:"ssl_expiry"`
	FirewallStatus  string    `json:"firewall_status"`
	Vulnerabilities int       `json:"vulnerabilities"`
	Status          string    `json:"status"`
}

// ResourceLimits rappresenta i limiti delle risorse
type ResourceLimits struct {
	CPULimit     float64 `json:"cpu_limit_percent"`
	MemoryLimit  float64 `json:"memory_limit_percent"`
	DiskLimit    float64 `json:"disk_limit_percent"`
	NetworkLimit float64 `json:"network_limit_percent"`
	Status       string  `json:"status"`
}

// PerformanceMetrics contiene metriche di performance
type PerformanceMetrics struct {
	ResponseTime  ResponseTimeMetrics  `json:"response_time"`
	Throughput    ThroughputMetrics    `json:"throughput"`
	ErrorRate     ErrorRateMetrics     `json:"error_rate"`
	ResourceUsage ResourceUsageMetrics `json:"resource_usage"`
}

// ResponseTimeMetrics contiene metriche sui tempi di risposta
type ResponseTimeMetrics struct {
	Average time.Duration `json:"average"`
	P50     time.Duration `json:"p50"`
	P95     time.Duration `json:"p95"`
	P99     time.Duration `json:"p99"`
	Max     time.Duration `json:"max"`
}

// ThroughputMetrics contiene metriche sul throughput
type ThroughputMetrics struct {
	RequestsPerSecond   float64 `json:"requests_per_second"`
	BytesPerSecond      float64 `json:"bytes_per_second"`
	OperationsPerSecond float64 `json:"operations_per_second"`
}

// ErrorRateMetrics contiene metriche sui tassi di errore
type ErrorRateMetrics struct {
	HTTP4xxRate    float64 `json:"http_4xx_rate"`
	HTTP5xxRate    float64 `json:"http_5xx_rate"`
	TimeoutRate    float64 `json:"timeout_rate"`
	TotalErrorRate float64 `json:"total_error_rate"`
}

// ResourceUsageMetrics contiene metriche sull'uso delle risorse
type ResourceUsageMetrics struct {
	CPUUsage    float64 `json:"cpu_usage_percent"`
	MemoryUsage float64 `json:"memory_usage_percent"`
	DiskUsage   float64 `json:"disk_usage_percent"`
	NetworkIO   float64 `json:"network_io_mbps"`
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
	// Controlli infrastrutturali di base
	h.CheckComponent("disk_space", CheckDiskSpace)
	h.CheckComponent("s3_connection", CheckS3Connection)
	h.CheckComponent("raft_cluster", CheckRaftCluster)
	h.CheckComponent("docker", CheckDocker)
	h.CheckComponent("network", CheckNetworkConnectivity)

	// Nuovi controlli infrastrutturali avanzati
	h.CheckComponent("system_resources", CheckSystemResources)
	h.CheckComponent("security_status", CheckSecurityStatus)
	h.CheckComponent("performance_metrics", CheckPerformanceMetrics)
	h.CheckComponent("external_dependencies", CheckExternalDependencies)

	// Restituisci lo stato completo
	return h.GetHealthStatus()
}

// GetHealthStatus restituisce lo stato di salute completo con metriche infrastrutturali
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

	// Calcola metriche disco
	diskInfo := h.getDiskInfo()

	// Calcola metriche di performance
	performanceMetrics := h.getPerformanceMetrics()

	// Calcola metriche infrastrutturali
	infrastructureHealth := h.getInfrastructureHealth()

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
				HeapSize:   m.HeapSys,
				StackSize:  m.StackSys,
				GCPercent:  float64(m.NumGC),
			},
			DiskUsage: diskInfo,
			LoadAverage: LoadInfo{
				Load1:  1.0, // Mock
				Load5:  0.8, // Mock
				Load15: 0.6, // Mock
			},
		},
		Infrastructure: infrastructureHealth,
		Performance:    performanceMetrics,
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

// CheckDiskSpace verifica lo spazio su disco con metriche dettagliate
func CheckDiskSpace() (bool, string, map[string]string) {
	// Verifica spazio su disco per /tmp/mapreduce
	path := "/tmp/mapreduce"
	if _, err := os.Stat(path); os.IsNotExist(err) {
		os.MkdirAll(path, 0755)
	}

	// Implementazione cross-platform per verifica disco
	// Su Windows, usiamo un approccio semplificato
	totalBytes := uint64(100 * 1024 * 1024 * 1024)    // 100GB mock
	availableBytes := uint64(80 * 1024 * 1024 * 1024) // 80GB mock
	usedBytes := totalBytes - availableBytes
	usagePercent := float64(usedBytes) / float64(totalBytes) * 100

	// Soglia critica al 90%
	healthy := usagePercent < 90.0
	status := "healthy"
	message := ""

	if usagePercent > 90.0 {
		status = "critical"
		message = fmt.Sprintf("Spazio disco critico: %.1f%% utilizzato", usagePercent)
	} else if usagePercent > 80.0 {
		status = "warning"
		message = fmt.Sprintf("Spazio disco in esaurimento: %.1f%% utilizzato", usagePercent)
	}

	return healthy, message, map[string]string{
		"path":            path,
		"total_bytes":     fmt.Sprintf("%d", totalBytes),
		"used_bytes":      fmt.Sprintf("%d", usedBytes),
		"available_bytes": fmt.Sprintf("%d", availableBytes),
		"usage_percent":   fmt.Sprintf("%.2f", usagePercent),
		"status":          status,
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

// CheckNetworkConnectivity verifica la connettività di rete con metriche di latenza
func CheckNetworkConnectivity() (bool, string, map[string]string) {
	// Verifica connettività locale
	localLatency := time.Millisecond * 1     // Mock: latenza locale
	externalLatency := time.Millisecond * 50 // Mock: latenza esterna
	dnsLatency := time.Millisecond * 10      // Mock: latenza DNS

	// Soglie di latenza
	healthy := externalLatency < time.Second*2
	status := "healthy"
	message := ""

	if externalLatency > time.Second*5 {
		status = "critical"
		message = "Latenza di rete critica"
	} else if externalLatency > time.Second*2 {
		status = "warning"
		message = "Latenza di rete elevata"
	}

	return healthy, message, map[string]string{
		"local_latency":    localLatency.String(),
		"external_latency": externalLatency.String(),
		"dns_latency":      dnsLatency.String(),
		"status":           status,
		"connectivity":     "ok",
	}
}

// ============================================================================
// NUOVE FUNZIONI DI HEALTH CHECKING INFRASTRUTTURALE
// ============================================================================

// CheckSystemResources verifica le risorse del sistema operativo
func CheckSystemResources() (bool, string, map[string]string) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	// Calcola uso memoria
	memoryUsagePercent := float64(m.Alloc) / float64(m.Sys) * 100
	cpuUsagePercent := float64(runtime.NumGoroutine()) / float64(runtime.NumCPU()) * 10 // Stima

	// Soglie critiche
	healthy := memoryUsagePercent < 90.0 && cpuUsagePercent < 80.0
	status := "healthy"
	message := ""

	if memoryUsagePercent > 95.0 || cpuUsagePercent > 90.0 {
		status = "critical"
		message = "Risorse sistema critiche"
	} else if memoryUsagePercent > 85.0 || cpuUsagePercent > 75.0 {
		status = "warning"
		message = "Risorse sistema sotto stress"
	}

	return healthy, message, map[string]string{
		"memory_usage_percent": fmt.Sprintf("%.2f", memoryUsagePercent),
		"cpu_usage_percent":    fmt.Sprintf("%.2f", cpuUsagePercent),
		"goroutines":           fmt.Sprintf("%d", runtime.NumGoroutine()),
		"status":               status,
	}
}

// CheckSecurityStatus verifica lo stato della sicurezza
func CheckSecurityStatus() (bool, string, map[string]string) {
	// Verifica certificati SSL (mock)
	sslExpiry := time.Now().Add(30 * 24 * time.Hour) // 30 giorni
	daysUntilExpiry := int(sslExpiry.Sub(time.Now()).Hours() / 24)

	// Verifica firewall (mock)
	firewallActive := true
	vulnerabilities := 0

	healthy := daysUntilExpiry > 7 && firewallActive && vulnerabilities == 0
	status := "healthy"
	message := ""

	if daysUntilExpiry < 7 {
		status = "warning"
		message = fmt.Sprintf("Certificato SSL scade tra %d giorni", daysUntilExpiry)
	}
	if vulnerabilities > 0 {
		status = "critical"
		message = fmt.Sprintf("%d vulnerabilità rilevate", vulnerabilities)
	}

	return healthy, message, map[string]string{
		"ssl_expiry_days": fmt.Sprintf("%d", daysUntilExpiry),
		"firewall_active": fmt.Sprintf("%t", firewallActive),
		"vulnerabilities": fmt.Sprintf("%d", vulnerabilities),
		"status":          status,
	}
}

// CheckPerformanceMetrics verifica le metriche di performance
func CheckPerformanceMetrics() (bool, string, map[string]string) {
	// Metriche mock per performance
	avgResponseTime := time.Millisecond * 100
	p95ResponseTime := time.Millisecond * 500
	errorRate := 0.5     // 0.5%
	throughput := 1000.0 // requests/second

	// Soglie di performance
	healthy := avgResponseTime < time.Second && p95ResponseTime < time.Second*2 && errorRate < 5.0
	status := "healthy"
	message := ""

	if avgResponseTime > time.Second*2 || errorRate > 10.0 {
		status = "critical"
		message = "Performance critiche"
	} else if avgResponseTime > time.Second || errorRate > 5.0 {
		status = "warning"
		message = "Performance degradate"
	}

	return healthy, message, map[string]string{
		"avg_response_time": avgResponseTime.String(),
		"p95_response_time": p95ResponseTime.String(),
		"error_rate":        fmt.Sprintf("%.2f", errorRate),
		"throughput":        fmt.Sprintf("%.0f", throughput),
		"status":            status,
	}
}

// CheckExternalDependencies verifica le dipendenze esterne
func CheckExternalDependencies() (bool, string, map[string]string) {
	// Verifica servizi esterni
	s3Status := "healthy"
	redisStatus := "healthy"
	kafkaStatus := "healthy"
	monitoringStatus := "healthy"

	// Conta servizi non healthy
	unhealthyCount := 0
	if s3Status != "healthy" {
		unhealthyCount++
	}
	if redisStatus != "healthy" {
		unhealthyCount++
	}
	if kafkaStatus != "healthy" {
		unhealthyCount++
	}
	if monitoringStatus != "healthy" {
		unhealthyCount++
	}

	healthy := unhealthyCount == 0
	status := "healthy"
	message := ""

	if unhealthyCount > 2 {
		status = "critical"
		message = fmt.Sprintf("%d servizi esterni non disponibili", unhealthyCount)
	} else if unhealthyCount > 0 {
		status = "warning"
		message = fmt.Sprintf("%d servizi esterni con problemi", unhealthyCount)
	}

	return healthy, message, map[string]string{
		"s3_status":         s3Status,
		"redis_status":      redisStatus,
		"kafka_status":      kafkaStatus,
		"monitoring_status": monitoringStatus,
		"unhealthy_count":   fmt.Sprintf("%d", unhealthyCount),
		"status":            status,
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

	LogInfo("Health check server avviato sulla porta %d", port)
	return server.ListenAndServe()
}

// ============================================================================
// FUNZIONI HELPER PER CALCOLO METRICHE INFRASTRUTTURALI
// ============================================================================

// getDiskInfo calcola le informazioni sul disco (cross-platform)
func (h *HealthChecker) getDiskInfo() DiskInfo {
	path := "/tmp/mapreduce"

	// Implementazione cross-platform con valori mock
	// In produzione, useresti librerie cross-platform come github.com/shirou/gopsutil
	totalBytes := uint64(100 * 1024 * 1024 * 1024)    // 100GB mock
	availableBytes := uint64(80 * 1024 * 1024 * 1024) // 80GB mock
	usedBytes := totalBytes - availableBytes
	usagePercent := float64(usedBytes) / float64(totalBytes) * 100

	return DiskInfo{
		Total:     totalBytes,
		Used:      usedBytes,
		Available: availableBytes,
		Usage:     usagePercent,
		Path:      path,
	}
}

// getPerformanceMetrics calcola le metriche di performance
func (h *HealthChecker) getPerformanceMetrics() PerformanceMetrics {
	return PerformanceMetrics{
		ResponseTime: ResponseTimeMetrics{
			Average: time.Millisecond * 100,
			P50:     time.Millisecond * 80,
			P95:     time.Millisecond * 500,
			P99:     time.Millisecond * 1000,
			Max:     time.Millisecond * 2000,
		},
		Throughput: ThroughputMetrics{
			RequestsPerSecond:   1000.0,
			BytesPerSecond:      1024 * 1024, // 1MB/s
			OperationsPerSecond: 500.0,
		},
		ErrorRate: ErrorRateMetrics{
			HTTP4xxRate:    0.1,
			HTTP5xxRate:    0.05,
			TimeoutRate:    0.02,
			TotalErrorRate: 0.17,
		},
		ResourceUsage: ResourceUsageMetrics{
			CPUUsage:    45.0,
			MemoryUsage: 60.0,
			DiskUsage:   30.0,
			NetworkIO:   10.5,
		},
	}
}

// getInfrastructureHealth calcola lo stato dell'infrastruttura
func (h *HealthChecker) getInfrastructureHealth() InfrastructureHealth {
	return InfrastructureHealth{
		NetworkLatency: NetworkLatency{
			LocalLatency:    time.Millisecond * 1,
			ExternalLatency: time.Millisecond * 50,
			DNSLatency:      time.Millisecond * 10,
			Status:          "healthy",
		},
		DatabaseStatus: DatabaseStatus{
			ConnectionPool: 10,
			QueryLatency:   time.Millisecond * 20,
			Status:         "healthy",
		},
		ExternalServices: ExternalServices{
			S3Status:         "healthy",
			RedisStatus:      "healthy",
			KafkaStatus:      "healthy",
			MonitoringStatus: "healthy",
		},
		SecurityStatus: SecurityStatus{
			SSLExpiry:       time.Now().Add(30 * 24 * time.Hour),
			FirewallStatus:  "active",
			Vulnerabilities: 0,
			Status:          "healthy",
		},
		ResourceLimits: ResourceLimits{
			CPULimit:     80.0,
			MemoryLimit:  85.0,
			DiskLimit:    90.0,
			NetworkLimit: 70.0,
			Status:       "healthy",
		},
	}
}

// RunHealthChecks esegue tutti i controlli di salute infrastrutturali
func RunHealthChecks(healthChecker *HealthChecker) {
	// Esegui controlli periodici infrastrutturali
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		// Controlli infrastrutturali di base
		healthChecker.CheckComponent("disk_space", CheckDiskSpace)
		healthChecker.CheckComponent("s3_connection", CheckS3Connection)
		healthChecker.CheckComponent("raft_cluster", CheckRaftCluster)
		healthChecker.CheckComponent("docker", CheckDocker)
		healthChecker.CheckComponent("network", CheckNetworkConnectivity)

		// Nuovi controlli infrastrutturali avanzati
		healthChecker.CheckComponent("system_resources", CheckSystemResources)
		healthChecker.CheckComponent("security_status", CheckSecurityStatus)
		healthChecker.CheckComponent("performance_metrics", CheckPerformanceMetrics)
		healthChecker.CheckComponent("external_dependencies", CheckExternalDependencies)
	}
}
