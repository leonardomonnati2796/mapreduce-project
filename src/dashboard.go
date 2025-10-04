package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/rpc"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const (
	electionDelay    = 1 * time.Second
	processingDelay  = 100 * time.Millisecond
	textProcessDelay = 2 * time.Second
	simulationDelay  = 3 * time.Second
	// Server configuration
	defaultPort = 8080
	maxPort     = 65535
	minPort     = 1
	// Timeouts
	readTimeout  = 15 * time.Second
	writeTimeout = 15 * time.Second
	idleTimeout  = 60 * time.Second
	// Job simulation
	defaultNReduce = 3
)

// Dashboard gestisce l'interfaccia web
type Dashboard struct {
	config        *Config
	healthChecker *HealthChecker
	metrics       *MetricCollector
	master        *Master
	worker        *WorkerInfo
	router        *gin.Engine
	startTime     time.Time
	mu            sync.RWMutex
	// WebSocket support
	upgrader     websocket.Upgrader
	clients      map[*websocket.Conn]bool
	clientsMutex sync.RWMutex
	broadcast    chan []byte
	// Load balancer support
	loadBalancer *LoadBalancer
	s3Manager    *S3StorageManager
}

// DashboardData contiene i dati per il dashboard
type DashboardData struct {
	Title           string                 `json:"title"`
	Version         string                 `json:"version"`
	Uptime          time.Duration          `json:"uptime"`
	Health          HealthStatus           `json:"health"`
	Metrics         map[string]interface{} `json:"metrics"`
	Jobs            []JobInfo              `json:"jobs"`
	Workers         []WorkerInfoDashboard  `json:"workers"`
	Masters         []MasterInfo           `json:"masters"`
	ActiveWorkers   int                    `json:"active_workers"`
	DegradedWorkers int                    `json:"degraded_workers"`
	FailedWorkers   int                    `json:"failed_workers"`
	LastUpdate      time.Time              `json:"last_update"`
}

// JobInfo informazioni su un job
type JobInfo struct {
	ID          string        `json:"id"`
	Status      string        `json:"status"`
	Phase       string        `json:"phase"`
	StartTime   time.Time     `json:"start_time"`
	EndTime     *time.Time    `json:"end_time,omitempty"`
	Duration    time.Duration `json:"duration"`
	MapTasks    int           `json:"map_tasks"`
	ReduceTasks int           `json:"reduce_tasks"`
	Progress    float64       `json:"progress"`
}

// WorkerInfoDashboard informazioni su un worker per il dashboard
type WorkerInfoDashboard struct {
	ID          string    `json:"id"`
	Status      string    `json:"status"`
	LastSeen    time.Time `json:"last_seen"`
	TasksDone   int       `json:"tasks_done"`
	CurrentTask string    `json:"current_task,omitempty"`
}

// MasterInfo informazioni su un master
type MasterInfo struct {
	ID       string    `json:"id"`
	Role     string    `json:"role"`
	State    string    `json:"state"`
	Leader   bool      `json:"leader"`
	LastSeen time.Time `json:"last_seen"`
}

// NewDashboard crea un nuovo dashboard
func NewDashboard(config *Config, healthChecker *HealthChecker, metrics *MetricCollector) (*Dashboard, error) {
	if config == nil {
		return nil, fmt.Errorf("config cannot be nil")
	}
	if healthChecker == nil {
		return nil, fmt.Errorf("healthChecker cannot be nil")
	}
	if metrics == nil {
		return nil, fmt.Errorf("metrics cannot be nil")
	}

	d := &Dashboard{
		config:        config,
		healthChecker: healthChecker,
		metrics:       metrics,
		router:        gin.Default(),
		startTime:     time.Now(),
		// WebSocket initialization
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for development
			},
		},
		clients:   make(map[*websocket.Conn]bool),
		broadcast: make(chan []byte),
	}

	// Inizializza load balancer se abilitato
	if os.Getenv("LOAD_BALANCER_ENABLED") == "true" {
		servers := d.initializeLoadBalancerServers()
		d.loadBalancer = NewLoadBalancer(servers, HealthBased)
		LogInfo("Load balancer inizializzato con %d server", len(servers))
	}

	// Inizializza S3 manager se abilitato
	if os.Getenv("S3_SYNC_ENABLED") == "true" {
		s3Config := GetS3ConfigFromEnv()
		if s3Manager, err := NewS3StorageManager(s3Config); err == nil {
			d.s3Manager = s3Manager
			LogInfo("S3 storage manager inizializzato")
		} else {
			LogWarn("Failed to initialize S3 manager: %v", err)
		}
	}

	d.setupRoutes()
	go d.handleWebSocketMessages()
	go d.startRealTimeUpdates()
	return d, nil
}

// setupRoutes configura le route del dashboard
func (d *Dashboard) setupRoutes() {
	// Static files
	d.router.Static("/static", "./web/static")
	d.router.LoadHTMLGlob("./web/templates/*")

	// API routes
	api := d.router.Group("/api/v1")
	{
		api.GET("/health", d.getHealth)
		api.GET("/metrics", d.getMetrics)
		api.GET("/jobs", d.getJobs)
		api.GET("/workers", d.getWorkers)
		api.GET("/masters", d.getMasters)
		api.GET("/status", d.getStatus)

		// Action routes for buttons
		api.POST("/jobs/:id/details", d.getJobDetails)
		api.POST("/jobs/:id/pause", d.pauseJob)
		api.POST("/jobs/:id/resume", d.resumeJob)
		api.POST("/jobs/:id/cancel", d.cancelJob)
		api.POST("/workers/:id/details", d.getWorkerDetails)
		api.POST("/workers/:id/pause", d.pauseWorker)
		api.POST("/workers/:id/resume", d.resumeWorker)
		api.POST("/workers/:id/restart", d.restartWorker)
		api.POST("/system/start-master", d.startMaster)
		api.POST("/system/start-worker", d.startWorker)
		api.POST("/system/stop-all", d.stopAll)
		api.POST("/system/restart-cluster", d.restartCluster)
		api.POST("/system/elect-leader", d.electLeader)

		// MapReduce job endpoints
		api.GET("/output", d.getCurrentOutput)
		api.POST("/jobs/submit", d.submitJob)
		api.GET("/jobs/:id/results", d.getJobResults)

		// Text processing endpoints
		api.POST("/text/process", d.processText)

		// Load balancer endpoints
		api.GET("/loadbalancer/stats", d.getLoadBalancerStatsEndpoint)
		api.POST("/loadbalancer/server/add", d.addLoadBalancerServer)
		api.POST("/loadbalancer/server/remove", d.removeLoadBalancerServer)

		// S3 storage endpoints
		api.GET("/s3/stats", d.getS3StatsEndpoint)
		api.POST("/s3/backup", d.createS3Backup)
		api.GET("/s3/backups", d.listS3Backups)
		api.POST("/s3/restore", d.restoreFromS3Backup)
	}

	// WebSocket endpoint
	d.router.GET("/ws", d.handleWebSocket)

	// Web routes
	d.router.GET("/", d.getIndex)
	d.router.GET("/health", d.getHealthPage)
	d.router.GET("/metrics", d.getMetricsPage)
	d.router.GET("/jobs", d.getJobsPage)
	d.router.GET("/workers", d.getWorkersPage)
	d.router.GET("/output", d.getOutputPage)
}

// getIndex restituisce la pagina principale
func (d *Dashboard) getIndex(c *gin.Context) {
	data := d.getDashboardData()
	c.HTML(http.StatusOK, "index.html", data)
}

// getHealth restituisce lo stato di salute in JSON
func (d *Dashboard) getHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	health := d.healthChecker.CheckAll(ctx)
	c.JSON(http.StatusOK, health)
}

// getHealthPage restituisce la pagina di salute
func (d *Dashboard) getHealthPage(c *gin.Context) {
	data := d.getDashboardData()
	c.HTML(http.StatusOK, "health.html", data)
}

