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
	// Prima controlla se ci sono indirizzi Raft nelle variabili d'ambiente (per Docker)
	if raftAddrs := os.Getenv("RAFT_ADDRESSES"); raftAddrs != "" {
		return strings.Split(raftAddrs, ",")
	}

	if globalConfig != nil {
		return globalConfig.GetRaftAddresses()
	}
	// Fallback ai valori di default se la configurazione non è inizializzata
	return []string{defaultRaftPort1, defaultRaftPort2, defaultRaftPort3}
}

func getMasterRpcAddresses() []string {
	// Prima controlla se ci sono indirizzi RPC nelle variabili d'ambiente (per Docker)
	if rpcAddrs := os.Getenv("RPC_ADDRESSES"); rpcAddrs != "" {
		return strings.Split(rpcAddrs, ",")
	}

	if globalConfig != nil {
		return globalConfig.GetRPCAddresses()
	}
	// Fallback ai valori di default se la configurazione non è inizializzata
	return []string{defaultRpcPort1, defaultRpcPort2, defaultRpcPort3}
}

type TaskType int

const (
	MapTask TaskType = iota
	ReduceTask
	NoTask
	ExitTask
)

type Task struct {
	Type    TaskType
	TaskID  int
	Input   string
	NReduce int
	NMap    int
}
type RequestTaskArgs struct{}
type TaskCompletedArgs struct {
	TaskID int
	Type   TaskType
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
