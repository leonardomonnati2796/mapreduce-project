package main

import (
	"context"
	"fmt"
	"net/http"
	"net/rpc"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
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
	}

	d.setupRoutes()
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
	}

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
	fmt.Printf("[Dashboard] Getting worker data from masters: %v\n", rpcAddrs)

	// Trova prima il leader master
	var leaderAddr string
	var leaderID int = -1

	for i, rpcAddr := range rpcAddrs {
		client, err := rpc.DialHTTP("tcp", rpcAddr)
		if err != nil {
			fmt.Printf("[Dashboard] Failed to connect to master %d at %s: %v\n", i, rpcAddr, err)
			continue
		}

		var args GetMasterInfoArgs
		var reply MasterInfoReply
		err = client.Call("Master.GetMasterInfo", &args, &reply)
		client.Close()

		if err == nil && reply.IsLeader {
			leaderAddr = rpcAddr
			leaderID = i
			fmt.Printf("[Dashboard] Found leader master %d at %s\n", i, rpcAddr)
			break
		}
	}

	// Se non troviamo il leader, interroga tutti i master come fallback
	if leaderAddr == "" {
		fmt.Printf("[Dashboard] No leader found, using fallback approach\n")
		return d.getWorkersDataFromAllMasters(rpcAddrs)
	}

	// Interroga solo il leader per ottenere le informazioni sui worker
	workerInfo, err := d.queryWorkerInfo(leaderID, leaderAddr)
	if err != nil {
		fmt.Printf("[Dashboard] Failed to get worker info from leader master %d at %s: %v\n", leaderID, leaderAddr, err)
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
		fmt.Printf("[Dashboard] No workers found from leader master\n")
		return []WorkerInfoDashboard{}, nil
	}

	fmt.Printf("[Dashboard] Found %d workers from leader master\n", len(allWorkers))
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
			fmt.Printf("[Dashboard] Failed to get worker info from master %d at %s: %v\n", i, rpcAddr, err)
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
		fmt.Printf("[Dashboard] No workers found from any master\n")
		return []WorkerInfoDashboard{}, nil
	}

	fmt.Printf("[Dashboard] Found %d unique workers from all masters\n", len(allWorkers))
	return allWorkers, nil
}

// getMastersData raccoglie i dati dei master interrogando i master reali
func (d *Dashboard) getMastersData() ([]MasterInfo, error) {
	// Ottieni gli indirizzi RPC dei master
	rpcAddrs := getMasterRpcAddresses()

	// Debug: stampa gli indirizzi RPC che stiamo usando
	fmt.Printf("[Dashboard] Using RPC addresses: %v\n", rpcAddrs)

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
	fmt.Printf("[Dashboard] Attempting to get worker info from master %d at %s\n", masterID, rpcAddr)

	// Crea una connessione RPC al master
	client, err := rpc.DialHTTP("tcp", rpcAddr)
	if err != nil {
		fmt.Printf("[Dashboard] Failed to connect to master %d at %s: %v\n", masterID, rpcAddr, err)
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

	fmt.Printf("[Dashboard] Got worker info from master %d: %d workers\n", masterID, len(reply.Workers))
	return reply, nil
}

// queryMasterInfo interroga un master specifico per ottenere le sue informazioni
func (d *Dashboard) queryMasterInfo(masterID int, rpcAddr string) (MasterInfo, error) {
	// Debug: stampa l'indirizzo che stiamo tentando di contattare
	fmt.Printf("[Dashboard] Attempting to connect to master %d at %s\n", masterID, rpcAddr)

	// Crea una connessione RPC al master
	client, err := rpc.DialHTTP("tcp", rpcAddr)
	if err != nil {
		fmt.Printf("[Dashboard] Failed to connect to master %d at %s: %v\n", masterID, rpcAddr, err)
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

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "New master added successfully",
		"action":    "start_master",
		"output":    result,
		"timestamp": time.Now(),
	})
}

// startWorker avvia un nuovo worker
func (d *Dashboard) startWorker(c *gin.Context) {
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

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "New worker added successfully",
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
	fmt.Println("=== LEADER ELECTION TRIGGERED ===")
	fmt.Println("Forzando l'elezione di un nuovo leader master...")

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

	fmt.Printf("Master disponibili: %d\n", len(raftAddrs))
	for i, addr := range raftAddrs {
		fmt.Printf("  Master %d: %s (RPC: %s)\n", i, addr, rpcAddrs[i])
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
			fmt.Printf("Leader attuale trovato: Master %d (%s)\n", i, rpcAddr)
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

	fmt.Printf("Trasferendo leadership da Master %d a Master %d...\n", currentLeaderID, newLeaderID)

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
		fmt.Printf("Errore trasferimento leadership: %v\n", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": fmt.Sprintf("Failed to transfer leadership: %v", err),
			"action":  "elect_leader",
		})
		return
	}

	fmt.Printf("✓ Leadership transfer avviato con successo!\n")
	fmt.Printf("✓ Nuovo leader dovrebbe essere: Master %d\n", newLeaderID)

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
			fmt.Printf("Nuovo leader confermato: Master %d (%s)\n", i, rpcAddr)
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
			tempDir = "temp-local"
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
		fmt.Printf("Error reading input file: %v\n", err)
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
		fmt.Printf("Error creating output directory: %v\n", err)
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
			fmt.Printf("Error writing output file %s: %v\n", outputFile, err)
			continue
		}

		outputFiles = append(outputFiles, outputFile)
	}

	// Pulisci il file di input temporaneo
	os.Remove(inputFile)

	fmt.Printf("Generated %d output files for job %s\n", len(outputFiles), jobID)
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