// getMetrics restituisce le metriche in JSON
func (d *Dashboard) getMetrics(c *gin.Context) {
	metrics, err := d.getMetricsData()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to collect metrics",
			"details": err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, metrics)
}

// getMetricsPage restituisce la pagina delle metriche
func (d *Dashboard) getMetricsPage(c *gin.Context) {
	data := d.getDashboardData()
	c.HTML(http.StatusOK, "metrics.html", data)
}

// getJobs restituisce le informazioni sui job
func (d *Dashboard) getJobs(c *gin.Context) {
	jobs, err := d.getJobsData()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get jobs data",
			"details": err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, jobs)
}

// getJobsPage restituisce la pagina dei job
func (d *Dashboard) getJobsPage(c *gin.Context) {
	data := d.getDashboardData()
	c.HTML(http.StatusOK, "jobs.html", data)
}

// getWorkers restituisce le informazioni sui worker
func (d *Dashboard) getWorkers(c *gin.Context) {
	workers, err := d.getWorkersData()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get workers data",
			"details": err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, workers)
}

// getWorkersPage restituisce la pagina dei worker
func (d *Dashboard) getWorkersPage(c *gin.Context) {
	data := d.getDashboardData()
	c.HTML(http.StatusOK, "workers.html", data)
}

// getMasters restituisce le informazioni sui master
func (d *Dashboard) getMasters(c *gin.Context) {
	masters, err := d.getMastersData()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get masters data",
			"details": err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, masters)
}

// getStatus restituisce lo stato generale del sistema
func (d *Dashboard) getStatus(c *gin.Context) {
	d.mu.RLock()
	uptime := time.Since(d.startTime)
	d.mu.RUnlock()

	status := map[string]interface{}{
		"status":    "running",
		"version":   "1.0.0",
		"uptime":    uptime.String(),
		"timestamp": time.Now(),
	}
	c.JSON(http.StatusOK, status)
}

// getDashboardData raccoglie tutti i dati per il dashboard
func (d *Dashboard) getDashboardData() DashboardData {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	d.mu.RLock()
	uptime := time.Since(d.startTime)
	d.mu.RUnlock()

	now := time.Now()

	// Health check
	health := d.healthChecker.CheckAll(ctx)

	// Gestione errori per metrics
	metrics, err := d.getMetricsData()
	if err != nil {
		metrics = map[string]interface{}{
			"error": "Failed to collect metrics: " + err.Error(),
		}
	}

	// Gestione errori per jobs
	jobs, err := d.getJobsData()
	if err != nil {
		jobs = []JobInfo{}
	}

	// Gestione errori per workers
	workers, err := d.getWorkersData()
	if err != nil {
		workers = []WorkerInfoDashboard{}
	}

	// Gestione errori per masters
	masters, err := d.getMastersData()
	if err != nil {
		masters = []MasterInfo{}
	}

	// Calcola contatori workers
	activeWorkers := 0
	degradedWorkers := 0
	failedWorkers := 0

	for _, worker := range workers {
		switch worker.Status {
		case "active":
			activeWorkers++
		case "degraded":
			degradedWorkers++
		case "failed":
			failedWorkers++
		}
	}

	return DashboardData{
		Title:           "MapReduce Dashboard",
		Version:         "1.0.0",
		Uptime:          uptime,
		Health:          health,
		Metrics:         metrics,
		Jobs:            jobs,
		Workers:         workers,
		Masters:         masters,
		ActiveWorkers:   activeWorkers,
		DegradedWorkers: degradedWorkers,
		FailedWorkers:   failedWorkers,
		LastUpdate:      now,
	}
}

// getMetricsData raccoglie i dati delle metriche
func (d *Dashboard) getMetricsData() (map[string]interface{}, error) {
	if d.metrics == nil {
		return nil, fmt.Errorf("metrics collector not initialized")
	}

	// In una implementazione reale, raccoglieresti le metriche da Prometheus
	// Per ora restituiamo dati simulati
	metrics := map[string]interface{}{
		"tasks_total": map[string]interface{}{
			"map_completed":    10,
			"reduce_completed": 5,
			"failed":           0,
		},
		"raft_state": map[string]interface{}{
			"leader":   true,
			"term":     1,
			"log_size": 100,
		},
		"performance": map[string]interface{}{
			"avg_task_duration": "2.5s",
			"throughput":        "10 tasks/min",
			"cpu_usage":         "45%",
			"memory_usage":      "128MB",
		},
	}
	return metrics, nil
}

// getJobsData raccoglie i dati dei job
func (d *Dashboard) getJobsData() ([]JobInfo, error) {
	// In una implementazione reale, raccoglieresti i dati dal Master
	// Per ora restituiamo dati simulati
	jobs := []JobInfo{
		{
			ID:          "job-1",
			Status:      "running",
			Phase:       "map",
			StartTime:   time.Now().Add(-5 * time.Minute),
			MapTasks:    10,
			ReduceTasks: 5,
			Progress:    75.5,
		},
	}
	return jobs, nil
}

// getWorkersData raccoglie i dati dei worker interrogando solo il leader master
func (d *Dashboard) getWorkersData() ([]WorkerInfoDashboard, error) {
	// Ottieni gli indirizzi RPC dei master
	rpcAddrs := getMasterRpcAddresses()

	// Debug: stampa gli indirizzi RPC che stiamo usando
	LogInfo("[Dashboard] Getting worker data from masters: %v", rpcAddrs)

	// Trova prima il leader master
	var leaderAddr string
	var leaderID int = -1

	for i, rpcAddr := range rpcAddrs {
		client, err := rpc.DialHTTP("tcp", rpcAddr)
		if err != nil {
			LogWarn("[Dashboard] Failed to connect to master %d at %s: %v", i, rpcAddr, err)
			continue
		}

		var args GetMasterInfoArgs
		var reply MasterInfoReply
		err = client.Call("Master.GetMasterInfo", &args, &reply)
		client.Close()

		if err == nil && reply.IsLeader {
			leaderAddr = rpcAddr
			leaderID = i
			LogInfo("[Dashboard] Found leader master %d at %s", i, rpcAddr)
			break
		}
	}

	// Se non troviamo il leader, interroga tutti i master come fallback
	if leaderAddr == "" {
		LogWarn("[Dashboard] No leader found, using fallback approach")
		return d.getWorkersDataFromAllMasters(rpcAddrs)
	}

	// Interroga solo il leader per ottenere le informazioni sui worker
	workerInfo, err := d.queryWorkerInfo(leaderID, leaderAddr)
	if err != nil {
		LogError("[Dashboard] Failed to get worker info from leader master %d at %s: %v", leaderID, leaderAddr, err)
		return d.getWorkersDataFromAllMasters(rpcAddrs)
	}

	// Converti i worker info in WorkerInfoDashboard
	var allWorkers []WorkerInfoDashboard
	for _, worker := range workerInfo.Workers {
		allWorkers = append(allWorkers, WorkerInfoDashboard{
			ID:        worker.ID,
			Status:    worker.Status,
			LastSeen:  worker.LastSeen,
			TasksDone: worker.TasksDone,
		})
	}

	// Se non ci sono worker reali, restituisce lista vuota (no fallback workers)
	if len(allWorkers) == 0 {
		LogWarn("[Dashboard] No workers found from leader master")
		return []WorkerInfoDashboard{}, nil
	}

	LogInfo("[Dashboard] Found %d workers from leader master", len(allWorkers))
	return allWorkers, nil
}

