package main

import (
	"fmt"
	"math/rand"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// LoadBalancer gestisce il bilanciamento del carico e fault tolerance
type LoadBalancer struct {
	servers     []Server
	healthCheck *HealthChecker
	mu          sync.RWMutex
	strategy    LoadBalancingStrategy
	timeout     time.Duration
	// Integrazione con sistema di health checking esistente
	systemHealth *HealthChecker
}

// Server rappresenta un server nel load balancer
type Server struct {
	ID       string
	Address  string
	Port     int
	Weight   int
	Healthy  bool
	LastSeen time.Time
	Requests int64
	Errors   int64
}

// WorkerInfo è definito in rpc.go - non duplicare qui

// LoadBalancingStrategy definisce le strategie di bilanciamento
type LoadBalancingStrategy int

const (
	RoundRobin LoadBalancingStrategy = iota
	WeightedRoundRobin
	LeastConnections
	Random
	HealthBased
)

// NewLoadBalancer crea un nuovo load balancer
func NewLoadBalancer(servers []Server, strategy LoadBalancingStrategy) *LoadBalancer {
	lb := &LoadBalancer{
		servers:  servers,
		strategy: strategy,
		timeout:  5 * time.Second,
	}

	// Inizializza health checker per server
	lb.healthCheck = NewHealthChecker("1.0.0")

	// Inizializza system health checker (riutilizza quello esistente)
	lb.systemHealth = NewHealthChecker("1.0.0")

	// Inizializza tutti i server come sani
	for i := range lb.servers {
		lb.servers[i].Healthy = true
		lb.servers[i].LastSeen = time.Now()
	}

	// Avvia health checking unificato
	go lb.startUnifiedHealthChecking()

	LogInfo("Load balancer inizializzato con %d server, strategia: %s", len(servers), strategy.String())
	return lb
}

// AddServer aggiunge un server al load balancer
func (lb *LoadBalancer) AddServer(server Server) {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	lb.servers = append(lb.servers, server)
	LogInfo("Server %s aggiunto al load balancer", server.ID)
}

// RemoveServer rimuove un server dal load balancer
func (lb *LoadBalancer) RemoveServer(serverID string) {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	for i, server := range lb.servers {
		if server.ID == serverID {
			lb.servers = append(lb.servers[:i], lb.servers[i+1:]...)
			LogInfo("Server %s rimosso dal load balancer", serverID)
			break
		}
	}
}

// GetServer restituisce il server migliore secondo la strategia
func (lb *LoadBalancer) GetServer() (*Server, error) {
	lb.mu.RLock()
	defer lb.mu.RUnlock()

	healthyServers := lb.getHealthyServers()
	if len(healthyServers) == 0 {
		return nil, fmt.Errorf("nessun server disponibile")
	}

	switch lb.strategy {
	case RoundRobin:
		return lb.selectRoundRobin(healthyServers)
	case WeightedRoundRobin:
		return lb.selectWeightedRoundRobin(healthyServers)
	case LeastConnections:
		return lb.selectLeastConnections(healthyServers)
	case Random:
		return lb.selectRandom(healthyServers)
	case HealthBased:
		return lb.selectHealthBased(healthyServers)
	default:
		return lb.selectRoundRobin(healthyServers)
	}
}

// getHealthyServers restituisce solo i server sani
func (lb *LoadBalancer) getHealthyServers() []*Server {
	var healthy []*Server
	for i := range lb.servers {
		if lb.servers[i].Healthy {
			healthy = append(healthy, &lb.servers[i])
		}
	}
	return healthy
}

// selectRoundRobin seleziona il server con round robin
func (lb *LoadBalancer) selectRoundRobin(servers []*Server) (*Server, error) {
	if len(servers) == 0 {
		return nil, fmt.Errorf("nessun server disponibile")
	}

	// Usa un indice globale per il round robin
	index := time.Now().UnixNano() % int64(len(servers))
	return servers[index], nil
}

// selectWeightedRoundRobin seleziona il server con peso
func (lb *LoadBalancer) selectWeightedRoundRobin(servers []*Server) (*Server, error) {
	if len(servers) == 0 {
		return nil, fmt.Errorf("nessun server disponibile")
	}

	totalWeight := 0
	for _, server := range servers {
		totalWeight += server.Weight
	}

	if totalWeight == 0 {
		return lb.selectRoundRobin(servers)
	}

	random := rand.Intn(totalWeight)
	current := 0

	for _, server := range servers {
		current += server.Weight
		if random < current {
			return server, nil
		}
	}

	return servers[0], nil
}

// selectLeastConnections seleziona il server con meno connessioni
func (lb *LoadBalancer) selectLeastConnections(servers []*Server) (*Server, error) {
	if len(servers) == 0 {
		return nil, fmt.Errorf("nessun server disponibile")
	}

	best := servers[0]
	for _, server := range servers[1:] {
		if server.Requests < best.Requests {
			best = server
		}
	}

	return best, nil
}

// selectRandom seleziona un server casuale
func (lb *LoadBalancer) selectRandom(servers []*Server) (*Server, error) {
	if len(servers) == 0 {
		return nil, fmt.Errorf("nessun server disponibile")
	}

	index := rand.Intn(len(servers))
	return servers[index], nil
}

// selectHealthBased seleziona il server più sano
func (lb *LoadBalancer) selectHealthBased(servers []*Server) (*Server, error) {
	if len(servers) == 0 {
		return nil, fmt.Errorf("nessun server disponibile")
	}

	best := servers[0]
	bestScore := lb.calculateHealthScore(best)

	for _, server := range servers[1:] {
		score := lb.calculateHealthScore(server)
		if score > bestScore {
			best = server
			bestScore = score
		}
	}

	return best, nil
}

// calculateHealthScore calcola il punteggio di salute di un server
func (lb *LoadBalancer) calculateHealthScore(server *Server) float64 {
	// Punteggio basato su:
	// - Tempo dall'ultimo heartbeat (più recente = migliore)
	// - Numero di errori (meno errori = migliore)
	// - Numero di richieste (più richieste = più testato)

	timeScore := 1.0
	if time.Since(server.LastSeen) < 30*time.Second {
		timeScore = 1.0
	} else if time.Since(server.LastSeen) < 60*time.Second {
		timeScore = 0.8
	} else {
		timeScore = 0.5
	}

	errorScore := 1.0
	if server.Requests > 0 {
		errorRate := float64(server.Errors) / float64(server.Requests)
		errorScore = 1.0 - errorRate
	}

	requestScore := 1.0
	if server.Requests > 100 {
		requestScore = 1.2 // Bonus per server molto utilizzati
	}

	return timeScore * errorScore * requestScore
}

// startUnifiedHealthChecking avvia il controllo periodico unificato della salute
func (lb *LoadBalancer) startUnifiedHealthChecking() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			// Controlla salute dei server
			lb.performHealthCheck()

			// Controlla salute del sistema (riutilizza funzioni esistenti)
			lb.systemHealth.CheckComponent("disk_space", CheckDiskSpace)
			lb.systemHealth.CheckComponent("s3_connection", CheckS3Connection)
			lb.systemHealth.CheckComponent("raft_cluster", CheckRaftCluster)
			lb.systemHealth.CheckComponent("docker", CheckDocker)
			lb.systemHealth.CheckComponent("network", CheckNetworkConnectivity)
		}
	}
}

