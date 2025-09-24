package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net"
	"net/http"
	"net/rpc"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/raft"
	raftboltdb "github.com/hashicorp/raft-boltdb/v2"
)

type JobPhase int

const (
	MapPhase JobPhase = iota
	ReducePhase
	DonePhase
)

type TaskState int

const (
	Idle TaskState = iota
	InProgress
	Completed
)

type TaskInfo struct {
	State     TaskState
	StartTime time.Time
}
type LogCommand struct {
	Operation string `json:"operation"`
	TaskID    int    `json:"task_id"`
	// Nuovi campi per gestione dinamica del cluster
	MasterID    int    `json:"master_id,omitempty"`
	RaftAddress string `json:"raft_address,omitempty"`
	RpcAddress  string `json:"rpc_address,omitempty"`
	ClusterInfo string `json:"cluster_info,omitempty"`
}
type Master struct {
	mu              sync.RWMutex
	raft            *raft.Raft
	isDone          bool
	phase           JobPhase
	inputFiles      []string
	nReduce         int
	mapTasks        []TaskInfo
	reduceTasks     []TaskInfo
	mapTasksDone    int
	reduceTasksDone int
	// Nuovi campi per gestione dinamica del cluster
	clusterMembers map[string]string // Raft address -> RPC address
	myID           int
	raftAddrs      []string
	rpcAddrs       []string
}

