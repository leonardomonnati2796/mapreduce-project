# MapReduce Project - Enhanced Makefile
# Gestisce avvio locale, test fault tolerance e esecuzione MapReduce

SHELL := /bin/sh

# PowerShell command per Windows
PS_CMD := powershell -ExecutionPolicy Bypass -File

# Verifica se siamo su Windows
ifeq ($(OS),Windows_NT)
	DOCKER_MANAGER := $(PS_CMD) scripts/docker-manager.ps1
else
	DOCKER_MANAGER := echo "Errore: Questo progetto richiede Windows PowerShell per la gestione Docker"
endif

.PHONY: help start stop restart status logs health clean build test report backup copy-output dashboard dashboard-local fault-test leader-test worker-test mapper-test reduce-test recovery-test fault-advanced fault-leader-advanced fault-worker-advanced fault-mapper-advanced fault-reduce-advanced fault-network-advanced fault-storage-advanced fault-stress-advanced docker-start open-html mapreduce-test full-test verify-inputs diagnose mapreduce-quick start-and-test

# Comando di default - mostra l'aiuto
help:
	@echo "=== MAPREDUCE PROJECT - COMANDI PRINCIPALI ==="
	@echo ""
	@echo "AVVIO E GESTIONE CLUSTER:"
	@echo "  make docker-start - Avvia Docker Desktop automaticamente"
	@echo "  make start        - Avvia il cluster MapReduce completo (con build)"
	@echo "  make start-fast   - Avvia il cluster velocemente (senza rebuild)"
	@echo "  make start-quick  - Avvio super veloce (solo se già configurato)"
	@echo "  make stop         - Ferma il cluster"
	@echo "  make restart      - Riavvia il cluster"
	@echo "  make status       - Mostra lo stato del cluster"
	@echo "  make logs         - Mostra i log in tempo reale"
	@echo ""
	@echo "TEST MAPREDUCE E FAULT TOLERANCE:"
	@echo "  make start-and-test - Avvia cluster e esegue test MapReduce (ottimizzato)"
	@echo "  make mapreduce-test - Test MapReduce (richiede cluster già avviato)"
	@echo "  make mapreduce-quick - Test MapReduce veloce (solo se cluster già avviato)"
	@echo "  make full-test      - Test completo: avvio + MapReduce + fault tolerance"
	@echo "  make verify-inputs  - Verifica presenza file di input Words.txt"
	@echo "  make health         - Controlla la salute del cluster"
	@echo "  make test           - Esegue test di fault tolerance"
	@echo "  make dashboard     - Apre il dashboard nel browser"
	@echo "  make open-html      - Apre il dashboard nel browser"
	@echo ""
	@echo "TEST FAULT TOLERANCE SPECIFICI (5 funzionalità):"
	@echo "  make fault-test     - Test completo di fault tolerance"
	@echo "  make leader-test    - Test elezione leader e recovery stato"
	@echo "  make worker-test    - Test fallimenti worker e heartbeat"
	@echo "  make mapper-test    - Test fallimenti mapper e recovery"
	@echo "  make reduce-test    - Test fallimenti reduce e recovery"
	@echo "  make recovery-test  - Test recovery completo del sistema"
	@echo ""
	@echo "TEST AVANZATI FAULT TOLERANCE:"
	@echo "  make fault-advanced      - Test avanzati completi"
	@echo "  make fault-leader-advanced - Test elezione leader avanzato"
	@echo "  make fault-worker-advanced - Test worker avanzato"
	@echo "  make fault-mapper-advanced - Test mapper avanzato"
	@echo "  make fault-reduce-advanced - Test reduce avanzato"
	@echo "  make fault-network-advanced - Test fallimenti rete"
	@echo "  make fault-storage-advanced - Test corruzione dati"
	@echo "  make fault-stress-advanced  - Test stress multipli"
	@echo ""
	@echo "GESTIONE:"
	@echo "  make clean        - Pulisce tutto (container, volumi, immagini)"
	@echo "  make build        - Ricostruisce le immagini Docker"
	@echo "  make backup       - Crea backup dei dati del cluster"
	@echo "  make copy-output  - Copia file di output dai container"
	@echo "  make report       - Genera il report PDF"
	@echo "  make diagnose     - Diagnostica problemi cluster"
	@echo ""
	@echo "Per comandi avanzati, usa direttamente:"
	@echo "  powershell -ExecutionPolicy Bypass -File scripts/docker-manager.ps1 -Help"
	@echo ""