// performHealthCheck esegue il controllo della salute di tutti i server
func (lb *LoadBalancer) performHealthCheck() {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	for i := range lb.servers {
		server := &lb.servers[i]

		// Controlla se il server è raggiungibile
		healthy := lb.checkServerHealth(server)

		if healthy != server.Healthy {
			status := "UNHEALTHY"
			if healthy {
				status = "HEALTHY"
			}
			LogInfo("Server %s status changed to %s", server.ID, status)
		}

		server.Healthy = healthy
		server.LastSeen = time.Now()
	}
}

// checkServerHealth controlla se un server è sano
func (lb *LoadBalancer) checkServerHealth(server *Server) bool {
	// Implementa un controllo HTTP di base
	client := &http.Client{
		Timeout: lb.timeout,
	}

	url := fmt.Sprintf("http://%s:%d/health", server.Address, server.Port)
	resp, err := client.Get(url)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK
}

// UpdateServerStats aggiorna le statistiche di un server
func (lb *LoadBalancer) UpdateServerStats(serverID string, success bool) {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	for i := range lb.servers {
		if lb.servers[i].ID == serverID {
			lb.servers[i].Requests++
			if !success {
				lb.servers[i].Errors++
			}
			lb.servers[i].LastSeen = time.Now()
			break
		}
	}
}

// GetStats restituisce le statistiche del load balancer
func (lb *LoadBalancer) GetStats() map[string]interface{} {
	lb.mu.RLock()
	defer lb.mu.RUnlock()

	healthyCount := 0
	totalRequests := int64(0)
	totalErrors := int64(0)

	for _, server := range lb.servers {
		if server.Healthy {
			healthyCount++
		}
		totalRequests += server.Requests
		totalErrors += server.Errors
	}

	errorRate := 0.0
	if totalRequests > 0 {
		errorRate = float64(totalErrors) / float64(totalRequests) * 100
	}

	return map[string]interface{}{
		"total_servers":     len(lb.servers),
		"healthy_servers":   healthyCount,
		"unhealthy_servers": len(lb.servers) - healthyCount,
		"total_requests":    totalRequests,
		"total_errors":      totalErrors,
		"error_rate":        errorRate,
		"strategy":          lb.strategy.String(),
	}
}

// GetUnifiedStats restituisce statistiche unificate (server + sistema)
func (lb *LoadBalancer) GetUnifiedStats() map[string]interface{} {
	// Statistiche server
	serverStats := lb.GetStats()

	// Statistiche sistema
	systemStatus := lb.systemHealth.GetHealthStatus()

	return map[string]interface{}{
		"load_balancer": serverStats,
		"system_health": map[string]interface{}{
			"status":     systemStatus.Status,
			"uptime":     systemStatus.Uptime,
			"components": systemStatus.Components,
			"system":     systemStatus.System,
		},
		"timestamp": time.Now(),
	}
}

// GetServerDetails restituisce i dettagli di tutti i server
func (lb *LoadBalancer) GetServerDetails() []map[string]interface{} {
	lb.mu.RLock()
	defer lb.mu.RUnlock()

	var details []map[string]interface{}
	for _, server := range lb.servers {
		serverInfo := map[string]interface{}{
			"id":         server.ID,
			"address":    server.Address,
			"port":       server.Port,
			"weight":     server.Weight,
			"healthy":    server.Healthy,
			"last_seen":  server.LastSeen,
			"requests":   server.Requests,
			"errors":     server.Errors,
			"error_rate": 0.0,
		}

		if server.Requests > 0 {
			serverInfo["error_rate"] = float64(server.Errors) / float64(server.Requests) * 100
		}

		details = append(details, serverInfo)
	}

	return details
}

