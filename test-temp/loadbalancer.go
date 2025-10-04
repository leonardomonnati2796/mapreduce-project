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

	fmt.Printf("Load balancer inizializzato con %d server, strategia: %s\n", len(servers), strategy.String())
	return lb
}

// AddServer aggiunge un server al load balancer
func (lb *LoadBalancer) AddServer(server Server) {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	lb.servers = append(lb.servers, server)
	fmt.Printf("Server %s aggiunto al load balancer\n", server.ID)
}

// RemoveServer rimuove un server dal load balancer
func (lb *LoadBalancer) RemoveServer(serverID string) {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	for i, server := range lb.servers {
		if server.ID == serverID {
			lb.servers = append(lb.servers[:i], lb.servers[i+1:]...)
			fmt.Printf("Server %s rimosso dal load balancer\n", serverID)
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

// startHealthChecking avvia il controllo periodico della salute (deprecato)
// Deprecated: Use startUnifiedHealthChecking instead
func (lb *LoadBalancer) startHealthChecking() {
	lb.startUnifiedHealthChecking()
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
			fmt.Printf("Server %s status changed to %s\n", server.ID, status)
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
	fmt.Printf("Load balancer strategy changed from %s to %s\n", oldStrategy.String(), strategy.String())
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
	fmt.Printf("Load balancer timeout set to %v\n", timeout)
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
			fmt.Printf("Statistics reset for server %s\n", serverID)
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
	fmt.Printf("Statistics reset for all %d servers\n", len(lb.servers))
}

// ForceHealthCheck forza un controllo di salute immediato
func (lb *LoadBalancer) ForceHealthCheck() {
	fmt.Println("Forcing immediate health check...")
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

	fmt.Printf("Load balancer integrato con %d worker esistenti\n", len(workerServers))
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

	fmt.Println("Load balancer ha sostituito il monitoring del master")
}
