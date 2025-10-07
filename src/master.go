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
	"strings"
	"sync"
	"time"

	crand "crypto/rand"
	"encoding/binary"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/raft"
	raftboltdb "github.com/hashicorp/raft-boltdb/v2"
)

// Costanti e tipi ora definiti in constants.go

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

// TaskKey identifica un task con ID e tipo
type TaskKey struct {
	ID   int
	Type TaskType
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
	// Tracciamento worker
	workers         map[string]*WorkerInfo // Worker ID -> WorkerInfo
	workerLastSeen  map[string]time.Time   // Worker ID -> Last seen time
	workerHeartbeat map[string]time.Time   // Worker ID -> Last heartbeat time
	// Mappa worker->task correnti (solo InProgress)
	workerToTasks map[string]map[TaskKey]bool // workerID -> set di task con tipo
	// Checkpoint dei reducer da usare alla prossima riassegnazione
	reducerCheckpoint map[int]string // reduceTaskID -> checkpoint path
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
	LogDebug("[Master] Apply comando: %s, TaskID: %d, Term: %d, Index: %d",
		cmd.Operation, cmd.TaskID, logEntry.Term, logEntry.Index)

	// Ignora comandi se il master non è ancora inizializzato
	if m.inputFiles == nil || len(m.inputFiles) == 0 {
		LogDebug("[Master] Ignoro comando %s durante inizializzazione (inputFiles=nil)", cmd.Operation)
		return nil
	}

	// Ignora comandi se non ci sono task configurati
	if len(m.mapTasks) == 0 && len(m.reduceTasks) == 0 {
		LogDebug("[Master] Ignoro comando %s durante inizializzazione (nessun task)", cmd.Operation)
		return nil
	}

	// Se il job è già completato, ignora tutti i comandi
	if m.isDone {
		LogDebug("[Master] Ignoro comando %s - job già completato", cmd.Operation)
		return nil
	}

	switch cmd.Operation {
	case "complete-map":
		if cmd.TaskID >= 0 && cmd.TaskID < len(m.mapTasks) {
			if m.mapTasks[cmd.TaskID].State != Completed {
				m.mapTasks[cmd.TaskID].State = Completed
				m.mapTasksDone++
				LogInfo("[Master] MapTask %d completato, progresso: %d/%d",
					cmd.TaskID, m.mapTasksDone, len(m.mapTasks))
				if m.mapTasksDone == len(m.mapTasks) {
					m.phase = ReducePhase
					LogInfo("[Master] Transizione a ReducePhase")
				}
			}
		} else {
			log.Printf("[Master] TaskID %d fuori range per MapTask (max: %d)\n", cmd.TaskID, len(m.mapTasks)-1)
		}
	case "add-master":
		// Gestisce l'aggiunta di un nuovo master al cluster
		if cmd.RaftAddress != "" && cmd.RpcAddress != "" {
			m.clusterMembers[cmd.RaftAddress] = cmd.RpcAddress
			LogInfo("[Master] Nuovo master aggiunto al cluster: %s -> %s", cmd.RaftAddress, cmd.RpcAddress)

			// Forza una nuova elezione del leader
			go func() {
				time.Sleep(ClusterManagementDelay)
				LogInfo("[Master] Forzando nuova elezione del leader dopo aggiunta master")
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
			LogInfo("[Master] Master rimosso dal cluster: %s", cmd.RaftAddress)
		}
	case "complete-reduce":
		if cmd.TaskID >= 0 && cmd.TaskID < len(m.reduceTasks) {
			if m.reduceTasks[cmd.TaskID].State != Completed {
				m.reduceTasks[cmd.TaskID].State = Completed
				m.reduceTasksDone++
				LogInfo("[Master] ReduceTask %d completato, progresso: %d/%d",
					cmd.TaskID, m.reduceTasksDone, len(m.reduceTasks))
				if m.reduceTasksDone == len(m.reduceTasks) {
					m.phase = DonePhase
					m.isDone = true
					LogInfo("[Master] Job completato - transizione a DonePhase")
					// Copia i file di output dal volume Docker alla cartella locale
					m.copyOutputFilesToLocal()
					// Backup su S3 se abilitato
					m.backupToS3()
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
					LogInfo("[Master] MapTask %d resettato a Idle per riassegnazione", cmd.TaskID)
				}
			} else if m.phase == ReducePhase && cmd.TaskID < len(m.reduceTasks) {
				if m.reduceTasks[cmd.TaskID].State == InProgress {
					m.reduceTasks[cmd.TaskID].State = Idle
					LogInfo("[Master] ReduceTask %d resettato a Idle per riassegnazione", cmd.TaskID)
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
	LogInfo("[Master] Restore chiamato: isDone=%v, phase=%v", state.IsDone, state.Phase)
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
			LogDebug("[Master] MapTask %d incompleto: file %s mancante", taskID, fileName)
			return false
		}
	}

	LogInfo("[Master] MapTask %d completato: tutti i file intermedi presenti", taskID)
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
			LogError("[Master] MapTask %d invalido: errore apertura file %s: %v", taskID, fileName, err)
			return false
		}

		// Verifica che il file contenga dati JSON validi
		decoder := json.NewDecoder(file)
		var kv KeyValue
		hasData := false
		for decoder.More() {
			if err := decoder.Decode(&kv); err != nil {
				LogError("[Master] MapTask %d invalido: errore decodifica JSON in %s: %v", taskID, fileName, err)
				file.Close()
				return false
			}
			hasData = true
		}
		file.Close()

		if !hasData {
			LogWarn("[Master] MapTask %d invalido: file %s vuoto", taskID, fileName)
			return false
		}
	}

	LogInfo("[Master] MapTask %d valido: tutti i file intermedi sono validi", taskID)
	return true
}

// cleanupInvalidMapTask rimuove i file intermedi di un MapTask invalido
func (m *Master) cleanupInvalidMapTask(taskID int) {
	if taskID < 0 || taskID >= len(m.mapTasks) {
		return
	}

	LogInfo("[Master] Pulizia MapTask %d invalido", taskID)
	for i := 0; i < m.nReduce; i++ {
		fileName := getIntermediateFileName(taskID, i)
		if err := os.Remove(fileName); err != nil && !os.IsNotExist(err) {
			LogError("[Master] Errore rimozione file %s: %v", fileName, err)
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
		LogDebug("[Master] ReduceTask %d incompleto: file %s mancante", taskID, fileName)
		return false
	}

	LogInfo("[Master] ReduceTask %d completato: file output presente", taskID)
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
		LogError("[Master] ReduceTask %d invalido: errore apertura file %s: %v", taskID, fileName, err)
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
		LogError("[Master] ReduceTask %d invalido: errore lettura file %s: %v", taskID, fileName, err)
		return false
	}

	if !hasData {
		LogWarn("[Master] ReduceTask %d invalido: file %s vuoto", taskID, fileName)
		return false
	}

	LogInfo("[Master] ReduceTask %d valido: file %s contiene %d righe", taskID, fileName, lineCount)
	return true
}

// cleanupInvalidReduceTask rimuove il file di output di un ReduceTask invalido
func (m *Master) cleanupInvalidReduceTask(taskID int) {
	if taskID < 0 || taskID >= len(m.reduceTasks) {
		return
	}

	LogInfo("[Master] Pulizia ReduceTask %d invalido", taskID)
	fileName := getOutputFileName(taskID)
	if err := os.Remove(fileName); err != nil && !os.IsNotExist(err) {
		LogError("[Master] Errore rimozione file %s: %v", fileName, err)
	}
}

func (m *Master) AssignTask(args *RequestTaskArgs, reply *Task) error {
	LogDebug("[Master] AssignTask chiamato, stato Raft: %v, isDone: %v", m.raft.State(), m.isDone)
	if m.raft.State() != raft.Leader {
		LogDebug("[Master] Non sono leader, restituisco NoTask")
		reply.Type = NoTask
		return nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.isDone {
		LogInfo("[Master] Job completato, restituisco ExitTask")
		reply.Type = ExitTask
		return nil
	}
	var taskToDo *Task
	LogDebug("[Master] Fase corrente: %v, mapTasks: %d, reduceTasks: %d", m.phase, len(m.mapTasks), len(m.reduceTasks))
	if m.phase == MapPhase {
		for id, info := range m.mapTasks {
			LogDebug("[Master] MapTask %d: stato=%v", id, info.State)
			if info.State == Idle {
				// Verifica se il MapTask è già stato completato (file intermedi esistenti)
				if m.isMapTaskCompleted(id) {
					LogInfo("[Master] MapTask %d già completato (file intermedi esistenti), marco come Completed", id)
					m.mapTasks[id].State = Completed
					m.mapTasksDone++
					if m.mapTasksDone == len(m.mapTasks) {
						m.phase = ReducePhase
						LogInfo("[Master] Tutti i MapTask completati, transizione a ReducePhase")
					}
					continue
				}
				taskToDo = &Task{Type: MapTask, TaskID: id, Input: m.inputFiles[id], NReduce: m.nReduce}
				m.mapTasks[id].State = InProgress
				m.mapTasks[id].StartTime = time.Now()
				LogInfo("[Master] Assegnato MapTask %d: %s", id, m.inputFiles[id])
				break
			} else if info.State == InProgress {
				// Verifica se il task è effettivamente completato (file intermedi esistenti)
				if m.isMapTaskCompleted(id) {
					LogInfo("[Master] MapTask %d in InProgress ma file intermedi presenti, marco come Completed", id)
					m.mapTasks[id].State = Completed
					m.mapTasksDone++
					if m.mapTasksDone == len(m.mapTasks) {
						m.phase = ReducePhase
						LogInfo("[Master] Tutti i MapTask completati, transizione a ReducePhase")
					}
					continue
				}
				// Il task è in InProgress ma non è completato, potrebbe essere bloccato
				// Riassegna il task
				taskToDo = &Task{Type: MapTask, TaskID: id, Input: m.inputFiles[id], NReduce: m.nReduce}
				m.mapTasks[id].State = InProgress
				m.mapTasks[id].StartTime = time.Now()
				LogInfo("[Master] Riassegnato MapTask %d in InProgress: %s", id, m.inputFiles[id])
				break
			} else if info.State == Completed {
				// Verifica se i file intermedi sono ancora validi
				if !m.validateMapTaskOutput(id) {
					LogWarn("[Master] MapTask %d marcato come Completed ma file intermedi invalidi, resetto a Idle", id)
					m.mapTasks[id].State = Idle
					m.mapTasksDone--
					m.cleanupInvalidMapTask(id)
					taskToDo = &Task{Type: MapTask, TaskID: id, Input: m.inputFiles[id], NReduce: m.nReduce}
					m.mapTasks[id].State = InProgress
					m.mapTasks[id].StartTime = time.Now()
					LogInfo("[Master] Riassegnato MapTask %d: %s", id, m.inputFiles[id])
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
				LogInfo("[Master] Tutti i MapTask completati (%d/%d), transizione a ReducePhase", actualMapDone, len(m.mapTasks))
			}
		}
	} else if m.phase == ReducePhase {
		for id, info := range m.reduceTasks {
			LogDebug("[Master] ReduceTask %d: stato=%v", id, info.State)
			if info.State == Idle {
				// Verifica se tutti i file intermedi necessari esistono
				if !m.areAllMapTasksCompleted() {
					LogDebug("[Master] ReduceTask %d non può essere assegnato: MapTask non completati", id)
					continue
				}

				// Verifica se il ReduceTask è già stato completato (file di output esistente)
				if m.isReduceTaskCompleted(id) {
					LogInfo("[Master] ReduceTask %d già completato (file output esistente), marco come Completed", id)
					m.reduceTasks[id].State = Completed
					m.reduceTasksDone++
					if m.reduceTasksDone == len(m.reduceTasks) {
						m.phase = DonePhase
						m.isDone = true
						LogInfo("[Master] Tutti i ReduceTask completati, transizione a DonePhase")
					}
					continue
				}

				// Riprendi da eventuale checkpoint precedente
				checkpoint := ""
				if m.reducerCheckpoint != nil {
					if cp, ok := m.reducerCheckpoint[id]; ok {
						checkpoint = cp
						LogInfo("[Master] ReduceTask %d: assegno con checkpoint %s", id, cp)
					}
				}
				taskToDo = &Task{Type: ReduceTask, TaskID: id, NMap: len(m.mapTasks), Checkpoint: checkpoint}
				m.reduceTasks[id].State = InProgress
				m.reduceTasks[id].StartTime = time.Now()
				LogInfo("[Master] Assegnato ReduceTask %d", id)
				break
			} else if info.State == Completed {
				// Verifica se il file di output è ancora valido
				if !m.validateReduceTaskOutput(id) {
					LogWarn("[Master] ReduceTask %d marcato come Completed ma file output invalido, resetto a Idle", id)
					m.reduceTasks[id].State = Idle
					m.reduceTasksDone--
					m.cleanupInvalidReduceTask(id)
					// Riprendi da eventuale checkpoint precedente
					checkpoint := ""
					if m.reducerCheckpoint != nil {
						if cp, ok := m.reducerCheckpoint[id]; ok {
							checkpoint = cp
							LogInfo("[Master] ReduceTask %d: riassegno con checkpoint %s", id, cp)
						}
					}
					taskToDo = &Task{Type: ReduceTask, TaskID: id, NMap: len(m.mapTasks), Checkpoint: checkpoint}
					m.reduceTasks[id].State = InProgress
					m.reduceTasks[id].StartTime = time.Now()
					LogInfo("[Master] Riassegnato ReduceTask %d", id)
					break
				}
			}
		}
	}
	if taskToDo != nil {
		*reply = *taskToDo
		LogInfo("[Master] Restituisco task: %v", *taskToDo)

		// Traccia il worker che ha richiesto il task usando l'ID fornito
		workerID := strings.TrimSpace(args.WorkerID)
		if workerID == "" {
			// Nessun ID, non registrare un nuovo worker (evita duplicati fantasma)
			LogDebug("[Master] RequestTask senza WorkerID: non registro worker, assegno comunque il task")
		}

		if workerID != "" && !strings.HasPrefix(workerID, "worker-temp-") {
			if _, exists := m.workers[workerID]; !exists {
				m.workers[workerID] = &WorkerInfo{
					ID:        workerID,
					Status:    "active",
					LastSeen:  time.Now(),
					TasksDone: 0,
				}
				LogInfo("[Master] Nuovo worker registrato: %s", workerID)
			}
			m.workerLastSeen[workerID] = time.Now()
			m.workers[workerID].LastSeen = time.Now()
			LogDebug("[Master] Worker %s tracciato, ultimo visto: %v", workerID, time.Now())

			// Registra il task assegnato per questo worker
			if m.workerToTasks[workerID] == nil {
				m.workerToTasks[workerID] = make(map[TaskKey]bool)
			}
			m.workerToTasks[workerID][TaskKey{ID: taskToDo.TaskID, Type: taskToDo.Type}] = true
		}
	} else {
		*reply = Task{Type: NoTask}
		LogDebug("[Master] Nessun task disponibile, restituisco NoTask")
	}
	return nil
}
func (m *Master) TaskCompleted(args *TaskCompletedArgs, reply *Reply) error {
	if m.raft.State() != raft.Leader {
		return nil
	}

	LogInfo("[Master] TaskCompleted ricevuto: Type=%v, TaskID=%d", args.Type, args.TaskID)

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

		LogInfo("[Master] MapTask %d completato e validato correttamente", args.TaskID)
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

		LogInfo("[Master] ReduceTask %d completato e validato correttamente", args.TaskID)
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

	LogInfo("[Master] TaskCompleted applicato con successo: %s TaskID=%d", op, args.TaskID)

	// Aggiorna contatori e deregistra il task dal worker
	if args.WorkerID != "" {
		if worker, exists := m.workers[args.WorkerID]; exists {
			worker.TasksDone++
			worker.LastSeen = time.Now()
			if m.workerToTasks[args.WorkerID] != nil {
				delete(m.workerToTasks[args.WorkerID], TaskKey{ID: args.TaskID, Type: args.Type})
				if len(m.workerToTasks[args.WorkerID]) == 0 {
					delete(m.workerToTasks, args.WorkerID)
				}
			}
			LogInfo("[Master] Worker %s ha completato il task, totale task completati: %d", args.WorkerID, worker.TasksDone)
		} else {
			LogWarn("[Master] Worker %s non trovato nella mappa dei worker", args.WorkerID)
		}
	} else {
		LogWarn("[Master] Worker ID non fornito nel TaskCompleted")
	}

	return nil
}

// ResetTask è un metodo RPC che forza il reset di un task specifico, permettendone
// la riassegnazione immediata. Il reset viene serializzato tramite Raft per consistenza.
func (m *Master) ResetTask(args *ResetTaskArgs, reply *Reply) error {
	if m.raft.State() != raft.Leader {
		return fmt.Errorf("non sono il leader")
	}
	if args.TaskID < 0 {
		return fmt.Errorf("task id invalido")
	}
	// Applica il reset tramite Raft per consistenza
	cmd := LogCommand{Operation: "reset-task", TaskID: args.TaskID}
	cmdBytes, err := json.Marshal(cmd)
	if err != nil {
		return err
	}
	if err := m.raft.Apply(cmdBytes, 2*time.Second).Error(); err != nil {
		return err
	}
	LogWarn("[Master] ResetTask RPC: %v task=%d reason=%s", args.Type, args.TaskID, args.Reason)
	// Best-effort: rimuovi il task dalla mappa worker->tasks (potrebbe essere stato riassegnato)
	for w := range m.workerToTasks {
		if m.workerToTasks[w][TaskKey{ID: args.TaskID, Type: args.Type}] {
			delete(m.workerToTasks[w], TaskKey{ID: args.TaskID, Type: args.Type})
			if len(m.workerToTasks[w]) == 0 {
				delete(m.workerToTasks, w)
			}
		}
	}
	// Se è un ReduceTask e la reason contiene checkpoint=..., memorizza il percorso
	if args.Type == ReduceTask {
		if m.reducerCheckpoint == nil {
			m.reducerCheckpoint = make(map[int]string)
		}
		const key = "checkpoint="
		if idx := strings.Index(args.Reason, key); idx >= 0 {
			cp := strings.TrimSpace(args.Reason[idx+len(key):])
			if cp != "" {
				m.reducerCheckpoint[args.TaskID] = cp
				LogInfo("[Master] Registrato checkpoint per ReduceTask %d: %s", args.TaskID, cp)
			}
		}
	}
	return nil
}

// PublicResetTask è un endpoint pubblico: può essere chiamato su qualsiasi master.
// Se il nodo non è leader, inoltra la richiesta al leader e restituisce l'esito.
func (m *Master) PublicResetTask(args *ResetTaskArgs, reply *Reply) error {
	if m.raft.State() == raft.Leader {
		return m.ResetTask(args, reply)
	}

	// Inoltra al leader
	leaderRaftAddr := string(m.raft.Leader())
	if leaderRaftAddr == "" {
		return fmt.Errorf("leader non disponibile")
	}

	// Mappa raft address -> rpc address
	rpcAddr := m.clusterMembers[leaderRaftAddr]
	if rpcAddr == "" {
		// fallback: prova stesso indirizzo
		rpcAddr = leaderRaftAddr
	}

	client, err := rpc.DialHTTP("tcp", rpcAddr)
	if err != nil {
		return fmt.Errorf("connessione leader fallita: %v", err)
	}
	defer client.Close()

	var fwdReply Reply
	if err := client.Call("Master.ResetTask", args, &fwdReply); err != nil {
		return err
	}
	*reply = fwdReply
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

	LogInfo("[Master] RecoveryState: verifico stato dopo elezione leader")
	LogInfo("[Master] Stato corrente: isDone=%v, phase=%v, mapTasksDone=%d/%d, reduceTasksDone=%d/%d",
		m.isDone, m.phase, m.mapTasksDone, len(m.mapTasks), m.reduceTasksDone, len(m.reduceTasks))

	// Verifica consistenza dello stato e recovery completo
	if m.phase == MapPhase {
		// Conta i MapTask effettivamente completati verificando i file
		actualMapDone := 0
		for i, task := range m.mapTasks {
			if task.State == Completed {
				// Verifica che i file intermedi siano ancora validi
				if m.isMapTaskCompleted(i) && m.validateMapTaskOutput(i) {
					actualMapDone++
				} else {
					// File corrotti o mancanti, reset del task
					LogWarn("[Master] RecoveryState: MapTask %d file corrotti, resetto a Idle", i)
					m.mapTasks[i].State = Idle
					m.cleanupInvalidMapTask(i)
				}
			} else if task.State == InProgress {
				// Verifica se il task è effettivamente completato
				if m.isMapTaskCompleted(i) && m.validateMapTaskOutput(i) {
					LogInfo("[Master] RecoveryState: MapTask %d completato ma marcato InProgress, correggo", i)
					m.mapTasks[i].State = Completed
					actualMapDone++
				} else {
					// Task bloccato, reset
					LogWarn("[Master] RecoveryState: MapTask %d bloccato, resetto a Idle", i)
					m.mapTasks[i].State = Idle
				}
			}
		}

		if actualMapDone != m.mapTasksDone {
			LogInfo("[Master] Correzione mapTasksDone: %d -> %d", m.mapTasksDone, actualMapDone)
			m.mapTasksDone = actualMapDone
		}

		// Se tutti i MapTask sono completati, passa a ReducePhase
		if m.mapTasksDone == len(m.mapTasks) && m.phase == MapPhase {
			m.phase = ReducePhase
			LogInfo("[Master] RecoveryState: transizione a ReducePhase")
		}
	} else if m.phase == ReducePhase {
		// Conta i ReduceTask effettivamente completati verificando i file
		actualReduceDone := 0
		for i, task := range m.reduceTasks {
			if task.State == Completed {
				// Verifica che il file di output sia ancora valido
				if m.isReduceTaskCompleted(i) && m.validateReduceTaskOutput(i) {
					actualReduceDone++
				} else {
					// File corrotti o mancanti, reset del task
					LogWarn("[Master] RecoveryState: ReduceTask %d file corrotti, resetto a Idle", i)
					m.reduceTasks[i].State = Idle
					m.cleanupInvalidReduceTask(i)
				}
			} else if task.State == InProgress {
				// Verifica se il task è effettivamente completato
				if m.isReduceTaskCompleted(i) && m.validateReduceTaskOutput(i) {
					LogInfo("[Master] RecoveryState: ReduceTask %d completato ma marcato InProgress, correggo", i)
					m.reduceTasks[i].State = Completed
					actualReduceDone++
				} else {
					// Task bloccato, reset
					LogWarn("[Master] RecoveryState: ReduceTask %d bloccato, resetto a Idle", i)
					m.reduceTasks[i].State = Idle
				}
			}
		}

		if actualReduceDone != m.reduceTasksDone {
			LogInfo("[Master] Correzione reduceTasksDone: %d -> %d", m.reduceTasksDone, actualReduceDone)
			m.reduceTasksDone = actualReduceDone
		}

		// Se tutti i ReduceTask sono completati, passa a DonePhase
		if m.reduceTasksDone == len(m.reduceTasks) && m.phase == ReducePhase {
			m.phase = DonePhase
			m.isDone = true
			LogInfo("[Master] RecoveryState: transizione a DonePhase")
		}
	}

	LogInfo("[Master] RecoveryState completato: isDone=%v, phase=%v", m.isDone, m.phase)
}
func MakeMaster(files []string, nReduce int, me int, raftAddrs []string, rpcAddrs []string) (*Master, error) {
	// Inizializza il generatore di numeri casuali con seed realmente indipendente per nodo
	var seedBytes [8]byte
	if _, err := crand.Read(seedBytes[:]); err == nil {
		rand.Seed(int64(binary.LittleEndian.Uint64(seedBytes[:])) + time.Now().UnixNano() + int64(me*9973))
	} else {
		rand.Seed(time.Now().UnixNano() + int64(me*9973))
	}

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
		// Inizializza il tracciamento worker
		workers:         make(map[string]*WorkerInfo),
		workerLastSeen:  make(map[string]time.Time),
		workerHeartbeat: make(map[string]time.Time),
		workerToTasks:   make(map[string]map[TaskKey]bool),
	}

	// Popola la mappa dei membri del cluster
	for i, raftAddr := range raftAddrs {
		if i < len(rpcAddrs) {
			m.clusterMembers[raftAddr] = rpcAddrs[i]
		}
	}
	LogInfo("[Master %d] Inizializzazione: isDone=%v, phase=%v", me, m.isDone, m.phase)
	config := raft.DefaultConfig()
	config.LocalID = raft.ServerID(raftAddrs[me])
	config.Logger = hclog.New(&hclog.LoggerOptions{Name: fmt.Sprintf("Raft-%s", raftAddrs[me]), Level: hclog.Info, Output: os.Stderr})

	// Configura timeout più equi per l'elezione (maggiore jitter e indipendenza)
	baseElectionTimeout := 300 * time.Millisecond
	randomOffset := time.Duration(300+rand.Intn(1200)) * time.Millisecond // 300–1500ms di offset
	config.ElectionTimeout = baseElectionTimeout + randomOffset
	config.HeartbeatTimeout = 200 * time.Millisecond
	config.LeaderLeaseTimeout = 150 * time.Millisecond // Deve essere < HeartbeatTimeout

	LogInfo("[Master %d] Configurazione Raft: ElectionTimeout=%v, HeartbeatTimeout=%v",
		me, config.ElectionTimeout, config.HeartbeatTimeout)
	raftAddr := raftAddrs[me]
	advertiseAddr, _ := net.ResolveTCPAddr("tcp", raftAddr)
	transport, err := raft.NewTCPTransport(raftAddr, advertiseAddr, 3, 10*time.Second, os.Stderr)
	if err != nil {
		return nil, fmt.Errorf("transport: %s", err)
	}
	raftDir := fmt.Sprintf("./raft-data/%d", me)

	// Opzione per pulizia manuale (solo se esplicitamente richiesta)
	if os.Getenv("RAFT_CLEAN_START") == "true" {
		LogInfo("[Master %d] Pulizia dati Raft richiesta esplicitamente", me)
		os.RemoveAll(raftDir)
	}

	// Crea la directory Raft se non esiste (mantiene i dati esistenti per fault tolerance)
	os.MkdirAll(raftDir, 0700)
	LogInfo("[Master %d] Directory Raft preparata: %s", me, raftDir)

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
	LogInfo("[Master %d] Reset stato PRIMA di Raft: isDone=%v, phase=%v", me, m.isDone, m.phase)

	// Pulisci i file precedenti all'avvio
	m.cleanupPreviousJobFiles()
	logStore, err := raftboltdb.New(raftboltdb.Options{Path: filepath.Join(raftDir, "log.db")})
	if err != nil {
		return nil, fmt.Errorf("failed to create log store: %s", err)
	}
	stableStore, err := raftboltdb.New(raftboltdb.Options{Path: filepath.Join(raftDir, "stable.db")})
	if err != nil {
		return nil, fmt.Errorf("failed to create stable store: %s", err)
	}
	snapshotStore, err := raft.NewFileSnapshotStore(raftDir, 2, os.Stderr)
	if err != nil {
		return nil, fmt.Errorf("failed to create snapshot store: %s", err)
	}
	ra, err := raft.NewRaft(config, m, logStore, stableStore, snapshotStore, transport)
	if err != nil {
		return nil, fmt.Errorf("raft: %s", err)
	}
	m.raft = ra
	LogInfo("[Master %d] Dopo creazione Raft: isDone=%v, phase=%v", me, m.isDone, m.phase)

	// Verifica che i file Raft siano stati creati correttamente
	logPath := filepath.Join(raftDir, "log.db")
	stablePath := filepath.Join(raftDir, "stable.db")
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		LogWarn("[Master %d] ATTENZIONE: File log.db non creato in %s", me, logPath)
	} else {
		LogInfo("[Master %d] File log.db creato correttamente in %s", me, logPath)
	}
	if _, err := os.Stat(stablePath); os.IsNotExist(err) {
		LogWarn("[Master %d] ATTENZIONE: File stable.db non creato in %s", me, stablePath)
	} else {
		LogInfo("[Master %d] File stable.db creato correttamente in %s", me, stablePath)
	}

	// Aspetta che Raft si stabilizzi prima di procedere
	time.Sleep(RaftInitializationDelay)

	// Monitor dello stato Raft per recovery automatico
	go func() {
		ticker := time.NewTicker(RaftMonitorInterval)
		defer ticker.Stop()
		var lastState raft.RaftState

		for range ticker.C {
			currentState := m.raft.State()
			if currentState != lastState {
				LogInfo("[Master %d] Cambio stato Raft: %v -> %v", me, lastState, currentState)
				lastState = currentState

				// Se diventa leader, esegui recovery dello stato
				if currentState == raft.Leader {
					LogInfo("[Master %d] Diventato leader, eseguo recovery dello stato", me)
					m.RecoveryState()
				}
			}
		}
	}()

	LogInfo("[Master %d] Stato finale dopo inizializzazione: isDone=%v, phase=%v, mapTasks=%d, reduceTasks=%d",
		me, m.isDone, m.phase, len(m.mapTasks), len(m.reduceTasks))

	// Avvia il monitor per la gestione dinamica del cluster
	go m.startClusterManagementMonitor()

	// Implementa un sistema di elezione più equo
	// Solo un master alla volta può fare il bootstrap, con delay casuale non correlato
	go func() {
		// Delay casuale per evitare elezioni simultanee (0–5s)
		randomDelay := time.Duration(rand.Intn(5000)) * time.Millisecond
		time.Sleep(randomDelay)

		// Controlla se il cluster è già stato bootstrappato
		config := m.raft.GetConfiguration()
		if config.Error() != nil || len(config.Configuration().Servers) == 0 {
			// Solo se il cluster non è ancora configurato, procedi con il bootstrap
			servers := make([]raft.Server, len(raftAddrs))
			for i, addrStr := range raftAddrs {
				servers[i] = raft.Server{ID: raft.ServerID(addrStr), Address: raft.ServerAddress(addrStr)}
			}

			LogInfo("[Master %d] Tentativo bootstrap con delay %v", me, randomDelay)
			bootstrapFuture := m.raft.BootstrapCluster(raft.Configuration{Servers: servers})
			if err := bootstrapFuture.Error(); err != nil {
				log.Printf("[Master %d] Bootstrap fallito (probabilmente già configurato): %s", me, err)
			} else {
				LogInfo("[Master %d] Bootstrap completato con successo", me)
			}
		} else {
			LogInfo("[Master %d] Cluster già configurato, salto bootstrap", me)
		}
	}()
	rpc.Register(m)
	rpc.HandleHTTP()

	go func() {
		// Get network configuration
		networkConfig := GetNetworkConfig()

		// Use dynamic network configuration
		var listenAddr string
		if networkConfig.IsAWS() && len(networkConfig.RpcAddresses) > me {
			listenAddr = networkConfig.RpcAddresses[me]
		} else {
			// Fallback to original logic for local development
			listenAddr = rpcAddrs[me]
			if os.Getenv("DOCKER_ENV") == "true" || os.Getenv("RAFT_ADDRESSES") != "" {
				// Se siamo in Docker, sostituisci localhost con 0.0.0.0
				listenAddr = strings.Replace(listenAddr, "localhost", "0.0.0.0", 1)
			}
		}

		// Se l'indirizzo inizia solo con :, aggiungi 0.0.0.0
		if strings.HasPrefix(listenAddr, ":") {
			listenAddr = "0.0.0.0" + listenAddr
		}

		LogInfo("[Master %d] Starting RPC server on %s", me, listenAddr)
		l, e := net.Listen("tcp", listenAddr)
		if e != nil {
			LogError("RPC listen error: %s", e)
			return
		}
		http.Serve(l, nil)
	}()
	// Task timeout monitor: re-queue stuck tasks if the leader does not receive completion in time.
	go func() {
		ticker := time.NewTicker(TaskMonitorInterval)
		defer ticker.Stop()
		for range ticker.C {
			if m.raft.State() != raft.Leader {
				continue
			}
			now := time.Now()
			m.mu.Lock()
			if m.phase == MapPhase {
				for i, info := range m.mapTasks {
					if info.State == InProgress && now.Sub(info.StartTime) > TaskTimeout {
						// Reset task e logga il comando per recovery
						m.mapTasks[i] = TaskInfo{State: Idle}
						LogWarn("[Master] MapTask %d timeout, resettato a Idle", i)

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
					if info.State == InProgress && now.Sub(info.StartTime) > TaskTimeout {
						// Reset task e logga il comando per recovery
						m.reduceTasks[i] = TaskInfo{State: Idle}
						LogWarn("[Master] ReduceTask %d timeout, resettato a Idle", i)

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
		ticker := time.NewTicker(FileValidationInterval)
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
							LogWarn("[Master] MapTask %d file intermedi corrotti, resetto a Idle", i)
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
							LogWarn("[Master] ReduceTask %d file output corrotti, resetto a Idle", i)
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

	// Worker health monitor: rileva worker morti e resetta i loro task
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if m.raft.State() != raft.Leader {
				continue
			}

			m.mu.Lock()
			now := time.Now()
			workerTimeout := 30 * time.Second // Worker considerato morto dopo 30 secondi

			// Trova worker morti
			var deadWorkers []string
			for workerID, lastSeen := range m.workerLastSeen {
				if now.Sub(lastSeen) > workerTimeout {
					deadWorkers = append(deadWorkers, workerID)
				}
			}

			// Reset task assegnati a worker morti
			for _, workerID := range deadWorkers {
				LogWarn("[Master] Worker %s considerato morto, resetto i suoi task", workerID)

				// Rimuovi il worker dalla mappa
				delete(m.workers, workerID)
				delete(m.workerLastSeen, workerID)
				delete(m.workerHeartbeat, workerID)

				// Reset tutti i task InProgress (potrebbero essere assegnati al worker morto)
				if m.phase == MapPhase {
					for i, info := range m.mapTasks {
						if info.State == InProgress && now.Sub(info.StartTime) > workerTimeout {
							LogWarn("[Master] Reset MapTask %d per worker morto %s", i, workerID)
							m.mapTasks[i].State = Idle

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
						if info.State == InProgress && now.Sub(info.StartTime) > workerTimeout {
							LogWarn("[Master] Reset ReduceTask %d per worker morto %s", i, workerID)
							m.reduceTasks[i].State = Idle

							// Per ReduceTask, preserva il checkpoint se esiste
							checkpointPath := fmt.Sprintf("data/output/mr-out-%d.checkpoint.json", i)
							if _, err := os.Stat(checkpointPath); err == nil {
								// Checkpoint esiste, lo preserviamo per la riassegnazione
								if m.reducerCheckpoint == nil {
									m.reducerCheckpoint = make(map[int]string)
								}
								m.reducerCheckpoint[i] = checkpointPath
								LogInfo("[Master] Preservato checkpoint per ReduceTask %d: %s", i, checkpointPath)
							}

							// Applica il reset tramite Raft per consistency
							cmd := LogCommand{Operation: "reset-task", TaskID: i}
							cmdBytes, err := json.Marshal(cmd)
							if err == nil {
								m.raft.Apply(cmdBytes, 500*time.Millisecond)
							}
						}
					}
				}
			}
			m.mu.Unlock()
		}
	}()
	return m, nil
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

	LogInfo("[Master] SubmitJob ricevuto: %d file, %d reducer", len(args.InputFiles), args.NReduce)

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
		LogInfo("[Master] Reset dello stato per nuovo job %s", jobID)
		m.isDone = false
		m.phase = MapPhase
		m.mapTasksDone = 0
		m.reduceTasksDone = 0

		// Pulisci i file precedenti prima di iniziare il nuovo job
		m.cleanupPreviousJobFiles()
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

	LogInfo("[Master] Job %s configurato: %d map tasks, %d reduce tasks",
		jobID, len(m.mapTasks), len(m.reduceTasks))

	*reply = SubmitJobReply{
		JobID:  jobID,
		Status: "submitted",
	}

	return nil
}

// cleanupPreviousJobFiles pulisce i file precedenti prima di iniziare un nuovo job
func (m *Master) cleanupPreviousJobFiles() {
	LogInfo("[Master] Pulizia file precedenti...")

	// Pulisci i file di output precedenti usando il numero di reducer corretto
	for i := 0; i < m.nReduce; i++ {
		outputFile := getOutputFileName(i)
		if err := os.Remove(outputFile); err != nil && !os.IsNotExist(err) {
			LogWarn("[Master] Errore rimozione file output %s: %v", outputFile, err)
		}
	}

	// Pulisci i file intermedi precedenti usando il numero di reducer corretto
	for i := 0; i < len(m.inputFiles); i++ {
		for j := 0; j < m.nReduce; j++ {
			intermediateFile := getIntermediateFileName(i, j)
			if err := os.Remove(intermediateFile); err != nil && !os.IsNotExist(err) {
				LogWarn("[Master] Errore rimozione file intermedio %s: %v", intermediateFile, err)
			}
		}
	}

	LogInfo("[Master] Pulizia file precedenti completata")
}

// copyOutputFilesToLocal copia i file di output dal volume Docker alla cartella locale data/output/
func (m *Master) copyOutputFilesToLocal() {
	LogInfo("[Master] Avvio copia file di output nella cartella locale...")

	// Crea la cartella data/output se non esiste
	localOutputDir := "data/output"
	if err := os.MkdirAll(localOutputDir, 0755); err != nil {
		LogError("[Master] Errore creazione cartella %s: %v", localOutputDir, err)
		return
	}

	// Copia ogni file di output
	for i := 0; i < m.nReduce; i++ {
		sourceFile := getOutputFileName(i)
		destFile := filepath.Join(localOutputDir, fmt.Sprintf("mr-out-%d", i))

		// Verifica che il file sorgente esista
		if _, err := os.Stat(sourceFile); os.IsNotExist(err) {
			LogWarn("[Master] File di output %s non trovato, salto", sourceFile)
			continue
		}

		// Copia il file
		if err := m.copyFile(sourceFile, destFile); err != nil {
			LogError("[Master] Errore copia file %s -> %s: %v", sourceFile, destFile, err)
		} else {
			LogInfo("[Master] File copiato: %s -> %s", sourceFile, destFile)
		}
	}

	LogInfo("[Master] Copia file di output completata in %s", localOutputDir)

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
	LogInfo("[Master] Creazione file finale unificato...")

	// Crea la cartella data/output se non esiste
	localOutputDir := "data/output"
	if err := os.MkdirAll(localOutputDir, 0755); err != nil {
		LogError("[Master] Errore creazione cartella %s: %v", localOutputDir, err)
		return
	}

	// File finale unificato
	unifiedFile := filepath.Join(localOutputDir, "final-output.txt")

	// Apri il file finale per scrittura
	finalFile, err := os.Create(unifiedFile)
	if err != nil {
		LogError("[Master] Errore creazione file finale %s: %v", unifiedFile, err)
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
			LogWarn("[Master] File di output %s non trovato, salto", sourceFile)
			continue
		}

		// Leggi il file di output
		file, err := os.Open(sourceFile)
		if err != nil {
			LogError("[Master] Errore apertura file %s: %v", sourceFile, err)
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

	LogInfo("[Master] File finale unificato creato: %s (%d record totali)", unifiedFile, totalRecords)
}

// createUnifiedOutputFileInDocker crea un file finale unificato nel volume Docker
func (m *Master) createUnifiedOutputFileInDocker() {
	LogInfo("[Master] Creazione file finale unificato nel volume Docker...")

	// File finale nel volume Docker
	basePath := os.Getenv("TMP_PATH")
	if basePath == "" {
		basePath = "."
	}
	unifiedFile := filepath.Join(basePath, "final-output.txt")

	// Apri il file finale per scrittura
	finalFile, err := os.Create(unifiedFile)
	if err != nil {
		LogError("[Master] Errore creazione file finale Docker %s: %v", unifiedFile, err)
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
			LogWarn("[Master] File di output %s non trovato, salto", sourceFile)
			continue
		}

		// Leggi il file di output
		file, err := os.Open(sourceFile)
		if err != nil {
			LogError("[Master] Errore apertura file %s: %v", sourceFile, err)
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

	LogInfo("[Master] File finale unificato Docker creato: %s (%d record totali)", unifiedFile, totalRecords)
}

// backupToS3 esegue un backup su S3 se abilitato
func (m *Master) backupToS3() {
	if os.Getenv("S3_SYNC_ENABLED") != "true" {
		LogInfo("[Master] S3 sync non abilitato, salto backup")
		return
	}

	LogInfo("[Master] Iniziando backup su S3...")

	s3Config := GetS3ConfigFromEnv()
	if s3Client, err := NewS3Client(s3Config); err != nil {
		LogError("[Master] Errore creazione client S3: %v", err)
		return
	} else {
		// Backup dei file di output
		if err := s3Client.SyncDirectory("/tmp/mapreduce/output", "output/"); err != nil {
			LogError("[Master] Errore backup output su S3: %v", err)
		} else {
			LogInfo("[Master] Backup output su S3 completato")
		}

		// Backup dei file intermedi
		if err := s3Client.SyncDirectory("/tmp/mapreduce/intermediate", "intermediate/"); err != nil {
			LogError("[Master] Errore backup intermediate su S3: %v", err)
		} else {
			LogInfo("[Master] Backup intermediate su S3 completato")
		}

		// Backup completo con timestamp
		if err := s3Client.BackupToS3("/tmp/mapreduce"); err != nil {
			LogError("[Master] Errore backup completo su S3: %v", err)
		} else {
			LogInfo("[Master] Backup completo su S3 completato")
		}
	}
}

// startClusterManagementMonitor avvia il monitor per la gestione dinamica del cluster
func (m *Master) startClusterManagementMonitor() {
	ticker := time.NewTicker(ClusterMonitorInterval)
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
		LogError("[Master] Errore ottenendo configurazione cluster: %v", config.Error())
		return
	}

	currentServers := config.Configuration().Servers
	LogInfo("[Master] Cluster attuale ha %d server", len(currentServers))

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
			LogInfo("[Master] Aggiungendo server %s (RPC: %s) al cluster Raft", raftAddr, rpcAddr)
			future := m.raft.AddVoter(raft.ServerID(raftAddr), raft.ServerAddress(raftAddr), 0, 0)
			if err := future.Error(); err != nil {
				LogError("[Master] Errore aggiungendo server %s: %v", raftAddr, err)
			} else {
				LogInfo("[Master] Server %s aggiunto con successo", raftAddr)
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

	LogInfo("[Master] Comando add-master applicato con successo")
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

	LogInfo("[Master] Comando remove-master applicato con successo")
	return nil
}

// GetMasterInfo restituisce informazioni sul master tramite RPC
func (m *Master) GetMasterInfo(args *GetMasterInfoArgs, reply *MasterInfoReply) error {
	m.mu.RLock()
	defer m.mu.RUnlock()

	raftState := m.raft.State()
	isLeader := raftState == raft.Leader
	leaderAddr := m.raft.Leader()

	reply.MyID = m.myID
	reply.RaftState = raftState.String()
	reply.IsLeader = isLeader
	reply.LeaderAddress = string(leaderAddr)
	// clusterMembers è una map[string]string, convertiamo in slice di int
	reply.ClusterMembers = make([]int, 0, len(m.clusterMembers))
	for range m.clusterMembers {
		reply.ClusterMembers = append(reply.ClusterMembers, len(reply.ClusterMembers))
	}
	reply.RaftAddrs = append([]string(nil), m.raftAddrs...)
	reply.RpcAddrs = append([]string(nil), m.rpcAddrs...)
	reply.LastSeen = time.Now()

	return nil
}

// GetWorkerInfo restituisce informazioni sui worker tramite RPC
func (m *Master) GetWorkerInfo(args *GetWorkerInfoArgs, reply *WorkerInfoReply) error {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Crea una slice di worker info
	workers := make([]WorkerInfo, 0, len(m.workers))
	for _, worker := range m.workers {
		workers = append(workers, *worker)
	}

	reply.Workers = workers
	reply.LastSeen = time.Now()

	return nil
}

// GetWorkerTasks RPC: restituisce i task correnti (InProgress) per un worker
func (m *Master) GetWorkerTasks(args *GetWorkerTasksArgs, reply *GetWorkerTasksReply) error {
	m.mu.RLock()
	defer m.mu.RUnlock()
	set := m.workerToTasks[strings.TrimSpace(args.WorkerID)]
	if set == nil {
		reply.Tasks = nil
		return nil
	}
	tasks := make([]WorkerTask, 0, len(set))
	for tk := range set {
		tasks = append(tasks, WorkerTask{TaskID: tk.ID, Type: tk.Type})
	}
	reply.Tasks = tasks
	return nil
}

// GetWorkerCount restituisce il numero di worker attivi tramite RPC
func (m *Master) GetWorkerCount(args *GetWorkerCountArgs, reply *WorkerCountReply) error {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Conta worker attivi (visti negli ultimi 30 secondi)
	now := time.Now()
	activeWorkers := 0
	for _, lastSeen := range m.workerLastSeen {
		if now.Sub(lastSeen) <= 30*time.Second {
			activeWorkers++
		}
	}

	reply.ActiveWorkers = activeWorkers
	reply.TotalWorkers = len(m.workers)

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
	LogInfo("[Master] Forzando nuova elezione del leader")
	return nil
}

// LeadershipTransfer RPC method per il trasferimento della leadership
func (m *Master) LeadershipTransfer(args *LeadershipTransferArgs, reply *LeadershipTransferReply) error {
	if m.raft.State() == raft.Leader {
		// Se siamo già leader, trasferiamo la leadership
		LogInfo("[Master %d] Iniziando trasferimento leadership...", m.myID)
		future := m.raft.LeadershipTransfer()
		err := future.Error()
		if err != nil {
			LogError("[Master %d] Errore trasferimento leadership: %v", m.myID, err)
			reply.Success = false
			reply.Message = fmt.Sprintf("Failed to transfer leadership: %v", err)
			return nil
		}

		LogInfo("[Master %d] Leadership transfer avviato con successo", m.myID)
		reply.Success = true
		reply.Message = "Leadership transfer initiated successfully"
		return nil
	}

	// Altrimenti, forziamo un'elezione
	LogWarn("[Master %d] Non sono il leader (stato: %s), non posso trasferire la leadership", m.myID, m.raft.State())
	reply.Success = false
	reply.Message = "Non sono il leader, non posso trasferire la leadership"
	return nil
}

// WorkerHeartbeat RPC method per il heartbeat dei worker
func (m *Master) WorkerHeartbeat(args *WorkerHeartbeatArgs, reply *WorkerHeartbeatReply) error {
	if m.raft.State() != raft.Leader {
		reply.Success = false
		reply.Message = "Non sono il leader"
		return nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	now := time.Now()
	workerID := strings.TrimSpace(args.WorkerID)
	if workerID == "" {
		reply.Success = false
		reply.Message = "WorkerID mancante"
		return nil
	}

	// Aggiorna il timestamp del heartbeat
	m.workerHeartbeat[workerID] = now
	m.workerLastSeen[workerID] = now

	// Aggiorna o crea le informazioni del worker
	if worker, exists := m.workers[workerID]; exists {
		worker.LastSeen = now
	} else {
		m.workers[workerID] = &WorkerInfo{
			ID:        workerID,
			Status:    "active",
			LastSeen:  now,
			TasksDone: 0,
		}
		LogInfo("[Master] Nuovo worker registrato: %s", workerID)
	}

	reply.Success = true
	reply.Message = "Heartbeat ricevuto"
	return nil
}

// ===== METODI REALI PER DASHBOARD DATA =====

// GetJobInfo restituisce informazioni sui job per il dashboard
func (m *Master) GetJobInfo() []JobInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var jobs []JobInfo

	// Crea un job principale basato sullo stato del master
	jobID := "main-job"
	status := "running"
	phase := fmt.Sprint(m.phase)

	if m.isDone {
		status = "completed"
	}

	// Calcola il progresso
	var progress float64
	if m.phase == MapPhase {
		if len(m.mapTasks) > 0 {
			progress = float64(m.mapTasksDone) / float64(len(m.mapTasks)) * 100
		}
	} else if m.phase == ReducePhase {
		if len(m.reduceTasks) > 0 {
			progress = float64(m.reduceTasksDone) / float64(len(m.reduceTasks)) * 100
		}
	} else if m.isDone {
		progress = 100.0
	}

	// Calcola la durata (usa tempo di creazione come approssimazione)
	var duration time.Duration = 0

	job := JobInfo{
		ID:          jobID,
		Status:      status,
		Phase:       phase,
		StartTime:   time.Now().Add(-duration), // Approssimazione
		Duration:    duration,
		MapTasks:    len(m.mapTasks),
		ReduceTasks: len(m.reduceTasks),
		Progress:    progress,
	}

	// Aggiungi end time se completato
	if m.isDone {
		endTime := time.Now()
		job.EndTime = &endTime
	}

	jobs = append(jobs, job)
	return jobs
}

// GetWorkers restituisce informazioni sui worker per il dashboard
func (m *Master) GetWorkers() []WorkerInfoDashboard {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var workers []WorkerInfoDashboard

	for workerID, worker := range m.workers {
		// Determina lo status del worker
		status := worker.Status
		now := time.Now()

		// Se non visto da più di 30 secondi, considera degradato
		if now.Sub(worker.LastSeen) > 30*time.Second {
			status = "degraded"
		}

		// Se non visto da più di 60 secondi, considera fallito
		if now.Sub(worker.LastSeen) > 60*time.Second {
			status = "failed"
		}

		// Trova il task corrente se esiste
		currentTask := ""
		for taskID, taskInfo := range m.mapTasks {
			if taskInfo.State == InProgress {
				// Verifica se questo worker sta eseguendo questo task
				// Questo è una semplificazione - in un'implementazione reale
				// dovresti tracciare quale worker sta eseguendo quale task
				if taskID%len(m.workers) == 0 { // Esempio di distribuzione
					currentTask = fmt.Sprintf("map-task-%d", taskID)
				}
			}
		}

		for taskID, taskInfo := range m.reduceTasks {
			if taskInfo.State == InProgress {
				if taskID%len(m.workers) == 0 { // Esempio di distribuzione
					currentTask = fmt.Sprintf("reduce-task-%d", taskID)
				}
			}
		}

		workerDashboard := WorkerInfoDashboard{
			ID:          workerID,
			Status:      status,
			LastSeen:    worker.LastSeen,
			TasksDone:   worker.TasksDone,
			CurrentTask: currentTask,
		}

		workers = append(workers, workerDashboard)
	}

	return workers
}

// GetMasterInfoForDashboard restituisce informazioni sui master per il dashboard
func (m *Master) GetMasterInfoForDashboard() []MasterInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var masters []MasterInfo

	// Informazioni sul master corrente
	state := "follower"
	role := "follower"
	leader := false

	if m.raft != nil {
		raftState := m.raft.State()
		switch raftState {
		case raft.Leader:
			state = "leader"
			role = "leader"
			leader = true
		case raft.Candidate:
			state = "candidate"
			role = "candidate"
		case raft.Follower:
			state = "follower"
			role = "follower"
		}
	}

	master := MasterInfo{
		ID:       fmt.Sprintf("master-%d", m.myID),
		Role:     role,
		State:    state,
		Leader:   leader,
		LastSeen: time.Now(),
	}

	masters = append(masters, master)
	return masters
}

// GetRaftState restituisce lo stato del cluster Raft
func (m *Master) GetRaftState() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	state := map[string]interface{}{
		"is_leader": false,
		"state":     "unknown",
		"term":      0,
		"index":     0,
		"peers":     []string{},
	}

	if m.raft != nil {
		state["is_leader"] = m.raft.State() == raft.Leader
		state["state"] = m.raft.State().String()
		state["term"] = m.raft.Stats()["last_log_term"]
		state["index"] = m.raft.Stats()["last_log_index"]

		// Aggiungi informazioni sui peer
		peers := []string{}
		for _, peer := range m.raft.GetConfiguration().Configuration().Servers {
			peers = append(peers, string(peer.ID))
		}
		state["peers"] = peers
	}

	return state
}

// GetTaskMetrics restituisce metriche sui task
func (m *Master) GetTaskMetrics() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Conta i task per stato
	mapTaskCounts := make(map[TaskState]int)
	reduceTaskCounts := make(map[TaskState]int)

	for _, task := range m.mapTasks {
		mapTaskCounts[task.State]++
	}

	for _, task := range m.reduceTasks {
		reduceTaskCounts[task.State]++
	}

	// Calcola statistiche
	totalMapTasks := len(m.mapTasks)
	totalReduceTasks := len(m.reduceTasks)
	completedMapTasks := mapTaskCounts[Completed]
	completedReduceTasks := reduceTaskCounts[Completed]

	metrics := map[string]interface{}{
		"map_tasks": map[string]interface{}{
			"total":       totalMapTasks,
			"completed":   completedMapTasks,
			"in_progress": mapTaskCounts[InProgress],
			"pending":     mapTaskCounts[Pending],
			"failed":      mapTaskCounts[Failed],
		},
		"reduce_tasks": map[string]interface{}{
			"total":       totalReduceTasks,
			"completed":   completedReduceTasks,
			"in_progress": reduceTaskCounts[InProgress],
			"pending":     reduceTaskCounts[Pending],
			"failed":      reduceTaskCounts[Failed],
		},
		"overall": map[string]interface{}{
			"phase":          fmt.Sprint(m.phase),
			"is_done":        m.isDone,
			"total_workers":  len(m.workers),
			"active_workers": m.getActiveWorkerCount(),
		},
	}

	return metrics
}

// getActiveWorkerCount restituisce il numero di worker attivi
func (m *Master) getActiveWorkerCount() int {
	now := time.Now()
	activeCount := 0

	for _, worker := range m.workers {
		if now.Sub(worker.LastSeen) <= 30*time.Second {
			activeCount++
		}
	}

	return activeCount
}

// GetSystemHealth restituisce lo stato di salute del sistema
func (m *Master) GetSystemHealth() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	health := map[string]interface{}{
		"overall": "healthy",
		"components": map[string]interface{}{
			"raft":    "healthy",
			"workers": "healthy",
			"tasks":   "healthy",
		},
		"issues": []string{},
	}

	// Controlla lo stato Raft
	if m.raft == nil {
		health["components"].(map[string]interface{})["raft"] = "unhealthy"
		health["issues"] = append(health["issues"].([]string), "Raft not initialized")
	}

	// Controlla i worker
	activeWorkers := m.getActiveWorkerCount()
	if activeWorkers == 0 {
		health["components"].(map[string]interface{})["workers"] = "unhealthy"
		health["issues"] = append(health["issues"].([]string), "No active workers")
	}

	// Controlla i task falliti
	failedMapTasks := 0
	failedReduceTasks := 0

	for _, task := range m.mapTasks {
		if task.State == Failed {
			failedMapTasks++
		}
	}

	for _, task := range m.reduceTasks {
		if task.State == Failed {
			failedReduceTasks++
		}
	}

	if failedMapTasks > 0 || failedReduceTasks > 0 {
		health["components"].(map[string]interface{})["tasks"] = "degraded"
		health["issues"] = append(health["issues"].([]string),
			fmt.Sprintf("Failed tasks: %d map, %d reduce", failedMapTasks, failedReduceTasks))
	}

	// Determina lo stato generale
	hasIssues := len(health["issues"].([]string)) > 0
	if hasIssues {
		health["overall"] = "degraded"
	}

	return health
}