// executeDockerManagerCommand esegue comandi del docker-manager.ps1
func (d *Dashboard) executeDockerManagerCommand(action string) (string, error) {
	// Trova il percorso del docker-manager.ps1
	scriptPath := "scripts/docker-manager.ps1"
	if _, err := os.Stat(scriptPath); err == nil {
		// Usa PowerShell su host Windows quando disponibile
		var cmd *exec.Cmd
		switch action {
		case "add-master":
			cmd = exec.Command("powershell", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "add-master")
		case "add-worker":
			cmd = exec.Command("powershell", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "add-worker")
		case "stop":
			cmd = exec.Command("powershell", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "stop")
		case "reset":
			cmd = exec.Command("powershell", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "reset")
		default:
			return "", fmt.Errorf("unknown action: %s", action)
		}
		output, err := cmd.CombinedOutput()
		if err != nil {
			return string(output), fmt.Errorf("command failed: %v, output: %s", err, string(output))
		}
		return string(output), nil
	}

	// Fallback in-container: usa docker CLI (richiede docker.sock montato)
	// Helpers
	run := func(name string, args ...string) (string, error) {
		cmd := exec.Command(name, args...)
		out, err := cmd.CombinedOutput()
		return string(out), err
	}
	// Elenco container per nome
	listAll, err := run("docker", "ps", "-a", "--format", "{{.Names}}")
	if err != nil {
		return listAll, fmt.Errorf("docker ps -a failed: %v", err)
	}
	listRun, err := run("docker", "ps", "--format", "{{.Names}}")
	if err != nil {
		return listRun, fmt.Errorf("docker ps failed: %v", err)
	}
	contains := func(haystack, needle string) bool { return strings.Contains(haystack, needle) }
	isRunning := func(name string) bool { return contains(listRun, name) }

	// Candidati robusti per nomi container (compose v2 con '-' e v1 con '_')
	masterCandidates := []string{"master1-1", "master2-1", "master1_1", "master2_1"}
	workerCandidates := []string{"worker1-1", "worker2-1", "worker1_1", "worker2_1"}

	switch action {
	case "add-master":
		for _, suffix := range masterCandidates {
			// Trova nome completo che termina con il suffisso
			lines := strings.Split(listAll, "\n")
			for _, n := range lines {
				n = strings.TrimSpace(n)
				if n == "" {
					continue
				}
				if strings.HasSuffix(n, suffix) && !isRunning(n) {
					out, err := run("docker", "start", n)
					if err != nil {
						return out, fmt.Errorf("failed to start %s: %v", n, err)
					}
					return fmt.Sprintf("started %s", n), nil
				}
			}
		}
		return "no stopped master to start", nil
	case "add-worker":
		for _, suffix := range workerCandidates {
			lines := strings.Split(listAll, "\n")
			for _, n := range lines {
				n = strings.TrimSpace(n)
				if n == "" {
					continue
				}
				if strings.HasSuffix(n, suffix) && !isRunning(n) {
					out, err := run("docker", "start", n)
					if err != nil {
						return out, fmt.Errorf("failed to start %s: %v", n, err)
					}
					return fmt.Sprintf("started %s", n), nil
				}
			}
		}
		return "no stopped worker to start", nil
	case "stop":
		// Ferma masters e workers, non fermare il dashboard stesso
		stopped := []string{}
		lines := strings.Split(listRun, "\n")
		for _, n := range lines {
			n = strings.TrimSpace(n)
			if n == "" {
				continue
			}
			if strings.Contains(n, "master") || strings.Contains(n, "worker") {
				out, err := run("docker", "stop", n)
				if err == nil {
					stopped = append(stopped, n)
				} else {
					_ = out
				}
			}
		}
		return fmt.Sprintf("stopped: %v", stopped), nil
	case "reset":
		// Ferma e riavvia i servizi di default
		_, _ = d.executeDockerManagerCommand("stop")
		// Avvia i default: master0/master1/master2/worker1/worker2
		started := []string{}
		targets := []string{"master0", "master1", "master2", "worker1", "worker2"}
		// Trova nomi reali in base ai target
		lines := strings.Split(listAll, "\n")
		for _, t := range targets {
			for _, n := range lines {
				n = strings.TrimSpace(n)
				if n == "" {
					continue
				}
				if strings.Contains(n, t) {
					_, err := run("docker", "start", n)
					if err == nil {
						started = append(started, n)
						break
					}
				}
			}
		}
		return fmt.Sprintf("started: %v", started), nil
	default:
		return "", fmt.Errorf("unknown action: %s", action)
	}
}