// getWorkersDataFromAllMasters fallback method che interroga tutti i master
func (d *Dashboard) getWorkersDataFromAllMasters(rpcAddrs []string) ([]WorkerInfoDashboard, error) {
	var allWorkers []WorkerInfoDashboard
	workerMap := make(map[string]*WorkerInfoDashboard) // Per evitare duplicati

	// Interroga ogni master per ottenere le informazioni sui worker
	for i, rpcAddr := range rpcAddrs {
		workerInfo, err := d.queryWorkerInfo(i, rpcAddr)
		if err != nil {
			LogWarn("[Dashboard] Failed to get worker info from master %d at %s: %v", i, rpcAddr, err)
			continue
		}

		// Aggiungi i worker alla mappa (evita duplicati)
		for _, worker := range workerInfo.Workers {
			if existingWorker, exists := workerMap[worker.ID]; exists {
				// Aggiorna il worker esistente se questo è più recente
				if worker.LastSeen.After(existingWorker.LastSeen) {
					workerMap[worker.ID] = &WorkerInfoDashboard{
						ID:        worker.ID,
						Status:    worker.Status,
						LastSeen:  worker.LastSeen,
						TasksDone: worker.TasksDone,
					}
				}
			} else {
				workerMap[worker.ID] = &WorkerInfoDashboard{
					ID:        worker.ID,
					Status:    worker.Status,
					LastSeen:  worker.LastSeen,
					TasksDone: worker.TasksDone,
				}
			}
		}
	}

	// Converti la mappa in slice
	for _, worker := range workerMap {
		allWorkers = append(allWorkers, *worker)
	}

	// Se non ci sono worker reali, restituisce lista vuota (no fallback workers)
	if len(allWorkers) == 0 {
		LogWarn("[Dashboard] No workers found from any master")
		return []WorkerInfoDashboard{}, nil
	}

	LogInfo("[Dashboard] Found %d unique workers from all masters", len(allWorkers))
	return allWorkers, nil
}

// getMastersData raccoglie i dati dei master interrogando i master reali
func (d *Dashboard) getMastersData() ([]MasterInfo, error) {
	// Ottieni gli indirizzi RPC dei master
	rpcAddrs := getMasterRpcAddresses()

	// Debug: stampa gli indirizzi RPC che stiamo usando
	LogInfo("[Dashboard] Using RPC addresses: %v", rpcAddrs)

	var masters []MasterInfo

	// Interroga ogni master per ottenere le informazioni reali
	for i, rpcAddr := range rpcAddrs {
		masterInfo, err := d.queryMasterInfo(i, rpcAddr)
		if err != nil {
			// Se non riesci a contattare il master, aggiungi informazioni di fallback
			masterInfo = MasterInfo{
				ID:       fmt.Sprintf("master-%d", i),
				Role:     "unknown",
				State:    "unreachable",
				Leader:   false,
				LastSeen: time.Now().Add(-5 * time.Minute), // Indica che è stato visto molto tempo fa
			}
		}
		masters = append(masters, masterInfo)
	}

	// Se non ci sono master configurati, restituisce dati di fallback
	if len(masters) == 0 {
		masters = []MasterInfo{
			{
				ID:       "master-0",
				Role:     "unknown",
				State:    "not_configured",
				Leader:   false,
				LastSeen: time.Now().Add(-10 * time.Minute),
			},
		}
	}

	return masters, nil
}

// queryWorkerInfo interroga un master specifico per ottenere le informazioni sui worker
func (d *Dashboard) queryWorkerInfo(masterID int, rpcAddr string) (WorkerInfoReply, error) {
	// Debug: stampa l'indirizzo che stiamo tentando di contattare
	LogInfo("[Dashboard] Attempting to get worker info from master %d at %s", masterID, rpcAddr)

	// Crea una connessione RPC al master
	client, err := rpc.DialHTTP("tcp", rpcAddr)
	if err != nil {
		LogWarn("[Dashboard] Failed to connect to master %d at %s: %v", masterID, rpcAddr, err)
		return WorkerInfoReply{}, fmt.Errorf("failed to connect to master %d at %s: %v", masterID, rpcAddr, err)
	}
	defer client.Close()

	// Prepara la richiesta
	var args GetWorkerInfoArgs
	var reply WorkerInfoReply

	// Chiama il metodo RPC con timeout
	done := make(chan error, 1)
	go func() {
		done <- client.Call("Master.GetWorkerInfo", &args, &reply)
	}()

	select {
	case err := <-done:
		if err != nil {
			return WorkerInfoReply{}, fmt.Errorf("RPC call failed: %v", err)
		}
	case <-time.After(3 * time.Second):
		return WorkerInfoReply{}, fmt.Errorf("RPC call timeout")
	}

	LogInfo("[Dashboard] Got worker info from master %d: %d workers", masterID, len(reply.Workers))
	return reply, nil
}

// queryMasterInfo interroga un master specifico per ottenere le sue informazioni
func (d *Dashboard) queryMasterInfo(masterID int, rpcAddr string) (MasterInfo, error) {
	// Debug: stampa l'indirizzo che stiamo tentando di contattare
	LogInfo("[Dashboard] Attempting to connect to master %d at %s", masterID, rpcAddr)

	// Crea una connessione RPC al master
	client, err := rpc.DialHTTP("tcp", rpcAddr)
	if err != nil {
		LogWarn("[Dashboard] Failed to connect to master %d at %s: %v", masterID, rpcAddr, err)
		return MasterInfo{}, fmt.Errorf("failed to connect to master %d at %s: %v", masterID, rpcAddr, err)
	}
	defer client.Close()

	// Prepara la richiesta
	var args GetMasterInfoArgs
	var reply MasterInfoReply

	// Chiama il metodo RPC con timeout
	done := make(chan error, 1)
	go func() {
		done <- client.Call("Master.GetMasterInfo", &args, &reply)
	}()

	select {
	case err := <-done:
		if err != nil {
			return MasterInfo{}, fmt.Errorf("RPC call failed: %v", err)
		}
	case <-time.After(3 * time.Second):
		return MasterInfo{}, fmt.Errorf("RPC call timeout")
	}

	// Converti la risposta in MasterInfo
	role := "follower"
	state := reply.RaftState
	if reply.IsLeader {
		role = "leader"
		state = "leader"
	}

	return MasterInfo{
		ID:       fmt.Sprintf("master-%d", masterID),
		Role:     role,
		State:    state,
		Leader:   reply.IsLeader,
		LastSeen: reply.LastSeen,
	}, nil
}

// Start avvia il server web
func (d *Dashboard) Start(port int) error {
	if port < minPort || port > maxPort {
		return fmt.Errorf("invalid port number: %d", port)
	}

	addr := fmt.Sprintf(":%d", port)

	// Configura il server con timeout
	server := &http.Server{
		Addr:         addr,
		Handler:      d.router,
		ReadTimeout:  readTimeout,
		WriteTimeout: writeTimeout,
		IdleTimeout:  idleTimeout,
	}

	return server.ListenAndServe()
}

// SetMaster imposta il riferimento al Master in modo thread-safe
func (d *Dashboard) SetMaster(master *Master) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.master = master
}

// SetWorker imposta il riferimento al Worker in modo thread-safe
func (d *Dashboard) SetWorker(worker *WorkerInfo) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.worker = worker
}

// GetMaster restituisce il riferimento al Master in modo thread-safe
func (d *Dashboard) GetMaster() *Master {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.master
}

// GetWorker restituisce il riferimento al Worker in modo thread-safe
func (d *Dashboard) GetWorker() *WorkerInfo {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.worker
}

// ===== JOB ACTIONS =====

// getJobDetails restituisce i dettagli di un job specifico
func (d *Dashboard) getJobDetails(c *gin.Context) {
	jobID := c.Param("id")

	// Simula dettagli del job
	details := map[string]interface{}{
		"id":       jobID,
		"status":   "running",
		"phase":    "Map",
		"progress": 65.5,
		"map_tasks": map[string]interface{}{
			"total":       10,
			"completed":   7,
			"in_progress": 2,
			"failed":      1,
		},
		"reduce_tasks": map[string]interface{}{
			"total":       5,
			"completed":   0,
			"in_progress": 0,
			"failed":      0,
		},
		"input_files":          []string{"input1.txt", "input2.txt", "input3.txt"},
		"output_files":         []string{},
		"start_time":           time.Now().Add(-5 * time.Minute),
		"estimated_completion": time.Now().Add(2 * time.Minute),
		"worker_assignments": map[string]interface{}{
			"worker-1": []int{0, 1, 2},
			"worker-2": []int{3, 4, 5},
			"worker-3": []int{6, 7, 8},
		},
		"error_log": []string{
			"MapTask 9 failed: timeout after 15 seconds",
		},
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": fmt.Sprintf("Job %s details retrieved", jobID),
		"data":    details,
	})
}

