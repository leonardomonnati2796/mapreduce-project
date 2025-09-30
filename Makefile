# MapReduce Project - Unified Interface
# Questo Makefile delega tutte le operazioni al docker-manager.ps1 per un'interfaccia unificata

SHELL := /bin/sh

# PowerShell command per Windows
PS_CMD := powershell -ExecutionPolicy Bypass -File

# Verifica se siamo su Windows
ifeq ($(OS),Windows_NT)
	DOCKER_MANAGER := $(PS_CMD) scripts/docker-manager.ps1
else
	DOCKER_MANAGER := echo "Errore: Questo progetto richiede Windows PowerShell per la gestione Docker"
endif

.PHONY: help start stop restart status logs health clean build test report backup copy-output dashboard dashboard-local fault-test leader-test worker-test mapper-test reduce-test recovery-test fault-advanced fault-leader-advanced fault-worker-advanced fault-mapper-advanced fault-reduce-advanced fault-network-advanced fault-storage-advanced fault-stress-advanced docker-start open-html

# Comando di default - mostra l'aiuto
help:
	@echo "=== MAPREDUCE PROJECT - COMANDI PRINCIPALI ==="
	@echo ""
	@echo "AVVIO E GESTIONE CLUSTER:"
	@echo "  make docker-start - Avvia Docker Desktop automaticamente"
	@echo "  make start        - Avvia il cluster MapReduce completo"
	@echo "  make stop         - Ferma il cluster"
	@echo "  make restart      - Riavvia il cluster"
	@echo "  make status       - Mostra lo stato del cluster"
	@echo "  make logs         - Mostra i log in tempo reale"
	@echo ""
	@echo "MONITORAGGIO E TEST:"
	@echo "  make health       - Controlla la salute del cluster"
	@echo "  make test         - Esegue test di fault tolerance"
	@echo "  make dashboard    - Apre il dashboard nel browser"
	@echo "  make dashboard-local - Avvia il dashboard in locale (abilita i controlli)"
	@echo "  make open-html    - Apre una pagina HTML locale (PAGE=percorso)"
	@echo ""
	@echo "TEST FAULT TOLERANCE SPECIFICI:"
	@echo "  make fault-test   - Test completo di fault tolerance"
	@echo "  make leader-test  - Test elezione leader e recovery stato"
	@echo "  make worker-test  - Test fallimenti worker e heartbeat"
	@echo "  make mapper-test  - Test fallimenti mapper e recovery"
	@echo "  make reduce-test  - Test fallimenti reduce e recovery"
	@echo "  make recovery-test - Test recovery completo del sistema"
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
	@echo ""
	@echo "Per comandi avanzati, usa direttamente:"
	@echo "  powershell -ExecutionPolicy Bypass -File scripts/docker-manager.ps1 -Help"
	@echo ""

# Comandi principali - delegano tutto al docker-manager.ps1
docker-start:
	@echo "Avvio Docker Desktop..."
	@powershell -Command "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'"
	@echo "Attesa avvio Docker Desktop (30 secondi)..."
	@timeout /t 30 /nobreak >nul
	@echo "Docker Desktop avviato!"

start:
	@echo "Verifica e avvio Docker Desktop..."
	@powershell -Command "if (-not (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)) { Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'; Start-Sleep -Seconds 30; Write-Host 'Docker Desktop avviato!' } else { Write-Host 'Docker Desktop gia in esecuzione!' }"
	@echo "Avvio cluster MapReduce..."
	$(DOCKER_MANAGER) start

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

# Avvia il dashboard localmente (fuori da Docker) per abilitare i controlli di sistema
dashboard-local:
	@echo "Avvio dashboard locale..."
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath .\mapreduce-dashboard.exe -ArgumentList 'dashboard'; Start-Sleep -Seconds 2; & scripts/open-dashboard.ps1 -Quick"