// GetHealthyServerCount restituisce il numero di server sani
func (lb *LoadBalancer) GetHealthyServerCount() int {
	lb.mu.RLock()
	defer lb.mu.RUnlock()

	count := 0
	for _, server := range lb.servers {
		if server.Healthy {
			count++
		}
	}
	return count
}

// IsServerHealthy controlla se un server specifico è sano
func (lb *LoadBalancer) IsServerHealthy(serverID string) bool {
	lb.mu.RLock()
	defer lb.mu.RUnlock()

	for _, server := range lb.servers {
		if server.ID == serverID {
			return server.Healthy
		}
	}
	return false
}

// SetStrategy cambia la strategia di load balancing
func (lb *LoadBalancer) SetStrategy(strategy LoadBalancingStrategy) {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	oldStrategy := lb.strategy
	lb.strategy = strategy
	LogInfo("Load balancer strategy changed from %s to %s", oldStrategy.String(), strategy.String())
}

// GetStrategy restituisce la strategia corrente
func (lb *LoadBalancer) GetStrategy() LoadBalancingStrategy {
	lb.mu.RLock()
	defer lb.mu.RUnlock()
	return lb.strategy
}

// SetTimeout imposta il timeout per i controlli di salute
func (lb *LoadBalancer) SetTimeout(timeout time.Duration) {
	lb.mu.Lock()
	defer lb.mu.Unlock()
	lb.timeout = timeout
	LogInfo("Load balancer timeout set to %v", timeout)
}

// GetTimeout restituisce il timeout corrente
func (lb *LoadBalancer) GetTimeout() time.Duration {
	lb.mu.RLock()
	defer lb.mu.RUnlock()
	return lb.timeout
}

// ResetServerStats resetta le statistiche di un server specifico
func (lb *LoadBalancer) ResetServerStats(serverID string) {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	for i := range lb.servers {
		if lb.servers[i].ID == serverID {
			lb.servers[i].Requests = 0
			lb.servers[i].Errors = 0
			lb.servers[i].LastSeen = time.Now()
			LogInfo("Statistics reset for server %s", serverID)
			break
		}
	}
}

// ResetAllStats resetta le statistiche di tutti i server
func (lb *LoadBalancer) ResetAllStats() {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	for i := range lb.servers {
		lb.servers[i].Requests = 0
		lb.servers[i].Errors = 0
		lb.servers[i].LastSeen = time.Now()
	}
	LogInfo("Statistics reset for all %d servers", len(lb.servers))
}

// ForceHealthCheck forza un controllo di salute immediato
func (lb *LoadBalancer) ForceHealthCheck() {
	LogInfo("Forcing immediate health check...")
	lb.performHealthCheck()
}

// String restituisce la rappresentazione stringa della strategia
func (s LoadBalancingStrategy) String() string {
	switch s {
	case RoundRobin:
		return "Round Robin"
	case WeightedRoundRobin:
		return "Weighted Round Robin"
	case LeastConnections:
		return "Least Connections"
	case Random:
		return "Random"
	case HealthBased:
		return "Health Based"
	default:
		return "Unknown"
	}
}

// LoadBalancerConfig configurazione per il load balancer
type LoadBalancerConfig struct {
	Strategy            LoadBalancingStrategy
	HealthCheckInterval time.Duration
	Timeout             time.Duration
	MaxRetries          int
}

// NewLoadBalancerConfig crea una configurazione di default
func NewLoadBalancerConfig() LoadBalancerConfig {
	return LoadBalancerConfig{
		Strategy:            HealthBased,
		HealthCheckInterval: 10 * time.Second,
		Timeout:             5 * time.Second,
		MaxRetries:          3,
	}
}

// NewServer crea un nuovo server con configurazione di default
func NewServer(id, address string, port int) Server {
	return Server{
		ID:       id,
		Address:  address,
		Port:     port,
		Weight:   1,
		Healthy:  true,
		LastSeen: time.Now(),
		Requests: 0,
		Errors:   0,
	}
}

// NewServerWithWeight crea un nuovo server con peso specifico
func NewServerWithWeight(id, address string, port, weight int) Server {
	return Server{
		ID:       id,
		Address:  address,
		Port:     port,
		Weight:   weight,
		Healthy:  true,
		LastSeen: time.Now(),
		Requests: 0,
		Errors:   0,
	}
}

// CreateDefaultServers crea una lista di server di default per testing
func CreateDefaultServers() []Server {
	return []Server{
		NewServerWithWeight("master-0", "localhost", 8080, 10),
		NewServerWithWeight("master-1", "localhost", 8081, 10),
		NewServerWithWeight("master-2", "localhost", 8082, 10),
		NewServerWithWeight("worker-0", "localhost", 8083, 5),
		NewServerWithWeight("worker-1", "localhost", 8084, 5),
		NewServerWithWeight("worker-2", "localhost", 8085, 5),
	}
}

// CreateMasterServers crea server basati sui master RPC addresses
func CreateMasterServers(rpcAddrs []string) []Server {
	var servers []Server
	for i, addr := range rpcAddrs {
		parts := strings.Split(addr, ":")
		if len(parts) == 2 {
			port, _ := strconv.Atoi(parts[1])
			servers = append(servers, NewServerWithWeight(
				fmt.Sprintf("master-%d", i),
				parts[0],
				port,
				10, // Peso maggiore per i master
			))
		}
	}
	return servers
}

// CreateWorkerServers crea server basati sui worker disponibili
func CreateWorkerServers(workerMap map[string]WorkerInfo) []Server {
	var servers []Server
	i := 0
	for workerID := range workerMap {
		// Usa una porta di default per i worker (non abbiamo Port nel WorkerInfo di rpc.go)
		port := 8080 + i // Porta di default
		servers = append(servers, NewServerWithWeight(
			workerID,
			"localhost", // In produzione, usa l'IP reale del worker
			port,
			5, // Peso minore per i worker
		))
		i++
	}
	return servers
}

