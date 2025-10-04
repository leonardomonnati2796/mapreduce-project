package main

const (
	defaultDashboardPort = 8080
	defaultTempPath      = "temp-local"
	defaultOutputPath    = "output"
	defaultRaftDataPath  = "raft-data"
	defaultRaftPort1     = "localhost:1234"
	defaultRaftPort2     = "localhost:1235"
	defaultRaftPort3     = "localhost:1236"
	defaultRpcPort1      = "localhost:8000"
	defaultRpcPort2      = "localhost:8001"
	defaultRpcPort3      = "localhost:8002"
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
	// Per ora restituisce una configurazione di default
	config := &Config{
		Dashboard: DashboardConfig{
			Port:    defaultDashboardPort,
			Enabled: true,
		},
		Paths: PathConfig{
			Temp:     defaultTempPath,
			Output:   defaultOutputPath,
			RaftData: defaultRaftDataPath,
		},
	}
	return config, nil
}

// GetConfig restituisce la configurazione di default
func GetConfig() *Config {
	config, _ := LoadConfig("")
	return config
}

// GetRaftAddresses restituisce gli indirizzi Raft dalla configurazione globale
func (c *Config) GetRaftAddresses() []string {
	return []string{defaultRaftPort1, defaultRaftPort2, defaultRaftPort3}
}

// GetRPCAddresses restituisce gli indirizzi RPC dalla configurazione globale
func (c *Config) GetRPCAddresses() []string {
	return []string{defaultRpcPort1, defaultRpcPort2, defaultRpcPort3}
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