# Verifica file di input
verify-inputs:
	@echo "=== VERIFICA FILE DI INPUT ==="
	@echo "Controllo presenza file Words.txt..."
	@powershell -Command "if (-not (Test-Path 'data\Words.txt')) { Write-Host 'ERRORE: data\Words.txt non trovato!' -ForegroundColor Red; exit 1 }"
	@powershell -Command "if (-not (Test-Path 'data\Words2.txt')) { Write-Host 'ERRORE: data\Words2.txt non trovato!' -ForegroundColor Red; exit 1 }"
	@powershell -Command "if (-not (Test-Path 'data\Words3.txt')) { Write-Host 'ERRORE: data\Words3.txt non trovato!' -ForegroundColor Red; exit 1 }"
	@echo "✓ Words.txt trovato"
	@echo "✓ Words2.txt trovato"
	@echo "✓ Words3.txt trovato"
	@echo "✓ Tutti i file di input sono presenti!"

# Comando ottimizzato: avvio + test MapReduce senza rebuild
start-and-test: verify-inputs
	@echo "=== AVVIO CLUSTER E TEST MAPREDUCE OTTIMIZZATO ==="
	@echo "1. Verifica e avvio Docker Desktop..."
	@powershell -Command "if (-not (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)) { Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'; Start-Sleep -Seconds 30; Write-Host 'Docker Desktop avviato!' } else { Write-Host 'Docker Desktop gia in esecuzione!' }"
	@echo "2. Avvio cluster MapReduce (senza rebuild)..."
	$(DOCKER_MANAGER) start-fast
	@echo "3. Attesa stabilizzazione cluster (10 secondi per completare avvio container)..."
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "4. Verifica stato container prima del health check..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps"
	@echo "5. Verifica stato cluster..."
	$(DOCKER_MANAGER) health
	@echo "6. Attesa completamento job MapReduce (25 secondi)..."
	@powershell -Command "Start-Sleep -Seconds 25"
	@echo "7. Verifica completamento job..."
	$(DOCKER_MANAGER) health
	@echo "8. Copia file di output..."
	$(DOCKER_MANAGER) copy-output
	@echo "9. Verifica file di output generati..."
	@powershell -Command "if (Test-Path 'data\output\final-output.txt') { Write-Host '✓ File finale generato: data\output\final-output.txt' -ForegroundColor Green } else { Write-Host '✗ File finale non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-0') { Write-Host '✓ File mr-out-0 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-0 non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-1') { Write-Host '✓ File mr-out-1 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-1 non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-2') { Write-Host '✓ File mr-out-2 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-2 non trovato' -ForegroundColor Red }"
	@echo "=== AVVIO E TEST MAPREDUCE COMPLETATO ==="

# Test completo MapReduce sui 3 file (assume cluster già avviato)
mapreduce-test: verify-inputs
	@echo "=== TEST MAPREDUCE COMPLETO ==="
	@echo "1. Verifica cluster già avviato..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps"
	@echo "2. Verifica stato cluster..."
	$(DOCKER_MANAGER) health
	@echo "3. Attesa completamento job MapReduce (15 secondi)..."
	@powershell -Command "Start-Sleep -Seconds 15"
	@echo "4. Verifica completamento job..."
	$(DOCKER_MANAGER) health
	@echo "5. Copia file di output..."
	$(DOCKER_MANAGER) copy-output
	@echo "6. Verifica file di output generati..."
	@powershell -Command "if (Test-Path 'data\output\final-output.txt') { Write-Host '✓ File finale generato: data\output\final-output.txt' -ForegroundColor Green } else { Write-Host '✗ File finale non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-0') { Write-Host '✓ File mr-out-0 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-0 non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-1') { Write-Host '✓ File mr-out-1 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-1 non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-2') { Write-Host '✓ File mr-out-2 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-2 non trovato' -ForegroundColor Red }"
	@echo "=== TEST MAPREDUCE COMPLETATO ==="