func (m *Master) Apply(logEntry *raft.Log) interface{} {
	var cmd LogCommand
	if err := json.Unmarshal(logEntry.Data, &cmd); err != nil {
		log.Printf("[Master] Error unmarshaling log entry: %v", err)
		return nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Log del comando ricevuto per debugging
	fmt.Printf("[Master] Apply comando: %s, TaskID: %d, Term: %d, Index: %d\n",
		cmd.Operation, cmd.TaskID, logEntry.Term, logEntry.Index)

	// Ignora comandi se il master non è ancora inizializzato
	if m.inputFiles == nil || len(m.inputFiles) == 0 {
		fmt.Printf("[Master] Ignoro comando %s durante inizializzazione (inputFiles=nil)\n", cmd.Operation)
		return nil
	}

	// Ignora comandi se non ci sono task configurati
	if len(m.mapTasks) == 0 && len(m.reduceTasks) == 0 {
		fmt.Printf("[Master] Ignoro comando %s durante inizializzazione (nessun task)\n", cmd.Operation)
		return nil
	}

	// Se il job è già completato, ignora tutti i comandi
	if m.isDone {
		fmt.Printf("[Master] Ignoro comando %s - job già completato\n", cmd.Operation)
		return nil
	}

	switch cmd.Operation {
	case "complete-map":
		if cmd.TaskID >= 0 && cmd.TaskID < len(m.mapTasks) {
			if m.mapTasks[cmd.TaskID].State != Completed {
				m.mapTasks[cmd.TaskID].State = Completed
				m.mapTasksDone++
				fmt.Printf("[Master] MapTask %d completato, progresso: %d/%d\n",
					cmd.TaskID, m.mapTasksDone, len(m.mapTasks))
				if m.mapTasksDone == len(m.mapTasks) {
					m.phase = ReducePhase
					fmt.Printf("[Master] Transizione a ReducePhase\n")
				}
			}
		} else {
			log.Printf("[Master] TaskID %d fuori range per MapTask (max: %d)\n", cmd.TaskID, len(m.mapTasks)-1)
		}
	case "add-master":
		// Gestisce l'aggiunta di un nuovo master al cluster
		if cmd.RaftAddress != "" && cmd.RpcAddress != "" {
			m.clusterMembers[cmd.RaftAddress] = cmd.RpcAddress
			fmt.Printf("[Master] Nuovo master aggiunto al cluster: %s -> %s\n", cmd.RaftAddress, cmd.RpcAddress)

			// Forza una nuova elezione del leader
			go func() {
				time.Sleep(2 * time.Second)
				fmt.Printf("[Master] Forzando nuova elezione del leader dopo aggiunta master\n")
				// Il leader attuale può dimettersi per forzare una nuova elezione
				if m.raft.State() == raft.Leader {
					m.raft.LeadershipTransfer()
				}
			}()
		}
	case "remove-master":
		// Gestisce la rimozione di un master dal cluster
		if cmd.RaftAddress != "" {
			delete(m.clusterMembers, cmd.RaftAddress)
			fmt.Printf("[Master] Master rimosso dal cluster: %s\n", cmd.RaftAddress)
		}
	case "complete-reduce":
		if cmd.TaskID >= 0 && cmd.TaskID < len(m.reduceTasks) {
			if m.reduceTasks[cmd.TaskID].State != Completed {
				m.reduceTasks[cmd.TaskID].State = Completed
				m.reduceTasksDone++
				fmt.Printf("[Master] ReduceTask %d completato, progresso: %d/%d\n",
					cmd.TaskID, m.reduceTasksDone, len(m.reduceTasks))
				if m.reduceTasksDone == len(m.reduceTasks) {
					m.phase = DonePhase
					m.isDone = true
					fmt.Printf("[Master] Job completato - transizione a DonePhase\n")
					// Copia i file di output dal volume Docker alla cartella locale
					m.copyOutputFilesToLocal()
				}
			}
		} else {
			log.Printf("[Master] TaskID %d fuori range per ReduceTask (max: %d)\n", cmd.TaskID, len(m.reduceTasks)-1)
		}
	case "reset-task":
		// Nuovo comando per reset di task in caso di fallimento worker
		if cmd.TaskID >= 0 {
			if m.phase == MapPhase && cmd.TaskID < len(m.mapTasks) {
				if m.mapTasks[cmd.TaskID].State == InProgress {
					m.mapTasks[cmd.TaskID].State = Idle
					fmt.Printf("[Master] MapTask %d resettato a Idle per riassegnazione\n", cmd.TaskID)
				}
			} else if m.phase == ReducePhase && cmd.TaskID < len(m.reduceTasks) {
				if m.reduceTasks[cmd.TaskID].State == InProgress {
					m.reduceTasks[cmd.TaskID].State = Idle
					fmt.Printf("[Master] ReduceTask %d resettato a Idle per riassegnazione\n", cmd.TaskID)
				}
			}
		}
	default:
		log.Printf("[Master] Comando sconosciuto: %s\n", cmd.Operation)
	}
	return nil
}

// Snapshot structures the FSM state into a durable snapshot.
func (m *Master) Snapshot() (raft.FSMSnapshot, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	state := struct {
		IsDone          bool
		Phase           JobPhase
		InputFiles      []string
		NReduce         int
		MapTasks        []TaskInfo
		ReduceTasks     []TaskInfo
		MapTasksDone    int
		ReduceTasksDone int
	}{
		IsDone:          m.isDone,
		Phase:           m.phase,
		InputFiles:      append([]string(nil), m.inputFiles...),
		NReduce:         m.nReduce,
		MapTasks:        append([]TaskInfo(nil), m.mapTasks...),
		ReduceTasks:     append([]TaskInfo(nil), m.reduceTasks...),
		MapTasksDone:    m.mapTasksDone,
		ReduceTasksDone: m.reduceTasksDone,
	}
	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(state); err != nil {
		return nil, err
	}
	snap := &memorySnapshot{data: buf.Bytes()}
	return snap, nil
}

type memorySnapshot struct{ data []byte }

func (s *memorySnapshot) Persist(sink raft.SnapshotSink) error {
	if _, err := sink.Write(s.data); err != nil {
		sink.Cancel()
		return err
	}
	return sink.Close()
}

func (s *memorySnapshot) Release() {}

// Restore rehydrates the FSM state from a snapshot stream.
func (m *Master) Restore(rc io.ReadCloser) error {
	defer rc.Close()
	var state struct {
		IsDone          bool
		Phase           JobPhase
		InputFiles      []string
		NReduce         int
		MapTasks        []TaskInfo
		ReduceTasks     []TaskInfo
		MapTasksDone    int
		ReduceTasksDone int
	}
	dec := json.NewDecoder(rc)
	if err := dec.Decode(&state); err != nil {
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	fmt.Printf("[Master] Restore chiamato: isDone=%v, phase=%v\n", state.IsDone, state.Phase)
	m.isDone = state.IsDone
	m.phase = state.Phase
	m.inputFiles = state.InputFiles
	m.nReduce = state.NReduce
	m.mapTasks = state.MapTasks
	m.reduceTasks = state.ReduceTasks
	m.mapTasksDone = state.MapTasksDone
	m.reduceTasksDone = state.ReduceTasksDone
	return nil
}

// isMapTaskCompleted verifica se un MapTask è completato controllando l'esistenza dei file intermedi
func (m *Master) isMapTaskCompleted(taskID int) bool {
	if taskID < 0 || taskID >= len(m.mapTasks) {
		return false
	}

	// Verifica che tutti i file intermedi per questo MapTask esistano
	for i := 0; i < m.nReduce; i++ {
		fileName := getIntermediateFileName(taskID, i)
		if _, err := os.Stat(fileName); os.IsNotExist(err) {
			fmt.Printf("[Master] MapTask %d incompleto: file %s mancante\n", taskID, fileName)
			return false
		}
	}

	fmt.Printf("[Master] MapTask %d completato: tutti i file intermedi presenti\n", taskID)
	return true
}

// areAllMapTasksCompleted verifica se tutti i MapTask sono completati
func (m *Master) areAllMapTasksCompleted() bool {
	for i := 0; i < len(m.mapTasks); i++ {
		if !m.isMapTaskCompleted(i) {
			return false
		}
	}
	return true
}

// validateMapTaskOutput verifica la validità dei file intermedi di un MapTask
func (m *Master) validateMapTaskOutput(taskID int) bool {
	if taskID < 0 || taskID >= len(m.mapTasks) {
		return false
	}

	// Verifica che tutti i file intermedi esistano e siano leggibili
	for i := 0; i < m.nReduce; i++ {
		fileName := getIntermediateFileName(taskID, i)
		file, err := os.Open(fileName)
		if err != nil {
			fmt.Printf("[Master] MapTask %d invalido: errore apertura file %s: %v\n", taskID, fileName, err)
			return false
		}

		// Verifica che il file contenga dati JSON validi
		decoder := json.NewDecoder(file)
		var kv KeyValue
		hasData := false
		for decoder.More() {
			if err := decoder.Decode(&kv); err != nil {
				fmt.Printf("[Master] MapTask %d invalido: errore decodifica JSON in %s: %v\n", taskID, fileName, err)
				file.Close()
				return false
			}
			hasData = true
		}
		file.Close()

		if !hasData {
			fmt.Printf("[Master] MapTask %d invalido: file %s vuoto\n", taskID, fileName)
			return false
		}
	}

	fmt.Printf("[Master] MapTask %d valido: tutti i file intermedi sono validi\n", taskID)
	return true
}

// cleanupInvalidMapTask rimuove i file intermedi di un MapTask invalido
func (m *Master) cleanupInvalidMapTask(taskID int) {
	if taskID < 0 || taskID >= len(m.mapTasks) {
		return
	}

	fmt.Printf("[Master] Pulizia MapTask %d invalido\n", taskID)
	for i := 0; i < m.nReduce; i++ {
		fileName := getIntermediateFileName(taskID, i)
		if err := os.Remove(fileName); err != nil && !os.IsNotExist(err) {
			fmt.Printf("[Master] Errore rimozione file %s: %v\n", fileName, err)
		}
	}
}

// isReduceTaskCompleted verifica se un ReduceTask è completato controllando l'esistenza del file di output
func (m *Master) isReduceTaskCompleted(taskID int) bool {
	if taskID < 0 || taskID >= len(m.reduceTasks) {
		return false
	}

	fileName := getOutputFileName(taskID)
	if _, err := os.Stat(fileName); os.IsNotExist(err) {
		fmt.Printf("[Master] ReduceTask %d incompleto: file %s mancante\n", taskID, fileName)
		return false
	}

	fmt.Printf("[Master] ReduceTask %d completato: file output presente\n", taskID)
	return true
}

// validateReduceTaskOutput verifica la validità del file di output di un ReduceTask
func (m *Master) validateReduceTaskOutput(taskID int) bool {
	if taskID < 0 || taskID >= len(m.reduceTasks) {
		return false
	}

	fileName := getOutputFileName(taskID)
	file, err := os.Open(fileName)
	if err != nil {
		fmt.Printf("[Master] ReduceTask %d invalido: errore apertura file %s: %v\n", taskID, fileName, err)
		return false
	}
	defer file.Close()

	// Verifica che il file contenga dati validi
	scanner := bufio.NewScanner(file)
	hasData := false
	lineCount := 0
	for scanner.Scan() {
		line := scanner.Text()
		if len(line) > 0 {
			hasData = true
			lineCount++
		}
	}

	if err := scanner.Err(); err != nil {
		fmt.Printf("[Master] ReduceTask %d invalido: errore lettura file %s: %v\n", taskID, fileName, err)
		return false
	}

	if !hasData {
		fmt.Printf("[Master] ReduceTask %d invalido: file %s vuoto\n", taskID, fileName)
		return false
	}

	fmt.Printf("[Master] ReduceTask %d valido: file %s contiene %d righe\n", taskID, fileName, lineCount)
	return true
}

// cleanupInvalidReduceTask rimuove il file di output di un ReduceTask invalido
func (m *Master) cleanupInvalidReduceTask(taskID int) {
	if taskID < 0 || taskID >= len(m.reduceTasks) {
		return
	}

	fmt.Printf("[Master] Pulizia ReduceTask %d invalido\n", taskID)
	fileName := getOutputFileName(taskID)
	if err := os.Remove(fileName); err != nil && !os.IsNotExist(err) {
		fmt.Printf("[Master] Errore rimozione file %s: %v\n", fileName, err)
	}
}

func (m *Master) AssignTask(args *RequestTaskArgs, reply *Task) error {
	fmt.Printf("[Master] AssignTask chiamato, stato Raft: %v, isDone: %v\n", m.raft.State(), m.isDone)
	if m.raft.State() != raft.Leader {
		fmt.Printf("[Master] Non sono leader, restituisco NoTask\n")
		reply.Type = NoTask
		return nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.isDone {
		fmt.Printf("[Master] Job completato, restituisco ExitTask\n")
		reply.Type = ExitTask
		return nil
	}
	var taskToDo *Task
	fmt.Printf("[Master] Fase corrente: %v, mapTasks: %d, reduceTasks: %d\n", m.phase, len(m.mapTasks), len(m.reduceTasks))
	if m.phase == MapPhase {
		for id, info := range m.mapTasks {
			fmt.Printf("[Master] MapTask %d: stato=%v\n", id, info.State)
			if info.State == Idle {
				// Verifica se il MapTask è già stato completato (file intermedi esistenti)
				if m.isMapTaskCompleted(id) {
					fmt.Printf("[Master] MapTask %d già completato (file intermedi esistenti), marco come Completed\n", id)
					m.mapTasks[id].State = Completed
					m.mapTasksDone++
					if m.mapTasksDone == len(m.mapTasks) {
						m.phase = ReducePhase
						fmt.Printf("[Master] Tutti i MapTask completati, transizione a ReducePhase\n")
					}
					continue
				}
				taskToDo = &Task{Type: MapTask, TaskID: id, Input: m.inputFiles[id], NReduce: m.nReduce}
				m.mapTasks[id].State = InProgress
				m.mapTasks[id].StartTime = time.Now()
				fmt.Printf("[Master] Assegnato MapTask %d: %s\n", id, m.inputFiles[id])
				break
			} else if info.State == InProgress {
				// Verifica se il task è effettivamente completato (file intermedi esistenti)
				if m.isMapTaskCompleted(id) {
					fmt.Printf("[Master] MapTask %d in InProgress ma file intermedi presenti, marco come Completed\n", id)
					m.mapTasks[id].State = Completed
					m.mapTasksDone++
					if m.mapTasksDone == len(m.mapTasks) {
						m.phase = ReducePhase
						fmt.Printf("[Master] Tutti i MapTask completati, transizione a ReducePhase\n")
					}
					continue
				}
				// Il task è in InProgress ma non è completato, potrebbe essere bloccato
				// Riassegna il task
				taskToDo = &Task{Type: MapTask, TaskID: id, Input: m.inputFiles[id], NReduce: m.nReduce}
				m.mapTasks[id].State = InProgress
				m.mapTasks[id].StartTime = time.Now()
				fmt.Printf("[Master] Riassegnato MapTask %d in InProgress: %s\n", id, m.inputFiles[id])
				break
			} else if info.State == Completed {
				// Verifica se i file intermedi sono ancora validi
				if !m.validateMapTaskOutput(id) {
					fmt.Printf("[Master] MapTask %d marcato come Completed ma file intermedi invalidi, resetto a Idle\n", id)
					m.mapTasks[id].State = Idle
					m.mapTasksDone--
					m.cleanupInvalidMapTask(id)
					taskToDo = &Task{Type: MapTask, TaskID: id, Input: m.inputFiles[id], NReduce: m.nReduce}
					m.mapTasks[id].State = InProgress
					m.mapTasks[id].StartTime = time.Now()
					fmt.Printf("[Master] Riassegnato MapTask %d: %s\n", id, m.inputFiles[id])
					break
				}
			}
		}

		// Verifica esplicita se tutti i MapTask sono completati
		if taskToDo == nil && m.phase == MapPhase {
			// Conta i MapTask effettivamente completati
			actualMapDone := 0
			for _, task := range m.mapTasks {
				if task.State == Completed {
					actualMapDone++
				}
			}
			if actualMapDone == len(m.mapTasks) {
				m.mapTasksDone = actualMapDone
				m.phase = ReducePhase
				fmt.Printf("[Master] Tutti i MapTask completati (%d/%d), transizione a ReducePhase\n", actualMapDone, len(m.mapTasks))
			}
		}
	} else if m.phase == ReducePhase {
		for id, info := range m.reduceTasks {
			fmt.Printf("[Master] ReduceTask %d: stato=%v\n", id, info.State)
			if info.State == Idle {
				// Verifica se tutti i file intermedi necessari esistono
				if !m.areAllMapTasksCompleted() {
					fmt.Printf("[Master] ReduceTask %d non può essere assegnato: MapTask non completati\n", id)
					continue
				}

				// Verifica se il ReduceTask è già stato completato (file di output esistente)
				if m.isReduceTaskCompleted(id) {
					fmt.Printf("[Master] ReduceTask %d già completato (file output esistente), marco come Completed\n", id)
					m.reduceTasks[id].State = Completed
					m.reduceTasksDone++
					if m.reduceTasksDone == len(m.reduceTasks) {
						m.phase = DonePhase
						m.isDone = true
						fmt.Printf("[Master] Tutti i ReduceTask completati, transizione a DonePhase\n")
					}
					continue
				}

				taskToDo = &Task{Type: ReduceTask, TaskID: id, NMap: len(m.mapTasks)}
				m.reduceTasks[id].State = InProgress
				m.reduceTasks[id].StartTime = time.Now()
				fmt.Printf("[Master] Assegnato ReduceTask %d\n", id)
				break
			} else if info.State == Completed {
				// Verifica se il file di output è ancora valido
				if !m.validateReduceTaskOutput(id) {
					fmt.Printf("[Master] ReduceTask %d marcato come Completed ma file output invalido, resetto a Idle\n", id)
					m.reduceTasks[id].State = Idle
					m.reduceTasksDone--
					m.cleanupInvalidReduceTask(id)
					taskToDo = &Task{Type: ReduceTask, TaskID: id, NMap: len(m.mapTasks)}
					m.reduceTasks[id].State = InProgress
					m.reduceTasks[id].StartTime = time.Now()
					fmt.Printf("[Master] Riassegnato ReduceTask %d\n", id)
					break
				}
			}
		}
	}
	if taskToDo != nil {
		*reply = *taskToDo
		fmt.Printf("[Master] Restituisco task: %v\n", *taskToDo)
	} else {
		*reply = Task{Type: NoTask}
		fmt.Printf("[Master] Nessun task disponibile, restituisco NoTask\n")
	}
	return nil
}
func (m *Master) TaskCompleted(args *TaskCompletedArgs, reply *Reply) error {
	if m.raft.State() != raft.Leader {
		return nil
	}

	fmt.Printf("[Master] TaskCompleted ricevuto: Type=%v, TaskID=%d\n", args.Type, args.TaskID)

	// Validazione specifica per MapTask
	if args.Type == MapTask {
		if args.TaskID < 0 || args.TaskID >= len(m.mapTasks) {
			log.Printf("[Master] TaskID %d fuori range per MapTask\n", args.TaskID)
			return fmt.Errorf("TaskID %d fuori range", args.TaskID)
		}

		// Verifica che i file intermedi siano stati creati correttamente
		if !m.validateMapTaskOutput(args.TaskID) {
			log.Printf("[Master] MapTask %d completato ma file intermedi invalidi, rifiuto completamento\n", args.TaskID)
			return fmt.Errorf("MapTask %d file intermedi invalidi", args.TaskID)
		}

		fmt.Printf("[Master] MapTask %d completato e validato correttamente\n", args.TaskID)
	} else if args.Type == ReduceTask {
		if args.TaskID < 0 || args.TaskID >= len(m.reduceTasks) {
			log.Printf("[Master] TaskID %d fuori range per ReduceTask\n", args.TaskID)
			return fmt.Errorf("TaskID %d fuori range", args.TaskID)
		}

		// Verifica che il file di output sia stato creato correttamente
		if !m.validateReduceTaskOutput(args.TaskID) {
			log.Printf("[Master] ReduceTask %d completato ma file output invalido, rifiuto completamento\n", args.TaskID)
			return fmt.Errorf("ReduceTask %d file output invalido", args.TaskID)
		}

		fmt.Printf("[Master] ReduceTask %d completato e validato correttamente\n", args.TaskID)
	}

	op := "complete-reduce"
	if args.Type == MapTask {
		op = "complete-map"
	}

	cmd := LogCommand{Operation: op, TaskID: args.TaskID}
	cmdBytes, err := json.Marshal(cmd)
	if err != nil {
		log.Printf("[Master] Error marshaling command: %v", err)
		return err
	}

	applyFuture := m.raft.Apply(cmdBytes, 500*time.Millisecond)
	if err := applyFuture.Error(); err != nil {
		log.Printf("[Master] Error applying command %v: %v", cmd, err)
		return err
	}

	fmt.Printf("[Master] TaskCompleted applicato con successo: %s TaskID=%d\n", op, args.TaskID)
	return nil
}
func (m *Master) Done() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.isDone
}

// RecoveryState verifica e ripristina lo stato dopo l'elezione del leader
func (m *Master) RecoveryState() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.raft.State() != raft.Leader {
		return
	}

	fmt.Printf("[Master] RecoveryState: verifico stato dopo elezione leader\n")
	fmt.Printf("[Master] Stato corrente: isDone=%v, phase=%v, mapTasksDone=%d/%d, reduceTasksDone=%d/%d\n",
		m.isDone, m.phase, m.mapTasksDone, len(m.mapTasks), m.reduceTasksDone, len(m.reduceTasks))

	// Verifica consistenza dello stato
	if m.phase == MapPhase {
		// Conta i MapTask completati
		actualMapDone := 0
		for _, task := range m.mapTasks {
			if task.State == Completed {
				actualMapDone++
			}
		}
		if actualMapDone != m.mapTasksDone {
			fmt.Printf("[Master] Correzione mapTasksDone: %d -> %d\n", m.mapTasksDone, actualMapDone)
			m.mapTasksDone = actualMapDone
		}

		// Se tutti i MapTask sono completati, passa a ReducePhase
		if m.mapTasksDone == len(m.mapTasks) && m.phase == MapPhase {
			m.phase = ReducePhase
			fmt.Printf("[Master] RecoveryState: transizione a ReducePhase\n")
		}
	} else if m.phase == ReducePhase {
		// Conta i ReduceTask completati
		actualReduceDone := 0
		for _, task := range m.reduceTasks {
			if task.State == Completed {
				actualReduceDone++
			}
		}
		if actualReduceDone != m.reduceTasksDone {
			fmt.Printf("[Master] Correzione reduceTasksDone: %d -> %d\n", m.reduceTasksDone, actualReduceDone)
			m.reduceTasksDone = actualReduceDone
		}

		// Se tutti i ReduceTask sono completati, passa a DonePhase
		if m.reduceTasksDone == len(m.reduceTasks) && m.phase == ReducePhase {
			m.phase = DonePhase
			m.isDone = true
			fmt.Printf("[Master] RecoveryState: transizione a DonePhase\n")
		}
	}

	fmt.Printf("[Master] RecoveryState completato: isDone=%v, phase=%v\n", m.isDone, m.phase)
}
func MakeMaster(files []string, nReduce int, me int, raftAddrs []string, rpcAddrs []string) *Master {
	// Inizializza il generatore di numeri casuali per il delay
	rand.Seed(time.Now().UnixNano() + int64(me))

	m := &Master{
		inputFiles: files, nReduce: nReduce,
		mapTasks: make([]TaskInfo, len(files)), reduceTasks: make([]TaskInfo, nReduce),
		phase:  MapPhase,
		isDone: false, // Forza isDone=false esplicitamente
		// Inizializza i nuovi campi per gestione dinamica del cluster
		clusterMembers: make(map[string]string),
		myID:           me,
		raftAddrs:      raftAddrs,
		rpcAddrs:       rpcAddrs,
	}

	// Popola la mappa dei membri del cluster
	for i, raftAddr := range raftAddrs {
		if i < len(rpcAddrs) {
			m.clusterMembers[raftAddr] = rpcAddrs[i]
		}
	}
	fmt.Printf("[Master %d] Inizializzazione: isDone=%v, phase=%v\n", me, m.isDone, m.phase)
	config := raft.DefaultConfig()
	config.LocalID = raft.ServerID(raftAddrs[me])
	config.Logger = hclog.New(&hclog.LoggerOptions{Name: fmt.Sprintf("Raft-%s", raftAddrs[me]), Level: hclog.Info, Output: os.Stderr})

	// Configura timeout più equi per l'elezione
	// Aggiunge variabilità ai timeout per evitare elezioni simultanee
	baseElectionTimeout := 1000 * time.Millisecond
	randomOffset := time.Duration(rand.Intn(500)) * time.Millisecond // 0-500ms di offset
	config.ElectionTimeout = baseElectionTimeout + randomOffset
	config.HeartbeatTimeout = 200 * time.Millisecond
	config.LeaderLeaseTimeout = 150 * time.Millisecond // Deve essere < HeartbeatTimeout

	fmt.Printf("[Master %d] Configurazione Raft: ElectionTimeout=%v, HeartbeatTimeout=%v\n",
		me, config.ElectionTimeout, config.HeartbeatTimeout)
	raftAddr := raftAddrs[me]
	advertiseAddr, _ := net.ResolveTCPAddr("tcp", raftAddr)
	transport, err := raft.NewTCPTransport(raftAddr, advertiseAddr, 3, 10*time.Second, os.Stderr)
	if err != nil {
		log.Fatalf("transport: %s", err)
	}
	raftDir := fmt.Sprintf("./raft-data/%d", me)

	// Opzione per pulizia manuale (solo se esplicitamente richiesta)
	if os.Getenv("RAFT_CLEAN_START") == "true" {
		fmt.Printf("[Master %d] Pulizia dati Raft richiesta esplicitamente\n", me)
		os.RemoveAll(raftDir)
	}

	// Crea la directory Raft se non esiste (mantiene i dati esistenti per fault tolerance)
	os.MkdirAll(raftDir, 0700)
	fmt.Printf("[Master %d] Directory Raft preparata: %s\n", me, raftDir)

	// Reset esplicito dello stato PRIMA della creazione di Raft
	m.mu.Lock()
	m.isDone = false
	m.phase = MapPhase
	m.mapTasksDone = 0
	m.reduceTasksDone = 0
	// Reset tutti i task a Idle
	for i := range m.mapTasks {
		m.mapTasks[i] = TaskInfo{State: Idle}
	}
	for i := range m.reduceTasks {
		m.reduceTasks[i] = TaskInfo{State: Idle}
	}
	m.mu.Unlock()
	fmt.Printf("[Master %d] Reset stato PRIMA di Raft: isDone=%v, phase=%v\n", me, m.isDone, m.phase)
	logStore, err := raftboltdb.New(raftboltdb.Options{Path: filepath.Join(raftDir, "log.db")})
	if err != nil {
		log.Fatalf("Failed to create log store: %s", err)
	}
	stableStore, err := raftboltdb.New(raftboltdb.Options{Path: filepath.Join(raftDir, "stable.db")})
	if err != nil {
		log.Fatalf("Failed to create stable store: %s", err)
	}
	snapshotStore, err := raft.NewFileSnapshotStore(raftDir, 2, os.Stderr)
	if err != nil {
		log.Fatalf("Failed to create snapshot store: %s", err)
	}
	ra, err := raft.NewRaft(config, m, logStore, stableStore, snapshotStore, transport)
	if err != nil {
		log.Fatalf("raft: %s", err)
	}
	m.raft = ra
	fmt.Printf("[Master %d] Dopo creazione Raft: isDone=%v, phase=%v\n", me, m.isDone, m.phase)

	// Verifica che i file Raft siano stati creati correttamente
	logPath := filepath.Join(raftDir, "log.db")
	stablePath := filepath.Join(raftDir, "stable.db")
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		fmt.Printf("[Master %d] ATTENZIONE: File log.db non creato in %s\n", me, logPath)
	} else {
		fmt.Printf("[Master %d] File log.db creato correttamente in %s\n", me, logPath)
	}
	if _, err := os.Stat(stablePath); os.IsNotExist(err) {
		fmt.Printf("[Master %d] ATTENZIONE: File stable.db non creato in %s\n", me, stablePath)
	} else {
		fmt.Printf("[Master %d] File stable.db creato correttamente in %s\n", me, stablePath)
	}

	// Aspetta che Raft si stabilizzi prima di procedere
	time.Sleep(2 * time.Second)

	// Monitor dello stato Raft per recovery automatico
	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()
		var lastState raft.RaftState

		for range ticker.C {
			currentState := m.raft.State()
			if currentState != lastState {
				fmt.Printf("[Master %d] Cambio stato Raft: %v -> %v\n", me, lastState, currentState)
				lastState = currentState

				// Se diventa leader, esegui recovery dello stato
				if currentState == raft.Leader {
					fmt.Printf("[Master %d] Diventato leader, eseguo recovery dello stato\n", me)
					m.RecoveryState()
				}
			}
		}
	}()

	fmt.Printf("[Master %d] Stato finale dopo inizializzazione: isDone=%v, phase=%v, mapTasks=%d, reduceTasks=%d\n",
		me, m.isDone, m.phase, len(m.mapTasks), len(m.reduceTasks))

	// Avvia il monitor per la gestione dinamica del cluster
	go m.startClusterManagementMonitor()

	// Implementa un sistema di elezione più equo
	// Solo un master alla volta può fare il bootstrap, con delay casuale
	go func() {
		// Delay casuale per evitare elezioni simultanee
		randomDelay := time.Duration(rand.Intn(3000)) * time.Millisecond // 0-3 secondi
		time.Sleep(randomDelay)

		// Controlla se il cluster è già stato bootstrappato
		config := m.raft.GetConfiguration()
		if config.Error() != nil || len(config.Configuration().Servers) == 0 {
			// Solo se il cluster non è ancora configurato, procedi con il bootstrap
			servers := make([]raft.Server, len(raftAddrs))
			for i, addrStr := range raftAddrs {
				servers[i] = raft.Server{ID: raft.ServerID(addrStr), Address: raft.ServerAddress(addrStr)}
			}

			fmt.Printf("[Master %d] Tentativo bootstrap con delay %v\n", me, randomDelay)
			bootstrapFuture := m.raft.BootstrapCluster(raft.Configuration{Servers: servers})
			if err := bootstrapFuture.Error(); err != nil {
				log.Printf("[Master %d] Bootstrap fallito (probabilmente già configurato): %s", me, err)
			} else {
				fmt.Printf("[Master %d] Bootstrap completato con successo\n", me)
			}
		} else {
			fmt.Printf("[Master %d] Cluster già configurato, salto bootstrap\n", me)
		}
	}()
	rpc.Register(m)
	rpc.HandleHTTP()

	go func() {
		l, e := net.Listen("tcp", rpcAddrs[me])
		if e != nil {
			log.Fatalf("RPC listen: %s", e)
		}
		http.Serve(l, nil)
	}()
	// Task timeout monitor: re-queue stuck tasks if the leader does not receive completion in time.
	go func() {
		const taskTimeout = 15 * time.Second
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if m.raft.State() != raft.Leader {
				continue
			}
			now := time.Now()
			m.mu.Lock()
			if m.phase == MapPhase {
				for i, info := range m.mapTasks {
					if info.State == InProgress && now.Sub(info.StartTime) > taskTimeout {
						// Reset task e logga il comando per recovery
						m.mapTasks[i] = TaskInfo{State: Idle}
						fmt.Printf("[Master] MapTask %d timeout, resettato a Idle\n", i)

						// Applica il reset tramite Raft per consistency
						cmd := LogCommand{Operation: "reset-task", TaskID: i}
						cmdBytes, err := json.Marshal(cmd)
						if err == nil {
							m.raft.Apply(cmdBytes, 500*time.Millisecond)
						}
					}
				}
			} else if m.phase == ReducePhase {
				for i, info := range m.reduceTasks {
					if info.State == InProgress && now.Sub(info.StartTime) > taskTimeout {
						// Reset task e logga il comando per recovery
						m.reduceTasks[i] = TaskInfo{State: Idle}
						fmt.Printf("[Master] ReduceTask %d timeout, resettato a Idle\n", i)

						// Applica il reset tramite Raft per consistency
						cmd := LogCommand{Operation: "reset-task", TaskID: i}
						cmdBytes, err := json.Marshal(cmd)
						if err == nil {
							m.raft.Apply(cmdBytes, 500*time.Millisecond)
						}
					}
				}
			}
			m.mu.Unlock()
		}
	}()

	// File validation monitor: verifica periodicamente la validità dei file intermedi e di output
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if m.raft.State() != raft.Leader {
				continue
			}

			m.mu.Lock()
			if m.phase == MapPhase {
				for i, info := range m.mapTasks {
					if info.State == Completed {
						// Verifica periodicamente che i file intermedi siano ancora validi
						if !m.validateMapTaskOutput(i) {
							fmt.Printf("[Master] MapTask %d file intermedi corrotti, resetto a Idle\n", i)
							m.mapTasks[i].State = Idle
							m.mapTasksDone--
							m.cleanupInvalidMapTask(i)
						}
					}
				}
			} else if m.phase == ReducePhase {
				for i, info := range m.reduceTasks {
					if info.State == Completed {
						// Verifica periodicamente che i file di output siano ancora validi
						if !m.validateReduceTaskOutput(i) {
							fmt.Printf("[Master] ReduceTask %d file output corrotti, resetto a Idle\n", i)
							m.reduceTasks[i].State = Idle
							m.reduceTasksDone--
							m.cleanupInvalidReduceTask(i)
						}
					}
				}
			}
			m.mu.Unlock()
		}
	}()
	return m
}

