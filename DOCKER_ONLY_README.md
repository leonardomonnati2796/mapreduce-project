# MapReduce Project - Solo Docker

## ⚠️ IMPORTANTE: Solo Docker

Questo progetto è progettato per funzionare **esclusivamente con Docker**. Non ci sono eseguibili locali o modalità di sviluppo locale.

## 🐳 Architettura Docker

### Container Principali
- **dashboard**: Dashboard web con WebSocket real-time
- **master0, master1, master2**: Nodi master del cluster Raft
- **worker1, worker2, worker3**: Worker per l'elaborazione MapReduce

### Rete Docker
- **mapreduce-net**: Rete interna per la comunicazione tra container
- **Porte esposte**: 8080 (dashboard), 8000-8002 (master RPC), 1234-1236 (Raft)

## 🚀 Comandi Principali

### Avvio e Gestione
```bash
# Avviare il cluster completo
make start

# Aprire la dashboard
make dashboard

# Verificare lo stato
make status

# Fermare il cluster
make stop

# Riavviare il cluster
make restart
```

### Monitoraggio
```bash
# Visualizzare i log
make logs

# Controllo salute del cluster
make health

# Test fault tolerance
make test
```

## 🔧 Configurazione

### Variabili d'Ambiente
```yaml
# docker-compose.yml
environment:
  RAFT_ADDRESSES: "master0:1234,master1:1234,master2:1234"
  RPC_ADDRESSES: "master0:8000,master1:8001,master2:8002"
  WEBSOCKET_ENABLED: "true"
  WEBSOCKET_UPDATE_INTERVAL: "5s"
```

### Volumi Docker
- **intermediate-data**: Dati intermedi MapReduce
- **./data**: File di input (solo lettura)

## 📊 Dashboard WebSocket

### Funzionalità Real-time
- **Aggiornamenti Automatici**: Tabelle master/worker ogni 5 secondi
- **Notifiche Istantanee**: Per azioni del sistema
- **Indicatore di Stato**: Mostra connessione WebSocket
- **Fallback al Polling**: Se WebSocket non disponibile

### Endpoint WebSocket
- **URL**: `ws://localhost:8080/ws`
- **Protocollo**: WebSocket standard
- **Formato**: JSON

## 🧪 Test e Verifica

### Test Automatico
```powershell
# Eseguire test WebSocket
.\test\test-websocket-realtime.ps1
```

### Test Manuale
1. Aprire `http://localhost:8080`
2. Verificare indicatore "Live Data (WebSocket)"
3. Testare azioni: Add Master, Add Worker, Elect Leader
4. Verificare aggiornamenti automatici delle tabelle

## 🚫 Cosa NON Usare

### ❌ File Eseguibili Locali
- ~~`mapreduce-dashboard.exe`~~ - **NON USARE**
- ~~`mapreduce.exe`~~ - **NON USARE**
- ~~`cli.exe`~~ - **NON USARE**

### ❌ Modalità di Sviluppo Locale
- ~~Esecuzione diretta del codice Go~~ - **NON SUPPORTATO**
- ~~Dashboard locale~~ - **NON SUPPORTATO**
- ~~Master/Worker locali~~ - **NON SUPPORTATO**

## 🔍 Troubleshooting

### Problemi Comuni

#### Porta 8080 Occupata
```bash
# Verificare processi sulla porta
netstat -an | findstr :8080

# Fermare processi locali
taskkill /f /im mapreduce-dashboard.exe
```

#### Container Non Si Avviano
```bash
# Verificare Docker
docker ps

# Riavviare cluster
make stop
make start
```

#### WebSocket Non Funziona
```bash
# Verificare log dashboard
docker logs docker-dashboard-1

# Controllare connessione
curl http://localhost:8080/api/v1/health
```

## 📁 Struttura Progetto

```
mapreduce-project/
├── docker/
│   ├── docker-compose.yml    # Configurazione cluster
│   ├── Dockerfile           # Immagine Docker
│   └── data/                # File di input
├── src/                     # Codice sorgente Go
├── web/                     # Frontend dashboard
├── scripts/                 # Script di gestione
├── test/                    # Test automatici
└── Makefile                # Comandi principali
```

## 🎯 Flusso di Lavoro

1. **Sviluppo**: Modificare codice in `src/`
2. **Build**: `make start` ricostruisce automaticamente
3. **Test**: `make test` per verificare funzionalità
4. **Deploy**: Tutto funziona tramite Docker

## 🔒 Sicurezza

- **Nessuna Autenticazione**: Solo per sviluppo
- **Porte Locali**: Accesso solo da localhost
- **Volumi Read-Only**: File di input protetti

---

**Nota**: Questo progetto è ottimizzato per l'ambiente Docker. Tutte le funzionalità, inclusi WebSocket real-time, funzionano esclusivamente tramite container Docker.