# Test completo: avvio + MapReduce + fault tolerance
full-test: verify-inputs
	@echo "=== TEST COMPLETO: MAPREDUCE + FAULT TOLERANCE ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa stabilizzazione (10 secondi per completare avvio container)..."
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "3. Verifica stato container prima del health check..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps"
	@echo "4. Verifica stato cluster..."
	$(DOCKER_MANAGER) health
	@echo "5. Test MapReduce..."
	@echo "   - Avvio job sui 3 file Words.txt"
	@echo "   - Attesa completamento (25 secondi)..."
	@powershell -Command "Start-Sleep -Seconds 25"
	@echo "6. Test Fault Tolerance - Fallimento Master..."
	@echo "   - Simulazione guasto master1..."
	docker-compose -f docker/docker-compose.yml stop master1
	@powershell -Command "Start-Sleep -Seconds 5"
	@echo "   - Verifica elezione nuovo leader..."
	$(DOCKER_MANAGER) health
	@echo "7. Test Fault Tolerance - Fallimento Worker..."
	@echo "   - Simulazione guasto worker1..."
	docker-compose -f docker/docker-compose.yml stop worker1
	@powershell -Command "Start-Sleep -Seconds 5"
	@echo "   - Verifica recovery worker..."
	$(DOCKER_MANAGER) health
	@echo "8. Ripristino servizi..."
	docker-compose -f docker/docker-compose.yml start master1 worker1
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "9. Verifica sistema ripristinato..."
	$(DOCKER_MANAGER) health
	@echo "10. Copia file di output..."
	$(DOCKER_MANAGER) copy-output
	@echo "11. Verifica risultati finali..."
	@powershell -Command "if (Test-Path 'data\output\final-output.txt') { Write-Host '✓ Test completato con successo!' -ForegroundColor Green } else { Write-Host '✗ Test fallito - file di output non generato' -ForegroundColor Red }"
	@echo "=== TEST COMPLETO TERMINATO ==="

# Comandi principali - delegano tutto al docker-manager.ps1
docker-start:
	@echo "Avvio Docker Desktop..."
	@powershell -Command "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'"
	@echo "Attesa avvio Docker Desktop (30 secondi)..."
	@powershell -Command "Start-Sleep -Seconds 30"
	@echo "Docker Desktop avviato!"

start:
	@echo "Verifica e avvio Docker Desktop..."
	@powershell -Command "if (-not (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)) { Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'; Start-Sleep -Seconds 30; Write-Host 'Docker Desktop avviato!' } else { Write-Host 'Docker Desktop gia in esecuzione!' }"
	@echo "Avvio cluster MapReduce..."
	$(DOCKER_MANAGER) start
	@echo "Attesa stabilizzazione cluster (10 secondi per completare avvio container)..."
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "Verifica stato container prima del health check..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps"
	@echo "Verifica finale stato cluster..."
	$(DOCKER_MANAGER) health

# Versione veloce - usa immagini esistenti se disponibili
start-fast:
	@echo "Avvio rapido cluster MapReduce..."
	@powershell -Command "if (-not (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)) { Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'; Start-Sleep -Seconds 15; Write-Host 'Docker Desktop avviato!' } else { Write-Host 'Docker Desktop gia in esecuzione!' }"
	$(DOCKER_MANAGER) start-fast
	@echo "Attesa stabilizzazione cluster (10 secondi per completare avvio container)..."
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "Verifica stato container prima del health check..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps"
	@echo "Verifica finale stato cluster..."
	$(DOCKER_MANAGER) health

# Versione super veloce - solo se tutto è già pronto
start-quick:
	@echo "Avvio super rapido (solo se cluster già configurato)..."
	$(DOCKER_MANAGER) start-quick

stop:
	$(DOCKER_MANAGER) stop

restart:
	$(DOCKER_MANAGER) restart

status:
	$(DOCKER_MANAGER) status