// SubmitJob gestisce la sottomissione di nuovi job MapReduce
type SubmitJobArgs struct {
	InputFiles []string `json:"input_files"`
	NReduce    int      `json:"n_reduce"`
}

type SubmitJobReply struct {
	JobID  string `json:"job_id"`
	Status string `json:"status"`
}

// IsLeader verifica se questo master è il leader
type IsLeaderArgs struct{}
type IsLeaderReply struct {
	IsLeader bool   `json:"is_leader"`
	State    string `json:"state"`
}

func (m *Master) IsLeader(args *IsLeaderArgs, reply *IsLeaderReply) error {
	*reply = IsLeaderReply{
		IsLeader: m.raft.State() == raft.Leader,
		State:    m.raft.State().String(),
	}
	return nil
}

func (m *Master) SubmitJob(args *SubmitJobArgs, reply *SubmitJobReply) error {
	if m.raft.State() != raft.Leader {
		return fmt.Errorf("non sono il leader, non posso accettare job")
	}

	fmt.Printf("[Master] SubmitJob ricevuto: %d file, %d reducer\n", len(args.InputFiles), args.NReduce)

	// Genera un JobID univoco
	jobID := fmt.Sprintf("job-%d", time.Now().Unix())

	// Verifica che i file di input esistano
	for _, file := range args.InputFiles {
		if _, err := os.Stat(file); os.IsNotExist(err) {
			return fmt.Errorf("file di input non trovato: %s", file)
		}
	}

	// Aggiorna la configurazione del master con i nuovi parametri
	m.mu.Lock()
	defer m.mu.Unlock()

	// Reset dello stato se necessario
	if m.isDone || m.phase == DonePhase {
		fmt.Printf("[Master] Reset dello stato per nuovo job %s\n", jobID)
		m.isDone = false
		m.phase = MapPhase
		m.mapTasksDone = 0
		m.reduceTasksDone = 0
	}

	// Aggiorna i parametri del job
	m.inputFiles = args.InputFiles
	m.nReduce = args.NReduce

	// Inizializza i task
	m.mapTasks = make([]TaskInfo, len(args.InputFiles))
	m.reduceTasks = make([]TaskInfo, args.NReduce)

	for i := range m.mapTasks {
		m.mapTasks[i].State = Idle
	}

	for i := range m.reduceTasks {
		m.reduceTasks[i].State = Idle
	}

	fmt.Printf("[Master] Job %s configurato: %d map tasks, %d reduce tasks\n",
		jobID, len(m.mapTasks), len(m.reduceTasks))

	*reply = SubmitJobReply{
		JobID:  jobID,
		Status: "submitted",
	}

	return nil
}

