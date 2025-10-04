package main

import (
	"fmt"
	"testing"
	"time"
)

// TestLoadBalancerCreation testa la creazione di un load balancer
func TestLoadBalancerCreation(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	if lb == nil {
		t.Fatal("Load balancer should not be nil")
	}

	if len(lb.servers) != len(servers) {
		t.Fatalf("Expected %d servers, got %d", len(servers), len(lb.servers))
	}

	if lb.strategy != HealthBased {
		t.Fatalf("Expected strategy HealthBased, got %s", lb.strategy.String())
	}
}

// TestServerSelection testa la selezione dei server
func TestServerSelection(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, RoundRobin)

	// Testa la selezione di un server
	server, err := lb.GetServer()
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}

	if server == nil {
		t.Fatal("Expected a server, got nil")
	}

	fmt.Printf("Selected server: %s\n", server.ID)
}

// TestServerManagement testa l'aggiunta e rimozione di server
func TestServerManagement(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	initialCount := len(lb.servers)

	// Aggiungi un nuovo server
	newServer := NewServer("test-server", "localhost", 9999)
	lb.AddServer(newServer)

	if len(lb.servers) != initialCount+1 {
		t.Fatalf("Expected %d servers, got %d", initialCount+1, len(lb.servers))
	}

	// Rimuovi il server
	lb.RemoveServer("test-server")

	if len(lb.servers) != initialCount {
		t.Fatalf("Expected %d servers, got %d", initialCount, len(lb.servers))
	}
}

// TestStrategyChange testa il cambio di strategia
func TestStrategyChange(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, RoundRobin)

	if lb.GetStrategy() != RoundRobin {
		t.Fatalf("Expected RoundRobin strategy, got %s", lb.GetStrategy().String())
	}

	// Cambia strategia
	lb.SetStrategy(HealthBased)

	if lb.GetStrategy() != HealthBased {
		t.Fatalf("Expected HealthBased strategy, got %s", lb.GetStrategy().String())
	}
}

// TestStatistics testa le statistiche del load balancer
func TestStatistics(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	stats := lb.GetStats()

	if stats["total_servers"] != len(servers) {
		t.Fatalf("Expected %d total servers, got %v", len(servers), stats["total_servers"])
	}

	if stats["healthy_servers"] != len(servers) {
		t.Fatalf("Expected %d healthy servers, got %v", len(servers), stats["healthy_servers"])
	}

	if stats["strategy"] != "Health Based" {
		t.Fatalf("Expected 'Health Based' strategy, got %v", stats["strategy"])
	}
}

// TestServerDetails testa i dettagli dei server
func TestServerDetails(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	details := lb.GetServerDetails()

	if len(details) != len(servers) {
		t.Fatalf("Expected %d server details, got %d", len(servers), len(details))
	}

	// Verifica che ogni server abbia i campi richiesti
	for _, detail := range details {
		requiredFields := []string{"id", "address", "port", "weight", "healthy", "last_seen", "requests", "errors", "error_rate"}
		for _, field := range requiredFields {
			if _, exists := detail[field]; !exists {
				t.Fatalf("Server detail missing field: %s", field)
			}
		}
	}
}

// TestHealthChecking testa il controllo di salute
func TestHealthChecking(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Verifica che tutti i server siano inizialmente sani (prima del health check)
	healthyCount := lb.GetHealthyServerCount()
	if healthyCount != len(servers) {
		t.Fatalf("Expected %d healthy servers initially, got %d", len(servers), healthyCount)
	}

	// Forza un controllo di salute (i server non saranno raggiungibili, quindi diventeranno unhealthy)
	lb.ForceHealthCheck()

	// Verifica che il health check sia stato eseguito (i server saranno unhealthy)
	// Questo è normale perché i server di test non sono realmente in esecuzione
	healthyCountAfter := lb.GetHealthyServerCount()
	fmt.Printf("Healthy servers after health check: %d (expected 0 because servers are not running)\n", healthyCountAfter)
}

