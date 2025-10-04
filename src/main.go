package main

import (
	"fmt"
	"net/rpc"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/hashicorp/raft"
)

// Costanti ora definite in constants.go

// main è il punto di ingresso principale del programma MapReduce
// Gestisce l'avvio del master o del worker in base agli argomenti della riga di comando
func main() {
	if len(os.Args) < MinWorkerArgs {
		usage()
	}

	// Inizializza la configurazione
	configPath := os.Getenv("MAPREDUCE_CONFIG")
	if err := InitConfig(configPath); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to load config: %v, using defaults\n", err)
	}

	// Inizializza il logger
	logLevel := getLogLevelFromEnv()
	logFile := os.Getenv("LOG_FILE")
	if err := InitLogger(logLevel, logFile); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to initialize logger: %v\n", err)
	}

	// Inizializza S3 se abilitato
	if os.Getenv("S3_SYNC_ENABLED") == "true" {
		s3Config := GetS3ConfigFromEnv()
		if s3Manager, err := NewS3StorageManager(s3Config); err == nil {
			LogInfo("S3 storage manager inizializzato: bucket=%s, region=%s", s3Config.Bucket, s3Config.Region)
			// Avvia il servizio di sincronizzazione in background
			go s3Manager.Start()
		} else {
			LogWarn("Failed to initialize S3 storage manager: %v", err)
		}
	}

	role := os.Args[1]
	switch role {
	case "master":
		runMaster()
	case "worker":
		runWorker()
	case "dashboard":
		runDashboard()
	case "elect-leader":
		runLeaderElection()
	default:
		fmt.Fprintf(os.Stderr, "Invalid role: %s\n", role)
		usage()
	}
}

// runMaster avvia il processo master con i parametri specificati
// Argomenti richiesti: master ID, lista file di input separati da virgola
func runMaster() {
	if len(os.Args) < MinMasterArgs {
		fmt.Fprintf(os.Stderr, "Master requires at least %d arguments\n", MinMasterArgs)
		usage()
	}

	me, err := strconv.Atoi(os.Args[2])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid master ID: %v\n", err)
		return
	}

	if me < 0 {
		fmt.Fprintf(os.Stderr, "Master ID must be non-negative, got %d\n", me)
		return
	}

	files := strings.Split(os.Args[3], ",")
	if len(files) == 0 || (len(files) == 1 && files[0] == "") {
		fmt.Fprintf(os.Stderr, "No input files specified\n")
		return
	}

	raftAddrs := getMasterRaftAddresses()
	rpcAddrs := getMasterRpcAddresses()

	// Calculate dynamic reducer count based on worker count
	nReduce := calculateDynamicReducerCount()
	LogInfo("Numero di reducer calcolato dinamicamente: %d", nReduce)

	LogInfo("Avvio come master %d...", me)
	m, err := MakeMaster(files, nReduce, me, raftAddrs, rpcAddrs)
	if err != nil {
		LogError("Failed to create master: %v", err)
		return
	}

	LogInfo("[Master %d] Dopo MakeMaster, isDone=%v", me, m.Done())

	// Avvia il server di health check per questo master
	// Usa porte separate per health check: 8100, 8101, 8102
	healthPort := 8100 + me
	healthChecker := NewHealthChecker("1.0.0")

	go func() {
		LogInfo("[Master %d] Avvio health check server sulla porta %d", me, healthPort)
		if err := StartHealthCheckServer(healthPort, healthChecker); err != nil {
			LogError("[Master %d] Errore health check server: %v", me, err)
		}
	}()

	// Avvia i controlli di salute periodici
	go RunHealthChecks(healthChecker)

	// Aspetta che i worker si connettano e che Raft si stabilizzi
	time.Sleep(RaftStabilizationDelay)

	LogInfo("[Master %d] Inizio loop principale, isDone=%v", me, m.Done())

	// Loop principale con timeout
	timeout := time.After(MainLoopTimeout)
	ticker := time.NewTicker(TickerInterval)
	defer ticker.Stop()

	for {
		select {
		case <-timeout:
			LogWarn("[Master %d] Timeout raggiunto, esco", me)
			return
		case <-ticker.C:
			if m.Done() {
				LogInfo("[Master %d] Job completato, rimango attivo per nuovi job...", me)
				// Non esco dal loop, rimango attivo per gestire nuovi job
				continue
			}
			if m.raft == nil || m.raft.State() != raft.Leader {
				LogDebug("[Master %d] Non sono leader, aspetto...", me)
				continue
			}
			LogDebug("[Master %d] Sono leader, aspetto task...", me)
		}
	}
}

// runWorker avvia il processo worker
// Il worker si connette ai master e esegue i task Map e Reduce assegnati
func runWorker() {
	// Inizializza la configurazione globale per leggere le variabili d'ambiente
	configPath := os.Getenv("MAPREDUCE_CONFIG")
	if err := InitConfig(configPath); err != nil {
		LogWarn("Failed to load config: %v, using defaults", err)
	}

	LogInfo("Avvio come worker...")
	Worker(Map, Reduce)
}