// copyOutputFilesToLocal copia i file di output dal volume Docker alla cartella locale data/output/
func (m *Master) copyOutputFilesToLocal() {
	fmt.Println("[Master] Avvio copia file di output nella cartella locale...")

	// Crea la cartella data/output se non esiste
	localOutputDir := "data/output"
	if err := os.MkdirAll(localOutputDir, 0755); err != nil {
		fmt.Printf("[Master] Errore creazione cartella %s: %v\n", localOutputDir, err)
		return
	}

	// Copia ogni file di output
	for i := 0; i < m.nReduce; i++ {
		sourceFile := getOutputFileName(i)
		destFile := filepath.Join(localOutputDir, fmt.Sprintf("mr-out-%d", i))

		// Verifica che il file sorgente esista
		if _, err := os.Stat(sourceFile); os.IsNotExist(err) {
			fmt.Printf("[Master] File di output %s non trovato, salto\n", sourceFile)
			continue
		}

		// Copia il file
		if err := m.copyFile(sourceFile, destFile); err != nil {
			fmt.Printf("[Master] Errore copia file %s -> %s: %v\n", sourceFile, destFile, err)
		} else {
			fmt.Printf("[Master] File copiato: %s -> %s\n", sourceFile, destFile)
		}
	}

	fmt.Printf("[Master] Copia file di output completata in %s\n", localOutputDir)

	// Crea anche il file finale unificato
	m.createUnifiedOutputFile()

	// Crea anche il file finale nel volume Docker
	m.createUnifiedOutputFileInDocker()
}

