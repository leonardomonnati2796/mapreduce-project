# WebSocket Real-time Updates per MapReduce Dashboard

## Panoramica

La dashboard MapReduce ora supporta aggiornamenti in tempo reale tramite WebSocket, permettendo alle tabelle del master e dei worker di aggiornarsi automaticamente senza bisogno di refresh manuale della pagina.

## Funzionalità Implementate

### 🔄 Aggiornamenti Real-time
- **Tabelle Master**: Si aggiornano automaticamente ogni 5 secondi
- **Tabelle Worker**: Si aggiornano automaticamente ogni 5 secondi  
- **Indicatori di Salute**: Aggiornamento in tempo reale dello stato del sistema
- **Notifiche Istantanee**: Le azioni del sistema (add master/worker, leader election, etc.) mostrano notifiche immediate

### 🌐 WebSocket Support
- **Connessione Automatica**: Il browser si connette automaticamente al WebSocket
- **Reconnessione Automatica**: Se la connessione si perde, il sistema tenta di riconnettersi automaticamente
- **Fallback al Polling**: Se WebSocket non è disponibile, il sistema usa polling HTTP ogni 30 secondi
- **Indicatore di Stato**: Mostra lo stato della connessione (Live Data, Disconnected, etc.)

### 📡 Tipi di Messaggi WebSocket

#### Messaggi Automatici
- `initial_data`: Dati iniziali caricati al primo accesso
- `realtime_update`: Aggiornamenti periodici ogni 5 secondi

#### Messaggi di Notifica
- `master_added`: Quando viene aggiunto un nuovo master
- `worker_added`: Quando viene aggiunto un nuovo worker
- `leader_elected`: Quando viene eletto un nuovo leader
- `system_stopped`: Quando il sistema viene fermato
- `cluster_restarted`: Quando il cluster viene riavviato

## Configurazione

### Variabili d'Ambiente
```yaml
# docker-compose.yml
environment:
  WEBSOCKET_ENABLED: "true"
  WEBSOCKET_UPDATE_INTERVAL: "5s"
```

### Dipendenze
```go
// go.mod
require (
    github.com/gorilla/websocket v1.5.1
)
```

## Architettura Tecnica

### Backend (Go)
```go
// Struttura Dashboard con supporto WebSocket
type Dashboard struct {
    // ... campi esistenti
    upgrader      websocket.Upgrader
    clients       map[*websocket.Conn]bool
    clientsMutex  sync.RWMutex
    broadcast     chan []byte
}
```

### Frontend (JavaScript)
```javascript
// Connessione WebSocket automatica
function initWebSocket() {
    const wsUrl = `ws://${window.location.host}/ws`;
    websocket = new WebSocket(wsUrl);
    // ... gestione eventi
}
```

## Endpoint WebSocket

- **URL**: `ws://localhost:8080/ws`
- **Protocollo**: WebSocket standard
- **Formato**: JSON
- **Autenticazione**: Nessuna (per sviluppo)

## Test e Verifica

### Test Automatico
```powershell
# Eseguire il test automatico
.\test\test-websocket-realtime.ps1
```

### Test Manuale
1. Aprire `http://localhost:8080`
2. Aprire Developer Tools (F12) → Console
3. Verificare i messaggi:
   - `WebSocket connected`
   - `Received WebSocket message: initial_data`
   - `Received WebSocket message: realtime_update`

### Test Azioni
1. **Add Master**: Cliccare il pulsante e verificare aggiornamento tabella
2. **Add Worker**: Cliccare il pulsante e verificare aggiornamento tabella  
3. **Elect Leader**: Cliccare il pulsante e verificare cambio leader
4. **Reset Cluster**: Cliccare il pulsante e verificare reset completo

## Indicatori di Stato

### Indicatore Real-time
- **🟢 Live Data (WebSocket)**: Connessione WebSocket attiva
- **🟡 Live Data**: Fallback al polling HTTP
- **🔴 Disconnected**: Connessione persa, tentativo di riconnessione

