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

.PHONY: help start stop restart status logs health clean build test report backup copy-output dashboard

# Comando di default - mostra l'aiuto
help:
	@echo "=== MAPREDUCE PROJECT - COMANDI PRINCIPALI ==="
	@echo ""
	@echo "AVVIO E GESTIONE CLUSTER:"
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
start:
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


