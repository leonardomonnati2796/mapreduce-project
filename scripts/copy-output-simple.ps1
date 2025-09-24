# Script PowerShell per copiare i file di output dal volume Docker alla cartella locale

param(
    [switch]$Help
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Show-Help {
    Write-ColorOutput "=== MapReduce Copy Output ===" "Blue"
    Write-Host ""
    Write-Host "Usage: .\scripts\copy-output-simple.ps1"
    Write-Host ""
    Write-Host "Questo script copia i file di output dai container Docker alla cartella locale data/output/"
    Write-Host ""
    Write-Host "File copiati:"
    Write-Host "  - mr-out-0 a mr-out-9 (file di output dei reducer)"
    Write-Host "  - final-output.txt (file finale unificato)"
    Write-Host ""
    Write-Host "Requisiti:"
    Write-Host "  - Docker deve essere in esecuzione"
    Write-Host "  - I container MapReduce devono essere attivi"
    Write-Host ""
}

function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    }
    catch {
        Write-ColorOutput "ERRORE: Docker non è in esecuzione!" "Red"
        Write-Host "Assicurati che Docker Desktop sia avviato e riprova."
        return $false
    }
}

function Copy-OutputFiles {
    Write-ColorOutput "=== COPIA FILE DI OUTPUT DAL VOLUME DOCKER ===" "Blue"
    Write-Host ""
    
    # Verifica che Docker sia in esecuzione
    if (-not (Test-DockerRunning)) {
        return $false
    }
    
    # Verifica che i container MapReduce siano attivi
    $activeWorker = $null
    
    # Prova prima con worker2, poi con worker1
    try {
        docker exec mapreduce-project-worker2-1 echo "test" | Out-Null
        $activeWorker = "mapreduce-project-worker2-1"
    }
    catch {
        try {
            docker exec mapreduce-project-worker1_1 echo "test" | Out-Null
            $activeWorker = "mapreduce-project-worker1_1"
        }
        catch {
            Write-ColorOutput "ERRORE: Nessun container worker attivo trovato" "Red"
            Write-Host "Assicurati che i servizi MapReduce siano in esecuzione con: docker-compose up -d"
            return $false
        }
    }
    
    Write-Host "Container worker attivo trovato: $activeWorker"
    Write-Host ""
    
    # Crea la cartella data/output se non esiste
    if (-not (Test-Path "data/output")) {
        New-Item -ItemType Directory -Path "data/output" -Force | Out-Null
        Write-Host "Cartella data/output creata"
    }
    
    Write-Host ""
    
    # Copia ogni file di output dal volume Docker
    Write-Host "Ricerca e copia file di output..."
    $copiedFiles = 0
    $skippedFiles = 0
    
    for ($i = 0; $i -le 9; $i++) {
        $sourceFile = "/tmp/mapreduce/mr-out-$i"
        $destFile = "data/output/mr-out-$i"
        
        # Verifica se il file esiste nel container
        try {
            docker exec $activeWorker test -f $sourceFile | Out-Null
            if ($LASTEXITCODE -eq 0) {
                # Copia il file dal container alla cartella locale
                docker cp "$activeWorker`:$sourceFile" $destFile
                if ($LASTEXITCODE -eq 0) {
                    Write-ColorOutput "File copiato: mr-out-$i" "Green"
                    $copiedFiles++
                } else {
                    Write-ColorOutput "Errore copia file: mr-out-$i" "Red"
                }
            } else {
                $skippedFiles++
            }
        }
        catch {
            $skippedFiles++
        }
    }
    
    # Copia anche il file finale unificato
    $unifiedSourceFile = "/tmp/mapreduce/final-output.txt"
    $unifiedDestFile = "data/output/final-output.txt"
    
    try {
        docker exec $activeWorker test -f $unifiedSourceFile | Out-Null
        if ($LASTEXITCODE -eq 0) {
            docker cp "$activeWorker`:$unifiedSourceFile" $unifiedDestFile
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "File finale unificato copiato: final-output.txt" "Green"
                $copiedFiles++
            } else {
                Write-ColorOutput "Errore copia file finale unificato" "Red"
            }
        } else {
            Write-Host "File finale unificato non trovato nel volume Docker"
        }
    }
    catch {
        Write-Host "File finale unificato non trovato nel volume Docker"
    }
    
    Write-Host ""
    if ($copiedFiles -gt 0) {
        Write-ColorOutput "Copiati $copiedFiles file di output in data/output/" "Green"
    } else {
        Write-ColorOutput "Nessun file di output trovato da copiare" "Yellow"
    }
    
    if ($skippedFiles -gt 0) {
        Write-Host "$skippedFiles file non trovati (normale se il job non è ancora completato)"
    }
    
    Write-Host ""
    Write-ColorOutput "=== COPIA COMPLETATA ===" "Green"
    
    # Mostra i file copiati
    if ($copiedFiles -gt 0) {
        Write-Host "File nella cartella data/output:"
        Get-ChildItem "data/output" | ForEach-Object {
            Write-Host "  File: $($_.Name) - Size: $($_.Length) bytes"
        }
    }
    
    return $true
}

# Main execution
if ($Help) {
    Show-Help
    exit 0
}

Write-ColorOutput "=== MAPREDUCE COPY OUTPUT ===" "Blue"
Write-Host ""

if (Copy-OutputFiles) {
    Write-ColorOutput "Copia file di output completata con successo!" "Green"
} else {
    Write-ColorOutput "Errore durante la copia dei file di output" "Red"
    exit 1
}

Write-Host ""
Write-ColorOutput "=== Operazione completata ===" "Green"
