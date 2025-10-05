package main

import (
	"fmt"
	"os"
	"strconv"
)

const (
	defaultTempPath     = "temp-local"
	defaultOutputPath   = "output"
	defaultRaftDataPath = "raft-data"
)

// Config contiene tutta la configurazione del sistema
type Config struct {
	Dashboard DashboardConfig `mapstructure:"dashboard"`
	Paths     PathConfig      `mapstructure:"paths"`
}

// PathConfig configurazione dei percorsi
type PathConfig struct {
	Temp     string `mapstructure:"temp"`
	Output   string `mapstructure:"output"`
	RaftData string `mapstructure:"raft_data"`
}

// DashboardConfig configurazione del dashboard
type DashboardConfig struct {
	Port    int  `mapstructure:"port"`
	Enabled bool `mapstructure:"enabled"`
}

// LoadConfig carica la configurazione con valori di default
func LoadConfig(configPath string) (*Config, error) {
	config := &Config{
		Dashboard: DashboardConfig{
			Port:    getEnvInt("DASHBOARD_PORT", 8080),
			Enabled: getEnvBool("DASHBOARD_ENABLED", true),
		},
		Paths: PathConfig{
			Temp:     getEnvString("TEMP_PATH", defaultTempPath),
			Output:   getEnvString("OUTPUT_PATH", defaultOutputPath),
			RaftData: getEnvString("RAFT_DATA_PATH", defaultRaftDataPath),
		},
	}

	// Validazione configurazione
	if err := validateConfig(config); err != nil {
		return nil, fmt.Errorf("configurazione non valida: %v", err)
	}

	return config, nil
}

// GetConfig restituisce la configurazione globale o di default
func GetConfig() *Config {
	if globalConfig != nil {
		return globalConfig
	}
	config, _ := LoadConfig("")
	return config
}

// GetRaftAddresses restituisce gli indirizzi Raft dalla configurazione globale
func (c *Config) GetRaftAddresses() []string {
	return []string{"localhost:1234", "localhost:1235", "localhost:1236"}
}

// GetRPCAddresses restituisce gli indirizzi RPC dalla configurazione globale
func (c *Config) GetRPCAddresses() []string {
	return []string{"localhost:8000", "localhost:8001", "localhost:8002"}
}

// GetTempPath restituisce il percorso temporaneo dalla configurazione globale
func (c *Config) GetTempPath() string {
	return c.Paths.Temp
}

// GetOutputPath restituisce il percorso di output dalla configurazione globale
func (c *Config) GetOutputPath() string {
	return c.Paths.Output
}

// GetRaftDataDir restituisce la directory dei dati Raft dalla configurazione globale
func (c *Config) GetRaftDataDir() string {
	return c.Paths.RaftData
}

// Helper functions per gestione variabili d'ambiente
func getEnvString(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolValue, err := strconv.ParseBool(value); err == nil {
			return boolValue
		}
	}
	return defaultValue
}

// validateConfig valida la configurazione
func validateConfig(config *Config) error {
	if config.Dashboard.Port <= 0 || config.Dashboard.Port > 65535 {
		return fmt.Errorf("porta dashboard non valida: %d", config.Dashboard.Port)
	}

	if config.Paths.Temp == "" {
		return fmt.Errorf("percorso temporaneo non può essere vuoto")
	}

	if config.Paths.Output == "" {
		return fmt.Errorf("percorso output non può essere vuoto")
	}

	if config.Paths.RaftData == "" {
		return fmt.Errorf("percorso dati Raft non può essere vuoto")
	}

	return nil
}