# Apre una pagina HTML locale nel browser di default
# Utilizzo: make open-html PAGE=web/templates/index.html
PAGE ?= web/templates/index.html
open-html:
	@echo "Apertura pagina HTML: $(PAGE)"
	@powershell -NoProfile -Command "$p = Resolve-Path '$(PAGE)'; Start-Process $p"

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

leader-test:
	@echo "=== TEST ELECTIONE LEADER E RECOVERY STATO ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa stabilizzazione..."
	@timeout /t 10 /nobreak >nul
	@echo "3. Test elezione leader..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto leader..."
	docker-compose -f docker/docker-compose.yml stop master0
	@timeout /t 5 /nobreak >nul
	@echo "5. Verifica nuovo leader..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino leader..."
	docker-compose -f docker/docker-compose.yml start master0
	@timeout /t 10 /nobreak >nul
	@echo "7. Verifica recovery stato..."
	$(DOCKER_MANAGER) health

worker-test:
	@echo "=== TEST FALLIMENTI WORKER E HEARTBEAT ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa stabilizzazione..."
	@timeout /t 10 /nobreak >nul
	@echo "3. Verifica worker attivi..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto worker..."
	docker-compose -f docker/docker-compose.yml stop worker1
	@timeout /t 5 /nobreak >nul
	@echo "5. Verifica heartbeat e recovery..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino worker..."
	docker-compose -f docker/docker-compose.yml start worker1
	@timeout /t 10 /nobreak >nul
	@echo "7. Verifica worker ripristinato..."
	$(DOCKER_MANAGER) health

mapper-test:
	@echo "=== TEST FALLIMENTI MAPPER E RECOVERY ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa avvio job..."
	@timeout /t 15 /nobreak >nul
	@echo "3. Verifica stato mapper..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto durante mappatura..."
	docker-compose -f docker/docker-compose.yml stop worker1
	@timeout /t 10 /nobreak >nul
	@echo "5. Verifica recovery mapper..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino worker..."
	docker-compose -f docker/docker-compose.yml start worker1
	@timeout /t 15 /nobreak >nul
	@echo "7. Verifica completamento job..."
	$(DOCKER_MANAGER) health

reduce-test:
	@echo "=== TEST FALLIMENTI REDUCE E RECOVERY ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa completamento fase map..."
	@timeout /t 30 /nobreak >nul
	@echo "3. Verifica stato reduce..."
	$(DOCKER_MANAGER) health
	@echo "4. Simulazione guasto durante riduzione..."
	docker-compose -f docker/docker-compose.yml stop worker1
	@timeout /t 10 /nobreak >nul
	@echo "5. Verifica recovery reduce..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino worker..."
	docker-compose -f docker/docker-compose.yml start worker1
	@timeout /t 20 /nobreak >nul
	@echo "7. Verifica completamento job..."
	$(DOCKER_MANAGER) health

recovery-test:
	@echo "=== TEST RECOVERY COMPLETO DEL SISTEMA ==="
	@echo "1. Avvio cluster..."
	$(DOCKER_MANAGER) start
	@echo "2. Attesa stabilizzazione..."
	@timeout /t 10 /nobreak >nul
	@echo "3. Backup stato iniziale..."
	$(DOCKER_MANAGER) backup
	@echo "4. Simulazione guasti multipli..."
	docker-compose -f docker/docker-compose.yml stop master1 worker1
	@timeout /t 5 /nobreak >nul
	@echo "5. Verifica recovery automatico..."
	$(DOCKER_MANAGER) health
	@echo "6. Ripristino servizi..."
	docker-compose -f docker/docker-compose.yml start master1 worker1
	@timeout /t 15 /nobreak >nul
	@echo "7. Verifica sistema completamente ripristinato..."
	$(DOCKER_MANAGER) health
	@echo "8. Test completato!"

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

# Build locale per sviluppo (opzionale)
build-local:
	go build -o mapreduce ./src
	go build -o cli.exe ./cmd/cli


