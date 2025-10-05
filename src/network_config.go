package main

import (
	"log"
	"strings"
)

// NetworkConfig holds network configuration for different environments
type NetworkConfig struct {
	// Environment detection
	DeploymentEnv string // "local" or "aws"
	LocalMode     bool

	// Network addresses
	RaftAddresses   []string
	RpcAddresses    []string
	WorkerAddresses []string

	// Instance information
	MyPrivateIP string
	MasterIPs   []string
	WorkerIPs   []string

	// Ports
	RaftPort   int
	RpcPort    int
	WorkerPort int
}

// GetNetworkConfig returns network configuration based on environment
func GetNetworkConfig() *NetworkConfig {
	// Get port configuration
	portConfig := GetPortConfig()

	config := &NetworkConfig{
		RaftPort:   portConfig.RaftPort,
		RpcPort:    portConfig.RpcPort,
		WorkerPort: portConfig.WorkerPort,
	}

	// Detect environment
	config.DeploymentEnv = getEnv("DEPLOYMENT_ENV", "local")
	config.LocalMode = getEnv("LOCAL_MODE", "true") == "true"

	// Get addresses from environment variables
	raftAddrs := getEnv("RAFT_ADDRESSES", "")
	rpcAddrs := getEnv("RPC_ADDRESSES", "")
	workerAddrs := getEnv("WORKER_ADDRESSES", "")

	// Parse addresses
	if raftAddrs != "" {
		config.RaftAddresses = strings.Split(raftAddrs, ",")
	} else if config.LocalMode {
		// Fallback for local development
		config.RaftAddresses = []string{
			"localhost:1234",
			"localhost:1235",
			"localhost:1236",
		}
	}

	if rpcAddrs != "" {
		config.RpcAddresses = strings.Split(rpcAddrs, ",")
	} else if config.LocalMode {
		// Fallback for local development
		config.RpcAddresses = []string{
			"localhost:8000",
			"localhost:8001",
			"localhost:8002",
		}
	}

	if workerAddrs != "" {
		config.WorkerAddresses = strings.Split(workerAddrs, ",")
	} else if config.LocalMode {
		// Fallback for local development
		config.WorkerAddresses = []string{
			"localhost:8081",
			"localhost:8082",
			"localhost:8083",
		}
	}

	// Get instance information
	config.MyPrivateIP = getEnv("MY_PRIVATE_IP", "localhost")

	masterIPs := getEnv("MASTER_IPS", "")
	if masterIPs != "" {
		config.MasterIPs = strings.Split(masterIPs, ",")
	}

	workerIPs := getEnv("WORKER_IPS", "")
	if workerIPs != "" {
		config.WorkerIPs = strings.Split(workerIPs, ",")
	}

	log.Printf("Network Config - Environment: %s, Local Mode: %v", config.DeploymentEnv, config.LocalMode)
	log.Printf("RAFT Addresses: %v", config.RaftAddresses)
	log.Printf("RPC Addresses: %v", config.RpcAddresses)
	log.Printf("Worker Addresses: %v", config.WorkerAddresses)

	return config
}

// GetRaftAddresses returns RAFT addresses as comma-separated string
func (nc *NetworkConfig) GetRaftAddresses() string {
	return strings.Join(nc.RaftAddresses, ",")
}

// GetRpcAddresses returns RPC addresses as comma-separated string
func (nc *NetworkConfig) GetRpcAddresses() string {
	return strings.Join(nc.RpcAddresses, ",")
}

// GetWorkerAddresses returns Worker addresses as comma-separated string
func (nc *NetworkConfig) GetWorkerAddresses() string {
	return strings.Join(nc.WorkerAddresses, ",")
}

// IsAWS returns true if running on AWS
func (nc *NetworkConfig) IsAWS() bool {
	return nc.DeploymentEnv == "aws" && !nc.LocalMode
}

// IsLocal returns true if running locally
func (nc *NetworkConfig) IsLocal() bool {
	return nc.LocalMode || nc.DeploymentEnv == "local"
}
