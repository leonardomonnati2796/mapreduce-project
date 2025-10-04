package main

import (
	"encoding/json"
	"fmt"
	"hash/fnv"
	"io"
	"net/rpc"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode"
)

// Costanti ora definite in constants.go

// KeyValue represents a key-value pair in MapReduce
type KeyValue struct {
	Key   string
	Value string
}

func Map(filename string, contents string) []KeyValue {
	ff := func(r rune) bool { return !unicode.IsLetter(r) }
	words := strings.FieldsFunc(contents, ff)
	kva := []KeyValue{}
	for _, w := range words {
		kv := KeyValue{Key: w, Value: MapValueCount}
		kva = append(kva, kv)
	}
	return kva
}

func Reduce(key string, values []string) string {
	return strconv.Itoa(len(values))
}

// Worker runs the worker process for MapReduce
func Worker(mapf func(string, string) []KeyValue, reducef func(string, []string) string) {
	LogInfo("Worker started - connecting to master cluster...")

	// Determina un ID worker stabile
	workerID := os.Getenv("WORKER_ID")
	if workerID == "" {
		if hn, err := os.Hostname(); err == nil && hn != "" {
			workerID = hn
		} else {
			workerID = fmt.Sprintf("worker-%d", os.Getpid())
		}
	}
	LogInfo("Worker ID: %s", workerID)

	// Ottiene gli indirizzi dei master dalla configurazione
	rpcAddrs := getMasterRpcAddresses()
	if len(rpcAddrs) == 0 {
		LogError("ERRORE: Nessun master configurato!")
		return
	}

	LogInfo("Worker connesso a %d master: %v", len(rpcAddrs), rpcAddrs)

	// Avvia il heartbeat in background
	go func() {
		heartbeatTicker := time.NewTicker(WorkerHeartbeatInterval)
		defer heartbeatTicker.Stop()

		for range heartbeatTicker.C {
			sendHeartbeat(workerID, rpcAddrs)
		}
	}()

	// Loop principale del worker
	for {
		// Cerca un master disponibile
		masterAddr := findAvailableMaster(rpcAddrs, workerID)
		if masterAddr == "" {
			LogWarn("Nessun master disponibile, riprovo tra 5 secondi...")
			time.Sleep(WorkerRetryDelay)
			continue
		}

		LogInfo("Worker connesso al master: %s", masterAddr)

		// Richiede un task dal master
		task := requestTaskFromMaster(masterAddr, workerID)
		if task == nil {
			LogDebug("Nessun task disponibile, riprovo tra 2 secondi...")
			time.Sleep(TaskRetryDelay)
			continue
		}

		// Esegue il task
		executeTask(task, mapf, reducef)

		// Segnala il completamento del task
		reportTaskCompletion(masterAddr, task, workerID)

		// Se il task è di uscita, termina
		if task.Type == ExitTask {
			LogInfo("Worker ricevuto task di uscita, termino...")
			break
		}
	}

	LogInfo("Worker terminato")
}

// findAvailableMaster cerca il master leader tra quelli configurati
func findAvailableMaster(rpcAddrs []string, workerID string) string {
	for _, addr := range rpcAddrs {
		// Prova a connettersi al master
		client, err := rpc.DialHTTP("tcp", addr)
		if err != nil {
			continue // Master non disponibile, prova il prossimo
		}

		// Chiedi informazioni sul master per verificare se è il leader
		var args GetMasterInfoArgs
		var reply MasterInfoReply
		err = client.Call("Master.GetMasterInfo", &args, &reply)
		client.Close()

		if err == nil && reply.IsLeader {
			LogInfo("Worker trovato leader master: %s (ID: %d)", addr, reply.MyID)
			return addr // Master leader disponibile
		}
	}

	// Se nessun leader è stato trovato, prova il primo master disponibile come fallback
	LogWarn("Nessun leader trovato, provo il primo master disponibile...")
	for _, addr := range rpcAddrs {
		client, err := rpc.DialHTTP("tcp", addr)
		if err != nil {
			continue
		}

		var reply Task
		err = client.Call("Master.AssignTask", RequestTaskArgs{WorkerID: workerID}, &reply)
		client.Close()

		if err == nil {
			LogInfo("Worker connesso al master fallback: %s", addr)
			return addr
		}
	}

	return "" // Nessun master disponibile
}

// requestTaskFromMaster richiede un task dal master specificato
func requestTaskFromMaster(masterAddr string, workerID string) *Task {
	client, err := rpc.DialHTTP("tcp", masterAddr)
	if err != nil {
		LogError("Errore connessione master %s: %v", masterAddr, err)
		return nil
	}
	defer client.Close()

	var task Task
	err = client.Call("Master.AssignTask", RequestTaskArgs{WorkerID: workerID}, &task)
	if err != nil {
		LogError("Errore richiesta task da %s: %v", masterAddr, err)
		return nil
	}

	return &task
}

// executeTask esegue il task assegnato
func executeTask(task *Task, mapf func(string, string) []KeyValue, reducef func(string, []string) string) {
	LogInfo("Eseguendo task: Type=%d, TaskID=%d", task.Type, task.TaskID)

	switch task.Type {
	case MapTask:
		executeMapTask(task, mapf)
	case ReduceTask:
		executeReduceTask(task, reducef)
	case NoTask:
		LogDebug("Nessun task da eseguire")
	case ExitTask:
		LogInfo("Task di uscita ricevuto")
	}
}

