# 🚀 MapReduce Distributed System with Fault Tolerance

Un sistema MapReduce distribuito implementato in Go con fault tolerance avanzata, gestione cluster tramite Docker e dashboard web per il monitoraggio in tempo reale.

## ✨ Caratteristiche Principali

- **🔄 Fault Tolerance**: Gestione automatica dei fallimenti con elezione leader Raft
- **🐳 Containerizzazione**: Deployment completo tramite Docker Compose
- **📊 Dashboard Web**: Interfaccia di monitoraggio in tempo reale
- **📈 Metriche**: Integrazione con Prometheus per osservabilità
- **⚡ Performance**: Elaborazione distribuita ottimizzata
- **🛠️ Gestione Semplificata**: Interfaccia unificata tramite Makefile

## 🏗️ Architettura

Il sistema è composto da:

- **3 Master Nodes**: Cluster Raft per fault tolerance
- **2 Worker Nodes**: Elaborazione distribuita dei task
- **Dashboard Web**: Monitoraggio e gestione cluster
- **Sistema di Metriche**: Prometheus per osservabilità

## 🚀 Avvio Rapido

### Prerequisiti
- **Windows** con PowerShell
- **Docker Desktop** installato e avviato
- **Make** (opzionale, per comandi semplificati)

### Installazione e Avvio

1. **Clona il repository**:
```bash
git clone https://github.com/[username]/mapreduce-project.git
cd mapreduce-project
```

2. **Avvia il cluster completo**:
```bash
make start
```

3. **Accedi alla dashboard**: http://localhost:8080

## 📋 Comandi Principali

### Tramite Make (Raccomandato)
```bash
# Mostra tutti i comandi disponibili
make help

# Avvia il cluster completo
make start

# Ferma il cluster
make stop

# Riavvia il cluster
make restart

# Mostra lo stato del cluster
make status

# Monitora i log in tempo reale
make logs

# Controlla la salute del cluster
make health

# Testa la fault tolerance
make test

# Pulisce tutto (container, volumi, immagini)
make clean

# Ricostruisce le immagini Docker
make build

# Genera il report PDF
make report
```

### Tramite PowerShell (Comandi Avanzati)
```powershell
# Avvia cluster
.\scripts\simple-docker-manager.ps1 start

# Mostra stato dettagliato
.\scripts\simple-docker-manager.ps1 status

# Monitora log in tempo reale
.\scripts\simple-docker-manager.ps1 logs

# Test fault tolerance
.\scripts\simple-docker-manager.ps1 test

# Pulisce tutto
.\scripts\simple-docker-manager.ps1 clean

# Mostra aiuto completo
.\scripts\simple-docker-manager.ps1 -Help
```

## 📁 Struttura del Progetto

```
mapreduce-project/
├── src/                    # Codice sorgente Go
│   ├── main.go            # Entry point principale
│   ├── master.go          # Implementazione master
│   ├── mapreduce.go       # Core MapReduce logic
│   ├── rpc.go             # Comunicazione RPC
│   ├── config.go          # Configurazione sistema
│   ├── dashboard.go       # Dashboard web
│   ├── health.go          # Health checks
│   └── metrics.go         # Sistema metriche
├── cmd/cli/               # CLI client
├── scripts/               # Script PowerShell per gestione
│   ├── simple-docker-manager.ps1
│   ├── docker-manager.ps1
│   └── copy-output-simple.ps1
├── docker/               # Configurazione Docker
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── Dockerfile.simple
├── data/                 # File di input e output
│   ├── Words.txt         # File di test
│   └── output/           # Risultati elaborazione
├── web/                  # Dashboard web
│   ├── static/           # CSS e JavaScript
│   └── templates/        # Template HTML
├── report/               # Documentazione e report
│   ├── report.pdf        # Report completo
│   └── diagrams/         # Diagrammi architettura
├── test/                 # Test e validazione
├── Makefile             # Interfaccia unificata
└── README.md            # Questo file
```

## 🎯 Flusso di Lavoro Tipico

1. **🚀 Avvio**: `make start` - Avvia il cluster completo tramite Docker
2. **📊 Monitoraggio**: `make status` - Verifica stato cluster
3. **👀 Osservazione**: Accedi a http://localhost:8080 per dashboard con WebSocket real-time
4. **🧪 Test**: `make test` - Verifica fault tolerance
5. **📁 Risultati**: File di output in `data/output/`
6. **🧹 Pulizia**: `make clean` - Pulisce tutto

⚠️ **IMPORTANTE**: Questo progetto funziona **esclusivamente con Docker**. Non ci sono eseguibili locali.

## 🌐 Accesso ai Servizi

