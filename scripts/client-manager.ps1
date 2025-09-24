# Script PowerShell per la gestione completa del Client MapReduce CLI
# Questo script unifica tutte le funzionalità del client: job management, monitoring, debugging e configurazione

param(
    [Parameter(Position=0)]
    [string]$Command = "help",
    
    # Job Management
    [string]$JobFile = "",
    [string]$JobId = "",
    [string]$ConfigFile = "",
    [string]$OutputDir = "",
    [int]$Reducers = 10,
    [string]$Status = "",
    [string]$Format = "table",
    
    # Monitoring & Debugging
    [string]$Component = "",
    [int]$Lines = 100,
    [switch]$Follow,
    [switch]$Watch,
    
    # Configuration & Build
    [switch]$Build,
    [switch]$Clean,
    [switch]$Validate,
    [switch]$ShowConfig,
    
    # Advanced Features
    [switch]$Benchmark,
    [switch]$StressTest,
    [switch]$Performance,
    [switch]$Help
)

# Colori per output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Cyan = "`e[36m"
$Magenta = "`e[35m"
$Reset = "`e[0m"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = $Reset)
    Write-Host "$Color$Message$Reset"
}

function Show-Help {
    Write-ColorOutput "=== MapReduce Client Manager ===" $Blue
    Write-Host ""
    Write-Host "Usage: .\scripts\client-manager.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Job Management Commands:"
    Write-Host "  submit [job-file]     Submit a MapReduce job"
    Write-Host "  list                  List all jobs"
    Write-Host "  get [job-id]          Get job details"
    Write-Host "  cancel [job-id]        Cancel a running job"
    Write-Host "  monitor [job-id]      Monitor job progress"
    Write-Host ""
    Write-Host "System Commands:"
    Write-Host "  status                Show system status"
    Write-Host "  health                Check system health"
    Write-Host "  logs [component]      Show logs for component"
    Write-Host "  debug                 Debug cluster status"
    Write-Host ""
    Write-Host "Configuration Commands:"
    Write-Host "  config                Show configuration"
    Write-Host "  validate              Validate configuration"
    Write-Host "  build                 Build client CLI"
    Write-Host ""
    Write-Host "Advanced Commands:"
    Write-Host "  benchmark             Run performance benchmark"
    Write-Host "  stress                Run stress test"
    Write-Host "  performance           Show performance metrics"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -JobFile <file>       Job file to submit"
    Write-Host "  -JobId <id>           Job ID for operations"
    Write-Host "  -ConfigFile <file>     Configuration file"
    Write-Host "  -OutputDir <dir>      Output directory"
    Write-Host "  -Reducers <num>       Number of reducers (default: 10)"
    Write-Host "  -Status <status>      Filter jobs by status"
    Write-Host "  -Format <format>      Output format: table, json (default: table)"
    Write-Host "  -Component <name>     Component name for logs"
    Write-Host "  -Lines <num>          Number of log lines (default: 100)"
    Write-Host "  -Follow               Follow log output"
    Write-Host "  -Watch                Watch mode for status"
    Write-Host "  -Verbose              Enable verbose output"
    Write-Host "  -Build                Build client before operation"
    Write-Host "  -Clean                Clean build environment"
    Write-Host "  -Validate             Validate configuration"
    Write-Host "  -ShowConfig           Show current configuration"
    Write-Host "  -Benchmark            Run benchmark tests"
    Write-Host "  -StressTest           Run stress tests"
    Write-Host "  -Performance          Show performance metrics"
    Write-Host "  -Help                 Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\scripts\client-manager.ps1 submit data/Words.txt"
    Write-Host "  .\scripts\client-manager.ps1 submit data/Words.txt -Reducers 5 -OutputDir output"
    Write-Host "  .\scripts\client-manager.ps1 list -Status running"
    Write-Host "  .\scripts\client-manager.ps1 status -Watch"
    Write-Host "  .\scripts\client-manager.ps1 logs master -Lines 50 -Follow"
    Write-Host "  .\scripts\client-manager.ps1 health -Debug"
    Write-Host "  .\scripts\client-manager.ps1 benchmark"
    Write-Host "  .\scripts\client-manager.ps1 stress"
    Write-Host ""
}

function Test-CLIExists {
    if (-not (Test-Path "cli.exe")) {
        Write-ColorOutput "ERRORE: cli.exe non trovato!" $Red
        Write-Host "Usa -Build per compilare il client o esegui:"
        Write-Host "  .\scripts\client-manager.ps1 build"
        return $false
    }
    return $true
}