// pauseJob mette in pausa un job
func (d *Dashboard) pauseJob(c *gin.Context) {
	jobID := c.Param("id")

	// Simula pausa del job
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   fmt.Sprintf("Job %s paused successfully", jobID),
		"action":    "pause",
		"timestamp": time.Now(),
	})
}

// resumeJob riprende un job in pausa
func (d *Dashboard) resumeJob(c *gin.Context) {
	jobID := c.Param("id")

	// Simula ripresa del job
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   fmt.Sprintf("Job %s resumed successfully", jobID),
		"action":    "resume",
		"timestamp": time.Now(),
	})
}

// cancelJob cancella un job
func (d *Dashboard) cancelJob(c *gin.Context) {
	jobID := c.Param("id")

	// Simula cancellazione del job
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   fmt.Sprintf("Job %s cancelled successfully", jobID),
		"action":    "cancel",
		"timestamp": time.Now(),
	})
}

// ===== WORKER ACTIONS =====

// getWorkerDetails restituisce i dettagli di un worker specifico
func (d *Dashboard) getWorkerDetails(c *gin.Context) {
	workerID := c.Param("id")

	// Simula dettagli del worker
	details := map[string]interface{}{
		"id":              workerID,
		"status":          "active",
		"last_seen":       time.Now().Add(-30 * time.Second),
		"tasks_completed": 15,
		"current_task": map[string]interface{}{
			"type":       "MapTask",
			"id":         7,
			"start_time": time.Now().Add(-2 * time.Minute),
			"progress":   45.0,
		},
		"performance": map[string]interface{}{
			"cpu_usage":    45.2,
			"memory_usage": 128,
			"disk_usage":   512,
			"network_io":   1024,
		},
		"task_history": []map[string]interface{}{
			{"task_id": 5, "type": "MapTask", "duration": "2.3s", "status": "completed"},
			{"task_id": 6, "type": "MapTask", "duration": "1.8s", "status": "completed"},
			{"task_id": 7, "type": "MapTask", "duration": "in_progress", "status": "running"},
		},
		"configuration": map[string]interface{}{
			"max_concurrent_tasks": 3,
			"timeout":              "30s",
			"retry_count":          3,
			"temp_path":            "/tmp/mapreduce",
		},
		"health_checks": map[string]interface{}{
			"disk_space":     "healthy",
			"memory":         "healthy",
			"network":        "healthy",
			"last_heartbeat": time.Now().Add(-5 * time.Second),
		},
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": fmt.Sprintf("Worker %s details retrieved", workerID),
		"data":    details,
	})
}

// pauseWorker mette in pausa un worker
func (d *Dashboard) pauseWorker(c *gin.Context) {
	workerID := c.Param("id")

	// Simula pausa del worker
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   fmt.Sprintf("Worker %s paused successfully", workerID),
		"action":    "pause",
		"timestamp": time.Now(),
	})
}

// resumeWorker riprende un worker in pausa
func (d *Dashboard) resumeWorker(c *gin.Context) {
	workerID := c.Param("id")

	// Simula ripresa del worker
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   fmt.Sprintf("Worker %s resumed successfully", workerID),
		"action":    "resume",
		"timestamp": time.Now(),
	})
}

// restartWorker riavvia un worker
func (d *Dashboard) restartWorker(c *gin.Context) {
	workerID := c.Param("id")

	// Simula riavvio del worker
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   fmt.Sprintf("Worker %s restarted successfully", workerID),
		"action":    "restart",
		"timestamp": time.Now(),
	})
}

// ===== SYSTEM ACTIONS =====

// startMaster avvia un nuovo master
func (d *Dashboard) startMaster(c *gin.Context) {
	// Conta i master prima
	before, _ := d.getMastersData()

	// Chiama il docker-manager.ps1 per aggiungere un nuovo master
	result, err := d.executeDockerManagerCommand("add-master")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": fmt.Sprintf("Failed to add master: %v", err),
			"action":  "start_master",
		})
		return
	}

	// Verifica con polling che il nuovo master si registri davvero
	deadline := time.Now().Add(20 * time.Second)
	increased := false
	for time.Now().Before(deadline) {
		time.Sleep(2 * time.Second)
		after, _ := d.getMastersData()
		if len(after) > len(before) {
			increased = true
			break
		}
	}

	if !increased {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"message": "Master start command executed, but cluster did not report a new master within timeout",
			"action":  "start_master",
			"output":  result,
		})
		return
	}

	// Invia notifica WebSocket
	d.broadcastCustomUpdate("master_added", map[string]interface{}{
		"message": "New master added to cluster",
		"output":  result,
	})

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "New master added and detected by cluster",
		"action":    "start_master",
		"output":    result,
		"timestamp": time.Now(),
	})
}

// startWorker avvia un nuovo worker
func (d *Dashboard) startWorker(c *gin.Context) {
	// Conta i worker prima
	before, _ := d.getWorkersData()

	// Chiama il docker-manager.ps1 per aggiungere un nuovo worker
	result, err := d.executeDockerManagerCommand("add-worker")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": fmt.Sprintf("Failed to add worker: %v", err),
			"action":  "start_worker",
		})
		return
	}

	// Verifica con polling che il nuovo worker si registri davvero
	deadline := time.Now().Add(20 * time.Second)
	increased := false
	for time.Now().Before(deadline) {
		time.Sleep(2 * time.Second)
		after, _ := d.getWorkersData()
		if len(after) > len(before) {
			increased = true
			break
		}
	}

	if !increased {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"message": "Worker start command executed, but no new worker registered within timeout",
			"action":  "start_worker",
			"output":  result,
		})
		return
	}

	// Invia notifica WebSocket
	d.broadcastCustomUpdate("worker_added", map[string]interface{}{
		"message": "New worker added to cluster",
		"output":  result,
	})

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "New worker added and detected by cluster",
		"action":    "start_worker",
		"output":    result,
		"timestamp": time.Now(),
	})
}

// stopAll ferma tutti i componenti del sistema
func (d *Dashboard) stopAll(c *gin.Context) {
	// Chiama il docker-manager.ps1 per fermare tutti i servizi
	result, err := d.executeDockerManagerCommand("stop")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": fmt.Sprintf("Failed to stop services: %v", err),
			"action":  "stop_all",
		})
		return
	}

	// Invia notifica WebSocket
	d.broadcastCustomUpdate("system_stopped", map[string]interface{}{
		"message": "All system components stopped",
		"output":  result,
	})

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "All system components stopped successfully",
		"action":    "stop_all",
		"output":    result,
		"timestamp": time.Now(),
	})
}

// restartCluster riavvia l'intero cluster
func (d *Dashboard) restartCluster(c *gin.Context) {
	// Chiama il docker-manager.ps1 per riavviare il cluster con reset alla configurazione default
	result, err := d.executeDockerManagerCommand("reset")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": fmt.Sprintf("Failed to restart cluster: %v", err),
			"action":  "restart_cluster",
		})
		return
	}

	// Invia notifica WebSocket
	d.broadcastCustomUpdate("cluster_restarted", map[string]interface{}{
		"message": "Cluster restarted with default configuration",
		"output":  result,
	})

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "Cluster restarted successfully with default configuration",
		"action":    "restart_cluster",
		"output":    result,
		"timestamp": time.Now(),
	})
}