Dopo l'avvio del cluster:

| Servizio | URL | Descrizione |
|----------|-----|-------------|
| **Dashboard** | http://localhost:8080 | Interfaccia web principale |
| **Metrics** | http://localhost:9090 | Metriche Prometheus |
| **Master 0 RPC** | localhost:8000 | RPC Master principale |
| **Master 1 RPC** | localhost:8001 | RPC Master secondario |
| **Master 2 RPC** | localhost:8002 | RPC Master terziario |

## 🔧 Sviluppo


### Configurazione
Il sistema utilizza variabili d'ambiente per la configurazione:

```bash
# Indirizzi Raft
RAFT_ADDRESSES="master0:1234,master1:1234,master2:1234"

# Indirizzi RPC
RPC_ADDRESSES="master0:8000,master1:8001,master2:8002"

# Path temporaneo
TMP_PATH="/tmp/mapreduce"

# Metriche
METRICS_ENABLED="true"
METRICS_PORT="9090"
```

## 📊 Monitoraggio e Osservabilità

### Dashboard Web
- **Stato Cluster**: Visualizzazione real-time dei nodi
- **Job Management**: Gestione task MapReduce
- **Health Checks**: Monitoraggio salute sistema
- **Metriche**: Grafici performance e utilizzo

### Metriche Prometheus
- **Task Completati**: Contatori task Map/Reduce
- **Tempo Elaborazione**: Durata media task
- **Errori**: Conteggio fallimenti e retry
- **Utilizzo Risorse**: CPU, memoria, network

### Health Checks
- **Master Status**: Verifica stato leader/follower
- **Worker Connectivity**: Connessioni worker attive
- **Raft Consensus**: Stato algoritmo Raft
- **Storage Health**: Verifica spazio disco

## 🛡️ Fault Tolerance

Il sistema implementa fault tolerance completa:

### Gestione Fallimenti Master
- **Leader Election**: Elezione automatica nuovo leader
- **State Recovery**: Ripristino stato dopo fallimento
- **Consensus Raft**: Algoritmo distribuito per coerenza

### Gestione Fallimenti Worker
- **Task Reassignment**: Riassegnazione task falliti
- **Retry Logic**: Tentativi automatici di riconnessione
- **Graceful Degradation**: Continuazione con worker disponibili

### Persistenza Dati
- **Intermediate Files**: Salvataggio dati intermedi
- **Checkpoint**: Punti di controllo per recovery
- **Durable Storage**: Storage persistente per risultati

## 🧪 Testing

### Test Fault Tolerance
```bash
# Test completo fault tolerance
make test

# Test specifico leader election
.\scripts\test-leader-election.ps1

# Test dashboard
.\scripts\test-dashboard-simple.ps1
```

### Test Manuali
- **Kill Master**: Simula fallimento master
- **Kill Worker**: Simula fallimento worker
- **Network Partition**: Simula partizione rete
- **Resource Exhaustion**: Test limiti risorse

## 🛠️ Troubleshooting

### Problemi Comuni

| Problema | Soluzione |
|----------|-----------|
| **Docker non risponde** | Verifica Docker Desktop avviato |
| **Porte occupate** | `make clean` e riavvia |
| **Errori permessi** | Esegui PowerShell come amministratore |
| **Script non funziona** | Verifica policy esecuzione PowerShell |
| **Cluster non si avvia** | Controlla log con `make logs` |
| **Worker non si connette** | Verifica configurazione RPC |

### Debug
```bash
# Log dettagliati
make logs

# Stato cluster
make status

# Health check
make health

# Pulisci e riavvia
make clean && make start
```

## 📚 Documentazione Tecnica

- **Report Completo**: `report/report.pdf`
- **Diagrammi Architettura**: `report/diagrams/`
- **API Documentation**: Codice sorgente commentato
- **Configuration Guide**: Variabili ambiente e setup

## 🤝 Contributi

1. Fork del repository
2. Crea branch feature (`git checkout -b feature/AmazingFeature`)
3. Commit modifiche (`git commit -m 'Add AmazingFeature'`)
4. Push branch (`git push origin feature/AmazingFeature`)
5. Apri Pull Request

## 📄 Licenza

Questo progetto è distribuito sotto licenza MIT. Vedi `LICENSE` per dettagli.

## 👥 Autori

- **Sviluppatore**: [Nome Sviluppatore]
- **Contatto**: [email@example.com]

## 🙏 Ringraziamenti

- HashiCorp Raft per algoritmo consensus
- Docker per containerizzazione
- Prometheus per sistema metriche
- Gin per framework web dashboard

---

**⭐ Se questo progetto ti è utile, considera di lasciare una stella!**