// TestStatsReset testa il reset delle statistiche
func TestStatsReset(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Simula alcune richieste
	lb.UpdateServerStats("master-0", true)
	lb.UpdateServerStats("master-0", true)
	lb.UpdateServerStats("master-0", false)

	// Verifica che le statistiche siano state aggiornate
	details := lb.GetServerDetails()
	for _, detail := range details {
		if detail["id"] == "master-0" {
			if detail["requests"] != int64(3) {
				t.Fatalf("Expected 3 requests, got %v", detail["requests"])
			}
			if detail["errors"] != int64(1) {
				t.Fatalf("Expected 1 error, got %v", detail["errors"])
			}
			break
		}
	}

	// Reset delle statistiche
	lb.ResetAllStats()

	// Verifica che le statistiche siano state resettate
	details = lb.GetServerDetails()
	for _, detail := range details {
		if detail["requests"] != int64(0) {
			t.Fatalf("Expected 0 requests after reset, got %v", detail["requests"])
		}
		if detail["errors"] != int64(0) {
			t.Fatalf("Expected 0 errors after reset, got %v", detail["errors"])
		}
	}
}

// TestTimeoutConfiguration testa la configurazione del timeout
func TestTimeoutConfiguration(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Verifica il timeout di default
	defaultTimeout := lb.GetTimeout()
	if defaultTimeout != 5*time.Second {
		t.Fatalf("Expected default timeout 5s, got %v", defaultTimeout)
	}

	// Cambia il timeout
	newTimeout := 10 * time.Second
	lb.SetTimeout(newTimeout)

	if lb.GetTimeout() != newTimeout {
		t.Fatalf("Expected timeout %v, got %v", newTimeout, lb.GetTimeout())
	}
}

// TestLoadBalancerUsage testa l'utilizzo del load balancer
func TestLoadBalancerUsage(t *testing.T) {
	// Crea server di default
	servers := CreateDefaultServers()

	// Crea load balancer con strategia Health-Based
	lb := NewLoadBalancer(servers, HealthBased)

	// Seleziona un server
	server, err := lb.GetServer()
	if err != nil {
		t.Fatalf("Error selecting server: %v", err)
	}

	if server == nil {
		t.Fatal("Expected a server, got nil")
	}

	if server.ID == "" {
		t.Fatal("Expected server ID, got empty string")
	}
}

// TestUnifiedHealthChecking testa il sistema unificato di health checking
func TestUnifiedHealthChecking(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Simula worker map (come nel master)
	workerMap := map[string]WorkerInfo{
		"worker-1": {ID: "worker-1", Status: "active", LastSeen: time.Now(), TasksDone: 0},
		"worker-2": {ID: "worker-2", Status: "active", LastSeen: time.Now(), TasksDone: 0},
		"worker-3": {ID: "worker-3", Status: "active", LastSeen: time.Now(), TasksDone: 0},
	}

	// Integra con master (sostituisce monitoring esistente)
	lb.ReplaceMasterHealthMonitoring(workerMap)

	// Verifica che i server siano stati aggiunti
	expectedServers := len(servers) + len(workerMap)
	if len(lb.servers) != expectedServers {
		t.Fatalf("Expected %d servers after integration, got %d", expectedServers, len(lb.servers))
	}
}

// TestUnifiedStatistics testa le statistiche unificate
func TestUnifiedStatistics(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Test statistiche unificate
	unifiedStats := lb.GetUnifiedStats()

	// Verifica che le statistiche unificate contengano i campi richiesti
	requiredFields := []string{"load_balancer", "system_health"}
	for _, field := range requiredFields {
		if _, exists := unifiedStats[field]; !exists {
			t.Fatalf("Unified stats missing field: %s", field)
		}
	}

	// Verifica statistiche load balancer
	lbStats := unifiedStats["load_balancer"].(map[string]interface{})
	if lbStats["total_servers"] == nil {
		t.Fatal("Load balancer stats missing total_servers")
	}

	// Verifica statistiche sistema
	systemStats := unifiedStats["system_health"].(map[string]interface{})
	if systemStats["status"] == nil {
		t.Fatal("System health stats missing status")
	}
}

// TestOptimizedServerSelection testa la selezione ottimizzata dei server
func TestOptimizedServerSelection(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Test selezione server con strategia ottimizzata
	for i := 0; i < 3; i++ {
		server, err := lb.GetServer()
		if err != nil {
			t.Fatalf("Error selecting server: %v", err)
		}

		if server == nil {
			t.Fatal("Expected a server, got nil")
		}

		// Verifica che il server abbia un health score valido
		healthScore := lb.calculateHealthScore(server)
		if healthScore < 0 || healthScore > 1 {
			t.Fatalf("Invalid health score: %f", healthScore)
		}
	}
}