// electLeader forza l'elezione di un nuovo leader master
func (d *Dashboard) electLeader(c *gin.Context) {
	LogInfo("=== LEADER ELECTION TRIGGERED ===")
	LogInfo("Forzando l'elezione di un nuovo leader master...")

	// Ottieni la configurazione
	config := d.config
	if config == nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "Configuration not available",
			"action":  "elect_leader",
		})
		return
	}

	// Ottieni gli indirizzi dei master
	raftAddrs := getMasterRaftAddresses()
	rpcAddrs := getMasterRpcAddresses()

	LogInfo("Master disponibili: %d", len(raftAddrs))
	for i, addr := range raftAddrs {
		LogInfo("  Master %d: %s (RPC: %s)", i, addr, rpcAddrs[i])
	}

	// Trova il leader attuale
	var currentLeaderID int = -1
	var currentLeaderAddr string
	for i, rpcAddr := range rpcAddrs {
		client, err := rpc.DialHTTP("tcp", rpcAddr)
		if err != nil {
			continue
		}

		var args GetMasterInfoArgs
		var reply MasterInfoReply
		err = client.Call("Master.GetMasterInfo", &args, &reply)
		client.Close()

		if err == nil && reply.IsLeader {
			currentLeaderID = i
			currentLeaderAddr = rpcAddr
			LogInfo("Leader attuale trovato: Master %d (%s)", i, rpcAddr)
			break
		}
	}

	if currentLeaderID == -1 {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "No leader found in the cluster",
			"action":  "elect_leader",
		})
		return
	}

	// Trova un candidato per la leadership (il prossimo master nella lista)
	newLeaderID := (currentLeaderID + 1) % len(rpcAddrs)

	LogInfo("Trasferendo leadership da Master %d a Master %d...", currentLeaderID, newLeaderID)

	// Prova a trasferire la leadership al nuovo master
	client, err := rpc.DialHTTP("tcp", currentLeaderAddr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": fmt.Sprintf("Failed to connect to current leader: %v", err),
			"action":  "elect_leader",
		})
		return
	}

	var transferArgs LeadershipTransferArgs
	var transferReply LeadershipTransferReply
	err = client.Call("Master.LeadershipTransfer", &transferArgs, &transferReply)
	client.Close()

	if err != nil {
		LogError("Errore trasferimento leadership: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": fmt.Sprintf("Failed to transfer leadership: %v", err),
			"action":  "elect_leader",
		})
		return
	}

	LogInfo("✓ Leadership transfer avviato con successo!")
	LogInfo("✓ Nuovo leader dovrebbe essere: Master %d", newLeaderID)

	// Aspetta un momento per permettere il trasferimento
	time.Sleep(2 * time.Second)

	// Verifica il nuovo leader
	var actualNewLeaderID int = -1
	for i, rpcAddr := range rpcAddrs {
		client, err := rpc.DialHTTP("tcp", rpcAddr)
		if err != nil {
			continue
		}

		var args GetMasterInfoArgs
		var reply MasterInfoReply
		err = client.Call("Master.GetMasterInfo", &args, &reply)
		client.Close()

		if err == nil && reply.IsLeader {
			actualNewLeaderID = i
			LogInfo("Nuovo leader confermato: Master %d (%s)", i, rpcAddr)
			break
		}
	}

	// Prepara la risposta
	leaderInfo := map[string]interface{}{
		"old_leader":          currentLeaderID,
		"new_leader":          actualNewLeaderID,
		"leader_id":           fmt.Sprintf("master-%d", actualNewLeaderID),
		"election_time":       time.Now(),
		"total_masters":       len(raftAddrs),
		"transfer_successful": actualNewLeaderID != currentLeaderID,
	}

	// Invia notifica WebSocket
	d.broadcastCustomUpdate("leader_elected", map[string]interface{}{
		"message":     fmt.Sprintf("New leader elected: Master %d", actualNewLeaderID),
		"leader_info": leaderInfo,
	})

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"message":     fmt.Sprintf("Leader election completed successfully. New leader: Master %d", actualNewLeaderID),
		"action":      "elect_leader",
		"leader_info": leaderInfo,
		"timestamp":   time.Now(),
	})
}

// submitJob gestisce la sottomissione di job MapReduce
func (d *Dashboard) submitJob(c *gin.Context) {
	var jobRequest struct {
		InputFiles []string `json:"input_files"`
		NReduce    int      `json:"n_reduce"`
	}

	if err := c.ShouldBindJSON(&jobRequest); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid request format",
			"details": err.Error(),
		})
		return
	}

	// Simula sottomissione job
	jobID := fmt.Sprintf("job-%d", time.Now().Unix())

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"message":     "Job submitted successfully",
		"job_id":      jobID,
		"status":      "submitted",
		"input_files": jobRequest.InputFiles,
		"n_reduce":    jobRequest.NReduce,
		"timestamp":   time.Now(),
	})
}

// getJobResults restituisce i risultati di un job
func (d *Dashboard) getJobResults(c *gin.Context) {
	jobID := c.Param("id")

	// Usa la funzione getCurrentOutput per evitare duplicazione
	outputData := d.getCurrentOutputData()

	// Gestisce errori nella lettura dei file
	if outputData.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to read output files",
			"details": outputData.Error.Error(),
		})
		return
	}

	// Per i job di testo, controlla se il job è ancora in processing
	if strings.HasPrefix(jobID, "text-job-") && len(outputData.Files) == 0 {
		// Simula che il job sia ancora in processing per i primi 5 secondi
		jobTimestamp := strings.TrimPrefix(jobID, "text-job-")
		if len(jobTimestamp) > 0 {
			time.Sleep(processingDelay) // Piccola pausa per simulare processing
			c.JSON(http.StatusOK, gin.H{
				"success":   true,
				"job_id":    jobID,
				"status":    "running",
				"progress":  50,
				"message":   "Job is still processing",
				"timestamp": time.Now(),
			})
			return
		}
	}

	// Se non ci sono file di output
	if len(outputData.Files) == 0 {
		c.JSON(http.StatusOK, gin.H{
			"success":         true,
			"job_id":          jobID,
			"status":          "completed",
			"results":         []gin.H{},
			"combined_output": "",
			"message":         "No output files found",
			"timestamp":       time.Now(),
		})
		return
	}

	// Prepara i risultati dettagliati
	var results []gin.H
	for _, file := range outputData.Files {
		// Legge il contenuto del file per i dettagli
		basePath := d.getOutputPath()
		filePath := filepath.Join(basePath, file)
		content, err := os.ReadFile(filePath)
		if err != nil {
			continue
		}

		lines := strings.Count(string(content), "\n")
		size := len(content)

		results = append(results, gin.H{
			"file":    file,
			"lines":   lines,
			"size":    fmt.Sprintf("%.1fKB", float64(size)/1024.0),
			"content": string(content),
		})
	}

	response := gin.H{
		"success":         true,
		"job_id":          jobID,
		"status":          "completed",
		"results":         results,
		"combined_output": outputData.Output,
		"timestamp":       time.Now(),
	}

	c.JSON(http.StatusOK, response)
}

// getCurrentOutput restituisce l'output del job corrente
func (d *Dashboard) getCurrentOutput(c *gin.Context) {
	outputData := d.getCurrentOutputData()

	// Gestisce errori nella lettura dei file
	if outputData.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to read output files",
			"details": outputData.Error.Error(),
		})
		return
	}

	// Se non ci sono file di output, restituisce un messaggio
	if len(outputData.Files) == 0 {
		c.JSON(http.StatusOK, gin.H{
			"success":   true,
			"message":   "No output files found",
			"output":    "",
			"files":     []string{},
			"timestamp": time.Now(),
		})
		return
	}

	response := gin.H{
		"success":   true,
		"message":   fmt.Sprintf("Found %d output files", len(outputData.Files)),
		"output":    outputData.Output,
		"files":     outputData.Files,
		"timestamp": time.Now(),
	}

	c.JSON(http.StatusOK, response)
}

// getOutputPage restituisce la pagina HTML per visualizzare l'output
func (d *Dashboard) getOutputPage(c *gin.Context) {
	data := d.getDashboardData()
	c.HTML(http.StatusOK, "output.html", data)
}

