# Test WebSocket Real-time Updates

## Obiettivo
Testare che le tabelle del master e dei worker si aggiornino in tempo reale tramite WebSocket utilizzando Docker.

## Prerequisiti
- Docker e Docker Compose installati
- Il progetto configurato per Docker

## Test Steps

### 1. Avvio del Sistema
```bash
# Navigare nella directory del progetto
cd C:\Users\hp\Desktop\mapreduce-project

# Avviare il cluster Docker tramite Makefile
make start
```

### 2. Verifica Dashboard
1. Aprire il browser su `http://localhost:8080`
2. Verificare che la dashboard si carichi correttamente
3. Controllare l'indicatore "Live Data (WebSocket)" in basso a sinistra

### 3. Test Aggiornamenti Real-time

#### Test 1: Connessione WebSocket
1. Aprire Developer Tools (F12)
2. Andare nella tab "Console"
3. Verificare i messaggi:
   - "WebSocket connected"
   - "Received initial data from WebSocket"
   - "Received real-time update from WebSocket" (ogni 5 secondi)

#### Test 2: Aggiornamento Tabelle Master
1. Nella dashboard, cliccare su "Add Master"
2. Verificare che:
   - Appaia una notifica di successo
   - La tabella Masters si aggiorni automaticamente
   - Il nuovo master appaia nella lista

#### Test 3: Aggiornamento Tabelle Worker
1. Nella dashboard, cliccare su "Add Worker"
2. Verificare che:
   - Appaia una notifica di successo
   - La tabella Workers si aggiorni automaticamente
   - Il nuovo worker appaia nella lista

#### Test 4: Leader Election
1. Nella dashboard, cliccare su "Elect New Leader"
2. Verificare che:
   - Appaia una notifica di successo
   - La tabella Masters mostri il nuovo leader
   - L'aggiornamento avvenga in tempo reale

#### Test 5: Reset Cluster
1. Nella dashboard, cliccare su "Reset Cluster"
2. Verificare che:
   - Appaia una notifica di successo
   - Tutte le tabelle si aggiornino automaticamente
   - Il cluster torni alla configurazione di default

### 4. Test Resilienza WebSocket

#### Test Disconnessione
1. Fermare il container dashboard: `docker stop <container_id>`
2. Verificare che l'indicatore mostri "Disconnected"
3. Riavviare il container: `docker start <container_id>`
4. Verificare che la connessione WebSocket si ristabilisca automaticamente

#### Test Fallback
1. Disabilitare WebSocket nel codice (commentare la chiamata a `initWebSocket()`)
2. Verificare che il sistema fallback al polling ogni 30 secondi
3. L'indicatore dovrebbe mostrare "Live Data" (senza WebSocket)

## Risultati Attesi

### ✅ Successo
- Le tabelle si aggiornano automaticamente ogni 5 secondi
- Le azioni del sistema (add master/worker, leader election, etc.) aggiornano immediatamente le tabelle
- Le notifiche appaiono in tempo reale
- Il sistema è resiliente alle disconnessioni WebSocket
- Il fallback al polling funziona correttamente

### ❌ Problemi Comuni
- **WebSocket non si connette**: Verificare che la porta 8080 sia aperta
- **Tabelle non si aggiornano**: Controllare la console del browser per errori JavaScript
- **Notifiche non appaiono**: Verificare che le funzioni di notifica siano implementate
- **Disconnessioni frequenti**: Controllare i log del container dashboard

## Log di Debug

### Console Browser
```javascript
// Messaggi attesi:
"WebSocket connected"
"Received WebSocket message: initial_data"
"Received WebSocket message: realtime_update"
"Received WebSocket message: master_added"
```

### Log Container Dashboard
```bash
# Verificare i log
docker logs <dashboard_container_id>

# Messaggi attesi:
"WebSocket client connected. Total clients: 1"
"WebSocket client disconnected. Total clients: 0"
```

## Note Tecniche

### WebSocket Endpoint
- URL: `ws://localhost:8080/ws`
- Protocollo: WebSocket standard
- Formato messaggi: JSON

### Aggiornamenti Automatici
- Intervallo: 5 secondi
- Tipi di messaggi:
  - `initial_data`: Dati iniziali al caricamento
  - `realtime_update`: Aggiornamenti periodici
  - `master_added`: Notifica aggiunta master
  - `worker_added`: Notifica aggiunta worker
  - `leader_elected`: Notifica elezione leader
  - `system_stopped`: Notifica stop sistema
  - `cluster_restarted`: Notifica restart cluster

### Fallback
- Se WebSocket non è disponibile, il sistema usa polling HTTP ogni 30 secondi
- L'indicatore mostra lo stato della connessione
- Reconnessione automatica con backoff esponenziale
