@echo off
REM Test rapido del Makefile migliorato
REM Verifica le funzionalità principali

echo ========================================
echo QUICK TEST - MAKEFILE MAPREDUCE
echo ========================================
echo.

echo 1. Verifica file di input...
make verify-inputs
if %errorlevel% neq 0 (
    echo ERRORE: File di input mancanti!
    echo Crea i file Words.txt, Words2.txt, Words3.txt in data/
    pause
    exit /b 1
)

echo.
echo 2. Test avvio cluster veloce...
make start-fast
if %errorlevel% neq 0 (
    echo ERRORE: Avvio cluster fallito!
    echo Verifica che Docker Desktop sia in esecuzione
    pause
    exit /b 1
)

echo.
echo 3. Test MapReduce sui 3 file...
make mapreduce-test
if %errorlevel% neq 0 (
    echo ERRORE: Test MapReduce fallito!
    pause
    exit /b 1
)

echo.
echo 4. Test fault tolerance (5 funzionalita)...
make fault-tolerance-complete
if %errorlevel% neq 0 (
    echo ERRORE: Test fault tolerance falliti!
    pause
    exit /b 1
)

echo.
echo ========================================
echo 🎉 TUTTI I TEST COMPLETATI CON SUCCESSO!
echo ========================================
echo.
echo ✓ Cluster MapReduce funzionante
echo ✓ MapReduce eseguito sui 3 file Words.txt
echo ✓ Tutte le 5 funzionalità di fault tolerance verificate
echo.
echo File di output: data/output/
echo Dashboard: http://localhost:8080
echo Metriche: http://localhost:9090
echo.
echo Premi un tasto per continuare...
pause >nul