function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    }
    catch {
        Write-ColorOutput "ERRORE: Docker non è in esecuzione!" $Red
        Write-Host "Assicurati che Docker Desktop sia avviato e riprova."
        return $false
    }
}

function Build-Client {
    Write-ColorOutput "=== COSTRUZIONE CLIENT CLI ===" $Yellow
    Write-Host ""
    
    # Verifica che Go sia installato
    try {
        $goVersion = go version
        Write-ColorOutput "Go installato: $goVersion" $Green
    }
    catch {
        Write-ColorOutput "ERRORE: Go non è installato!" $Red
        Write-Host "Installa Go da https://golang.org/dl/"
        return $false
    }
    
    # Verifica che i file sorgente esistano
    if (-not (Test-Path "cmd/cli/main.go")) {
        Write-ColorOutput "ERRORE: cmd/cli/main.go non trovato!" $Red
        return $false
    }
    
    if (-not (Test-Path "cmd/cli/cli.go")) {
        Write-ColorOutput "ERRORE: cmd/cli/cli.go non trovato!" $Red
        return $false
    }
    
    # Compila il client
    Write-Host "Compilazione in corso..."
    $buildCmd = "go build -o cli.exe ./cmd/cli"
    
    Invoke-Expression $buildCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "ERRORE durante la compilazione!" $Red
        return $false
    }
    
    # Verifica che il file sia stato creato
    if (Test-Path "cli.exe") {
        $fileSize = (Get-Item "cli.exe").Length
        Write-ColorOutput "Client CLI compilato con successo!" $Green
        Write-Host "File: cli.exe ($fileSize bytes)"
        return $true
    } else {
        Write-ColorOutput "ERRORE: cli.exe non è stato creato!" $Red
        return $false
    }
}

function Invoke-CLICommand {
    param([string]$Arguments, [bool]$RequireDocker = $true)
    
    if (-not (Test-CLIExists)) {
        return $false
    }
    
    if ($RequireDocker -and -not (Test-DockerRunning)) {
        return $false
    }
    
    Write-ColorOutput "Esecuzione comando CLI: cli.exe $Arguments" $Cyan
    Write-Host ""
    
    $process = Start-Process -FilePath "cli.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    return $process.ExitCode -eq 0
}

