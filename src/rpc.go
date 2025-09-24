package main

import (
	"fmt"
	"os"
	"path/filepath"
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
	if globalConfig != nil {
		return globalConfig.GetRaftAddresses()
	}
	// Fallback ai valori di default se la configurazione non è inizializzata
	return []string{"localhost:1234", "localhost:1235", "localhost:1236"}
}

func getMasterRpcAddresses() []string {
	if globalConfig != nil {
		return globalConfig.GetRPCAddresses()
	}
	// Fallback ai valori di default se la configurazione non è inizializzata
	return []string{"localhost:8000", "localhost:8001", "localhost:8002"}
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
