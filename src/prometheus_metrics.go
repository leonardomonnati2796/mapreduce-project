package main

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// PrometheusMetrics gestisce tutte le metriche Prometheus per il dashboard
type PrometheusMetrics struct {
	// Metriche del dashboard
	DashboardUptime        prometheus.Gauge
	DashboardRequests     prometheus.Counter
	DashboardErrors       prometheus.Counter
	DashboardResponseTime prometheus.Histogram
	
	// Metriche WebSocket
	WebSocketConnections  prometheus.Gauge
	WebSocketMessages     prometheus.Counter
	WebSocketErrors       prometheus.Counter
	
	// Metriche di cache
	CacheHits             prometheus.Counter
	CacheMisses           prometheus.Counter
	CacheSize             prometheus.Gauge
	
	// Metriche di performance
	DataCollectionTime    prometheus.Histogram
	MemoryPoolUsage       prometheus.Gauge
	ConcurrentRequests    prometheus.Gauge
	
	// Metriche del sistema
	SystemHealth          prometheus.Gauge
	LoadBalancerHealth    prometheus.Gauge
	S3Health              prometheus.Gauge
	
	// Metriche dei job
	JobsTotal             prometheus.Counter
	JobsActive            prometheus.Gauge
	JobsCompleted         prometheus.Counter
	JobsFailed            prometheus.Counter
	
	// Metriche dei worker
	WorkersTotal          prometheus.Gauge
	WorkersActive         prometheus.Gauge
	WorkersDegraded       prometheus.Gauge
	WorkersFailed         prometheus.Gauge
	
	// Metriche dei master
	MastersTotal          prometheus.Gauge
	MastersActive         prometheus.Gauge
	MastersLeader         prometheus.Gauge
}

// NewPrometheusMetrics crea una nuova istanza delle metriche Prometheus
func NewPrometheusMetrics() *PrometheusMetrics {
	return &PrometheusMetrics{
		// Metriche del dashboard
		DashboardUptime: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "dashboard_uptime_seconds",
			Help: "Tempo di uptime del dashboard in secondi",
		}),
		DashboardRequests: promauto.NewCounter(prometheus.CounterOpts{
			Name: "dashboard_requests_total",
			Help: "Numero totale di richieste al dashboard",
		}),
		DashboardErrors: promauto.NewCounter(prometheus.CounterOpts{
			Name: "dashboard_errors_total",
			Help: "Numero totale di errori del dashboard",
		}),
		DashboardResponseTime: promauto.NewHistogram(prometheus.HistogramOpts{
			Name:    "dashboard_response_time_seconds",
			Help:    "Tempo di risposta del dashboard in secondi",
			Buckets: prometheus.DefBuckets,
		}),
		
		// Metriche WebSocket
		WebSocketConnections: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "websocket_connections_active",
			Help: "Numero di connessioni WebSocket attive",
		}),
		WebSocketMessages: promauto.NewCounter(prometheus.CounterOpts{
			Name: "websocket_messages_total",
			Help: "Numero totale di messaggi WebSocket inviati",
		}),
		WebSocketErrors: promauto.NewCounter(prometheus.CounterOpts{
			Name: "websocket_errors_total",
			Help: "Numero totale di errori WebSocket",
		}),
		
		// Metriche di cache
		CacheHits: promauto.NewCounter(prometheus.CounterOpts{
			Name: "cache_hits_total",
			Help: "Numero totale di cache hits",
		}),
		CacheMisses: promauto.NewCounter(prometheus.CounterOpts{
			Name: "cache_misses_total",
			Help: "Numero totale di cache misses",
		}),
		CacheSize: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "cache_size_bytes",
			Help: "Dimensione della cache in bytes",
		}),
		
		// Metriche di performance
		DataCollectionTime: promauto.NewHistogram(prometheus.HistogramOpts{
			Name:    "data_collection_time_seconds",
			Help:    "Tempo impiegato per raccogliere i dati in secondi",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
		}),
		MemoryPoolUsage: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "memory_pool_usage_ratio",
			Help: "Rapporto di utilizzo dei pool di memoria (0-1)",
		}),
		ConcurrentRequests: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "concurrent_requests",
			Help: "Numero di richieste concorrenti",
		}),
		
		// Metriche del sistema
		SystemHealth: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "system_health_status",
			Help: "Stato di salute del sistema (1=healthy, 0=unhealthy)",
		}),
		LoadBalancerHealth: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "load_balancer_health_status",
			Help: "Stato di salute del load balancer (1=healthy, 0=unhealthy)",
		}),
		S3Health: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "s3_health_status",
			Help: "Stato di salute di S3 (1=healthy, 0=unhealthy)",
		}),
		
		// Metriche dei job
		JobsTotal: promauto.NewCounter(prometheus.CounterOpts{
			Name: "jobs_total",
			Help: "Numero totale di job processati",
		}),
		JobsActive: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "jobs_active",
			Help: "Numero di job attivi",
		}),
		JobsCompleted: promauto.NewCounter(prometheus.CounterOpts{
			Name: "jobs_completed_total",
			Help: "Numero totale di job completati",
		}),
		JobsFailed: promauto.NewCounter(prometheus.CounterOpts{
			Name: "jobs_failed_total",
			Help: "Numero totale di job falliti",
		}),
		
		// Metriche dei worker
		WorkersTotal: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "workers_total",
			Help: "Numero totale di worker",
		}),
		WorkersActive: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "workers_active",
			Help: "Numero di worker attivi",
		}),
		WorkersDegraded: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "workers_degraded",
			Help: "Numero di worker degradati",
		}),
		WorkersFailed: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "workers_failed",
			Help: "Numero di worker falliti",
		}),
		
		// Metriche dei master
		MastersTotal: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "masters_total",
			Help: "Numero totale di master",
		}),
		MastersActive: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "masters_active",
			Help: "Numero di master attivi",
		}),
		MastersLeader: promauto.NewGauge(prometheus.GaugeOpts{
			Name: "masters_leader",
			Help: "Numero di master leader (dovrebbe essere 0 o 1)",
		}),
	}
}

