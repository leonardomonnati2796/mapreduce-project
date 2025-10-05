package main

import (
	"os"
	"strconv"
	"strings"
)

// PortConfig holds all port configurations
type PortConfig struct {
	// Core service ports
	RaftPort      int
	RpcPort       int
	WorkerPort    int
	DashboardPort int

	// Health check ports
	HealthPort int

	// Load balancer ports
	LoadBalancerPort int
	NginxPort        int

	// Database ports
	RedisPort int

	// Monitoring ports
	PrometheusPort int
	GrafanaPort    int
}

// GetPortConfig returns port configuration from environment variables
func GetPortConfig() *PortConfig {
	config := &PortConfig{
		// Default ports
		RaftPort:         getEnvInt("RAFT_PORT", 1234),
		RpcPort:          getEnvInt("RPC_PORT", 8000),
		WorkerPort:       getEnvInt("WORKER_PORT", 8081),
		DashboardPort:    getEnvInt("DASHBOARD_PORT", 8080),
		HealthPort:       getEnvInt("HEALTH_PORT", 8100),
		LoadBalancerPort: getEnvInt("LOADBALANCER_PORT", 80),
		NginxPort:        getEnvInt("NGINX_PORT", 80),
		RedisPort:        getEnvInt("REDIS_PORT", 6379),
		PrometheusPort:   getEnvInt("PROMETHEUS_PORT", 9090),
		GrafanaPort:      getEnvInt("GRAFANA_PORT", 3000),
	}

	return config
}

// GetRaftPorts returns RAFT ports for multiple masters
func (pc *PortConfig) GetRaftPorts(masterCount int) []string {
	ports := make([]string, masterCount)
	for i := 0; i < masterCount; i++ {
		ports[i] = ":" + strconv.Itoa(pc.RaftPort+i)
	}
	return ports
}

// GetRpcPorts returns RPC ports for multiple masters
func (pc *PortConfig) GetRpcPorts(masterCount int) []string {
	ports := make([]string, masterCount)
	for i := 0; i < masterCount; i++ {
		ports[i] = ":" + strconv.Itoa(pc.RpcPort+i)
	}
	return ports
}

// GetWorkerPorts returns Worker ports for multiple workers
func (pc *PortConfig) GetWorkerPorts(workerCount int) []string {
	ports := make([]string, workerCount)
	for i := 0; i < workerCount; i++ {
		ports[i] = ":" + strconv.Itoa(pc.WorkerPort+i)
	}
	return ports
}

// GetHealthPorts returns Health check ports for multiple instances
func (pc *PortConfig) GetHealthPorts(instanceCount int) []string {
	ports := make([]string, instanceCount)
	for i := 0; i < instanceCount; i++ {
		ports[i] = ":" + strconv.Itoa(pc.HealthPort+i)
	}
	return ports
}

// GetPortRanges returns port ranges for Docker port mapping
func (pc *PortConfig) GetPortRanges(instanceCount int) map[string][]string {
	return map[string][]string{
		"raft":   pc.GetRaftPorts(instanceCount),
		"rpc":    pc.GetRpcPorts(instanceCount),
		"worker": pc.GetWorkerPorts(instanceCount),
		"health": pc.GetHealthPorts(instanceCount),
	}
}

// getEnvInt gets environment variable as integer with default value
func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

// getEnv gets environment variable with default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// GetPortMapping returns Docker port mapping string
func (pc *PortConfig) GetPortMapping(hostPort, containerPort int) string {
	return strconv.Itoa(hostPort) + ":" + strconv.Itoa(containerPort)
}

// GetPortMappings returns multiple port mappings
func (pc *PortConfig) GetPortMappings(hostPorts, containerPorts []int) []string {
	mappings := make([]string, len(hostPorts))
	for i := 0; i < len(hostPorts); i++ {
		mappings[i] = pc.GetPortMapping(hostPorts[i], containerPorts[i])
	}
	return mappings
}

// GetEnvironmentPorts returns environment variable string for ports
func (pc *PortConfig) GetEnvironmentPorts() map[string]string {
	return map[string]string{
		"RAFT_PORT":         strconv.Itoa(pc.RaftPort),
		"RPC_PORT":          strconv.Itoa(pc.RpcPort),
		"WORKER_PORT":       strconv.Itoa(pc.WorkerPort),
		"DASHBOARD_PORT":    strconv.Itoa(pc.DashboardPort),
		"HEALTH_PORT":       strconv.Itoa(pc.HealthPort),
		"LOADBALANCER_PORT": strconv.Itoa(pc.LoadBalancerPort),
		"NGINX_PORT":        strconv.Itoa(pc.NginxPort),
		"REDIS_PORT":        strconv.Itoa(pc.RedisPort),
		"PROMETHEUS_PORT":   strconv.Itoa(pc.PrometheusPort),
		"GRAFANA_PORT":      strconv.Itoa(pc.GrafanaPort),
	}
}

// GetPortList returns comma-separated list of ports
func (pc *PortConfig) GetPortList(ports []int) string {
	portStrings := make([]string, len(ports))
	for i, port := range ports {
		portStrings[i] = strconv.Itoa(port)
	}
	return strings.Join(portStrings, ",")
}