// copyFile copia un file da source a destination
func (m *Master) copyFile(source, destination string) error {
	srcFile, err := os.Open(source)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	destFile, err := os.Create(destination)
	if err != nil {
		return err
	}
	defer destFile.Close()

	_, err = io.Copy(destFile, srcFile)
	return err
}

// createUnifiedOutputFile crea un file finale unificato che combina tutti i file di output
func (m *Master) createUnifiedOutputFile() {
	fmt.Println("[Master] Creazione file finale unificato...")

	// Crea la cartella data/output se non esiste
	localOutputDir := "data/output"
	if err := os.MkdirAll(localOutputDir, 0755); err != nil {
		fmt.Printf("[Master] Errore creazione cartella %s: %v\n", localOutputDir, err)
		return
	}

	// File finale unificato
	unifiedFile := filepath.Join(localOutputDir, "final-output.txt")

	// Apri il file finale per scrittura
	finalFile, err := os.Create(unifiedFile)
	if err != nil {
		fmt.Printf("[Master] Errore creazione file finale %s: %v\n", unifiedFile, err)
		return
	}
	defer finalFile.Close()

	// Scrivi header
	fmt.Fprintf(finalFile, "=== RISULTATO FINALE MAPREDUCE ===\n")
	fmt.Fprintf(finalFile, "Generato il: %s\n", time.Now().Format("2006-01-02 15:04:05"))
	fmt.Fprintf(finalFile, "Numero di reducer: %d\n", m.nReduce)
	fmt.Fprintf(finalFile, "=====================================\n\n")

	// Combina tutti i file di output
	totalRecords := 0
	for i := 0; i < m.nReduce; i++ {
		sourceFile := getOutputFileName(i)

		// Verifica che il file sorgente esista
		if _, err := os.Stat(sourceFile); os.IsNotExist(err) {
			fmt.Printf("[Master] File di output %s non trovato, salto\n", sourceFile)
			continue
		}

		// Leggi il file di output
		file, err := os.Open(sourceFile)
		if err != nil {
			fmt.Printf("[Master] Errore apertura file %s: %v\n", sourceFile, err)
			continue
		}

		// Copia il contenuto nel file finale
		fmt.Fprintf(finalFile, "--- OUTPUT REDUCER %d ---\n", i)
		scanner := bufio.NewScanner(file)
		recordCount := 0
		for scanner.Scan() {
			line := scanner.Text()
			if line != "" { // Salta righe vuote
				fmt.Fprintf(finalFile, "%s\n", line)
				recordCount++
			}
		}
		file.Close()

		fmt.Fprintf(finalFile, "Record nel reducer %d: %d\n\n", i, recordCount)
		totalRecords += recordCount
	}

	// Scrivi footer
	fmt.Fprintf(finalFile, "=====================================\n")
	fmt.Fprintf(finalFile, "TOTALE RECORD PROCESSATI: %d\n", totalRecords)
	fmt.Fprintf(finalFile, "=====================================\n")

	fmt.Printf("[Master] File finale unificato creato: %s (%d record totali)\n", unifiedFile, totalRecords)
}

