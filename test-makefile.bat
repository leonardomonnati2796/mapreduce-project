@echo off
REM Script di test per il Makefile migliorato
REM Esegue i test principali per verificare il funzionamento

echo ========================================
echo TEST MAKEFILE MAPREDUCE PROJECT
echo ========================================
echo.

echo 1. Verifica file di input...
make verify-inputs
if %errorlevel% neq 0 (
    echo ERRORE: File di input non trovati!
    pause
    exit /b 1
)

echo.
echo 2. Test avvio cluster...
make start-fast
if %errorlevel% neq 0 (
    echo ERRORE: Avvio cluster fallito!
    pause
    exit /b 1
)

echo.
echo 3. Test MapReduce sui 3 file Words.txt...
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
echo 5. Verifica file di output...
if exist "data\output\final-output.txt" (
    echo ✓ File finale generato: data\output\final-output.txt
) else (
    echo ✗ File finale non trovato
)

if exist "data\output\mr-out-0" (
    echo ✓ File mr-out-0 generato
) else (
    echo ✗ File mr-out-0 non trovato
)

echo.
echo ========================================
echo TUTTI I TEST COMPLETATI CON SUCCESSO!
echo ========================================
echo.
echo File di output disponibili in data/output/
echo Dashboard: http://localhost:8080
echo Metriche: http://localhost:9090
echo.
pause