// executeMapTask esegue un task di mappatura
func executeMapTask(task *Task, mapf func(string, string) []KeyValue) {
	LogInfo("Eseguendo MapTask %d su file: %s", task.TaskID, task.Input)

	// Legge il file di input
	file, err := os.Open(task.Input)
	if err != nil {
		LogError("Errore apertura file %s: %v", task.Input, err)
		return
	}
	defer file.Close()

	content, err := io.ReadAll(file)
	if err != nil {
		LogError("Errore lettura file %s: %v", task.Input, err)
		return
	}

	// Applica la funzione di mappatura
	kva := mapf(task.Input, string(content))

	// Raggruppa i risultati per chiave di riduzione
	intermediate := make(map[int][]KeyValue)
	for _, kv := range kva {
		reduceTaskID := ihash(kv.Key) % task.NReduce
		intermediate[reduceTaskID] = append(intermediate[reduceTaskID], kv)
	}

	// Scrive i file intermedi
	for reduceTaskID, kvs := range intermediate {
		filename := getIntermediateFileName(task.TaskID, reduceTaskID)
		writeKeyValuesToFile(filename, kvs)
	}

	LogInfo("MapTask %d completato, scritti %d file intermedi", task.TaskID, len(intermediate))
}

// executeReduceTask esegue un task di riduzione
func executeReduceTask(task *Task, reducef func(string, []string) string) {
	LogInfo("Eseguendo ReduceTask %d", task.TaskID)

	// Raccoglie tutti i valori per ogni chiave
	keyValues := make(map[string][]string)

	// Legge tutti i file intermedi per questo task di riduzione
	for mapTaskID := 0; mapTaskID < task.NMap; mapTaskID++ {
		filename := getIntermediateFileName(mapTaskID, task.TaskID)
		file, err := os.Open(filename)
		if err != nil {
			continue // File non esiste o errore, continua
		}

		decoder := json.NewDecoder(file)
		for {
			var kv KeyValue
			if err := decoder.Decode(&kv); err != nil {
				break // Fine file o errore
			}
			keyValues[kv.Key] = append(keyValues[kv.Key], kv.Value)
		}
		file.Close()
	}

	// Applica la funzione di riduzione
	var results []string
	for key, values := range keyValues {
		result := reducef(key, values)
		results = append(results, fmt.Sprintf("%s %s", key, result))
	}

	// Scrive il file di output
	outputFile := getOutputFileName(task.TaskID)
	writeStringsToFile(outputFile, results)

	LogInfo("ReduceTask %d completato, scritti %d record", task.TaskID, len(results))
}

// reportTaskCompletion segnala il completamento del task al master
func reportTaskCompletion(masterAddr string, task *Task, workerID string) {
	client, err := rpc.DialHTTP("tcp", masterAddr)
	if err != nil {
		LogError("Errore connessione master %s per report: %v", masterAddr, err)
		return
	}
	defer client.Close()

	args := TaskCompletedArgs{
		TaskID:   task.TaskID,
		Type:     task.Type,
		WorkerID: workerID,
	}

	var reply Reply
	err = client.Call("Master.TaskCompleted", args, &reply)
	if err != nil {
		LogError("Errore report completamento task %d: %v", task.TaskID, err)
	} else {
		LogInfo("Task %d segnalato come completato", task.TaskID)
	}
}

// writeKeyValuesToFile scrive una slice di KeyValue in un file
func writeKeyValuesToFile(filename string, kvs []KeyValue) {
	file, err := os.Create(filename)
	if err != nil {
		LogError("Errore creazione file %s: %v", filename, err)
		return
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	for _, kv := range kvs {
		encoder.Encode(kv)
	}
}

// writeStringsToFile scrive una slice di stringhe in un file
func writeStringsToFile(filename string, lines []string) {
	file, err := os.Create(filename)
	if err != nil {
		LogError("Errore creazione file %s: %v", filename, err)
		return
	}
	defer file.Close()

	for _, line := range lines {
		fmt.Fprintln(file, line)
	}
}

// ihash genera un hash per la distribuzione delle chiavi
func ihash(key string) int {
	h := fnv.New32a()
	h.Write([]byte(key))
	return int(h.Sum32() & 0x7fffffff)
}

// sendHeartbeat invia un heartbeat al master leader
func sendHeartbeat(workerID string, rpcAddrs []string) {
	for _, addr := range rpcAddrs {
		client, err := rpc.DialHTTP("tcp", addr)
		if err != nil {
			continue // Master non disponibile, prova il prossimo
		}

		// Chiedi informazioni sul master per verificare se è il leader
		var args GetMasterInfoArgs
		var reply MasterInfoReply
		err = client.Call("Master.GetMasterInfo", &args, &reply)
		if err == nil && reply.IsLeader {
			// Invia heartbeat al leader
			heartbeatArgs := WorkerHeartbeatArgs{WorkerID: workerID}
			var heartbeatReply WorkerHeartbeatReply
			err = client.Call("Master.WorkerHeartbeat", &heartbeatArgs, &heartbeatReply)
			client.Close()

			if err == nil && heartbeatReply.Success {
				LogDebug("Worker %s: Heartbeat inviato con successo", workerID)
				return
			}
		} else {
			client.Close()
		}
	}
	LogWarn("Worker %s: Nessun leader trovato per heartbeat", workerID)
}