// createUnifiedOutputFileInDocker crea un file finale unificato nel volume Docker
func (m *Master) createUnifiedOutputFileInDocker() {
	fmt.Println("[Master] Creazione file finale unificato nel volume Docker...")

	// File finale nel volume Docker
	basePath := os.Getenv("TMP_PATH")
	if basePath == "" {
		basePath = "."
	}
	unifiedFile := filepath.Join(basePath, "final-output.txt")

	// Apri il file finale per scrittura
	finalFile, err := os.Create(unifiedFile)
	if err != nil {
		fmt.Printf("[Master] Errore creazione file finale Docker %s: %v\n", unifiedFile, err)
		return
	}
	defer finalFile.Close()

	// Scrivi header
	fmt.Fprintf(finalFile, "=== RISULTATO FINALE MAPREDUCE ===\n")
	fmt.Fprintf(finalFile, "Generato il: %s\n", time.Now().Format("2006-01-02 15:04:05"))
	fmt.Fprintf(finalFile, "Numero di reducer: %d\n", m.nReduce)
	fmt.Fprintf(finalFile, "=====================================\n\n")

	// Combina tutti i file di output
	totalRecords := 0
	for i := 0; i < m.nReduce; i++ {
		sourceFile := getOutputFileName(i)

		// Verifica che il file sorgente esista
		if _, err := os.Stat(sourceFile); os.IsNotExist(err) {
			fmt.Printf("[Master] File di output %s non trovato, salto\n", sourceFile)
			continue
		}

		// Leggi il file di output
		file, err := os.Open(sourceFile)
		if err != nil {
			fmt.Printf("[Master] Errore apertura file %s: %v\n", sourceFile, err)
			continue
		}

		// Copia il contenuto nel file finale
		fmt.Fprintf(finalFile, "--- OUTPUT REDUCER %d ---\n", i)
		scanner := bufio.NewScanner(file)
		recordCount := 0
		for scanner.Scan() {
			line := scanner.Text()
			if line != "" { // Salta righe vuote
				fmt.Fprintf(finalFile, "%s\n", line)
				recordCount++
			}
		}
		file.Close()

		fmt.Fprintf(finalFile, "Record nel reducer %d: %d\n\n", i, recordCount)
		totalRecords += recordCount
	}

	// Scrivi footer
	fmt.Fprintf(finalFile, "=====================================\n")
	fmt.Fprintf(finalFile, "TOTALE RECORD PROCESSATI: %d\n", totalRecords)
	fmt.Fprintf(finalFile, "=====================================\n")

	fmt.Printf("[Master] File finale unificato Docker creato: %s (%d record totali)\n", unifiedFile, totalRecords)
}