// UpdateDashboardMetrics aggiorna le metriche del dashboard
func (pm *PrometheusMetrics) UpdateDashboardMetrics(uptime time.Duration, requests, errors int64, responseTime time.Duration) {
	pm.DashboardUptime.Set(uptime.Seconds())
	pm.DashboardRequests.Add(float64(requests))
	pm.DashboardErrors.Add(float64(errors))
	pm.DashboardResponseTime.Observe(responseTime.Seconds())
}

// UpdateWebSocketMetrics aggiorna le metriche WebSocket
func (pm *PrometheusMetrics) UpdateWebSocketMetrics(connections int, messages, errors int64) {
	pm.WebSocketConnections.Set(float64(connections))
	pm.WebSocketMessages.Add(float64(messages))
	pm.WebSocketErrors.Add(float64(errors))
}

// UpdateCacheMetrics aggiorna le metriche di cache
func (pm *PrometheusMetrics) UpdateCacheMetrics(hits, misses int64, size int64) {
	pm.CacheHits.Add(float64(hits))
	pm.CacheMisses.Add(float64(misses))
	pm.CacheSize.Set(float64(size))
}

// UpdatePerformanceMetrics aggiorna le metriche di performance
func (pm *PrometheusMetrics) UpdatePerformanceMetrics(collectionTime time.Duration, poolUsage float64, concurrentRequests int) {
	pm.DataCollectionTime.Observe(collectionTime.Seconds())
	pm.MemoryPoolUsage.Set(poolUsage)
	pm.ConcurrentRequests.Set(float64(concurrentRequests))
}

// UpdateSystemMetrics aggiorna le metriche del sistema
func (pm *PrometheusMetrics) UpdateSystemMetrics(systemHealthy, lbHealthy, s3Healthy bool) {
	if systemHealthy {
		pm.SystemHealth.Set(1)
	} else {
		pm.SystemHealth.Set(0)
	}
	
	if lbHealthy {
		pm.LoadBalancerHealth.Set(1)
	} else {
		pm.LoadBalancerHealth.Set(0)
	}
	
	if s3Healthy {
		pm.S3Health.Set(1)
	} else {
		pm.S3Health.Set(0)
	}
}

// UpdateJobMetrics aggiorna le metriche dei job
func (pm *PrometheusMetrics) UpdateJobMetrics(total, active, completed, failed int64) {
	pm.JobsTotal.Add(float64(total))
	pm.JobsActive.Set(float64(active))
	pm.JobsCompleted.Add(float64(completed))
	pm.JobsFailed.Add(float64(failed))
}

// UpdateWorkerMetrics aggiorna le metriche dei worker
func (pm *PrometheusMetrics) UpdateWorkerMetrics(total, active, degraded, failed int) {
	pm.WorkersTotal.Set(float64(total))
	pm.WorkersActive.Set(float64(active))
	pm.WorkersDegraded.Set(float64(degraded))
	pm.WorkersFailed.Set(float64(failed))
}

// UpdateMasterMetrics aggiorna le metriche dei master
func (pm *PrometheusMetrics) UpdateMasterMetrics(total, active, leader int) {
	pm.MastersTotal.Set(float64(total))
	pm.MastersActive.Set(float64(active))
	pm.MastersLeader.Set(float64(leader))
}

// GetCacheHitRatio calcola il rapporto di cache hit
func (pm *PrometheusMetrics) GetCacheHitRatio() float64 {
	// Questa è una semplificazione - in un'implementazione reale
	// dovresti tracciare i valori correnti
	return 0.85 // Esempio: 85% cache hit ratio
}

// GetSystemHealthScore calcola un punteggio di salute del sistema
func (pm *PrometheusMetrics) GetSystemHealthScore() float64 {
	// Calcola un punteggio basato su varie metriche
	// Questo è un esempio semplificato
	return 0.95 // Esempio: 95% di salute del sistema
}
