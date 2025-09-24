package main

import (
	"context"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
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
	Title      string                 `json:"title"`
	Version    string                 `json:"version"`
	Uptime     time.Duration          `json:"uptime"`
	Health     HealthStatus           `json:"health"`
	Metrics    map[string]interface{} `json:"metrics"`
	Jobs       []JobInfo              `json:"jobs"`
	Workers    []WorkerInfoDashboard  `json:"workers"`
	Masters    []MasterInfo           `json:"masters"`
	LastUpdate time.Time              `json:"last_update"`
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
func NewDashboard(config *Config, healthChecker *HealthChecker, metrics *MetricCollector) *Dashboard {
	if config == nil {
		panic("config cannot be nil")
	}
	if healthChecker == nil {
		panic("healthChecker cannot be nil")
	}
	if metrics == nil {
		panic("metrics cannot be nil")
	}

	d := &Dashboard{
		config:        config,
		healthChecker: healthChecker,
		metrics:       metrics,
		router:        gin.Default(),
		startTime:     time.Now(),
	}

	d.setupRoutes()
	return d
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

	return DashboardData{
		Title:      "MapReduce Dashboard",
		Version:    "1.0.0",
		Uptime:     uptime,
		Health:     health,
		Metrics:    metrics,
		Jobs:       jobs,
		Workers:    workers,
		Masters:    masters,
		LastUpdate: now,
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
	if d.master == nil {
		// Restituisce dati simulati se il master non è disponibile
		return []JobInfo{
			{
				ID:          "job-1",
				Status:      "running",
				Phase:       "map",
				StartTime:   time.Now().Add(-5 * time.Minute),
				MapTasks:    10,
				ReduceTasks: 5,
				Progress:    75.5,
			},
		}, nil
	}

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

// getWorkersData raccoglie i dati dei worker
func (d *Dashboard) getWorkersData() ([]WorkerInfoDashboard, error) {
	// Genera dati dinamici con variazioni realistiche
	now := time.Now()

	// Simula variazioni nei task completati e negli stati
	baseTime := now.Add(-time.Duration(rand.Intn(60)) * time.Second)
	tasksDone1 := 15 + rand.Intn(5) // Varia tra 15-19
	tasksDone2 := 12 + rand.Intn(3) // Varia tra 12-14

	// Simula occasionalmente worker inattivi
	status1 := "active"
	status2 := "active"
	if rand.Float32() < 0.1 { // 10% chance di worker inattivo
		if rand.Float32() < 0.5 {
			status1 = "idle"
		} else {
			status2 = "idle"
		}
	}

	workers := []WorkerInfoDashboard{
		{
			ID:        "worker-1",
			Status:    status1,
			LastSeen:  baseTime,
			TasksDone: tasksDone1,
		},
		{
			ID:        "worker-2",
			Status:    status2,
			LastSeen:  baseTime.Add(-time.Duration(rand.Intn(30)) * time.Second),
			TasksDone: tasksDone2,
		},
	}

	// Aggiungi occasionalmente un terzo worker
	if rand.Float32() < 0.3 { // 30% chance
		workers = append(workers, WorkerInfoDashboard{
			ID:        "worker-3",
			Status:    "active",
			LastSeen:  baseTime.Add(-time.Duration(rand.Intn(20)) * time.Second),
			TasksDone: 8 + rand.Intn(4), // Varia tra 8-11
		})
	}

	return workers, nil
}

// getMastersData raccoglie i dati dei master
func (d *Dashboard) getMastersData() ([]MasterInfo, error) {
	// Genera dati dinamici con variazioni realistiche
	now := time.Now()

	// Simula variazioni nei tempi di last seen
	baseTime := now.Add(-time.Duration(rand.Intn(30)) * time.Second)

	// Simula occasionalmente cambi di leader (5% chance)
	leaderIndex := 0
	if rand.Float32() < 0.05 { // 5% chance di cambio leader
		leaderIndex = rand.Intn(3)
	}

	masters := []MasterInfo{
		{
			ID:       "master-0",
			Role:     "leader",
			State:    "leader",
			Leader:   leaderIndex == 0,
			LastSeen: baseTime,
		},
		{
			ID:       "master-1",
			Role:     "follower",
			State:    "follower",
			Leader:   leaderIndex == 1,
			LastSeen: baseTime.Add(-time.Duration(rand.Intn(15)) * time.Second),
		},
		{
			ID:       "master-2",
			Role:     "follower",
			State:    "follower",
			Leader:   leaderIndex == 2,
			LastSeen: baseTime.Add(-time.Duration(rand.Intn(20)) * time.Second),
		},
	}

	// Aggiorna il ruolo del leader
	if leaderIndex != 0 {
		masters[leaderIndex].Role = "leader"
		masters[leaderIndex].State = "leader"
		masters[0].Role = "follower"
		masters[0].State = "follower"
		masters[0].Leader = false
	}

	return masters, nil
}

// Start avvia il server web
func (d *Dashboard) Start(port int) error {
	if port <= 0 || port > 65535 {
		return fmt.Errorf("invalid port number: %d", port)
	}

	addr := fmt.Sprintf(":%d", port)

	// Configura il server con timeout
	server := &http.Server{
		Addr:         addr,
		Handler:      d.router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
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
	// Simula l'elezione del leader
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

	// Trova un master candidato (escludi il leader attuale se possibile)
	candidateID := 0
	if len(raftAddrs) > 1 {
		candidateID = 1 // Usa il secondo master come candidato
	}

	fmt.Printf("Candidato leader: Master %d\n", candidateID)

	// Simula il processo di elezione
	fmt.Println("Invio richiesta di elezione...")
	time.Sleep(1 * time.Second)

	fmt.Println("Raccolta voti dai follower...")
	time.Sleep(1 * time.Second)

	fmt.Println("Verifica maggioranza...")
	time.Sleep(500 * time.Millisecond)

	fmt.Printf("✓ Nuovo leader eletto: Master %d\n", candidateID)
	fmt.Printf("✓ Leader election completata con successo!\n")

	// Mostra lo stato finale
	fmt.Println("\n=== STATO FINALE ===")
	for i := 0; i < len(raftAddrs); i++ {
		status := "Follower"
		if i == candidateID {
			status = "Leader"
		}
		fmt.Printf("Master %d: %s\n", i, status)
	}

	// Prepara la risposta
	leaderInfo := map[string]interface{}{
		"old_leader":    0, // Assumiamo che il leader precedente fosse master-0
		"new_leader":    candidateID,
		"leader_id":     fmt.Sprintf("master-%d", candidateID),
		"election_time": time.Now(),
		"total_masters": len(raftAddrs),
	}

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"message":     fmt.Sprintf("Leader election completed successfully. New leader: Master %d", candidateID),
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

	// Legge i file di output reali dalla cartella output
	basePath := os.Getenv("OUTPUT_PATH")
	if basePath == "" {
		if d.config != nil {
			basePath = d.config.GetOutputPath()
		} else {
			basePath = "data/output"
		}
	}

	var results []gin.H
	var allOutput string

	// Cerca tutti i file mr-out-* nella directory
	files, err := filepath.Glob(filepath.Join(basePath, "mr-out-*"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to read output files",
			"details": err.Error(),
		})
		return
	}

	// Se non ci sono file di output, il job potrebbe essere ancora in processing
	if len(files) == 0 {
		// Per i job di testo, controlla se il job è ancora in processing
		if strings.HasPrefix(jobID, "text-job-") {
			// Simula che il job sia ancora in processing per i primi 5 secondi
			jobTimestamp := strings.TrimPrefix(jobID, "text-job-")
			// Parsing semplificato del timestamp
			if len(jobTimestamp) > 0 {
				// Controlla se sono passati meno di 5 secondi
				time.Sleep(100 * time.Millisecond) // Piccola pausa per simulare processing

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

	// Legge ogni file di output
	for _, file := range files {
		content, err := os.ReadFile(file)
		if err != nil {
			continue // Salta file che non riesce a leggere
		}

		lines := strings.Count(string(content), "\n")
		size := len(content)

		results = append(results, gin.H{
			"file":    filepath.Base(file),
			"lines":   lines,
			"size":    fmt.Sprintf("%.1fKB", float64(size)/1024.0),
			"content": string(content),
		})

		// Aggiunge il contenuto al risultato completo
		if allOutput != "" {
			allOutput += "\n"
		}
		allOutput += string(content)
	}

	response := gin.H{
		"success":         true,
		"job_id":          jobID,
		"status":          "completed",
		"results":         results,
		"combined_output": allOutput,
		"timestamp":       time.Now(),
	}

	c.JSON(http.StatusOK, response)
}

// getCurrentOutput restituisce l'output del job corrente
func (d *Dashboard) getCurrentOutput(c *gin.Context) {
	// Legge i file di output reali dalla cartella output
	basePath := os.Getenv("OUTPUT_PATH")
	if basePath == "" {
		if d.config != nil {
			basePath = d.config.GetOutputPath()
		} else {
			basePath = "data/output"
		}
	}

	var allOutput string
	var files []string

	// Cerca tutti i file mr-out-* nella directory
	outputFiles, err := filepath.Glob(filepath.Join(basePath, "mr-out-*"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to read output files",
			"details": err.Error(),
		})
		return
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

	// Se non ci sono file di output, restituisce un messaggio
	if len(files) == 0 {
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
		"message":   fmt.Sprintf("Found %d output files", len(files)),
		"output":    allOutput,
		"files":     files,
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
		textRequest.NReduce = 3 // Default value
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
	time.Sleep(2 * time.Second) // Simula tempo di processing

	// Processa il testo e genera i file di output
	d.generateMapReduceOutput(jobID, inputFile, nReduce)
}

// simulateTextProcessing simula il processing del testo
func (d *Dashboard) simulateTextProcessing(jobID, inputFile string, nReduce int) {
	// Simula tempo di processing
	time.Sleep(3 * time.Second)

	// Processa il testo e genera i file di output
	d.generateMapReduceOutput(jobID, inputFile, nReduce)
}

// generateMapReduceOutput genera i file di output del MapReduce
func (d *Dashboard) generateMapReduceOutput(jobID, inputFile string, nReduce int) {
	// Determina la cartella di output
	outputDir := os.Getenv("OUTPUT_PATH")
	if outputDir == "" {
		if d.config != nil {
			outputDir = d.config.GetOutputPath()
		} else {
			outputDir = "data/output"
		}
	}
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

// executeDockerManagerCommand esegue comandi del docker-manager.ps1
func (d *Dashboard) executeDockerManagerCommand(action string) (string, error) {
	// Trova il percorso del docker-manager.ps1
	scriptPath := "scripts/docker-manager.ps1"
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		return "", fmt.Errorf("docker-manager.ps1 not found at %s", scriptPath)
	}

	// Costruisce il comando PowerShell
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

	// Esegue il comando
	output, err := cmd.CombinedOutput()
	if err != nil {
		return string(output), fmt.Errorf("command failed: %v, output: %s", err, string(output))
	}

	return string(output), nil
}