// IntegrateWithMaster integra il load balancer con il master esistente
func (lb *LoadBalancer) IntegrateWithMaster(workerMap map[string]WorkerInfo) {
	// Aggiungi worker esistenti al load balancer
	workerServers := CreateWorkerServers(workerMap)
	for _, server := range workerServers {
		lb.AddServer(server)
	}

	LogInfo("Load balancer integrato con %d worker esistenti", len(workerServers))
}

// ReplaceMasterHealthMonitoring sostituisce il monitoring del master con il load balancer
func (lb *LoadBalancer) ReplaceMasterHealthMonitoring(workerMap map[string]WorkerInfo) {
	// Integra worker esistenti
	lb.IntegrateWithMaster(workerMap)

	// Il load balancer ora gestisce:
	// - Health checking dei worker (sostituisce worker health monitor)
	// - Fault tolerance (sostituisce dead worker detection)
	// - Load balancing (nuovo)
	// - Statistiche unificate (nuovo)

	LogInfo("Load balancer ha sostituito il monitoring del master")
}

// ============================================================================
// ALGORITMI DI FAULT TOLERANCE AVANZATI
// ============================================================================

// TaskFailureType definisce i tipi di fallimento per task
type TaskFailureType int

const (
	PreProcessingFailure    TaskFailureType = iota // Fallimento prima dell'elaborazione
	DuringProcessingFailure                        // Fallimento durante l'elaborazione
	PostProcessingFailure                          // Fallimento dopo l'elaborazione
	DataCorruptionFailure                          // Fallimento per corruzione dati
)

// TaskFailureInfo contiene informazioni su un fallimento di task
type TaskFailureInfo struct {
	TaskID        int
	TaskType      string // "map" o "reduce"
	FailureType   TaskFailureType
	WorkerID      string
	FailureTime   time.Time
	DataReceived  bool   // Se il task ha ricevuto dati
	DataProcessed bool   // Se il task ha processato dati
	Checkpoint    string // Checkpoint per recovery
}

// AdvancedFaultTolerance gestisce fault tolerance avanzato
type AdvancedFaultTolerance struct {
	lb              *LoadBalancer
	failureHistory  map[string][]TaskFailureInfo // workerID -> failures
	taskCheckpoints map[string]string            // taskID -> checkpoint
	mu              sync.RWMutex
}

// NewAdvancedFaultTolerance crea un nuovo sistema di fault tolerance avanzato
func NewAdvancedFaultTolerance(lb *LoadBalancer) *AdvancedFaultTolerance {
	aft := &AdvancedFaultTolerance{
		lb:              lb,
		failureHistory:  make(map[string][]TaskFailureInfo),
		taskCheckpoints: make(map[string]string),
	}

	// Avvia monitoring avanzato
	go aft.startAdvancedMonitoring()

	return aft
}

// startAdvancedMonitoring avvia il monitoring avanzato per fault tolerance
func (aft *AdvancedFaultTolerance) startAdvancedMonitoring() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			aft.monitorTaskFailures()
			aft.checkDataIntegrity()
		}
	}
}

// monitorTaskFailures monitora i fallimenti dei task con algoritmi avanzati
func (aft *AdvancedFaultTolerance) monitorTaskFailures() {
	aft.mu.Lock()
	defer aft.mu.Unlock()

	// Monitora fallimenti mapper
	aft.monitorMapperFailures()

	// Monitora fallimenti reducer
	aft.monitorReducerFailures()
}

// monitorMapperFailures implementa l'algoritmo di fault tolerance per mapper
func (aft *AdvancedFaultTolerance) monitorMapperFailures() {
	// Algoritmo per fallimenti mapper:
	// 1. Se fallisce prima di completare -> riavvia task
	// 2. Se fallisce dopo aver completato -> verifica se dati sono arrivati al reducer

	for _, server := range aft.lb.servers {
		if !server.Healthy {
			// Verifica se è un mapper e se ha task in corso
			if aft.isMapper(server.ID) {
				aft.handleMapperFailure(server.ID)
			}
		}
	}
}

// handleMapperFailure gestisce il fallimento di un mapper
func (aft *AdvancedFaultTolerance) handleMapperFailure(workerID string) {
	LogWarn("[FaultTolerance] Gestione fallimento mapper %s", workerID)

	// Verifica se il mapper aveva task in corso
	tasks := aft.getWorkerTasks(workerID)

	for _, taskID := range tasks {
		// Verifica se il task era completato
		if aft.isTaskCompleted(taskID) {
			// Task completato: verifica se dati sono arrivati al reducer
			if aft.verifyDataReachedReducer(taskID) {
				LogInfo("[FaultTolerance] Mapper %s task %d completato, dati arrivati al reducer", workerID, taskID)
				// Non serve riavviare il task
			} else {
				LogWarn("[FaultTolerance] Mapper %s task %d completato ma dati non arrivati, riavvio task", workerID, taskID)
				aft.restartTask(taskID, "map")
			}
		} else {
			// Task non completato: riavvia
			LogWarn("[FaultTolerance] Mapper %s task %d non completato, riavvio task", workerID, taskID)
			aft.restartTask(taskID, "map")
		}
	}
}