// processText gestisce l'elaborazione diretta del testo tramite MapReduce
func (d *Dashboard) processText(c *gin.Context) {
	var textRequest struct {
		Text    string `json:"text" binding:"required"`
		NReduce int    `json:"n_reduce"`
	}

	if err := c.ShouldBindJSON(&textRequest); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid request format",
			"details": err.Error(),
		})
		return
	}

	// Validazione input
	if textRequest.Text == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Text cannot be empty",
		})
		return
	}

	if textRequest.NReduce <= 0 {
		textRequest.NReduce = defaultNReduce // Default value
	}

	// Genera un ID univoco per il job
	jobID := fmt.Sprintf("text-job-%d", time.Now().Unix())

	// Crea un file temporaneo con il testo
	tempDir := os.Getenv("TMP_PATH")
	if tempDir == "" {
		if d.config != nil {
			tempDir = d.config.GetTempPath()
		} else {
			tempDir = "/tmp/mapreduce"
		}
	}

	// Assicurati che la directory temp esista
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to create temp directory",
			"details": err.Error(),
		})
		return
	}

	// Crea il file di input
	inputFile := filepath.Join(tempDir, fmt.Sprintf("input-%s.txt", jobID))
	if err := os.WriteFile(inputFile, []byte(textRequest.Text), 0644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to create input file",
			"details": err.Error(),
		})
		return
	}

	// Se abbiamo un master, usa quello per processare il job
	if d.master != nil {
		go d.processTextWithMaster(jobID, inputFile, textRequest.NReduce, tempDir)
	} else {
		// Simula il processing se non abbiamo un master
		go d.simulateTextProcessing(jobID, inputFile, textRequest.NReduce)
	}

	c.JSON(http.StatusOK, gin.H{
		"success":    true,
		"message":    "Text processing job submitted successfully",
		"job_id":     jobID,
		"status":     "submitted",
		"input_file": inputFile,
		"n_reduce":   textRequest.NReduce,
		"timestamp":  time.Now(),
	})
}

// processTextWithMaster usa il master reale per processare il testo
func (d *Dashboard) processTextWithMaster(jobID, inputFile string, nReduce int, tempDir string) {
	// In una implementazione reale, useresti il master per processare il file
	// Per ora, simula il processing
	time.Sleep(textProcessDelay) // Simula tempo di processing

	// Processa il testo e genera i file di output
	_ = tempDir
	d.generateMapReduceOutput(jobID, inputFile, nReduce)
}

// simulateTextProcessing simula il processing del testo
func (d *Dashboard) simulateTextProcessing(jobID, inputFile string, nReduce int) {
	// Simula tempo di processing
	time.Sleep(simulationDelay)

	// Processa il testo e genera i file di output
	d.generateMapReduceOutput(jobID, inputFile, nReduce)
}

// generateMapReduceOutput genera i file di output del MapReduce
func (d *Dashboard) generateMapReduceOutput(jobID, inputFile string, nReduce int) {
	// Usa la funzione helper per ottenere il percorso di output
	outputDir := d.getOutputPath()
	// Leggi il file di input
	content, err := os.ReadFile(inputFile)
	if err != nil {
		LogError("Error reading input file: %v", err)
		return
	}

	// Processa il testo per contare le parole
	wordCount := make(map[string]int)
	words := strings.Fields(strings.ToLower(string(content)))

	for _, word := range words {
		// Rimuovi punteggiatura
		word = strings.Trim(word, ".,!?;:\"'()[]{}")
		if word != "" {
			wordCount[word]++
		}
	}

	// Assicurati che la directory di output esista
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		LogError("Error creating output directory: %v", err)
		return
	}

	// Crea i file di output nella cartella output
	var outputFiles []string
	for i := 0; i < nReduce; i++ {
		outputFile := filepath.Join(outputDir, fmt.Sprintf("mr-out-%d", i))

		// Raggruppa le parole per questo reduce task
		var taskWords []string
		for word, count := range wordCount {
			if hash(word)%nReduce == i {
				taskWords = append(taskWords, fmt.Sprintf("%s %d", word, count))
			}
		}

		// Ordina le parole
		sort.Strings(taskWords)

		// Scrivi il file di output
		outputContent := strings.Join(taskWords, "\n")
		if err := os.WriteFile(outputFile, []byte(outputContent), 0644); err != nil {
			LogError("Error writing output file %s: %v", outputFile, err)
			continue
		}

		outputFiles = append(outputFiles, outputFile)
	}

	// Pulisci il file di input temporaneo
	os.Remove(inputFile)

	LogInfo("Generated %d output files for job %s", len(outputFiles), jobID)
}

// hash function per distribuire le parole tra i reduce tasks
func hash(s string) int {
	h := 0
	for _, c := range s {
		h = h*31 + int(c)
	}
	if h < 0 {
		h = -h
	}
	return h
}

// OutputData struttura per i dati di output
type OutputData struct {
	Output string
	Files  []string
	Error  error
}

// getCurrentOutputData raccoglie i dati di output senza duplicazione
func (d *Dashboard) getCurrentOutputData() OutputData {
	basePath := d.getOutputPath()

	var allOutput string
	var files []string

	// Cerca tutti i file mr-out-* nella directory
	outputFiles, err := filepath.Glob(filepath.Join(basePath, "mr-out-*"))
	if err != nil {
		return OutputData{
			Output: "",
			Files:  []string{},
			Error:  fmt.Errorf("failed to read output files: %v", err),
		}
	}

	// Legge ogni file di output e li ordina
	for _, file := range outputFiles {
		content, err := os.ReadFile(file)
		if err != nil {
			continue // Salta file che non riesce a leggere
		}

		files = append(files, filepath.Base(file))
		if allOutput != "" {
			allOutput += "\n"
		}
		allOutput += string(content)
	}

	return OutputData{
		Output: allOutput,
		Files:  files,
		Error:  nil,
	}
}

// getOutputPath restituisce il percorso della directory di output
func (d *Dashboard) getOutputPath() string {
	basePath := os.Getenv("OUTPUT_PATH")
	if basePath == "" {
		if d.config != nil {
			basePath = d.config.GetOutputPath()
		} else {
			basePath = "data/output"
		}
	}
	return basePath
}

// executeDockerManagerCommand esegue comandi Docker tramite script esterno
func (d *Dashboard) executeDockerManagerCommand(action string) (string, error) {
	// Usa lo script bash per gestire Docker dal sistema host
	scriptPath := "/root/scripts/docker-manager.sh"

	// Verifica se lo script esiste
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		// Fallback: usa comandi Docker diretti (potrebbe non funzionare nel container)
		return d.executeDockerCommandDirect(action)
	}

	// Usa bash per eseguire lo script
	cmd := exec.Command("bash", scriptPath, action)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return string(output), fmt.Errorf("script execution failed: %v, output: %s", err, string(output))
	}
	return string(output), nil
}

// executeDockerCommandDirect esegue comandi Docker direttamente (fallback)
func (d *Dashboard) executeDockerCommandDirect(action string) (string, error) {
	var cmd *exec.Cmd

	switch action {
	case "add-master":
		// Trova il prossimo ID master disponibile
		masterID := d.findNextMasterID()
		return d.addDynamicMaster(masterID)
	case "add-worker":
		// Trova il prossimo ID worker disponibile
		workerID := d.findNextWorkerID()
		return d.addDynamicWorker(workerID)
	case "stop":
		// Ferma tutti i container del cluster
		cmd = exec.Command("docker", "compose", "-f", "docker/docker-compose.yml", "down")
	case "reset":
		// Ferma e riavvia il cluster con sequenza stop + start
		// Prima ferma tutto
		stopCmd := exec.Command("docker", "compose", "-f", "docker/docker-compose.yml", "down")
		stopOutput, stopErr := stopCmd.CombinedOutput()
		if stopErr != nil {
			return string(stopOutput), fmt.Errorf("failed to stop cluster: %v, output: %s", stopErr, string(stopOutput))
		}

		// Poi riavvia
		startCmd := exec.Command("docker", "compose", "-f", "docker/docker-compose.yml", "up", "-d")
		startOutput, startErr := startCmd.CombinedOutput()
		if startErr != nil {
			return string(startOutput), fmt.Errorf("failed to start cluster: %v, output: %s", startErr, string(startOutput))
		}

		return fmt.Sprintf("Cluster restarted successfully. Stop output: %s\nStart output: %s", string(stopOutput), string(startOutput)), nil
	default:
		return "", fmt.Errorf("unknown action: %s", action)
	}

	output, err := cmd.CombinedOutput()
	if err != nil {
		return string(output), fmt.Errorf("command failed: %v, output: %s", err, string(output))
	}
	return string(output), nil
}