function Submit-Job {
    if ($JobFile -eq "") {
        Write-ColorOutput "ERRORE: Specificare un file job con -JobFile" $Red
        return $false
    }
    
    if (-not (Test-Path $JobFile)) {
        Write-ColorOutput "ERRORE: File job non trovato: $JobFile" $Red
        return $false
    }
    
    Write-ColorOutput "=== SUBMISSION JOB MAPREDUCE ===" $Blue
    Write-Host ""
    
    $args = "job submit `"$JobFile`" -r $Reducers"
    
    if ($ConfigFile -ne "") {
        $args += " -c `"$ConfigFile`""
    }
    
    if ($OutputDir -ne "") {
        $args += " -o `"$OutputDir`""
    }
    
    if ($Verbose) {
        $args += " --verbose"
    }
    
    return Invoke-CLICommand $args
}

function List-Jobs {
    Write-ColorOutput "=== LISTA JOB ===" $Blue
    Write-Host ""
    
    $args = "job list -f $Format"
    
    if ($Status -ne "") {
        $args += " -s $Status"
    }
    
    return Invoke-CLICommand $args
}

function Get-Job {
    if ($JobId -eq "") {
        Write-ColorOutput "ERRORE: Specificare un Job ID con -JobId" $Red
        return $false
    }
    
    Write-ColorOutput "=== DETTAGLI JOB: $JobId ===" $Blue
    Write-Host ""
    
    return Invoke-CLICommand "job get $JobId"
}

function Cancel-Job {
    if ($JobId -eq "") {
        Write-ColorOutput "ERRORE: Specificare un Job ID con -JobId" $Red
        return $false
    }
    
    Write-ColorOutput "=== CANCELLAZIONE JOB: $JobId ===" $Blue
    Write-Host ""
    
    return Invoke-CLICommand "job cancel $JobId"
}

function Monitor-Job {
    if ($JobId -eq "") {
        Write-ColorOutput "ERRORE: Specificare un Job ID con -JobId" $Red
        return $false
    }
    
    Write-ColorOutput "=== MONITORAGGIO JOB: $JobId ===" $Blue
    Write-Host ""
    
    if ($Watch) {
        Write-Host "Monitoraggio in tempo reale (premi Ctrl+C per uscire)..."
        while ($true) {
            Invoke-CLICommand "job get $JobId" $false
            Start-Sleep -Seconds 5
        }
    } else {
        return Invoke-CLICommand "job get $JobId"
    }
}

function Show-Status {
    Write-ColorOutput "=== STATO SISTEMA ===" $Blue
    Write-Host ""
    
    $args = "status -f $Format"
    
    if ($Watch) {
        $args += " -w"
    }
    
    return Invoke-CLICommand $args
}

function Check-Health {
    Write-ColorOutput "=== HEALTH CHECK ===" $Blue
    Write-Host ""
    
    $args = "health -f $Format"
    
    if ($Verbose) {
        $args += " --verbose"
    }
    
    return Invoke-CLICommand $args
}

function Show-Logs {
    if ($Component -eq "") {
        Write-ColorOutput "ERRORE: Specificare un componente con -Component" $Red
        Write-Host "Componenti disponibili: master, worker, dashboard"
        return $false
    }
    
    Write-ColorOutput "=== LOG COMPONENTE: $Component ===" $Blue
    Write-Host ""
    
    $args = "log show $Component -n $Lines -l info"
    
    if ($Follow) {
        $args += " -f"
    }
    
    return Invoke-CLICommand $args
}

function Debug-Cluster {
    Write-ColorOutput "=== DEBUG CLUSTER ===" $Blue
    Write-Host ""
    
    return Invoke-CLICommand "debug cluster"
}

function Show-Config {
    Write-ColorOutput "=== CONFIGURAZIONE ===" $Blue
    Write-Host ""
    
    return Invoke-CLICommand "config show" $false
}

function Validate-Config {
    Write-ColorOutput "=== VALIDAZIONE CONFIGURAZIONE ===" $Blue
    Write-Host ""
    
    if ($ConfigFile -eq "") {
        $ConfigFile = "config.yaml"
    }
    
    return Invoke-CLICommand "config validate `"$ConfigFile`"" $false
}

