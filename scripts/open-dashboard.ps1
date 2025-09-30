# Script unificato per aprire il dashboard MapReduce nel browser
# Combina semplicita e funzionalita avanzate

param(
    [string]$Port = "8080",
    [string]$HostName = "localhost",
    [switch]$Quick,
    [switch]$Help
)

# Funzione per mostrare l'help
function Show-Help {
    Write-Host "=== MAPREDUCE DASHBOARD OPENER ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "DESCRIZIONE:" -ForegroundColor Yellow
    Write-Host "  Questo script apre il dashboard MapReduce nel browser predefinito."
    Write-Host ""
    Write-Host "SINTASSI:" -ForegroundColor Yellow
    Write-Host "  .\open-dashboard.ps1 [PARAMETRI]"
    Write-Host ""
    Write-Host "PARAMETRI:" -ForegroundColor Yellow
    Write-Host "  -Port <numero>     Porta del dashboard (default: 8080)"
    Write-Host "  -Host <indirizzo>  Host del dashboard (default: localhost)"
    Write-Host "  -Quick             Modalità rapida (meno output)"
    Write-Host "  -Help              Mostra questo messaggio di aiuto"
    Write-Host ""
    Write-Host "ESEMPI:" -ForegroundColor Yellow
    Write-Host "  .\open-dashboard.ps1                    # Apre su localhost:8080"
    Write-Host "  .\open-dashboard.ps1 -Port 9090          # Apre su localhost:9090"
    Write-Host "  .\open-dashboard.ps1 -Host 192.168.1.100 # Apre su IP specifico"
    Write-Host ""
    Write-Host "FUNZIONALITA DASHBOARD:" -ForegroundColor Yellow
    Write-Host "  - Monitoraggio tempo reale di Masters e Workers"
    Write-Host "  - Controllo cluster dinamico"
    Write-Host "  - Elezione leader manuale"
    Write-Host "  - Processing testo con MapReduce"
    Write-Host "  - Gestione job e metriche"
    Write-Host ""
}

# Mostra help se richiesto
if ($Help) {
    Show-Help
    exit 0
}

# Costruisce l'URL del dashboard
$DashboardUrl = "http://${HostName}:${Port}"

if (-not $Quick) {
    Write-Host "=== MAPREDUCE DASHBOARD OPENER ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verificando stato del dashboard..." -ForegroundColor Yellow
} else {
    Write-Host "Aprendo MapReduce Dashboard..." -ForegroundColor Green
    Write-Host "Verificando dashboard..." -ForegroundColor Yellow
}

try {
    $response = Invoke-WebRequest -Uri $DashboardUrl -UseBasicParsing -TimeoutSec 3
    if ($response.StatusCode -eq 200) {
        if ($Quick) {
            Write-Host "Dashboard attivo!" -ForegroundColor Green
        } else {
            Write-Host "Dashboard attivo su $DashboardUrl" -ForegroundColor Green
        }
    } else {
        Write-Host "Dashboard risponde ma con status: $($response.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    if ($Quick) {
        Write-Host "Dashboard non raggiungibile" -ForegroundColor Yellow
        Write-Host "Avvia il dashboard con: .\mapreduce-dashboard.exe dashboard" -ForegroundColor Cyan
    } else {
        Write-Host "Dashboard non raggiungibile su $DashboardUrl" -ForegroundColor Red
        Write-Host ""
        Write-Host "POSSIBILI SOLUZIONI:" -ForegroundColor Yellow
        Write-Host "1. Avvia il dashboard con: .\mapreduce-dashboard.exe dashboard" -ForegroundColor Cyan
        Write-Host "2. Verifica che la porta $Port sia libera" -ForegroundColor Cyan
        Write-Host "3. Controlla che il firewall non blocchi la connessione" -ForegroundColor Cyan
        Write-Host ""
        
        $choice = Read-Host "Vuoi comunque aprire il browser? (s/n)"
        if ($choice -notmatch "^[sS]") {
            Write-Host "Operazione annullata." -ForegroundColor Yellow
            exit 1
        }
    }
}

