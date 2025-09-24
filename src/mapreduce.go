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

const (
	// Map function constants
	mapValueCount = "1"
)

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
		kv := KeyValue{Key: w, Value: mapValueCount}
		kva = append(kva, kv)
	}
	return kva
}

func Reduce(key string, values []string) string {
	return strconv.Itoa(len(values))
}

// Worker runs the worker process for MapReduce
func Worker(mapf func(string, string) []KeyValue, reducef func(string, []string) string) {
	fmt.Println("Worker started - connecting to master cluster...")

	// Ottiene gli indirizzi dei master dalla configurazione
	rpcAddrs := getMasterRpcAddresses()
	if len(rpcAddrs) == 0 {
		fmt.Println("ERRORE: Nessun master configurato!")
		return
	}

	fmt.Printf("Worker connesso a %d master: %v\n", len(rpcAddrs), rpcAddrs)

	// Loop principale del worker
	for {
		// Cerca un master disponibile
		masterAddr := findAvailableMaster(rpcAddrs)
		if masterAddr == "" {
			fmt.Println("Nessun master disponibile, riprovo tra 5 secondi...")
			time.Sleep(5 * time.Second)
			continue
		}

		fmt.Printf("Worker connesso al master: %s\n", masterAddr)

		// Richiede un task dal master
		task := requestTaskFromMaster(masterAddr)
		if task == nil {
			fmt.Println("Nessun task disponibile, riprovo tra 2 secondi...")
			time.Sleep(2 * time.Second)
			continue
		}

		// Esegue il task
		executeTask(task, mapf, reducef)

		// Segnala il completamento del task
		reportTaskCompletion(masterAddr, task)

		// Se il task è di uscita, termina
		if task.Type == ExitTask {
			fmt.Println("Worker ricevuto task di uscita, termino...")
			break
		}
	}

	fmt.Println("Worker terminato")
}

// findAvailableMaster cerca un master disponibile tra quelli configurati
func findAvailableMaster(rpcAddrs []string) string {
	for _, addr := range rpcAddrs {
		// Prova a connettersi al master
		client, err := rpc.DialHTTP("tcp", addr)
		if err != nil {
			continue // Master non disponibile, prova il prossimo
		}

		// Testa la connessione con una chiamata RPC semplice
		var reply Reply
		err = client.Call("Master.RequestTask", RequestTaskArgs{}, &reply)
		client.Close()

		if err == nil {
			return addr // Master disponibile
		}
	}

	return "" // Nessun master disponibile
}

// requestTaskFromMaster richiede un task dal master specificato
func requestTaskFromMaster(masterAddr string) *Task {
	client, err := rpc.DialHTTP("tcp", masterAddr)
	if err != nil {
		fmt.Printf("Errore connessione master %s: %v\n", masterAddr, err)
		return nil
	}
	defer client.Close()

	var task Task
	err = client.Call("Master.RequestTask", RequestTaskArgs{}, &task)
	if err != nil {
		fmt.Printf("Errore richiesta task da %s: %v\n", masterAddr, err)
		return nil
	}

	return &task
}

// executeTask esegue il task assegnato
func executeTask(task *Task, mapf func(string, string) []KeyValue, reducef func(string, []string) string) {
	fmt.Printf("Eseguendo task: Type=%d, TaskID=%d\n", task.Type, task.TaskID)

	switch task.Type {
	case MapTask:
		executeMapTask(task, mapf)
	case ReduceTask:
		executeReduceTask(task, reducef)
	case NoTask:
		fmt.Println("Nessun task da eseguire")
	case ExitTask:
		fmt.Println("Task di uscita ricevuto")
	}
}

// executeMapTask esegue un task di mappatura
func executeMapTask(task *Task, mapf func(string, string) []KeyValue) {
	fmt.Printf("Eseguendo MapTask %d su file: %s\n", task.TaskID, task.Input)

	// Legge il file di input
	file, err := os.Open(task.Input)
	if err != nil {
		fmt.Printf("Errore apertura file %s: %v\n", task.Input, err)
		return
	}
	defer file.Close()

	content, err := io.ReadAll(file)
	if err != nil {
		fmt.Printf("Errore lettura file %s: %v\n", task.Input, err)
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

	fmt.Printf("MapTask %d completato, scritti %d file intermedi\n", task.TaskID, len(intermediate))
}

// executeReduceTask esegue un task di riduzione
func executeReduceTask(task *Task, reducef func(string, []string) string) {
	fmt.Printf("Eseguendo ReduceTask %d\n", task.TaskID)

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

	fmt.Printf("ReduceTask %d completato, scritti %d record\n", task.TaskID, len(results))
}

// reportTaskCompletion segnala il completamento del task al master
func reportTaskCompletion(masterAddr string, task *Task) {
	client, err := rpc.DialHTTP("tcp", masterAddr)
	if err != nil {
		fmt.Printf("Errore connessione master %s per report: %v\n", masterAddr, err)
		return
	}
	defer client.Close()

	args := TaskCompletedArgs{
		TaskID: task.TaskID,
		Type:   task.Type,
	}

	var reply Reply
	err = client.Call("Master.TaskCompleted", args, &reply)
	if err != nil {
		fmt.Printf("Errore report completamento task %d: %v\n", task.TaskID, err)
	} else {
		fmt.Printf("Task %d segnalato come completato\n", task.TaskID)
	}
}

// writeKeyValuesToFile scrive una slice di KeyValue in un file
func writeKeyValuesToFile(filename string, kvs []KeyValue) {
	file, err := os.Create(filename)
	if err != nil {
		fmt.Printf("Errore creazione file %s: %v\n", filename, err)
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
		fmt.Printf("Errore creazione file %s: %v\n", filename, err)
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
