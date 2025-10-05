@echo off
REM Test per verificare che il Makefile funzioni correttamente dopo le correzioni

echo ========================================
echo TEST CORREZIONE MAKEFILE
echo ========================================
echo.

echo 1. Test verifica file di input...
make verify-inputs
if %errorlevel% neq 0 (
    echo ERRORE: verify-inputs fallito!
    pause
    exit /b 1
)

echo.
echo 2. Test comando mapreduce-test...
echo (Questo test potrebbe richiedere alcuni minuti)
echo Premi un tasto per continuare...
pause >nul

make mapreduce-test
if %errorlevel% neq 0 (
    echo ERRORE: mapreduce-test fallito!
    echo Esegui: make diagnose per debug
    pause
    exit /b 1
)

echo.
echo ========================================
echo ✅ CORREZIONE MAKEFILE COMPLETATA!
echo ========================================
echo.
echo Il Makefile ora funziona correttamente con PowerShell
echo invece di sintassi Windows batch.
echo.
pause