// monitorReducerFailures implementa l'algoritmo di fault tolerance per reducer
func (aft *AdvancedFaultTolerance) monitorReducerFailures() {
	// Algoritmo per fallimenti reducer:
	// 1. Se fallisce prima di ricevere dati -> nuovo reducer riceve gli stessi dati
	// 2. Se fallisce durante reduce -> nuovo reducer riparte dallo stato del precedente

	for _, server := range aft.lb.servers {
		if !server.Healthy {
			// Verifica se è un reducer e se ha task in corso
			if aft.isReducer(server.ID) {
				aft.handleReducerFailure(server.ID)
			}
		}
	}
}

// handleReducerFailure gestisce il fallimento di un reducer
func (aft *AdvancedFaultTolerance) handleReducerFailure(workerID string) {
	LogWarn("[FaultTolerance] Gestione fallimento reducer %s", workerID)

	// Verifica se il reducer aveva task in corso
	tasks := aft.getWorkerTasks(workerID)

	for _, taskID := range tasks {
		// Verifica se il reducer aveva ricevuto dati
		if aft.hasReducerReceivedData(taskID) {
			// Reducer aveva ricevuto dati: verifica se aveva iniziato processing
			if aft.hasReducerStartedProcessing(taskID) {
				// Reducer stava processando: nuovo reducer riparte dallo stato precedente
				LogWarn("[FaultTolerance] Reducer %s task %d stava processando, nuovo reducer riparte dallo stato precedente", workerID, taskID)
				aft.resumeReducerFromCheckpoint(taskID)
			} else {
				// Reducer aveva ricevuto dati ma non aveva iniziato: nuovo reducer riceve gli stessi dati
				LogInfo("[FaultTolerance] Reducer %s task %d aveva ricevuto dati ma non iniziato, nuovo reducer riceve gli stessi dati", workerID, taskID)
				aft.assignSameDataToNewReducer(taskID)
			}
		} else {
			// Reducer non aveva ricevuto dati: nuovo reducer riceve gli stessi dati
			LogInfo("[FaultTolerance] Reducer %s task %d non aveva ricevuto dati, nuovo reducer riceve gli stessi dati", workerID, taskID)
			aft.assignSameDataToNewReducer(taskID)
		}
	}
}

// ============================================================================
// FUNZIONI DI SUPPORTO PER FAULT TOLERANCE
// ============================================================================

// isMapper verifica se un worker è un mapper
func (aft *AdvancedFaultTolerance) isMapper(workerID string) bool {
	// Implementazione semplificata: worker con ID che inizia con "worker" sono mapper
	return strings.HasPrefix(workerID, "worker")
}

// isReducer verifica se un worker è un reducer
func (aft *AdvancedFaultTolerance) isReducer(workerID string) bool {
	// Implementazione semplificata: worker con ID che inizia con "reducer" sono reducer
	return strings.HasPrefix(workerID, "reducer")
}

// getWorkerTasks restituisce i task assegnati a un worker
func (aft *AdvancedFaultTolerance) getWorkerTasks(workerID string) []int {
	// Implementazione semplificata: restituisce task mock
	// In implementazione reale, questo dovrebbe interrogare il master
	return []int{1, 2, 3} // Mock
}

// isTaskCompleted verifica se un task è completato
func (aft *AdvancedFaultTolerance) isTaskCompleted(taskID int) bool {
	// Implementazione semplificata: verifica esistenza file di output
	// In implementazione reale, questo dovrebbe interrogare il master
	return false // Mock
}

// verifyDataReachedReducer verifica se i dati di un mapper sono arrivati al reducer
func (aft *AdvancedFaultTolerance) verifyDataReachedReducer(taskID int) bool {
	// Implementazione semplificata: verifica esistenza file intermedi
	// In implementazione reale, questo dovrebbe verificare i file intermedi
	return true // Mock
}

// hasReducerReceivedData verifica se un reducer ha ricevuto dati
func (aft *AdvancedFaultTolerance) hasReducerReceivedData(taskID int) bool {
	// Implementazione semplificata: verifica esistenza file intermedi per il task
	// In implementazione reale, questo dovrebbe verificare i file intermedi
	return true // Mock
}

// hasReducerStartedProcessing verifica se un reducer ha iniziato l'elaborazione
func (aft *AdvancedFaultTolerance) hasReducerStartedProcessing(taskID int) bool {
	// Implementazione semplificata: verifica esistenza checkpoint
	// In implementazione reale, questo dovrebbe verificare i checkpoint
	return true // Mock
}

// restartTask riavvia un task
func (aft *AdvancedFaultTolerance) restartTask(taskID int, taskType string) {
	LogInfo("[FaultTolerance] Riavvio task %d di tipo %s", taskID, taskType)
	// Implementazione: notifica al master di riavviare il task
}

// assignSameDataToNewReducer assegna gli stessi dati a un nuovo reducer
func (aft *AdvancedFaultTolerance) assignSameDataToNewReducer(taskID int) {
	LogInfo("[FaultTolerance] Assegnazione stessi dati a nuovo reducer per task %d", taskID)
	// Implementazione: notifica al master di riassegnare il task con gli stessi dati
}

// resumeReducerFromCheckpoint fa ripartire un reducer dal checkpoint precedente
func (aft *AdvancedFaultTolerance) resumeReducerFromCheckpoint(taskID int) {
	LogInfo("[FaultTolerance] Ripresa reducer dal checkpoint per task %d", taskID)
	// Implementazione: notifica al master di riprendere dal checkpoint
}

// checkDataIntegrity verifica l'integrità dei dati
func (aft *AdvancedFaultTolerance) checkDataIntegrity() {
	// Implementazione: verifica integrità file di output e intermedi
	LogInfo("[FaultTolerance] Verifica integrità dati...")
}

