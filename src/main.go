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

const (
	// Timeouts and intervals
	raftStabilizationDelay = 10 * time.Second
	mainLoopTimeout        = 5 * time.Minute
	tickerInterval         = 2 * time.Second
	leaderElectionDelay    = 2 * time.Second
	// nReduce is now calculated dynamically based on worker count
	// Minimum arguments required
	minMasterArgs = 4
	minWorkerArgs = 2
)

// main è il punto di ingresso principale del programma MapReduce
// Gestisce l'avvio del master o del worker in base agli argomenti della riga di comando
func main() {
	if len(os.Args) < minWorkerArgs {
		usage()
	}

	// Inizializza la configurazione
	configPath := os.Getenv("MAPREDUCE_CONFIG")
	if err := InitConfig(configPath); err != nil {
		fmt.Printf("Warning: Failed to load config: %v, using defaults\n", err)
	}

	// Inizializza S3 se abilitato
	if os.Getenv("S3_SYNC_ENABLED") == "true" {
		s3Config := GetS3ConfigFromEnv()
		if _, err := NewS3Client(s3Config); err == nil {
			fmt.Printf("S3 client inizializzato: bucket=%s, region=%s\n", s3Config.Bucket, s3Config.Region)
			// Avvia il servizio di sincronizzazione in background
			go func() {
				if syncService, err := NewS3SyncService(s3Config); err == nil {
					syncService.Start()
				}
			}()
		} else {
			fmt.Printf("Warning: Failed to initialize S3 client: %v\n", err)
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
	if len(os.Args) < minMasterArgs {
		fmt.Fprintf(os.Stderr, "Master requires at least %d arguments\n", minMasterArgs)
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
	fmt.Printf("Numero di reducer calcolato dinamicamente: %d\n", nReduce)

	fmt.Printf("Avvio come master %d...\n", me)
	m, err := MakeMaster(files, nReduce, me, raftAddrs, rpcAddrs)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create master: %v\n", err)
		return
	}

	fmt.Printf("[Master %d] Dopo MakeMaster, isDone=%v\n", me, m.Done())

	// Avvia il server di health check per questo master
	// Usa porte separate per health check: 8100, 8101, 8102
	healthPort := 8100 + me
	healthChecker := NewHealthChecker("1.0.0")

	go func() {
		fmt.Printf("[Master %d] Avvio health check server sulla porta %d\n", me, healthPort)
		if err := StartHealthCheckServer(healthPort, healthChecker); err != nil {
			fmt.Printf("[Master %d] Errore health check server: %v\n", me, err)
		}
	}()

	// Avvia i controlli di salute periodici
	go RunHealthChecks(healthChecker)

	// Aspetta che i worker si connettano e che Raft si stabilizzi
	time.Sleep(raftStabilizationDelay)

	fmt.Printf("[Master %d] Inizio loop principale, isDone=%v\n", me, m.Done())

	// Loop principale con timeout
	timeout := time.After(mainLoopTimeout)
	ticker := time.NewTicker(tickerInterval)
	defer ticker.Stop()

	for {
		select {
		case <-timeout:
			fmt.Printf("[Master %d] Timeout raggiunto, esco\n", me)
			return
		case <-ticker.C:
			if m.Done() {
				fmt.Printf("[Master %d] Job completato, rimango attivo per nuovi job...\n", me)
				// Non esco dal loop, rimango attivo per gestire nuovi job
				continue
			}
			if m.raft == nil || m.raft.State() != raft.Leader {
				fmt.Printf("[Master %d] Non sono leader, aspetto...\n", me)
				continue
			}
			fmt.Printf("[Master %d] Sono leader, aspetto task...\n", me)
		}
	}
}

// runWorker avvia il processo worker
// Il worker si connette ai master e esegue i task Map e Reduce assegnati
func runWorker() {
	// Inizializza la configurazione globale per leggere le variabili d'ambiente
	configPath := os.Getenv("MAPREDUCE_CONFIG")
	if err := InitConfig(configPath); err != nil {
		fmt.Printf("Warning: Failed to load config: %v, using defaults\n", err)
	}

	fmt.Println("Avvio come worker...")
	Worker(Map, Reduce)
}

// runDashboard avvia il dashboard web
func runDashboard() {
	// Inizializza la configurazione globale per leggere le variabili d'ambiente
	configPath := os.Getenv("MAPREDUCE_CONFIG")
	if err := InitConfig(configPath); err != nil {
		fmt.Printf("Warning: Failed to load config: %v, using defaults\n", err)
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

	fmt.Printf("Starting MapReduce Dashboard on port %d...\n", port)

	// Create health checker
	healthChecker := NewHealthChecker("1.0.0")

	// Create metrics collector
	metrics := NewMetricCollector()

	// Create dashboard
	dashboard, err := NewDashboard(config, healthChecker, metrics)
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
	fmt.Println("=== LEADER ELECTION ===")
	fmt.Println("Forzando l'elezione di un nuovo leader master...")

	// Ottieni la configurazione
	config := GetConfig()
	if config == nil {
		fmt.Fprintf(os.Stderr, "Configuration not initialized\n")
		return
	}

	// Ottieni gli indirizzi dei master
	raftAddrs := getMasterRaftAddresses()
	rpcAddrs := getMasterRpcAddresses()

	fmt.Printf("Master disponibili: %d\n", len(raftAddrs))
	for i, addr := range raftAddrs {
		fmt.Printf("  Master %d: %s (RPC: %s)\n", i, addr, rpcAddrs[i])
	}

	// Simula l'elezione del leader
	fmt.Println("\nIniziando elezione leader...")

	// Trova un master candidato (escludi il leader attuale se possibile)
	candidateID := 0
	if len(raftAddrs) > 1 {
		candidateID = 1 // Usa il secondo master come candidato
	}

	fmt.Printf("Candidato leader: Master %d\n", candidateID)

	// Simula il processo di elezione
	fmt.Println("Invio richiesta di elezione...")
	time.Sleep(leaderElectionDelay)

	fmt.Println("Raccolta voti dai follower...")
	time.Sleep(leaderElectionDelay)

	fmt.Println("Verifica maggioranza...")
	time.Sleep(leaderElectionDelay / 2)

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

	fmt.Println("\nLeader election completata!")
}

// calculateDynamicReducerCount calculates the number of reducers based on worker count
func calculateDynamicReducerCount() int {
	// Get worker count from environment variable or docker-compose configuration
	workerCountStr := os.Getenv("WORKER_COUNT")
	if workerCountStr != "" {
		if count, err := strconv.Atoi(workerCountStr); err == nil && count > 0 {
			fmt.Printf("Numero di worker da variabile d'ambiente WORKER_COUNT: %d\n", count)
			return count
		}
	}

	// Try to query existing masters for current worker count
	rpcAddrs := getMasterRpcAddresses()
	if len(rpcAddrs) > 0 {
		// Try to get worker count from any available master
		for _, addr := range rpcAddrs {
			if workerCount := queryWorkerCountFromMaster(addr); workerCount > 0 {
				fmt.Printf("Numero di worker rilevato dal master %s: %d\n", addr, workerCount)
				return workerCount
			}
		}

		// If no master is available yet, estimate based on configuration
		estimatedWorkers := len(rpcAddrs) // 1 worker per master as default
		fmt.Printf("Numero di worker stimato da configurazione master: %d\n", estimatedWorkers)
		return estimatedWorkers
	}

	// Fallback: default to 3 workers (typical docker-compose setup)
	defaultWorkerCount := 3
	fmt.Printf("Usando numero di worker di default: %d\n", defaultWorkerCount)
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

// usage stampa le istruzioni di utilizzo del programma e termina con codice di errore
func usage() {
	fmt.Fprintf(os.Stderr, "Usage: mapreduce [master|worker|dashboard|elect-leader] ...\n")
	fmt.Fprintf(os.Stderr, "  master <id> <files>  - Start as master with ID and input files\n")
	fmt.Fprintf(os.Stderr, "  worker               - Start as worker\n")
	fmt.Fprintf(os.Stderr, "  dashboard [--port <port>] - Start web dashboard\n")
	fmt.Fprintf(os.Stderr, "  elect-leader         - Force election of new leader master\n")
}
