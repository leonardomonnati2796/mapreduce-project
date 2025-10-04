package main

import (
	"fmt"
)

// Demo delle differenze tra Health Checking e Load Balancer
func main() {
	fmt.Println("🔍 DEMO: Differenze tra Health Checking e Load Balancer")
	fmt.Println("============================================================")

	// ============================================================================
	// HEALTH CHECKING (health.go) - INFRASTRUTTURALE E SISTEMICO
	// ============================================================================
	fmt.Println("\n🏥 HEALTH CHECKING (health.go) - INFRASTRUTTURALE")
	fmt.Println("----------------------------------------")

	// Crea health checker per infrastruttura
	healthChecker := NewHealthChecker("1.0.0")

	// Esegui controlli infrastrutturali
	fmt.Println("\n📊 Controlli Infrastrutturali:")

	// 1. Controllo spazio disco
	healthChecker.CheckComponent("disk_space", CheckDiskSpace)
	fmt.Println("   ✅ Spazio disco verificato")

	// 2. Controllo risorse sistema
	healthChecker.CheckComponent("system_resources", CheckSystemResources)
	fmt.Println("   ✅ Risorse sistema verificate")

	// 3. Controllo sicurezza
	healthChecker.CheckComponent("security_status", CheckSecurityStatus)
	fmt.Println("   ✅ Stato sicurezza verificato")

	// 4. Controllo performance
	healthChecker.CheckComponent("performance_metrics", CheckPerformanceMetrics)
	fmt.Println("   ✅ Metriche performance verificate")

	// 5. Controllo dipendenze esterne
	healthChecker.CheckComponent("external_dependencies", CheckExternalDependencies)
	fmt.Println("   ✅ Dipendenze esterne verificate")

	// Ottieni stato completo infrastrutturale
	infraStatus := healthChecker.GetHealthStatus()
	fmt.Printf("\n📈 Stato Infrastrutturale Completo:\n")
	fmt.Printf("   Status: %s\n", infraStatus.Status)
	fmt.Printf("   Uptime: %v\n", infraStatus.Uptime)
	fmt.Printf("   Componenti: %d\n", len(infraStatus.Components))
	fmt.Printf("   CPU Usage: %.1f%%\n", infraStatus.Performance.ResourceUsage.CPUUsage)
	fmt.Printf("   Memory Usage: %.1f%%\n", infraStatus.Performance.ResourceUsage.MemoryUsage)
	fmt.Printf("   Disk Usage: %.1f%%\n", infraStatus.System.DiskUsage.Usage)

	// ============================================================================
	// LOAD BALANCER (loadbalancer.go) - SERVER E WORKER
	// ============================================================================
	fmt.Println("\n⚖️ LOAD BALANCER (loadbalancer.go) - SERVER E WORKER")
	fmt.Println("----------------------------------------")

	// Crea load balancer per server/worker
	servers := CreateDefaultServers()
	lb := NewLoadBalancer(servers, HealthBased)

	// Integra fault tolerance avanzato
	aft := lb.IntegrateAdvancedFaultTolerance()
	fmt.Println("   ✅ Load balancer con fault tolerance integrato")

	// Esegui controlli server/worker
	fmt.Println("\n📊 Controlli Server/Worker:")

	// 1. Selezione server
	server, err := lb.GetServer()
	if err == nil {
		fmt.Printf("   ✅ Server selezionato: %s\n", server.ID)
	}

	// 2. Statistiche load balancer
	lbStats := lb.GetStats()
	fmt.Printf("   ✅ Server totali: %v\n", lbStats["total_servers"])
	fmt.Printf("   ✅ Server sani: %v\n", lbStats["healthy_servers"])
	fmt.Printf("   ✅ Strategia: %v\n", lbStats["strategy"])

	// 3. Statistiche unificate
	unifiedStats := lb.GetUnifiedStats()
	fmt.Printf("   ✅ Statistiche unificate disponibili\n")

	// ============================================================================
	// CONFRONTO DETTAGLIATO
	// ============================================================================
	fmt.Println("\n🆚 CONFRONTO DETTAGLIATO")
	fmt.Println("----------------------------------------")

	fmt.Println("\n🏥 HEALTH CHECKING (health.go):")
	fmt.Println("   🎯 SCOPO: Monitoraggio infrastruttura e sistema operativo")
	fmt.Println("   📊 METRICHE:")
	fmt.Println("      • Spazio disco (bytes, percentuale)")
	fmt.Println("      • Uso CPU e memoria del sistema")
	fmt.Println("      • Latenza di rete (locale, esterna, DNS)")
	fmt.Println("      • Stato sicurezza (SSL, firewall, vulnerabilità)")
	fmt.Println("      • Performance (tempi risposta, throughput, error rate)")
	fmt.Println("      • Dipendenze esterne (S3, Redis, Kafka)")
	fmt.Println("      • Risorse sistema (CPU, memoria, disco, rete)")
	fmt.Println("   🔧 CONTROLLI:")
	fmt.Println("      • CheckDiskSpace() - Spazio disco con syscall.Statfs")
	fmt.Println("      • CheckSystemResources() - CPU, memoria, goroutine")
	fmt.Println("      • CheckSecurityStatus() - SSL, firewall, vulnerabilità")
	fmt.Println("      • CheckPerformanceMetrics() - Tempi risposta, error rate")
	fmt.Println("      • CheckExternalDependencies() - Servizi esterni")
	fmt.Println("   📡 ENDPOINT:")
	fmt.Println("      • /health - Stato completo infrastrutturale")
	fmt.Println("      • /health/live - Liveness probe")
	fmt.Println("      • /health/ready - Readiness probe")
	fmt.Println("      • /health/metrics - Metriche dettagliate")

	fmt.Println("\n⚖️ LOAD BALANCER (loadbalancer.go):")
	fmt.Println("   🎯 SCOPO: Bilanciamento carico e fault tolerance server/worker")
	fmt.Println("   📊 METRICHE:")
	fmt.Println("      • Server sani vs totali")
	fmt.Println("      • Richieste per server")
	fmt.Println("      • Errori per server")
	fmt.Println("      • Tasso di errore")
	fmt.Println("      • Strategia di bilanciamento")
	fmt.Println("      • Health score dei server")
	fmt.Println("   🔧 CONTROLLI:")
	fmt.Println("      • Health checking server HTTP")
	fmt.Println("      • Selezione server ottimale")
	fmt.Println("      • Gestione fallimenti mapper/reducer")
	fmt.Println("      • Checkpointing per recovery")
	fmt.Println("      • Fault tolerance avanzato")
	fmt.Println("   📡 FUNZIONALITÀ:")
	fmt.Println("      • 5 strategie di load balancing")
	fmt.Println("      • Health checking unificato")
	fmt.Println("      • Gestione dinamica server")
	fmt.Println("      • Statistiche unificate")

	// ============================================================================
	// DIFFERENZE CHIAVE
	// ============================================================================
	fmt.Println("\n🔑 DIFFERENZE CHIAVE")
	fmt.Println("----------------------------------------")

	fmt.Println("\n1️⃣ LIVELLO DI MONITORAGGIO:")
	fmt.Println("   🏥 Health Checking: INFRASTRUTTURALE (OS, risorse, sicurezza)")
	fmt.Println("   ⚖️ Load Balancer: APPLICAZIONALE (server, worker, task)")

	fmt.Println("\n2️⃣ OGGETTO DI MONITORAGGIO:")
	fmt.Println("   🏥 Health Checking: Sistema operativo, infrastruttura, sicurezza")
	fmt.Println("   ⚖️ Load Balancer: Server applicativi, worker, task MapReduce")

	fmt.Println("\n3️⃣ METRICHE:")
	fmt.Println("   🏥 Health Checking: CPU, memoria, disco, rete, sicurezza, performance")
	fmt.Println("   ⚖️ Load Balancer: Server health, richieste, errori, fault tolerance")

	fmt.Println("\n4️⃣ STRATEGIE:")
	fmt.Println("   🏥 Health Checking: Monitoraggio passivo, allerting, metriche")
	fmt.Println("   ⚖️ Load Balancer: Bilanciamento attivo, selezione server, recovery")

	fmt.Println("\n5️⃣ INTEGRAZIONE:")
	fmt.Println("   🏥 Health Checking: Integrato con load balancer per health checking unificato")
	fmt.Println("   ⚖️ Load Balancer: Utilizza health checker per monitoraggio server")

	// ============================================================================
	// COMPLEMENTARIETÀ
	// ============================================================================
	fmt.Println("\n🤝 COMPLEMENTARIETÀ")
	fmt.Println("----------------------------------------")

	fmt.Println("\n✅ I due sistemi sono COMPLEMENTARI:")
	fmt.Println("   🏥 Health Checking fornisce metriche infrastrutturali")
	fmt.Println("   ⚖️ Load Balancer utilizza queste metriche per decisioni intelligenti")
	fmt.Println("   🔄 Integrazione: Load balancer usa health checker per server health")
	fmt.Println("   📊 Risultato: Monitoring completo sistema + applicazione")

	fmt.Println("\n✅ BENEFICI DELL'INTEGRAZIONE:")
	fmt.Println("   🎯 Monitoring completo: Infrastruttura + Applicazione")
	fmt.Println("   📈 Metriche unificate: Sistema + Server + Performance")
	fmt.Println("   🔧 Health checking unificato: Un solo sistema per tutto")
	fmt.Println("   ⚡ Decisioni intelligenti: Load balancer con metriche infrastrutturali")
	fmt.Println("   🛡️ Fault tolerance completo: Infrastruttura + Applicazione")

	// ============================================================================
	// ESEMPIO PRATICO
	// ============================================================================
	fmt.Println("\n💡 ESEMPIO PRATICO")
	fmt.Println("----------------------------------------")

	fmt.Println("\n📋 Scenario: Server sotto stress")
	fmt.Println("   1. Health Checking rileva: CPU 90%, Memoria 85%")
	fmt.Println("   2. Load Balancer riceve metriche infrastrutturali")
	fmt.Println("   3. Load Balancer riduce peso del server stressato")
	fmt.Println("   4. Traffico ridiretto a server più sani")
	fmt.Println("   5. Sistema mantiene performance ottimali")

	fmt.Println("\n📋 Scenario: Fallimento server")
	fmt.Println("   1. Load Balancer rileva server non risponde")
	fmt.Println("   2. Health Checking verifica infrastruttura")
	fmt.Println("   3. Se infrastruttura OK: fault tolerance applicativo")
	fmt.Println("   4. Se infrastruttura KO: allerting infrastrutturale")
	fmt.Println("   5. Recovery appropriato basato su causa")

	fmt.Println("\n🎉 SISTEMA COMPLETO E INTEGRATO!")
	fmt.Println("   Health Checking + Load Balancer = Monitoring completo")
}