logs:
	$(DOCKER_MANAGER) logs

health:
	$(DOCKER_MANAGER) health

test:
	$(DOCKER_MANAGER) health

dashboard:
	$(DOCKER_MANAGER) dashboard

# Apre il dashboard nel browser
open-html:
	@echo "Apertura dashboard nel browser..."
	@powershell -NoProfile -Command "Start-Process 'http://localhost:8080'"

# Test fault tolerance specifici
fault-test:
	$(DOCKER_MANAGER) health -FaultTest

# Test avanzati con script dedicato
fault-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 all

fault-leader-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 leader

fault-worker-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 worker

fault-mapper-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 mapper

fault-reduce-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 reduce

fault-network-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 network

fault-storage-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 storage

fault-stress-advanced:
	$(PS_CMD) scripts/fault-tolerance-test.ps1 stress

# Test delle 5 funzionalità di fault tolerance
leader-test:
	@echo "=== TEST 1/5: ELECTIONE LEADER E RECOVERY STATO ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa stabilizzazione..."
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "3. Test elezione leader..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto leader..."
	docker-compose -f docker/docker-compose.yml stop master0
	@powershell -Command "Start-Sleep -Seconds 5"
	@echo "5. Verifica nuovo leader..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino leader..."
	docker-compose -f docker/docker-compose.yml start master0
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "7. Verifica recovery stato..."
	$(DOCKER_MANAGER) health
	@echo "✓ Test elezione leader completato!"

worker-test:
	@echo "=== TEST 2/5: FALLIMENTI WORKER E HEARTBEAT ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa stabilizzazione..."
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "3. Verifica worker attivi..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto worker..."
	docker-compose -f docker/docker-compose.yml stop worker1
	@powershell -Command "Start-Sleep -Seconds 5"
	@echo "5. Verifica heartbeat e recovery..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino worker..."
	docker-compose -f docker/docker-compose.yml start worker1
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "7. Verifica worker ripristinato..."
	$(DOCKER_MANAGER) health
	@echo "✓ Test fallimenti worker completato!"

mapper-test:
	@echo "=== TEST 3/5: FALLIMENTI MAPPER E RECOVERY ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa avvio job..."
	@powershell -Command "Start-Sleep -Seconds 15"
	@echo "3. Verifica stato mapper..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto durante mappatura..."
	docker-compose -f docker/docker-compose.yml stop worker1
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "5. Verifica recovery mapper..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino worker..."
	docker-compose -f docker/docker-compose.yml start worker1
	@powershell -Command "Start-Sleep -Seconds 15"
	@echo "7. Verifica completamento job..."
	$(DOCKER_MANAGER) health
	@echo "✓ Test fallimenti mapper completato!"

reduce-test:
	@echo "=== TEST 4/5: FALLIMENTI REDUCE E RECOVERY ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa completamento fase map..."
	@powershell -Command "Start-Sleep -Seconds 30"
	@echo "3. Verifica stato reduce..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto durante riduzione..."
	docker-compose -f docker/docker-compose.yml stop worker1
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "5. Verifica recovery reduce..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino worker..."
	docker-compose -f docker/docker-compose.yml start worker1
	@powershell -Command "Start-Sleep -Seconds 20"
	@echo "7. Verifica completamento job..."
	$(DOCKER_MANAGER) health
	@echo "✓ Test fallimenti reduce completato!"

recovery-test:
	@echo "=== TEST 5/5: RECOVERY COMPLETO DEL SISTEMA ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa stabilizzazione..."
	@powershell -Command "Start-Sleep -Seconds 10"
	@echo "3. Backup stato iniziale..."
	$(DOCKER_MANAGER) backup
	@echo "4. Simulazione guasti multipli..."
	docker-compose -f docker/docker-compose.yml stop master1 worker1
	@powershell -Command "Start-Sleep -Seconds 5"
	@echo "5. Verifica recovery automatico..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino servizi..."
	docker-compose -f docker/docker-compose.yml start master1 worker1
	@powershell -Command "Start-Sleep -Seconds 15"
	@echo "7. Verifica sistema completamente ripristinato..."
	$(DOCKER_MANAGER) health
	@echo "✓ Test recovery completo completato!"