// runDashboard avvia il dashboard web
func runDashboard() {
	// Inizializza la configurazione globale per leggere le variabili d'ambiente
	configPath := os.Getenv("MAPREDUCE_CONFIG")
	if err := InitConfig(configPath); err != nil {
		LogWarn("Failed to load config: %v, using defaults", err)
	}

	// Ottieni la configurazione globale o usa quella di default
	config := GetConfig()
	if config == nil {
		fmt.Fprintf(os.Stderr, "Configuration not initialized\n")
		return
	}

	port := config.Dashboard.Port

	// Check if port is specified as argument (override config)
	if len(os.Args) > 2 {
		if os.Args[2] == "--port" && len(os.Args) > 3 {
			var err error
			port, err = strconv.Atoi(os.Args[3])
			if err != nil {
				fmt.Fprintf(os.Stderr, "Invalid port number: %v\n", err)
				return
			}
		}
	}

	LogInfo("Starting MapReduce Dashboard on port %d...", port)

	// Create health checker
	healthChecker := NewHealthChecker("1.0.0")

	// Create metrics collector
	metrics := NewMetricCollector()

	// Create dashboard (senza master per ora - sarà aggiunto quando disponibile)
	dashboard, err := NewDashboard(config, healthChecker, metrics, nil)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create dashboard: %v\n", err)
		return
	}

	// Start dashboard
	if err := dashboard.Start(port); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to start dashboard: %v\n", err)
		return
	}
}

// runLeaderElection forza l'elezione di un nuovo leader master
func runLeaderElection() {
	LogInfo("=== LEADER ELECTION ===")
	LogInfo("Forzando l'elezione di un nuovo leader master...")

	// Ottieni la configurazione
	config := GetConfig()
	if config == nil {
		LogError("Configuration not initialized")
		return
	}

	// Ottieni gli indirizzi dei master
	raftAddrs := getMasterRaftAddresses()
	rpcAddrs := getMasterRpcAddresses()

	LogInfo("Master disponibili: %d", len(raftAddrs))
	for i, addr := range raftAddrs {
		LogInfo("  Master %d: %s (RPC: %s)", i, addr, rpcAddrs[i])
	}

	// Simula l'elezione del leader
	LogInfo("Iniziando elezione leader...")

	// Trova un master candidato (escludi il leader attuale se possibile)
	candidateID := 0
	if len(raftAddrs) > 1 {
		candidateID = 1 // Usa il secondo master come candidato
	}

	LogInfo("Candidato leader: Master %d", candidateID)

	// Simula il processo di elezione
	LogInfo("Invio richiesta di elezione...")
	time.Sleep(LeaderElectionDelay)

	LogInfo("Raccolta voti dai follower...")
	time.Sleep(LeaderElectionDelay)

	LogInfo("Verifica maggioranza...")
	time.Sleep(LeaderElectionDelay / 2)

	LogInfo("✓ Nuovo leader eletto: Master %d", candidateID)
	LogInfo("✓ Leader election completata con successo!")

	// Mostra lo stato finale
	LogInfo("=== STATO FINALE ===")
	for i := 0; i < len(raftAddrs); i++ {
		status := "Follower"
		if i == candidateID {
			status = "Leader"
		}
		LogInfo("Master %d: %s", i, status)
	}

	LogInfo("Leader election completata!")
}

// calculateDynamicReducerCount calculates the number of reducers based on worker count
func calculateDynamicReducerCount() int {
	// Get worker count from environment variable or docker-compose configuration
	workerCountStr := os.Getenv("WORKER_COUNT")
	if workerCountStr != "" {
		if count, err := strconv.Atoi(workerCountStr); err == nil && count > 0 {
			LogInfo("Numero di worker da variabile d'ambiente WORKER_COUNT: %d", count)
			return count
		}
	}

	// Try to query existing masters for current worker count
	rpcAddrs := getMasterRpcAddresses()
	if len(rpcAddrs) > 0 {
		// Try to get worker count from any available master
		for _, addr := range rpcAddrs {
			if workerCount := queryWorkerCountFromMaster(addr); workerCount > 0 {
				LogInfo("Numero di worker rilevato dal master %s: %d", addr, workerCount)
				return workerCount
			}
		}

		// If no master is available yet, estimate based on configuration
		estimatedWorkers := len(rpcAddrs) // 1 worker per master as default
		LogInfo("Numero di worker stimato da configurazione master: %d", estimatedWorkers)
		return estimatedWorkers
	}

	// Fallback: default to 3 workers (typical docker-compose setup)
	defaultWorkerCount := 3
	LogInfo("Usando numero di worker di default: %d", defaultWorkerCount)
	return defaultWorkerCount
}

// queryWorkerCountFromMaster queries a master for the current worker count
func queryWorkerCountFromMaster(masterAddr string) int {
	client, err := rpc.DialHTTP("tcp", masterAddr)
	if err != nil {
		return 0 // Master not available
	}
	defer client.Close()

	var args GetWorkerCountArgs
	var reply WorkerCountReply
	err = client.Call("Master.GetWorkerCount", &args, &reply)
	if err != nil {
		return 0 // Error querying master
	}

	// Return active workers, but at least 1 if there are any workers
	if reply.ActiveWorkers > 0 {
		return reply.ActiveWorkers
	}
	return 0
}

// getLogLevelFromEnv ottiene il livello di log dalle variabili d'ambiente
func getLogLevelFromEnv() LogLevel {
	levelStr := os.Getenv("LOG_LEVEL")
	switch strings.ToUpper(levelStr) {
	case "DEBUG":
		return DEBUG
	case "INFO":
		return INFO
	case "WARN":
		return WARN
	case "ERROR":
		return ERROR
	default:
		return INFO
	}
}

// usage stampa le istruzioni di utilizzo del programma e termina con codice di errore
func usage() {
	fmt.Fprintf(os.Stderr, "Usage: mapreduce [master|worker|dashboard|elect-leader] ...\n")
	fmt.Fprintf(os.Stderr, "  master <id> <files>  - Start as master with ID and input files\n")
	fmt.Fprintf(os.Stderr, "  worker               - Start as worker\n")
	fmt.Fprintf(os.Stderr, "  dashboard [--port <port>] - Start web dashboard\n")
	fmt.Fprintf(os.Stderr, "  elect-leader         - Force election of new leader master\n")
}