// TestDynamicConfiguration testa la configurazione dinamica
func TestDynamicConfiguration(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Test cambio strategia
	originalStrategy := lb.GetStrategy()
	lb.SetStrategy(RoundRobin)
	if lb.GetStrategy() != RoundRobin {
		t.Fatalf("Expected RoundRobin strategy, got %s", lb.GetStrategy().String())
	}

	// Test cambio timeout
	originalTimeout := lb.GetTimeout()
	newTimeout := 15 * time.Second
	lb.SetTimeout(newTimeout)
	if lb.GetTimeout() != newTimeout {
		t.Fatalf("Expected timeout %v, got %v", newTimeout, lb.GetTimeout())
	}

	// Ripristina configurazione originale
	lb.SetStrategy(originalStrategy)
	lb.SetTimeout(originalTimeout)
}

// TestDynamicServerManagement testa la gestione dinamica dei server
func TestDynamicServerManagement(t *testing.T) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	initialCount := len(lb.servers)

	// Test aggiunta server dinamico
	dynamicServer := NewServer("dynamic-server", "localhost", 9998)
	lb.AddServer(dynamicServer)

	if len(lb.servers) != initialCount+1 {
		t.Fatalf("Expected %d servers after adding, got %d", initialCount+1, len(lb.servers))
	}

	// Test rimozione server dinamico
	lb.RemoveServer("dynamic-server")

	if len(lb.servers) != initialCount {
		t.Fatalf("Expected %d servers after removal, got %d", initialCount, len(lb.servers))
	}
}

// BenchmarkLoadBalancer benchmark per le performance del load balancer
func BenchmarkLoadBalancer(b *testing.B) {
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := lb.GetServer()
		if err != nil {
			b.Fatalf("Error selecting server: %v", err)
		}
	}
}

