package main

import "time"

// Timeouts and intervals
const (
	// Raft configuration
	RaftStabilizationDelay  = 10 * time.Second
	RaftInitializationDelay = 2 * time.Second
	RaftMonitorInterval     = 1 * time.Second

	// Task configuration
	TaskTimeout         = 15 * time.Second
	TaskMonitorInterval = 2 * time.Second
	TaskRetryDelay      = 2 * time.Second

	// Worker configuration
	WorkerRetryDelay        = 5 * time.Second
	WorkerHeartbeatInterval = 10 * time.Second

	// Master configuration
	MainLoopTimeout        = 5 * time.Minute
	TickerInterval         = 2 * time.Second
	LeaderElectionDelay    = 2 * time.Second
	ClusterManagementDelay = 2 * time.Second
	ClusterMonitorInterval = 10 * time.Second
	FileValidationInterval = 10 * time.Second

	// Minimum arguments
	MinMasterArgs = 4
	MinWorkerArgs = 2

	// Map function constants
	MapValueCount = "1"

	// Default paths
	DefaultDashboardPort = 8080
	DefaultTempPath      = "temp-local"
	DefaultOutputPath    = "output"
	DefaultRaftDataPath  = "raft-data"

	// Default network addresses
	DefaultRaftPort1 = "localhost:1234"
	DefaultRaftPort2 = "localhost:1235"
	DefaultRaftPort3 = "localhost:1236"
	DefaultRpcPort1  = "localhost:8000"
	DefaultRpcPort2  = "localhost:8001"
	DefaultRpcPort3  = "localhost:8002"
)

// Job phases
type JobPhase int

const (
	MapPhase JobPhase = iota
	ReducePhase
	DonePhase
)

// Task states
type TaskState int

const (
	Idle TaskState = iota
	InProgress
	Completed
)

// Task types
type TaskType int

const (
	MapTask TaskType = iota
	ReduceTask
	NoTask
	ExitTask
)

// Log levels
type LogLevel int

const (
	DEBUG LogLevel = iota
	INFO
	WARN
	ERROR
)

// String representations
func (jp JobPhase) String() string {
	switch jp {
	case MapPhase:
		return "Map"
	case ReducePhase:
		return "Reduce"
	case DonePhase:
		return "Done"
	default:
		return "Unknown"
	}
}

func (ts TaskState) String() string {
	switch ts {
	case Idle:
		return "Idle"
	case InProgress:
		return "InProgress"
	case Completed:
		return "Completed"
	default:
		return "Unknown"
	}
}

func (tt TaskType) String() string {
	switch tt {
	case MapTask:
		return "Map"
	case ReduceTask:
		return "Reduce"
	case NoTask:
		return "NoTask"
	case ExitTask:
		return "Exit"
	default:
		return "Unknown"
	}
}

func (ll LogLevel) String() string {
	switch ll {
	case DEBUG:
		return "DEBUG"
	case INFO:
		return "INFO"
	case WARN:
		return "WARN"
	case ERROR:
		return "ERROR"
	default:
		return "UNKNOWN"
	}
}
