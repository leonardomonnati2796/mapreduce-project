@echo off
REM Script batch per aprire il dashboard MapReduce nel browser
REM Autore: MapReduce Project
REM Versione: 1.0

setlocal enabledelayedexpansion

REM Configurazione default
set PORT=8080
set HOST=localhost
set DASHBOARD_URL=http://%HOST%:%PORT%

echo.
echo ========================================
echo    MAPREDUCE DASHBOARD OPENER
echo ========================================
echo.

REM Verifica se PowerShell è disponibile
powershell -Command "Get-Host" >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRORE: PowerShell non disponibile
    echo Usa lo script PowerShell: open-dashboard.ps1
    pause
    exit /b 1
)

REM Verifica se il dashboard è in esecuzione
echo Verificando stato del dashboard...
powershell -Command "try { $response = Invoke-WebRequest -Uri '%DASHBOARD_URL%' -UseBasicParsing -TimeoutSec 5; if ($response.StatusCode -eq 200) { Write-Host 'Dashboard attivo su %DASHBOARD_URL%' -ForegroundColor Green } else { Write-Host 'Dashboard risponde ma con status:' $response.StatusCode -ForegroundColor Yellow } } catch { Write-Host 'Dashboard non raggiungibile su %DASHBOARD_URL%' -ForegroundColor Red; Write-Host ''; Write-Host 'POSSIBILI SOLUZIONI:' -ForegroundColor Yellow; Write-Host '1. Avvia il dashboard con: .\mapreduce-dashboard.exe dashboard' -ForegroundColor Cyan; Write-Host '2. Verifica che la porta %PORT% sia libera' -ForegroundColor Cyan; Write-Host '3. Controlla che il firewall non blocchi la connessione' -ForegroundColor Cyan; Write-Host ''; $choice = Read-Host 'Vuoi comunque aprire il browser? (s/n)'; if ($choice -notmatch '^[sS]') { Write-Host 'Operazione annullata.' -ForegroundColor Yellow; exit 1 } }"

if %errorlevel% neq 0 (
    echo.
    echo Operazione annullata.
    pause
    exit /b 1
)

REM Apre il browser
echo.
echo Aprendo il dashboard nel browser...
start "" "%DASHBOARD_URL%"

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo    DASHBOARD APERTO CON SUCCESSO!
    echo ========================================
    echo.
    echo URL: %DASHBOARD_URL%
    echo Porta: %PORT%
    echo Host: %HOST%
    echo.
    echo FUNZIONALITA DISPONIBILI:
    echo - Monitoraggio tempo reale Masters e Workers
    echo - Controllo cluster dinamico
    echo - Elezione leader manuale
    echo - Processing testo con MapReduce
    echo - Gestione job e metriche
    echo.
    echo COMANDI UTILI:
    echo Terminale:
    echo   .\mapreduce-dashboard.exe dashboard
    echo   .\mapreduce-dashboard.exe elect-leader
    echo   .\mapreduce-dashboard.exe master 0 file.txt
    echo   .\mapreduce-dashboard.exe worker
    echo.
    echo Dashboard aperto con successo! 🚀
) else (
    echo.
    echo ERRORE: Impossibile aprire il browser
    echo.
    echo APERTURA MANUALE:
    echo Copia e incolla questo URL nel browser:
    echo %DASHBOARD_URL%
)

echo.
pause
