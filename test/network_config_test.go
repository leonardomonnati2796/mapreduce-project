package test

import (
	"os"
	"testing"

	"../src"
)

func TestNetworkConfigLocal(t *testing.T) {
	// Test local environment
	os.Setenv("DEPLOYMENT_ENV", "local")
	os.Setenv("LOCAL_MODE", "true")
	os.Unsetenv("RAFT_ADDRESSES")
	os.Unsetenv("RPC_ADDRESSES")
	os.Unsetenv("WORKER_ADDRESSES")

	config := src.GetNetworkConfig()

	if !config.IsLocal() {
		t.Errorf("Expected IsLocal() to be true, got false")
	}

	if config.IsAWS() {
		t.Errorf("Expected IsAWS() to be false, got true")
	}

	expectedRaftAddrs := []string{"localhost:1234", "localhost:1235", "localhost:1236"}
	if len(config.RaftAddresses) != len(expectedRaftAddrs) {
		t.Errorf("Expected %d RAFT addresses, got %d", len(expectedRaftAddrs), len(config.RaftAddresses))
	}

	expectedRpcAddrs := []string{"localhost:8000", "localhost:8001", "localhost:8002"}
	if len(config.RpcAddresses) != len(expectedRpcAddrs) {
		t.Errorf("Expected %d RPC addresses, got %d", len(expectedRpcAddrs), len(config.RpcAddresses))
	}
}

func TestNetworkConfigAWS(t *testing.T) {
	// Test AWS environment
	os.Setenv("DEPLOYMENT_ENV", "aws")
	os.Setenv("LOCAL_MODE", "false")
	os.Setenv("RAFT_ADDRESSES", "10.0.1.10:1234,10.0.1.11:1234,10.0.1.12:1234")
	os.Setenv("RPC_ADDRESSES", "10.0.1.10:8000,10.0.1.11:8001,10.0.1.12:8002")
	os.Setenv("WORKER_ADDRESSES", "10.0.2.10:8081,10.0.2.11:8081,10.0.2.12:8081")
	os.Setenv("MASTER_IPS", "10.0.1.10,10.0.1.11,10.0.1.12")
	os.Setenv("WORKER_IPS", "10.0.2.10,10.0.2.11,10.0.2.12")

	config := src.GetNetworkConfig()

	if !config.IsAWS() {
		t.Errorf("Expected IsAWS() to be true, got false")
	}

	if config.IsLocal() {
		t.Errorf("Expected IsLocal() to be false, got true")
	}

	expectedRaftAddrs := []string{"10.0.1.10:1234", "10.0.1.11:1234", "10.0.1.12:1234"}
	if len(config.RaftAddresses) != len(expectedRaftAddrs) {
		t.Errorf("Expected %d RAFT addresses, got %d", len(expectedRaftAddrs), len(config.RaftAddresses))
	}

	expectedRpcAddrs := []string{"10.0.1.10:8000", "10.0.1.11:8001", "10.0.1.12:8002"}
	if len(config.RpcAddresses) != len(expectedRpcAddrs) {
		t.Errorf("Expected %d RPC addresses, got %d", len(expectedRpcAddrs), len(config.RpcAddresses))
	}

	expectedMasterIPs := []string{"10.0.1.10", "10.0.1.11", "10.0.1.12"}
	if len(config.MasterIPs) != len(expectedMasterIPs) {
		t.Errorf("Expected %d Master IPs, got %d", len(expectedMasterIPs), len(config.MasterIPs))
	}

	expectedWorkerIPs := []string{"10.0.2.10", "10.0.2.11", "10.0.2.12"}
	if len(config.WorkerIPs) != len(expectedWorkerIPs) {
		t.Errorf("Expected %d Worker IPs, got %d", len(expectedWorkerIPs), len(config.WorkerIPs))
	}
}

func TestNetworkConfigFallback(t *testing.T) {
	// Test fallback behavior
	os.Unsetenv("DEPLOYMENT_ENV")
	os.Unsetenv("LOCAL_MODE")
	os.Unsetenv("RAFT_ADDRESSES")
	os.Unsetenv("RPC_ADDRESSES")
	os.Unsetenv("WORKER_ADDRESSES")

	config := src.GetNetworkConfig()

	// Should default to local mode
	if !config.IsLocal() {
		t.Errorf("Expected IsLocal() to be true (default), got false")
	}

	if config.IsAWS() {
		t.Errorf("Expected IsAWS() to be false (default), got true")
	}
}