### Console Browser
```javascript
// Messaggi di debug
"WebSocket connected"
"WebSocket disconnected" 
"Attempting to reconnect (1/5)..."
"Max reconnection attempts reached. Falling back to polling."
```

## Resilienza e Fallback

### Gestione Disconnessioni
- **Reconnessione Automatica**: Fino a 5 tentativi con delay di 3 secondi
- **Fallback al Polling**: Se WebSocket non è disponibile, usa HTTP polling
- **Indicatore di Stato**: Mostra sempre lo stato corrente della connessione

### Gestione Errori
- **Timeout**: Gestione timeout delle connessioni
- **Errori di Parsing**: Gestione errori nei messaggi JSON
- **Connessioni Multiple**: Supporto per più client connessi simultaneamente

## Performance

### Ottimizzazioni
- **Aggiornamenti Incrementali**: Solo i dati modificati vengono inviati
- **Broadcast Efficiente**: Un solo messaggio per tutti i client connessi
- **Gestione Memoria**: Cleanup automatico delle connessioni chiuse

### Metriche
- **Intervallo Aggiornamenti**: 5 secondi (configurabile)
- **Timeout Connessione**: 3 secondi per riconnessione
- **Max Client**: Illimitato (gestito dinamicamente)

## Troubleshooting

### Problemi Comuni

#### WebSocket non si connette
```bash
# Verificare che la porta 8080 sia aperta
netstat -an | findstr :8080

# Verificare i log del container
docker logs <dashboard_container_id>
```

#### Tabelle non si aggiornano
```javascript
// Controllare la console del browser
// Verificare errori JavaScript
// Verificare che WebSocket sia connesso
```

#### Notifiche non appaiono
```javascript
// Verificare che le funzioni di notifica siano implementate
// Controllare i messaggi WebSocket ricevuti
```

### Log di Debug

#### Backend (Go)
```bash
# Log del container dashboard
docker logs <dashboard_container_id>

# Messaggi attesi:
"WebSocket client connected. Total clients: 1"
"WebSocket client disconnected. Total clients: 0"
"Broadcasting update to 1 clients"
```

#### Frontend (JavaScript)
```javascript
// Console del browser
console.log("WebSocket connected");
console.log("Received WebSocket message:", data.type);
console.log("Updating masters table with", data.masters.length, "masters");
```

## Avvio del Sistema

### Tramite Makefile (Raccomandato)
```bash
# Avviare il cluster completo
make start

# Aprire la dashboard
make dashboard

# Verificare lo stato
make status

# Fermare il cluster
make stop
```

### Tramite Docker Compose
```bash
# Avviare il cluster
docker-compose -f docker/docker-compose.yml up -d

# Verificare i container
docker ps

# Fermare il cluster
docker-compose -f docker/docker-compose.yml down
```

## Sviluppi Futuri

### Funzionalità Pianificate
- **Autenticazione WebSocket**: Supporto per autenticazione sicura
- **Compressione Messaggi**: Riduzione del traffico di rete
- **Metriche Real-time**: Grafici che si aggiornano in tempo reale
- **Notifiche Push**: Notifiche del browser per eventi importanti

### Ottimizzazioni
- **WebSocket Pooling**: Gestione più efficiente delle connessioni
- **Message Queuing**: Coda per messaggi quando client non disponibili
- **Selective Updates**: Aggiornamenti solo per i dati modificati

## Contribuire

### Aggiungere Nuovi Tipi di Messaggi
1. **Backend**: Aggiungere nuovo tipo in `broadcastCustomUpdate()`
2. **Frontend**: Aggiungere case in `handleWebSocketMessage()`
3. **Test**: Aggiornare i test per includere il nuovo tipo

### Modificare Intervalli di Aggiornamento
1. **Backend**: Modificare `time.NewTicker(5 * time.Second)`
2. **Frontend**: Modificare il fallback polling interval
3. **Config**: Aggiungere variabile d'ambiente per l'intervallo

---

**Nota**: Questa implementazione è ottimizzata per l'ambiente Docker. Tutte le funzionalità sono progettate per funzionare esclusivamente tramite container Docker.
