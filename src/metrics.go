package main

import (
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Constants for metrics configuration
const (
	// DefaultHistogramBuckets represents the default number of histogram buckets
	DefaultHistogramBuckets = 20
	// DefaultExponentialBase represents the base for exponential buckets
	DefaultExponentialBase = 2.0
	// MinMetricsFileSize represents the minimum file size to record in metrics
	MinMetricsFileSize = int64(0)
)

// Prometheus metrics per il sistema MapReduce
var (
	// Metriche per task
	tasksTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "mapreduce_tasks_total",
			Help: "Total number of tasks processed",
		},
		[]string{"type", "status"},
	)

	taskDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "mapreduce_task_duration_seconds",
			Help:    "Task execution duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"type"},
	)

	// Metriche per Raft
	raftState = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mapreduce_raft_state",
			Help: "Current Raft state (0=Follower, 1=Candidate, 2=Leader)",
		},
		[]string{"node_id"},
	)

	// Metriche per RPC
	rpcRequests = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "mapreduce_rpc_requests_total",
			Help: "Total number of RPC requests",
		},
		[]string{"method", "status"},
	)

	rpcDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "mapreduce_rpc_duration_seconds",
			Help:    "RPC request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method"},
	)

	// Metriche per job
	jobPhase = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mapreduce_job_phase",
			Help: "Current job phase (0=Map, 1=Reduce, 2=Done)",
		},
		[]string{"master_id"},
	)

	jobDuration = promauto.NewHistogram(
		prometheus.HistogramOpts{
			Name:    "mapreduce_job_duration_seconds",
			Help:    "Total job duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
	)

	// Metriche per worker
	workerConnections = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mapreduce_worker_connections",
			Help: "Number of active worker connections",
		},
		[]string{"master_id"},
	)

	// Metriche per file I/O
	fileOperations = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "mapreduce_file_operations_total",
			Help: "Total number of file operations",
		},
		[]string{"operation", "status"},
	)

	fileSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "mapreduce_file_size_bytes",
			Help:    "File size in bytes",
			Buckets: prometheus.ExponentialBuckets(1024, 2, 20),
		},
		[]string{"type"},
	)
)

// MetricCollector gestisce la raccolta delle metriche in modo thread-safe
type MetricCollector struct {
	jobStartTime time.Time
	mu           sync.RWMutex
}

// NewMetricCollector crea un nuovo collector di metriche
// Il collector è thread-safe e può essere utilizzato concorrentemente
func NewMetricCollector() *MetricCollector {
	return &MetricCollector{}
}

// RecordTaskCompletion registra il completamento di un task con la sua durata
// taskType deve essere "map" o "reduce", duration deve essere positiva
func (mc *MetricCollector) RecordTaskCompletion(taskType string, duration time.Duration) {
	if taskType == "" || duration < 0 {
		return // Ignora valori non validi
	}
	tasksTotal.WithLabelValues(taskType, "completed").Inc()
	taskDuration.WithLabelValues(taskType).Observe(duration.Seconds())
}

// RecordTaskFailure registra il fallimento di un task
// taskType deve essere "map" o "reduce"
func (mc *MetricCollector) RecordTaskFailure(taskType string) {
	if taskType == "" {
		return // Ignora valori non validi
	}
	tasksTotal.WithLabelValues(taskType, "failed").Inc()
}

// RecordRaftState registra lo stato corrente di Raft per un nodo
// nodeID identifica il nodo, state deve essere 0=Follower, 1=Candidate, 2=Leader
func (mc *MetricCollector) RecordRaftState(nodeID string, state int) {
	if nodeID == "" || state < 0 || state > 2 {
		return // Ignora valori non validi
	}
	raftState.WithLabelValues(nodeID).Set(float64(state))
}

// RecordRPCRequest registra una richiesta RPC con la sua durata e stato
// method identifica il metodo RPC, duration deve essere positiva, success indica se la richiesta è riuscita
func (mc *MetricCollector) RecordRPCRequest(method string, duration time.Duration, success bool) {
	if method == "" || duration < 0 {
		return // Ignora valori non validi
	}
	status := "success"
	if !success {
		status = "error"
	}
	rpcRequests.WithLabelValues(method, status).Inc()
	rpcDuration.WithLabelValues(method).Observe(duration.Seconds())
}

// RecordJobPhase registra la fase corrente del job per un master
// masterID identifica il master, phase deve essere 0=Map, 1=Reduce, 2=Done
func (mc *MetricCollector) RecordJobPhase(masterID string, phase int) {
	if masterID == "" || phase < 0 || phase > 2 {
		return // Ignora valori non validi
	}
	jobPhase.WithLabelValues(masterID).Set(float64(phase))
}

// RecordJobCompletion registra il completamento del job e calcola la durata totale
// Deve essere chiamato dopo SetJobStartTime per calcolare correttamente la durata
func (mc *MetricCollector) RecordJobCompletion() {
	mc.mu.RLock()
	startTime := mc.jobStartTime
	mc.mu.RUnlock()

	if !startTime.IsZero() {
		jobDuration.Observe(time.Since(startTime).Seconds())
	}
}

// RecordWorkerConnection registra una connessione o disconnessione di un worker
// masterID identifica il master, connected indica se il worker si sta connettendo o disconnettendo
func (mc *MetricCollector) RecordWorkerConnection(masterID string, connected bool) {
	if masterID == "" {
		return // Ignora valori non validi
	}
	if connected {
		workerConnections.WithLabelValues(masterID).Inc()
	} else {
		workerConnections.WithLabelValues(masterID).Dec()
	}
}

// RecordFileOperation registra un'operazione su file con il suo risultato e dimensione
// operation identifica il tipo di operazione, success indica se l'operazione è riuscita,
// size è la dimensione del file in bytes (0 se non applicabile)
func (mc *MetricCollector) RecordFileOperation(operation string, success bool, size int64) {
	if operation == "" || size < MinMetricsFileSize {
		return // Ignora valori non validi
	}
	status := "success"
	if !success {
		status = "error"
	}
	fileOperations.WithLabelValues(operation, status).Inc()
	if size > MinMetricsFileSize {
		fileSize.WithLabelValues(operation).Observe(float64(size))
	}
}

// SetJobStartTime imposta il tempo di inizio del job per il calcolo della durata
// Deve essere chiamato prima di RecordJobCompletion
func (mc *MetricCollector) SetJobStartTime() {
	mc.mu.Lock()
	defer mc.mu.Unlock()
	mc.jobStartTime = time.Now()
}

// GetJobStartTime restituisce il tempo di inizio del job in modo thread-safe
func (mc *MetricCollector) GetJobStartTime() time.Time {
	mc.mu.RLock()
	defer mc.mu.RUnlock()
	return mc.jobStartTime
}