// findNextMasterID trova il prossimo ID master disponibile
func (d *Dashboard) findNextMasterID() int {
	// Conta i master esistenti
	cmd := exec.Command("docker", "ps", "--filter", "name=docker-master", "--format", "{{.Names}}")
	output, err := cmd.Output()
	if err != nil {
		return 3 // Default al primo aggiuntivo
	}

	// Conta i master esistenti
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	maxID := 2 // master0, master1, master2 sono i default

	for _, line := range lines {
		if strings.Contains(line, "docker-master") {
			// Estrai numero dal nome (es: docker-master3-1 -> 3)
			parts := strings.Split(line, "master")
			if len(parts) > 1 {
				numStr := strings.Split(parts[1], "-")[0]
				if num, err := strconv.Atoi(numStr); err == nil {
					if num > maxID {
						maxID = num
					}
				}
			}
		}
	}

	return maxID + 1
}

// findNextWorkerID trova il prossimo ID worker disponibile
func (d *Dashboard) findNextWorkerID() int {
	// Conta i worker esistenti
	cmd := exec.Command("docker", "ps", "--filter", "name=docker-worker", "--format", "{{.Names}}")
	output, err := cmd.Output()
	if err != nil {
		return 4 // Default al primo aggiuntivo
	}

	// Conta i worker esistenti
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	maxID := 3 // worker1, worker2, worker3 sono i default

	for _, line := range lines {
		if strings.Contains(line, "docker-worker") {
			// Estrai numero dal nome (es: docker-worker4-1 -> 4)
			parts := strings.Split(line, "worker")
			if len(parts) > 1 {
				numStr := strings.Split(parts[1], "-")[0]
				if num, err := strconv.Atoi(numStr); err == nil {
					if num > maxID {
						maxID = num
					}
				}
			}
		}
	}

	return maxID + 1
}

// addDynamicMaster aggiunge un master dinamicamente
func (d *Dashboard) addDynamicMaster(masterID int) (string, error) {
	// Calcola le porte
	raftPort := 1234 + masterID
	rpcPort := 8000 + masterID

	// Ottieni la lista dei master esistenti per RAFT_ADDRESSES
	existingMasters := d.getExistingMasters()
	raftAddresses := strings.Join(existingMasters, ",")
	rpcAddresses := d.getExistingRPCAddresses()

	// Crea il comando docker run
	cmd := exec.Command("docker", "run", "-d",
		"--name", fmt.Sprintf("docker-master%d-1", masterID),
		"--network", "docker_mapreduce-net",
		"-p", fmt.Sprintf("%d:1234", raftPort),
		"-p", fmt.Sprintf("%d:8000", rpcPort),
		"-v", "mapreduce-project_intermediate-data:/tmp/mapreduce",
		"-v", "./data:/root/data:ro",
		"-e", fmt.Sprintf("RAFT_ADDRESSES=%s", raftAddresses),
		"-e", fmt.Sprintf("RPC_ADDRESSES=%s", rpcAddresses),
		"-e", "TMP_PATH=/tmp/mapreduce",
		"-e", "METRICS_ENABLED=true",
		"-e", "METRICS_PORT=9090",
		"docker-master0", // Usa la stessa immagine
		"./mapreduce", "master", fmt.Sprintf("%d", masterID), "/root/data/Words.txt")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return string(output), fmt.Errorf("failed to add master %d: %v, output: %s", masterID, err, string(output))
	}

	return fmt.Sprintf("Master %d added successfully", masterID), nil
}

// addDynamicWorker aggiunge un worker dinamicamente
func (d *Dashboard) addDynamicWorker(workerID int) (string, error) {
	// Ottieni la lista dei master esistenti per RPC_ADDRESSES
	rpcAddresses := d.getExistingRPCAddresses()

	// Crea il comando docker run
	cmd := exec.Command("docker", "run", "-d",
		"--name", fmt.Sprintf("docker-worker%d-1", workerID),
		"--network", "docker_mapreduce-net",
		"-v", "mapreduce-project_intermediate-data:/tmp/mapreduce",
		"-v", "./data:/root/data:ro",
		"-e", fmt.Sprintf("RPC_ADDRESSES=%s", rpcAddresses),
		"-e", "TMP_PATH=/tmp/mapreduce",
		"-e", fmt.Sprintf("WORKER_ID=worker-%d", workerID),
		"-e", "MAPREDUCE_WORKER_RETRY_INTERVAL=2s",
		"-e", "MAPREDUCE_WORKER_MAX_RETRIES=10",
		"docker-worker1", // Usa la stessa immagine
		"./mapreduce", "worker")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return string(output), fmt.Errorf("failed to add worker %d: %v, output: %s", workerID, err, string(output))
	}

	return fmt.Sprintf("Worker %d added successfully", workerID), nil
}

// getExistingMasters ottiene la lista dei master esistenti per RAFT
func (d *Dashboard) getExistingMasters() []string {
	cmd := exec.Command("docker", "ps", "--filter", "name=docker-master", "--format", "{{.Names}}")
	output, err := cmd.Output()
	if err != nil {
		return []string{"master0:1234", "master1:1234", "master2:1234"} // Default
	}

	var masters []string
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")

	for _, line := range lines {
		if strings.Contains(line, "docker-master") {
			// Estrai numero dal nome
			parts := strings.Split(line, "master")
			if len(parts) > 1 {
				numStr := strings.Split(parts[1], "-")[0]
				if num, err := strconv.Atoi(numStr); err == nil {
					masters = append(masters, fmt.Sprintf("master%d:1234", num))
				}
			}
		}
	}

	// Ordina per numero
	sort.Slice(masters, func(i, j int) bool {
		numI := strings.Split(masters[i], "master")[1]
		numJ := strings.Split(masters[j], "master")[1]
		return numI < numJ
	})

	return masters
}

// getExistingRPCAddresses ottiene la lista degli indirizzi RPC esistenti
func (d *Dashboard) getExistingRPCAddresses() string {
	cmd := exec.Command("docker", "ps", "--filter", "name=docker-master", "--format", "{{.Names}}")
	output, err := cmd.Output()
	if err != nil {
		return "master0:8000,master1:8001,master2:8002" // Default
	}

	var rpcAddrs []string
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")

	for _, line := range lines {
		if strings.Contains(line, "docker-master") {
			// Estrai numero dal nome
			parts := strings.Split(line, "master")
			if len(parts) > 1 {
				numStr := strings.Split(parts[1], "-")[0]
				if num, err := strconv.Atoi(numStr); err == nil {
					rpcAddrs = append(rpcAddrs, fmt.Sprintf("master%d:800%d", num, num))
				}
			}
		}
	}

	// Ordina per numero
	sort.Slice(rpcAddrs, func(i, j int) bool {
		numI := strings.Split(rpcAddrs[i], "master")[1]
		numJ := strings.Split(rpcAddrs[j], "master")[1]
		return numI < numJ
	})

	return strings.Join(rpcAddrs, ",")
}

// ===== WEBSOCKET FUNCTIONS =====

// handleWebSocket gestisce le connessioni WebSocket
func (d *Dashboard) handleWebSocket(c *gin.Context) {
	conn, err := d.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		LogError("WebSocket upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	// Registra il client
	d.clientsMutex.Lock()
	d.clients[conn] = true
	d.clientsMutex.Unlock()

	LogInfo("WebSocket client connected. Total clients: %d", len(d.clients))

	// Invia dati iniziali
	d.sendInitialData(conn)

	// Gestisce i messaggi dal client
	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				LogError("WebSocket error: %v", err)
			}
			break
		}
	}

	// Rimuove il client quando si disconnette
	d.clientsMutex.Lock()
	delete(d.clients, conn)
	d.clientsMutex.Unlock()
	LogInfo("WebSocket client disconnected. Total clients: %d", len(d.clients))
}