// startClusterManagementMonitor avvia il monitor per la gestione dinamica del cluster
func (m *Master) startClusterManagementMonitor() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		if m.raft.State() == raft.Leader {
			m.monitorClusterHealth()
		}
	}
}

// monitorClusterHealth monitora la salute del cluster e gestisce i membri
func (m *Master) monitorClusterHealth() {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Verifica la configurazione attuale del cluster Raft
	config := m.raft.GetConfiguration()
	if config.Error() != nil {
		fmt.Printf("[Master] Errore ottenendo configurazione cluster: %v\n", config.Error())
		return
	}

	currentServers := config.Configuration().Servers
	fmt.Printf("[Master] Cluster attuale ha %d server\n", len(currentServers))

	// Verifica se ci sono server da aggiungere
	for raftAddr, rpcAddr := range m.clusterMembers {
		found := false
		for _, server := range currentServers {
			if string(server.Address) == raftAddr {
				found = true
				break
			}
		}

		if !found {
			fmt.Printf("[Master] Aggiungendo server %s (RPC: %s) al cluster Raft\n", raftAddr, rpcAddr)
			future := m.raft.AddVoter(raft.ServerID(raftAddr), raft.ServerAddress(raftAddr), 0, 0)
			if err := future.Error(); err != nil {
				fmt.Printf("[Master] Errore aggiungendo server %s: %v\n", raftAddr, err)
			} else {
				fmt.Printf("[Master] Server %s aggiunto con successo\n", raftAddr)
			}
		}
	}
}