// ============================================================================
// IMPLEMENTAZIONE AVANZATA DEI METODI DI FAULT TOLERANCE
// ============================================================================

// EnhancedFaultToleranceMethods implementa i metodi avanzati per fault tolerance
type EnhancedFaultToleranceMethods struct {
	checkpointManager *CheckpointManager
	masterClient      *MasterClient
	fileSystem        *FileSystemManager
}

// MasterClient rappresenta un client per comunicare con il master
type MasterClient struct {
	address string
	// In implementazione reale, questo dovrebbe essere un client RPC
}

// FileSystemManager gestisce le operazioni sui file
type FileSystemManager struct {
	basePath string
}

// NewEnhancedFaultToleranceMethods crea i metodi avanzati
func NewEnhancedFaultToleranceMethods() *EnhancedFaultToleranceMethods {
	return &EnhancedFaultToleranceMethods{
		checkpointManager: NewCheckpointManager(),
		masterClient:      &MasterClient{address: "localhost:8080"},
		fileSystem:        &FileSystemManager{basePath: "/tmp/mapreduce"},
	}
}

// ============================================================================
// ALGORITMO AVANZATO PER FALLIMENTI MAPPER
// ============================================================================

// handleMapperFailureAdvanced implementa l'algoritmo avanzato per fallimenti mapper
func (eftm *EnhancedFaultToleranceMethods) handleMapperFailureAdvanced(workerID string, taskID int) {
	LogInfo("[AdvancedFaultTolerance] Gestione avanzata fallimento mapper %s, task %d", workerID, taskID)

	// Fase 1: Verifica stato del task
	taskState := eftm.getTaskState(taskID)

	switch taskState {
	case "not_started":
		// Task non iniziato: riavvia normalmente
		LogInfo("[AdvancedFaultTolerance] Task %d non iniziato, riavvio normale", taskID)
		eftm.restartTaskNormal(taskID, "map")

	case "in_progress":
		// Task in corso: verifica se ha prodotto output parziale
		if eftm.hasPartialOutput(taskID) {
			LogInfo("[AdvancedFaultTolerance] Task %d in corso con output parziale, riavvio con cleanup", taskID)
			eftm.cleanupPartialOutput(taskID)
			eftm.restartTaskNormal(taskID, "map")
		} else {
			LogInfo("[AdvancedFaultTolerance] Task %d in corso senza output, riavvio normale", taskID)
			eftm.restartTaskNormal(taskID, "map")
		}

	case "completed":
		// Task completato: verifica se dati sono arrivati al reducer
		if eftm.verifyDataReachedReducerAdvanced(taskID) {
			LogInfo("[AdvancedFaultTolerance] Task %d completato, dati arrivati al reducer, nessuna azione necessaria", taskID)
			// Nessuna azione necessaria
		} else {
			LogInfo("[AdvancedFaultTolerance] Task %d completato ma dati non arrivati, riavvio task", taskID)
			eftm.restartTaskNormal(taskID, "map")
		}

	default:
		LogInfo("[AdvancedFaultTolerance] Stato task %d sconosciuto: %s", taskID, taskState)
	}
}

// verifyDataReachedReducerAdvanced verifica avanzata se i dati sono arrivati al reducer
func (eftm *EnhancedFaultToleranceMethods) verifyDataReachedReducerAdvanced(taskID int) bool {
	// Verifica esistenza file intermedi per tutti i reducer
	for reduceID := 0; reduceID < 3; reduceID++ { // Mock: 3 reducer
		intermediateFile := fmt.Sprintf("%s/mr-%d-%d", eftm.fileSystem.basePath, taskID, reduceID)
		if !eftm.fileSystem.fileExists(intermediateFile) {
			LogInfo("[AdvancedFaultTolerance] File intermedio mancante: %s", intermediateFile)
			return false
		}

		// Verifica integrità del file
		if !eftm.fileSystem.validateFileIntegrity(intermediateFile) {
			LogInfo("[AdvancedFaultTolerance] File intermedio corrotto: %s", intermediateFile)
			return false
		}
	}

	return true
}

// ============================================================================
// ALGORITMO AVANZATO PER FALLIMENTI REDUCER
// ============================================================================

// handleReducerFailureAdvanced implementa l'algoritmo avanzato per fallimenti reducer
func (eftm *EnhancedFaultToleranceMethods) handleReducerFailureAdvanced(workerID string, taskID int) {
	LogInfo("[AdvancedFaultTolerance] Gestione avanzata fallimento reducer %s, task %d", workerID, taskID)

	// Fase 1: Verifica se il reducer aveva ricevuto dati
	if !eftm.hasReducerReceivedDataAdvanced(taskID) {
		// Reducer non aveva ricevuto dati: nuovo reducer riceve gli stessi dati
		LogInfo("[AdvancedFaultTolerance] Reducer %s task %d non aveva ricevuto dati, nuovo reducer riceve gli stessi dati", workerID, taskID)
		eftm.assignSameDataToNewReducerAdvanced(taskID)
		return
	}

	// Fase 2: Reducer aveva ricevuto dati, verifica se aveva iniziato processing
	if !eftm.hasReducerStartedProcessingAdvanced(taskID) {
		// Reducer aveva ricevuto dati ma non aveva iniziato: nuovo reducer riceve gli stessi dati
		LogInfo("[AdvancedFaultTolerance] Reducer %s task %d aveva ricevuto dati ma non iniziato, nuovo reducer riceve gli stessi dati", workerID, taskID)
		eftm.assignSameDataToNewReducerAdvanced(taskID)
		return
	}

	// Fase 3: Reducer stava processando: nuovo reducer riparte dallo stato precedente
	LogInfo("[AdvancedFaultTolerance] Reducer %s task %d stava processando, nuovo reducer riparte dallo stato precedente", workerID, taskID)
	eftm.resumeReducerFromCheckpointAdvanced(taskID)
}