// sendInitialData invia i dati iniziali al client WebSocket
func (d *Dashboard) sendInitialData(conn *websocket.Conn) {
	data := d.getDashboardData()

	// Prepara i dati per l'invio
	updateData := map[string]interface{}{
		"type":      "initial_data",
		"timestamp": time.Now(),
		"data":      data,
	}

	if err := conn.WriteJSON(updateData); err != nil {
		LogError("Error sending initial data: %v", err)
	}
}

// handleWebSocketMessages gestisce i messaggi broadcast
func (d *Dashboard) handleWebSocketMessages() {
	for {
		select {
		case message := <-d.broadcast:
			d.clientsMutex.RLock()
			for client := range d.clients {
				err := client.WriteMessage(websocket.TextMessage, message)
				if err != nil {
					LogError("Error broadcasting message: %v", err)
					client.Close()
					delete(d.clients, client)
				}
			}
			d.clientsMutex.RUnlock()
		}
	}
}

// startRealTimeUpdates avvia gli aggiornamenti in tempo reale
func (d *Dashboard) startRealTimeUpdates() {
	ticker := time.NewTicker(5 * time.Second) // Aggiorna ogni 5 secondi
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			d.broadcastUpdate()
		}
	}
}

// broadcastUpdate invia un aggiornamento a tutti i client connessi
func (d *Dashboard) broadcastUpdate() {
	d.clientsMutex.RLock()
	clientCount := len(d.clients)
	d.clientsMutex.RUnlock()

	if clientCount == 0 {
		return // Nessun client connesso
	}

	// Raccoglie i dati aggiornati
	mastersData, _ := d.getMastersData()
	workersData, _ := d.getWorkersData()
	healthData := d.healthChecker.CheckAll(context.Background())

	// Prepara l'aggiornamento
	updateData := map[string]interface{}{
		"type":      "realtime_update",
		"timestamp": time.Now(),
		"data": map[string]interface{}{
			"masters": mastersData,
			"workers": workersData,
			"health":  healthData,
		},
	}

	// Converte in JSON
	jsonData, err := json.Marshal(updateData)
	if err != nil {
		LogError("Error marshaling update data: %v", err)
		return
	}

	// Invia il broadcast
	select {
	case d.broadcast <- jsonData:
	default:
		// Se il canale è pieno, salta questo aggiornamento
	}
}

// broadcastCustomUpdate invia un aggiornamento personalizzato
func (d *Dashboard) broadcastCustomUpdate(updateType string, data interface{}) {
	updateData := map[string]interface{}{
		"type":      updateType,
		"timestamp": time.Now(),
		"data":      data,
	}

	jsonData, err := json.Marshal(updateData)
	if err != nil {
		LogError("Error marshaling custom update: %v", err)
		return
	}

	select {
	case d.broadcast <- jsonData:
	default:
		// Se il canale è pieno, salta questo aggiornamento
	}
}

// initializeLoadBalancerServers inizializza i server per il load balancer
func (d *Dashboard) initializeLoadBalancerServers() []Server {
	var servers []Server

	// Aggiungi server master
	rpcAddrs := getMasterRpcAddresses()
	for i, addr := range rpcAddrs {
		parts := strings.Split(addr, ":")
		if len(parts) == 2 {
			port, _ := strconv.Atoi(parts[1])
			servers = append(servers, Server{
				ID:      fmt.Sprintf("master-%d", i),
				Address: parts[0],
				Port:    port,
				Weight:  10, // Peso maggiore per i master
				Healthy: true,
			})
		}
	}

	// Aggiungi server worker (se disponibili)
	// Questo è un esempio - in un'implementazione reale dovresti
	// interrogare i master per ottenere la lista dei worker
	workerPorts := []int{8081, 8082, 8083} // Porte di esempio per i worker
	for i, port := range workerPorts {
		servers = append(servers, Server{
			ID:      fmt.Sprintf("worker-%d", i),
			Address: "localhost", // In produzione, usa l'IP reale
			Port:    port,
			Weight:  5, // Peso minore per i worker
			Healthy: true,
		})
	}

	return servers
}

// getLoadBalancerStats restituisce le statistiche del load balancer
func (d *Dashboard) getLoadBalancerStats() map[string]interface{} {
	if d.loadBalancer == nil {
		return map[string]interface{}{
			"enabled": false,
			"message": "Load balancer non abilitato",
		}
	}

	stats := d.loadBalancer.GetStats()
	stats["enabled"] = true
	return stats
}

// getS3Stats restituisce le statistiche S3
func (d *Dashboard) getS3Stats() map[string]interface{} {
	if d.s3Manager == nil {
		return map[string]interface{}{
			"enabled": false,
			"message": "S3 storage non abilitato",
		}
	}

	return d.s3Manager.GetStorageStats()
}

// ===== LOAD BALANCER ENDPOINTS =====

// getLoadBalancerStatsEndpoint restituisce le statistiche del load balancer
func (d *Dashboard) getLoadBalancerStatsEndpoint(c *gin.Context) {
	stats := d.getLoadBalancerStats()
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    stats,
	})
}

// addLoadBalancerServer aggiunge un server al load balancer
func (d *Dashboard) addLoadBalancerServer(c *gin.Context) {
	var request struct {
		ID      string `json:"id" binding:"required"`
		Address string `json:"address" binding:"required"`
		Port    int    `json:"port" binding:"required"`
		Weight  int    `json:"weight"`
	}

	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid request format",
			"details": err.Error(),
		})
		return
	}

	if d.loadBalancer == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"error":   "Load balancer non abilitato",
		})
		return
	}

	server := Server{
		ID:      request.ID,
		Address: request.Address,
		Port:    request.Port,
		Weight:  request.Weight,
		Healthy: true,
	}

	d.loadBalancer.AddServer(server)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": fmt.Sprintf("Server %s aggiunto al load balancer", request.ID),
	})
}

// removeLoadBalancerServer rimuove un server dal load balancer
func (d *Dashboard) removeLoadBalancerServer(c *gin.Context) {
	var request struct {
		ServerID string `json:"server_id" binding:"required"`
	}

	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid request format",
			"details": err.Error(),
		})
		return
	}

	if d.loadBalancer == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"error":   "Load balancer non abilitato",
		})
		return
	}

	d.loadBalancer.RemoveServer(request.ServerID)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": fmt.Sprintf("Server %s rimosso dal load balancer", request.ServerID),
	})
}

// ===== S3 STORAGE ENDPOINTS =====

// getS3StatsEndpoint restituisce le statistiche S3
func (d *Dashboard) getS3StatsEndpoint(c *gin.Context) {
	stats := d.getS3Stats()
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    stats,
	})
}

// createS3Backup crea un backup S3
func (d *Dashboard) createS3Backup(c *gin.Context) {
	if d.s3Manager == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"error":   "S3 storage non abilitato",
		})
		return
	}

	err := d.s3Manager.BackupClusterData()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to create backup",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Backup S3 creato con successo",
	})
}

// listS3Backups elenca i backup S3 disponibili
func (d *Dashboard) listS3Backups(c *gin.Context) {
	if d.s3Manager == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"error":   "S3 storage non abilitato",
		})
		return
	}

	backups, err := d.s3Manager.ListBackups()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to list backups",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    backups,
	})
}

// restoreFromS3Backup ripristina da un backup S3
func (d *Dashboard) restoreFromS3Backup(c *gin.Context) {
	var request struct {
		BackupTimestamp string `json:"backup_timestamp" binding:"required"`
		LocalPath       string `json:"local_path" binding:"required"`
	}

	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid request format",
			"details": err.Error(),
		})
		return
	}

	if d.s3Manager == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"error":   "S3 storage non abilitato",
		})
		return
	}

	err := d.s3Manager.RestoreFromBackup(request.BackupTimestamp, request.LocalPath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to restore from backup",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": fmt.Sprintf("Ripristino da backup %s completato", request.BackupTimestamp),
	})
}