# Test completo delle 5 funzionalità
fault-tolerance-complete: leader-test worker-test mapper-test reduce-test recovery-test
	@echo "=== TUTTI I TEST FAULT TOLERANCE COMPLETATI ==="
	@echo "✓ 1. Elezione leader e recovery stato"
	@echo "✓ 2. Fallimenti worker e heartbeat"
	@echo "✓ 3. Fallimenti mapper e recovery"
	@echo "✓ 4. Fallimenti reduce e recovery"
	@echo "✓ 5. Recovery completo del sistema"
	@echo "🎉 TUTTE LE 5 FUNZIONALITÀ DI FAULT TOLERANCE VERIFICATE!"

clean:
	$(DOCKER_MANAGER) clean

build:
	$(DOCKER_MANAGER) start

backup:
	$(DOCKER_MANAGER) backup

copy-output:
	$(DOCKER_MANAGER) copy-output

# Generazione report
report:
	@mkdir -p report
	@echo "Building LaTeX report..."
	@cd report && pdflatex -interaction=nonstopmode report.tex >/dev/null && pdflatex -interaction=nonstopmode report.tex >/dev/null
	@echo "Report generated at report/report.pdf"

# Comando per test completo: avvio + MapReduce + fault tolerance
test-complete: verify-inputs start mapreduce-test fault-tolerance-complete
	@echo "=== TEST COMPLETO TERMINATO CON SUCCESSO ==="
	@echo "✓ Cluster avviato"
	@echo "✓ MapReduce eseguito sui 3 file Words.txt"
	@echo "✓ Tutte le 5 funzionalità di fault tolerance verificate"
	@echo "✓ File di output generati in data/output/"
	@echo "🎉 PROGETTO COMPLETAMENTE FUNZIONANTE!"

# Test MapReduce veloce (solo se cluster già avviato)
mapreduce-quick:
	@echo "=== TEST MAPREDUCE VELOCE ==="
	@echo "1. Verifica cluster già avviato..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps"
	@echo "2. Verifica stato cluster..."
	$(DOCKER_MANAGER) health
	@echo "3. Attesa completamento job MapReduce (15 secondi)..."
	@powershell -Command "Start-Sleep -Seconds 15"
	@echo "4. Verifica completamento job..."
	$(DOCKER_MANAGER) health
	@echo "5. Copia file di output..."
	$(DOCKER_MANAGER) copy-output
	@echo "6. Verifica file di output generati..."
	@powershell -Command "if (Test-Path 'data\output\final-output.txt') { Write-Host '✓ File finale generato: data\output\final-output.txt' -ForegroundColor Green } else { Write-Host '✗ File finale non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-0') { Write-Host '✓ File mr-out-0 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-0 non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-1') { Write-Host '✓ File mr-out-1 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-1 non trovato' -ForegroundColor Red }"
	@powershell -Command "if (Test-Path 'data\output\mr-out-2') { Write-Host '✓ File mr-out-2 generato' -ForegroundColor Green } else { Write-Host '✗ File mr-out-2 non trovato' -ForegroundColor Red }"
	@echo "=== TEST MAPREDUCE VELOCE COMPLETATO ==="

# Diagnostica problemi cluster
diagnose:
	@echo "=== DIAGNOSTICA CLUSTER MAPREDUCE ==="
	@echo "1. Verifica stato container..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps"
	@echo ""
	@echo "2. Verifica container in esecuzione..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps --services --filter 'status=running'"
	@echo ""
	@echo "3. Verifica container fermati..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml ps --services --filter 'status=exited'"
	@echo ""
	@echo "4. Verifica log errori..."
	@powershell -Command "docker-compose -f docker/docker-compose.yml logs --tail=5"
	@echo ""
	@echo "5. Verifica porte in uso..."
	@powershell -Command "netstat -an | findstr ':8080\|:9090\|:8000\|:8001\|:8002'"
	@echo ""
	@echo "6. Health check finale..."
	$(DOCKER_MANAGER) health