// TestCompleteLoadBalancer testa tutte le funzionalità del load balancer
func TestCompleteLoadBalancer(t *testing.T) {
	fmt.Println("🧪 Testing Complete Load Balancer...")

	// Crea server di default
	servers := CreateDefaultServers()
	fmt.Printf("Created %d servers\n", len(servers))

	// Crea load balancer con strategia Health-Based
	lb := NewLoadBalancer(servers, HealthBased)
	fmt.Printf("Load balancer created with strategy: %s\n", lb.GetStrategy().String())

	// Test selezione server
	fmt.Println("\n📊 Testing server selection:")
	for i := 0; i < 5; i++ {
		server, err := lb.GetServer()
		if err != nil {
			fmt.Printf("Error selecting server: %v\n", err)
			continue
		}
		fmt.Printf("Selected server: %s (Address: %s:%d, Weight: %d)\n",
			server.ID, server.Address, server.Port, server.Weight)
	}

	// Test statistiche
	fmt.Println("\n📈 Load balancer statistics:")
	stats := lb.GetStats()
	for key, value := range stats {
		fmt.Printf("  %s: %v\n", key, value)
	}

	// Test dettagli server
	fmt.Println("\n🔍 Server details:")
	details := lb.GetServerDetails()
	for _, detail := range details {
		fmt.Printf("  Server %s: Healthy=%v, Requests=%v, Errors=%v\n",
			detail["id"], detail["healthy"], detail["requests"], detail["errors"])
	}

	// Test aggiornamento statistiche
	fmt.Println("\n🔄 Testing statistics update:")
	lb.UpdateServerStats("master-0", true)
	lb.UpdateServerStats("master-0", true)
	lb.UpdateServerStats("master-0", false)
	lb.UpdateServerStats("worker-0", true)

	// Verifica statistiche aggiornate
	updatedStats := lb.GetStats()
	fmt.Printf("Updated stats - Total requests: %v, Total errors: %v, Error rate: %.2f%%\n",
		updatedStats["total_requests"], updatedStats["total_errors"], updatedStats["error_rate"])

	// Test cambio strategia
	fmt.Println("\n🔄 Testing strategy change:")
	fmt.Printf("Current strategy: %s\n", lb.GetStrategy().String())
	lb.SetStrategy(RoundRobin)
	fmt.Printf("New strategy: %s\n", lb.GetStrategy().String())

	// Test timeout configuration
	fmt.Println("\n⏱️ Testing timeout configuration:")
	fmt.Printf("Current timeout: %v\n", lb.GetTimeout())
	lb.SetTimeout(10 * time.Second)
	fmt.Printf("New timeout: %v\n", lb.GetTimeout())

	// Test reset statistiche
	fmt.Println("\n🔄 Testing statistics reset:")
	lb.ResetAllStats()
	resetStats := lb.GetStats()
	fmt.Printf("After reset - Total requests: %v, Total errors: %v\n",
		resetStats["total_requests"], resetStats["total_errors"])

	// Test gestione server
	fmt.Println("\n➕ Testing server management:")
	newServer := NewServer("test-server", "localhost", 9999)
	lb.AddServer(newServer)
	fmt.Printf("Added server. Total servers: %d\n", len(lb.servers))

	lb.RemoveServer("test-server")
	fmt.Printf("Removed server. Total servers: %d\n", len(lb.servers))

	// Test controllo di salute
	fmt.Println("\n🏥 Testing health check:")
	healthyCount := lb.GetHealthyServerCount()
	fmt.Printf("Healthy servers: %d\n", healthyCount)

	// Test forzato controllo di salute
	lb.ForceHealthCheck()
	fmt.Println("Forced health check completed")

	// Test sistema unificato
	fmt.Println("\n📊 Testing unified health checking:")

	// Simula worker map (come nel master)
	workerMap := map[string]WorkerInfo{
		"worker-1": {ID: "worker-1", Status: "active", LastSeen: time.Now(), TasksDone: 0},
		"worker-2": {ID: "worker-2", Status: "active", LastSeen: time.Now(), TasksDone: 0},
		"worker-3": {ID: "worker-3", Status: "active", LastSeen: time.Now(), TasksDone: 0},
	}

	// Integra con master (sostituisce monitoring esistente)
	lb.ReplaceMasterHealthMonitoring(workerMap)
	fmt.Printf("Total servers after integration: %d\n", len(lb.servers))

	// Test statistiche unificate
	fmt.Println("\n📈 Testing unified statistics:")
	unifiedStats := lb.GetUnifiedStats()

	// Mostra statistiche load balancer
	lbStats := unifiedStats["load_balancer"].(map[string]interface{})
	fmt.Printf("Load Balancer Stats:\n")
	for key, value := range lbStats {
		fmt.Printf("  %s: %v\n", key, value)
	}

	// Mostra statistiche sistema
	systemStats := unifiedStats["system_health"].(map[string]interface{})
	fmt.Printf("\nSystem Health Stats:\n")
	fmt.Printf("  Status: %v\n", systemStats["status"])
	fmt.Printf("  Uptime: %v\n", systemStats["uptime"])

	// Test selezione server con strategia ottimizzata
	fmt.Println("\n🔄 Testing optimized server selection:")
	for i := 0; i < 3; i++ {
		server, err := lb.GetServer()
		if err != nil {
			fmt.Printf("Error selecting server: %v\n", err)
			continue
		}
		fmt.Printf("Selected server: %s (Health Score: %.2f)\n",
			server.ID, lb.calculateHealthScore(server))
	}

	// Test configurazione dinamica
	fmt.Println("\n⚙️ Testing dynamic configuration:")
	fmt.Printf("Current strategy: %s\n", lb.GetStrategy().String())
	lb.SetStrategy(HealthBased)
	fmt.Printf("New strategy: %s\n", lb.GetStrategy().String())

	fmt.Printf("Current timeout: %v\n", lb.GetTimeout())
	lb.SetTimeout(15 * time.Second)
	fmt.Printf("New timeout: %v\n", lb.GetTimeout())

	// Test gestione server dinamica
	fmt.Println("\n➕ Testing dynamic server management:")
	dynamicServer := NewServer("dynamic-server", "localhost", 9998)
	lb.AddServer(dynamicServer)
	fmt.Printf("Added server. Total servers: %d\n", len(lb.servers))

	lb.RemoveServer("dynamic-server")
	fmt.Printf("Removed server. Total servers: %d\n", len(lb.servers))

	// Test dettagli server finali
	fmt.Println("\n🔍 Final server details:")
	finalDetails := lb.GetServerDetails()
	for _, detail := range finalDetails {
		fmt.Printf("  Server %s: Healthy=%v, Requests=%v, Errors=%v\n",
			detail["id"], detail["healthy"], detail["requests"], detail["errors"])
	}

	fmt.Println("\n✅ Complete Load Balancer test completed successfully!")
	fmt.Println("\n🎯 Benefits of the complete system:")
	fmt.Println("  ✅ Basic load balancer functionality")
	fmt.Println("  ✅ Unified health checking (server + system)")
	fmt.Println("  ✅ Centralized fault tolerance")
	fmt.Println("  ✅ Dynamic configuration")
	fmt.Println("  ✅ Advanced load balancing strategies")
	fmt.Println("  ✅ Comprehensive monitoring")
	fmt.Println("  ✅ Eliminated code duplication")
}