function Run-Benchmark {
    Write-ColorOutput "=== BENCHMARK PERFORMANCE ===" $Magenta
    Write-Host ""
    
    # Test con file di dimensioni diverse
    $testFiles = @("data/Words.txt")
    $reducerCounts = @(1, 5, 10, 20)
    
    foreach ($file in $testFiles) {
        if (Test-Path $file) {
            Write-Host "Testando con file: $file"
            
            foreach ($reducers in $reducerCounts) {
                Write-Host "  Reducers: $reducers"
                
                $startTime = Get-Date
                $success = Invoke-CLICommand "job submit `"$file`" -r $reducers"
                $endTime = Get-Date
                
                if ($success) {
                    $duration = ($endTime - $startTime).TotalSeconds
                    Write-ColorOutput "    Completato in $duration secondi" $Green
                } else {
                    Write-ColorOutput "    Fallito" $Red
                }
                
                Start-Sleep -Seconds 2
            }
        }
    }
    
    Write-ColorOutput "Benchmark completato" $Green
}

function Run-StressTest {
    Write-ColorOutput "=== STRESS TEST ===" $Magenta
    Write-Host ""
    
    # Test con job multipli simultanei
    $jobCount = 5
    $jobs = @()
    
    Write-Host "Avviando $jobCount job simultanei..."
    
    for ($i = 1; $i -le $jobCount; $i++) {
        if (Test-Path "data/Words.txt") {
            $job = Start-Job -ScriptBlock {
                param($file, $reducers)
                & "cli.exe" "job" "submit" $file "-r" $reducers
            } -ArgumentList "data/Words.txt", 5
            
            $jobs += $job
            Write-Host "Job $i avviato (ID: $($job.Id))"
        }
    }
    
    Write-Host "Aspettando completamento job..."
    
    foreach ($job in $jobs) {
        Wait-Job $job
        $result = Receive-Job $job
        Remove-Job $job
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Job completato con successo" $Green
        } else {
            Write-ColorOutput "Job fallito" $Red
        }
    }
    
    Write-ColorOutput "Stress test completato" $Green
}

function Show-Performance {
    Write-ColorOutput "=== METRICHE PERFORMANCE ===" $Magenta
    Write-Host ""
    
    # Mostra metriche di sistema
    Write-Host "Metriche di sistema:"
    
    # CPU
    $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    Write-Host "  CPU: $($cpu.Name)"
    
    # Memoria
    $memory = Get-WmiObject -Class Win32_ComputerSystem
    $totalMemory = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
    Write-Host "  Memoria totale: $totalMemory GB"
    
    # Docker
    try {
        $dockerInfo = docker system info --format "{{.ServerVersion}}"
        Write-Host "  Docker: $dockerInfo"
    }
    catch {
        Write-Host "  Docker: Non disponibile"
    }
    
    # File di input
    if (Test-Path "data/Words.txt") {
        $fileSize = (Get-Item "data/Words.txt").Length
        Write-Host "  File input: $fileSize bytes"
    }
    
    Write-Host ""
    Write-Host "Metriche cluster:"
    Invoke-CLICommand "status -f json"
}

# Main execution
if ($Help) {
    Show-Help
    exit 0
}

# Build client se richiesto
if ($Build) {
    if (-not (Build-Client)) {
        exit 1
    }
}

Write-ColorOutput "=== MAPREDUCE CLIENT MANAGER ===" $Blue
Write-Host "Comando: $Command"
Write-Host ""

switch ($Command.ToLower()) {
    "submit" {
        if (Submit-Job) {
            Write-ColorOutput "Job inviato con successo!" $Green
        } else {
            Write-ColorOutput "Errore durante l'invio del job" $Red
            exit 1
        }
    }
    "list" {
        if (List-Jobs) {
            Write-ColorOutput "Lista job completata" $Green
        } else {
            Write-ColorOutput "Errore durante il recupero della lista job" $Red
            exit 1
        }
    }
    "get" {
        if (Get-Job) {
            Write-ColorOutput "Dettagli job recuperati" $Green
        } else {
            Write-ColorOutput "Errore durante il recupero dei dettagli job" $Red
            exit 1
        }
    }
    "cancel" {
        if (Cancel-Job) {
            Write-ColorOutput "Job cancellato con successo" $Green
        } else {
            Write-ColorOutput "Errore durante la cancellazione del job" $Red
            exit 1
        }
    }
    "monitor" {
        if (Monitor-Job) {
            Write-ColorOutput "Monitoraggio completato" $Green
        } else {
            Write-ColorOutput "Errore durante il monitoraggio" $Red
            exit 1
        }
    }
    "status" {
        if (Show-Status) {
            Write-ColorOutput "Stato sistema recuperato" $Green
        } else {
            Write-ColorOutput "Errore durante il recupero dello stato" $Red
            exit 1
        }
    }
    "health" {
        if (Check-Health) {
            Write-ColorOutput "Health check completato" $Green
        } else {
            Write-ColorOutput "Errore durante l'health check" $Red
            exit 1
        }
    }
    "config" {
        if ($ShowConfig) {
            if (Show-Config) {
                Write-ColorOutput "Configurazione recuperata" $Green
            } else {
                Write-ColorOutput "Errore durante il recupero della configurazione" $Red
                exit 1
            }
        } elseif ($Validate) {
            if (Validate-Config) {
                Write-ColorOutput "Configurazione validata" $Green
            } else {
                Write-ColorOutput "Errore durante la validazione" $Red
                exit 1
            }
        } else {
            Show-Config
        }
    }
    "logs" {
        if (Show-Logs) {
            Write-ColorOutput "Log recuperati" $Green
        } else {
            Write-ColorOutput "Errore durante il recupero dei log" $Red
            exit 1
        }
    }
    "debug" {
        if (Debug-Cluster) {
            Write-ColorOutput "Debug cluster completato" $Green
        } else {
            Write-ColorOutput "Errore durante il debug del cluster" $Red
            exit 1
        }
    }
    "build" {
        if (Build-Client) {
            Write-ColorOutput "Build completato" $Green
        } else {
            Write-ColorOutput "Errore durante il build" $Red
            exit 1
        }
    }
    "benchmark" {
        Run-Benchmark
    }
    "stress" {
        Run-StressTest
    }
    "performance" {
        Show-Performance
    }
    "help" {
        Show-Help
    }
    default {
        Write-ColorOutput "Comando non riconosciuto: $Command" $Red
        Write-Host ""
        Show-Help
        exit 1
    }
}

Write-Host ""
Write-ColorOutput "=== Operazione completata ===" $Green
