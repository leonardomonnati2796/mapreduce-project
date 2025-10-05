package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Variabile globale per la configurazione
var globalConfig *Config

// InitConfig inizializza la configurazione globale
func InitConfig(configPath string) error {
	config, err := LoadConfig(configPath)
	if err != nil {
		return err
	}
	globalConfig = config
	return nil
}

func getMasterRaftAddresses() []string {
	// Use new network configuration
	networkConfig := GetNetworkConfig()
	if len(networkConfig.RaftAddresses) > 0 {
		return networkConfig.RaftAddresses
	}

	// Fallback to environment variables
	if raftAddrs := os.Getenv("RAFT_ADDRESSES"); raftAddrs != "" {
		return strings.Split(raftAddrs, ",")
	}

	if globalConfig != nil {
		return globalConfig.GetRaftAddresses()
	}
	// Fallback ai valori di default se la configurazione non è inizializzata
	return []string{"localhost:1234", "localhost:1235", "localhost:1236"}
}

func getMasterRpcAddresses() []string {
	// Use new network configuration
	networkConfig := GetNetworkConfig()
	if len(networkConfig.RpcAddresses) > 0 {
		return networkConfig.RpcAddresses
	}

	// Fallback to environment variables
	if rpcAddrs := os.Getenv("RPC_ADDRESSES"); rpcAddrs != "" {
		return strings.Split(rpcAddrs, ",")
	}

	if globalConfig != nil {
		return globalConfig.GetRPCAddresses()
	}
	// Fallback ai valori di default se la configurazione non è inizializzata
	return []string{"localhost:8000", "localhost:8001", "localhost:8002"}
}

// TaskType è definito in constants.go

type Task struct {
	Type       TaskType
	TaskID     int
	Input      string
	NReduce    int
	NMap       int
	Checkpoint string `json:"checkpoint,omitempty"`
}
type RequestTaskArgs struct {
	WorkerID string `json:"worker_id"`
}
type TaskCompletedArgs struct {
	TaskID   int      `json:"task_id"`
	Type     TaskType `json:"type"`
	WorkerID string   `json:"worker_id"`
}
type Reply struct{}

// Strutture per ottenere informazioni sui master
type GetMasterInfoArgs struct{}
type MasterInfoReply struct {
	MyID           int       `json:"my_id"`
	RaftState      string    `json:"raft_state"`
	IsLeader       bool      `json:"is_leader"`
	LeaderAddress  string    `json:"leader_address"`
	ClusterMembers []int     `json:"cluster_members"`
	RaftAddrs      []string  `json:"raft_addrs"`
	RpcAddrs       []string  `json:"rpc_addrs"`
	LastSeen       time.Time `json:"last_seen"`
}

// Strutture per ottenere informazioni sui worker
type GetWorkerInfoArgs struct{}
type WorkerInfoReply struct {
	Workers  []WorkerInfo `json:"workers"`
	LastSeen time.Time    `json:"last_seen"`
}

type WorkerInfo struct {
	ID        string    `json:"id"`
	Status    string    `json:"status"`
	LastSeen  time.Time `json:"last_seen"`
	TasksDone int       `json:"tasks_done"`
}

// Strutture per il trasferimento della leadership
type LeadershipTransferArgs struct{}
type LeadershipTransferReply struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// Strutture per il heartbeat dei worker
type WorkerHeartbeatArgs struct {
	WorkerID string `json:"worker_id"`
}

type WorkerHeartbeatReply struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// Strutture per ottenere il conteggio dei worker attivi
type GetWorkerCountArgs struct{}
type WorkerCountReply struct {
	ActiveWorkers int `json:"active_workers"`
	TotalWorkers  int `json:"total_workers"`
}

// ResetTaskArgs consente di richiedere il reset di un task specifico
type ResetTaskArgs struct {
	TaskID int      `json:"task_id"`
	Type   TaskType `json:"type"` // MapTask o ReduceTask
	Reason string   `json:"reason,omitempty"`
}

// GetWorkerTasksArgs/Reply per ottenere i task assegnati a un worker
type GetWorkerTasksArgs struct {
	WorkerID string `json:"worker_id"`
}
type GetWorkerTasksReply struct {
	Tasks []WorkerTask `json:"tasks"`
}

// WorkerTask rappresenta un task con ID e tipo
type WorkerTask struct {
	TaskID int      `json:"task_id"`
	Type   TaskType `json:"type"`
}

func getIntermediateFileName(mapTaskID, reduceTaskID int) string {
	basePath := os.Getenv("TMP_PATH")
	if basePath == "" {
		if globalConfig != nil {
			basePath = globalConfig.GetTempPath()
		} else {
			basePath = "." // Fallback
		}
	}
	return filepath.Join(basePath, fmt.Sprintf("mr-intermediate-%d-%d", mapTaskID, reduceTaskID))
}

func getOutputFileName(reduceTaskID int) string {
	basePath := os.Getenv("TMP_PATH")
	if basePath == "" {
		if globalConfig != nil {
			basePath = globalConfig.GetOutputPath()
		} else {
			basePath = "." // Fallback
		}
	}
	return filepath.Join(basePath, fmt.Sprintf("mr-out-%d", reduceTaskID))
}