// AddClusterMember aggiunge un nuovo membro al cluster (chiamato esternamente)
func (m *Master) AddClusterMember(raftAddr, rpcAddr string) error {
	if m.raft.State() != raft.Leader {
		return fmt.Errorf("solo il leader può aggiungere membri al cluster")
	}

	// Aggiunge il membro alla mappa locale
	m.mu.Lock()
	m.clusterMembers[raftAddr] = rpcAddr
	m.mu.Unlock()

	// Applica il comando tramite Raft per consistency
	cmd := LogCommand{
		Operation:   "add-master",
		RaftAddress: raftAddr,
		RpcAddress:  rpcAddr,
	}

	cmdBytes, err := json.Marshal(cmd)
	if err != nil {
		return fmt.Errorf("errore marshaling comando: %v", err)
	}

	future := m.raft.Apply(cmdBytes, 5*time.Second)
	if err := future.Error(); err != nil {
		return fmt.Errorf("errore applicando comando: %v", err)
	}

	fmt.Printf("[Master] Comando add-master applicato con successo\n")
	return nil
}

// RemoveClusterMember rimuove un membro dal cluster
func (m *Master) RemoveClusterMember(raftAddr string) error {
	if m.raft.State() != raft.Leader {
		return fmt.Errorf("solo il leader può rimuovere membri dal cluster")
	}

	// Rimuove il membro dalla mappa locale
	m.mu.Lock()
	delete(m.clusterMembers, raftAddr)
	m.mu.Unlock()

	// Applica il comando tramite Raft per consistency
	cmd := LogCommand{
		Operation:   "remove-master",
		RaftAddress: raftAddr,
	}

	cmdBytes, err := json.Marshal(cmd)
	if err != nil {
		return fmt.Errorf("errore marshaling comando: %v", err)
	}

	future := m.raft.Apply(cmdBytes, 5*time.Second)
	if err := future.Error(); err != nil {
		return fmt.Errorf("errore applicando comando: %v", err)
	}

	fmt.Printf("[Master] Comando remove-master applicato con successo\n")
	return nil
}

// GetClusterInfo restituisce informazioni sul cluster
func (m *Master) GetClusterInfo() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	info := map[string]interface{}{
		"my_id":           m.myID,
		"raft_state":      m.raft.State().String(),
		"cluster_members": m.clusterMembers,
		"raft_addrs":      m.raftAddrs,
		"rpc_addrs":       m.rpcAddrs,
	}

	// Aggiunge informazioni sulla configurazione Raft
	config := m.raft.GetConfiguration()
	if config.Error() == nil {
		servers := make([]map[string]string, 0)
		for _, server := range config.Configuration().Servers {
			servers = append(servers, map[string]string{
				"id":      string(server.ID),
				"address": string(server.Address),
			})
		}
		info["raft_servers"] = servers
	}

	return info
}

// ForceLeaderElection forza una nuova elezione del leader
func (m *Master) ForceLeaderElection() error {
	if m.raft.State() == raft.Leader {
		// Se siamo già leader, trasferiamo la leadership
		future := m.raft.LeadershipTransfer()
		return future.Error()
	}

	// Altrimenti, forziamo un'elezione
	// Questo può essere fatto riavviando il leader attuale
	fmt.Printf("[Master] Forzando nuova elezione del leader\n")
	return nil
}