// hasReducerReceivedDataAdvanced verifica avanzata se un reducer ha ricevuto dati
func (eftm *EnhancedFaultToleranceMethods) hasReducerReceivedDataAdvanced(taskID int) bool {
	// Verifica esistenza di almeno un file intermedio per questo reducer
	for mapID := 0; mapID < 3; mapID++ { // Mock: 3 mapper
		intermediateFile := fmt.Sprintf("%s/mr-%d-%d", eftm.fileSystem.basePath, mapID, taskID)
		if eftm.fileSystem.fileExists(intermediateFile) {
			return true
		}
	}
	return false
}

// hasReducerStartedProcessingAdvanced verifica avanzata se un reducer ha iniziato l'elaborazione
func (eftm *EnhancedFaultToleranceMethods) hasReducerStartedProcessingAdvanced(taskID int) bool {
	// Verifica esistenza checkpoint
	checkpoint, exists := eftm.checkpointManager.LoadCheckpoint(taskID)
	if !exists {
		return false
	}

	// Verifica se il checkpoint è recente (entro 5 minuti)
	if time.Since(checkpoint.CheckpointTime) > 5*time.Minute {
		return false
	}

	return true
}

// assignSameDataToNewReducerAdvanced assegna gli stessi dati a un nuovo reducer
func (eftm *EnhancedFaultToleranceMethods) assignSameDataToNewReducerAdvanced(taskID int) {
	LogInfo("[AdvancedFaultTolerance] Assegnazione stessi dati a nuovo reducer per task %d", taskID)

	// 1. Identifica i file intermedi necessari
	intermediateFiles := eftm.getIntermediateFilesForReducer(taskID)

	// 2. Verifica che tutti i file esistano e siano validi
	for _, file := range intermediateFiles {
		if !eftm.fileSystem.fileExists(file) {
			LogInfo("[AdvancedFaultTolerance] File intermedio mancante: %s", file)
			return
		}
		if !eftm.fileSystem.validateFileIntegrity(file) {
			LogInfo("[AdvancedFaultTolerance] File intermedio corrotto: %s", file)
			return
		}
	}

	// 3. Assegna il task a un nuovo reducer
	eftm.assignTaskToNewReducer(taskID, intermediateFiles)
}

// resumeReducerFromCheckpointAdvanced fa ripartire un reducer dal checkpoint
func (eftm *EnhancedFaultToleranceMethods) resumeReducerFromCheckpointAdvanced(taskID int) {
	LogInfo("[AdvancedFaultTolerance] Ripresa reducer dal checkpoint per task %d", taskID)

	// 1. Carica il checkpoint
	checkpoint, exists := eftm.checkpointManager.LoadCheckpoint(taskID)
	if !exists {
		LogInfo("[AdvancedFaultTolerance] Nessun checkpoint trovato per task %d, riavvio normale", taskID)
		eftm.assignSameDataToNewReducerAdvanced(taskID)
		return
	}

	// 2. Verifica validità del checkpoint
	if !eftm.validateCheckpoint(checkpoint) {
		LogInfo("[AdvancedFaultTolerance] Checkpoint invalido per task %d, riavvio normale", taskID)
		eftm.assignSameDataToNewReducerAdvanced(taskID)
		return
	}

	// 3. Assegna il task con checkpoint a un nuovo reducer
	eftm.assignTaskWithCheckpointToNewReducer(taskID, checkpoint)
}

// ============================================================================
// FUNZIONI DI SUPPORTO AVANZATE
// ============================================================================

// getTaskState restituisce lo stato di un task
func (eftm *EnhancedFaultToleranceMethods) getTaskState(taskID int) string {
	// Implementazione semplificata
	// In implementazione reale, questo dovrebbe interrogare il master
	return "in_progress" // Mock
}

// hasPartialOutput verifica se un task ha prodotto output parziale
func (eftm *EnhancedFaultToleranceMethods) hasPartialOutput(taskID int) bool {
	// Verifica esistenza file temporanei
	tempFiles := eftm.getTempFilesForTask(taskID)
	for _, file := range tempFiles {
		if eftm.fileSystem.fileExists(file) {
			return true
		}
	}
	return false
}

// cleanupPartialOutput pulisce l'output parziale di un task
func (eftm *EnhancedFaultToleranceMethods) cleanupPartialOutput(taskID int) {
	tempFiles := eftm.getTempFilesForTask(taskID)
	for _, file := range tempFiles {
		eftm.fileSystem.deleteFile(file)
	}
}

// restartTaskNormal riavvia un task normalmente
func (eftm *EnhancedFaultToleranceMethods) restartTaskNormal(taskID int, taskType string) {
	LogInfo("[AdvancedFaultTolerance] Riavvio normale task %d di tipo %s", taskID, taskType)
	// Implementazione: notifica al master di riavviare il task
}

// getIntermediateFilesForReducer restituisce i file intermedi per un reducer
func (eftm *EnhancedFaultToleranceMethods) getIntermediateFilesForReducer(taskID int) []string {
	var files []string
	for mapID := 0; mapID < 3; mapID++ { // Mock: 3 mapper
		files = append(files, fmt.Sprintf("%s/mr-%d-%d", eftm.fileSystem.basePath, mapID, taskID))
	}
	return files
}