# Apre il browser
if (-not $Quick) {
    Write-Host ""
    Write-Host "Aprendo il dashboard nel browser..." -ForegroundColor Yellow
} else {
    Write-Host "Aprendo browser..." -ForegroundColor Yellow
}

try {
    Start-Process $DashboardUrl
    if ($Quick) {
        Write-Host "Browser aperto: $DashboardUrl" -ForegroundColor Cyan
    } else {
        Write-Host "Browser aperto con successo!" -ForegroundColor Green
        Write-Host "URL: $DashboardUrl" -ForegroundColor Cyan
    }
} catch {
    Write-Host "Errore nell'apertura del browser: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "APERTURA MANUALE:" -ForegroundColor Yellow
    Write-Host "Copia e incolla questo URL nel browser:" -ForegroundColor Cyan
    Write-Host $DashboardUrl -ForegroundColor White
    exit 1
}

# Mostra informazioni aggiuntive
if ($Quick) {
    Write-Host ""
    Write-Host "Per avviare il dashboard:" -ForegroundColor Yellow
    Write-Host "   .\mapreduce-dashboard.exe dashboard" -ForegroundColor White
    Write-Host ""
    Write-Host "Per elezione leader:" -ForegroundColor Yellow
    Write-Host "   .\mapreduce-dashboard.exe elect-leader" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "=== INFORMAZIONI DASHBOARD ===" -ForegroundColor Green
    Write-Host "URL: $DashboardUrl" -ForegroundColor Cyan
    Write-Host "Porta: $Port" -ForegroundColor Cyan
    Write-Host "Host: $HostName" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "=== FUNZIONALITA DISPONIBILI ===" -ForegroundColor Green
    Write-Host "Monitoraggio Tempo Reale:" -ForegroundColor Yellow
    Write-Host "   - Tabelle Masters e Workers che si aggiornano automaticamente" -ForegroundColor White
    Write-Host "   - Health checks e metriche di sistema" -ForegroundColor White
    Write-Host ""

    Write-Host "Controllo Cluster:" -ForegroundColor Yellow
    Write-Host "   - Add Master - Aggiunge un nuovo master" -ForegroundColor White
    Write-Host "   - Add Worker - Aggiunge un nuovo worker" -ForegroundColor White
    Write-Host "   - Elect Leader - Forza elezione nuovo leader" -ForegroundColor White
    Write-Host "   - Reset Cluster - Riavvia cluster con configurazione default" -ForegroundColor White
    Write-Host "   - Stop All - Ferma tutti i servizi" -ForegroundColor White
    Write-Host ""

    Write-Host "Processing MapReduce:" -ForegroundColor Yellow
    Write-Host "   - Text Processing - Elabora testo con MapReduce" -ForegroundColor White
    Write-Host "   - Job Management - Gestione job e risultati" -ForegroundColor White
    Write-Host "   - Output Visualization - Visualizzazione risultati" -ForegroundColor White
    Write-Host ""

    Write-Host "=== COMANDI UTILI ===" -ForegroundColor Green
    Write-Host "Terminale:" -ForegroundColor Yellow
    Write-Host "  .\mapreduce-dashboard.exe dashboard          # Avvia dashboard" -ForegroundColor Cyan
    Write-Host "  .\mapreduce-dashboard.exe elect-leader      # Elezione leader" -ForegroundColor Cyan
    Write-Host "  .\mapreduce-dashboard.exe master 0 file.txt  # Avvia master" -ForegroundColor Cyan
    Write-Host "  .\mapreduce-dashboard.exe worker             # Avvia worker" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "API REST:" -ForegroundColor Yellow
    Write-Host "  GET  $DashboardUrl/api/v1/health            # Health check" -ForegroundColor Cyan
    Write-Host "  GET  $DashboardUrl/api/v1/masters           # Lista masters" -ForegroundColor Cyan
    Write-Host "  GET  $DashboardUrl/api/v1/workers           # Lista workers" -ForegroundColor Cyan
    Write-Host "  POST $DashboardUrl/api/v1/system/elect-leader # Elezione leader" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Dashboard aperto con successo!" -ForegroundColor Green
}