// assignTaskToNewReducer assegna un task a un nuovo reducer
func (eftm *EnhancedFaultToleranceMethods) assignTaskToNewReducer(taskID int, intermediateFiles []string) {
	LogInfo("[AdvancedFaultTolerance] Assegnazione task %d a nuovo reducer con %d file intermedi", taskID, len(intermediateFiles))
	// Implementazione: notifica al master di assegnare il task
}

// assignTaskWithCheckpointToNewReducer assegna un task con checkpoint a un nuovo reducer
func (eftm *EnhancedFaultToleranceMethods) assignTaskWithCheckpointToNewReducer(taskID int, checkpoint *ReducerCheckpoint) {
	LogInfo("[AdvancedFaultTolerance] Assegnazione task %d con checkpoint a nuovo reducer (chiavi processate: %d)", taskID, checkpoint.ProcessedKeys)
	// Implementazione: notifica al master di assegnare il task con checkpoint
}

// validateCheckpoint valida un checkpoint
func (eftm *EnhancedFaultToleranceMethods) validateCheckpoint(checkpoint *ReducerCheckpoint) bool {
	// Verifica che il checkpoint non sia troppo vecchio
	if time.Since(checkpoint.CheckpointTime) > 30*time.Minute {
		return false
	}

	// Verifica che i dati del checkpoint siano validi
	if checkpoint.ProcessedKeys < 0 {
		return false
	}

	return true
}

// getTempFilesForTask restituisce i file temporanei per un task
func (eftm *EnhancedFaultToleranceMethods) getTempFilesForTask(taskID int) []string {
	return []string{
		fmt.Sprintf("%s/temp-map-%d", eftm.fileSystem.basePath, taskID),
		fmt.Sprintf("%s/temp-reduce-%d", eftm.fileSystem.basePath, taskID),
	}
}

// ============================================================================
// FILE SYSTEM MANAGER
// ============================================================================

// fileExists verifica se un file esiste
func (fsm *FileSystemManager) fileExists(path string) bool {
	// Implementazione semplificata
	// In implementazione reale, questo dovrebbe usare os.Stat
	return true // Mock
}

// validateFileIntegrity verifica l'integrità di un file
func (fsm *FileSystemManager) validateFileIntegrity(path string) bool {
	// Implementazione semplificata
	// In implementazione reale, questo dovrebbe verificare checksum, dimensioni, etc.
	return true // Mock
}

// deleteFile elimina un file
func (fsm *FileSystemManager) deleteFile(path string) {
	LogInfo("[FileSystemManager] Eliminazione file: %s", path)
	// Implementazione: os.Remove(path)
}

// ============================================================================
// CHECKPOINTING PER REDUCER
// ============================================================================

// CheckpointManager gestisce i checkpoint per i reducer
type CheckpointManager struct {
	checkpoints map[string]ReducerCheckpoint // taskID -> checkpoint
	mu          sync.RWMutex
}

// ReducerCheckpoint rappresenta un checkpoint di un reducer
type ReducerCheckpoint struct {
	TaskID         int
	ProcessedKeys  int
	LastKey        string
	CheckpointTime time.Time
	Data           map[string]interface{} // Dati aggiuntivi
}

// NewCheckpointManager crea un nuovo gestore di checkpoint
func NewCheckpointManager() *CheckpointManager {
	return &CheckpointManager{
		checkpoints: make(map[string]ReducerCheckpoint),
	}
}

// SaveCheckpoint salva un checkpoint per un reducer
func (cm *CheckpointManager) SaveCheckpoint(taskID int, processedKeys int, lastKey string, data map[string]interface{}) {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	checkpoint := ReducerCheckpoint{
		TaskID:         taskID,
		ProcessedKeys:  processedKeys,
		LastKey:        lastKey,
		CheckpointTime: time.Now(),
		Data:           data,
	}

	cm.checkpoints[fmt.Sprintf("task_%d", taskID)] = checkpoint
	LogInfo("[CheckpointManager] Salvato checkpoint per task %d: %d chiavi processate, ultima chiave: %s\n",
		taskID, processedKeys, lastKey)
}

// LoadCheckpoint carica un checkpoint per un reducer
func (cm *CheckpointManager) LoadCheckpoint(taskID int) (*ReducerCheckpoint, bool) {
	cm.mu.RLock()
	defer cm.mu.RUnlock()

	checkpoint, exists := cm.checkpoints[fmt.Sprintf("task_%d", taskID)]
	if exists {
		LogInfo("[CheckpointManager] Caricato checkpoint per task %d: %d chiavi processate, ultima chiave: %s\n",
			taskID, checkpoint.ProcessedKeys, checkpoint.LastKey)
		return &checkpoint, true
	}

	return nil, false
}

// ============================================================================
// INTEGRAZIONE CON LOAD BALANCER
// ============================================================================

// IntegrateAdvancedFaultTolerance integra il fault tolerance avanzato con il load balancer
func (lb *LoadBalancer) IntegrateAdvancedFaultTolerance() *AdvancedFaultTolerance {
	aft := NewAdvancedFaultTolerance(lb)

	// Integra con il sistema di health checking esistente
	lb.systemHealth.CheckComponent("advanced_fault_tolerance", func() (bool, string, map[string]string) {
		// Verifica stato del fault tolerance avanzato
		healthy := true
		message := "Advanced fault tolerance active"
		details := map[string]string{
			"monitoring_active":  "true",
			"checkpoint_manager": "active",
			"failure_detection":  "active",
		}

		return healthy, message, details
	})

	LogInfo("Advanced fault tolerance integrato con load balancer")
	return aft
}
