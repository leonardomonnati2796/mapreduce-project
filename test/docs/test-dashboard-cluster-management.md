# Test Dashboard Cluster Management

## Funzionalità Implementate

### 1. Pulsanti del Pannello di Controllo Sistema

I pulsanti nel dashboard web ora sono collegati alle funzioni reali del `docker-manager.ps1`:

- **Add Master**: Aggiunge un nuovo master al cluster e forza una nuova elezione del leader
- **Add Worker**: Aggiunge un nuovo worker per aumentare la capacità di processing
- **Reset Cluster**: Riavvia il cluster con la configurazione di default (3 master, 3 worker)
- **Stop All**: Ferma tutti i servizi del cluster

### 2. Funzioni Dashboard.go Implementate

#### `executeDockerManagerCommand(action string)`
- Esegue comandi PowerShell per gestire il cluster
- Supporta le azioni: `add-master`, `add-worker`, `stop`, `reset`
- Gestisce errori e restituisce output dettagliato

#### Funzioni API Aggiornate
- `startMaster()`: Chiama `docker-manager.ps1 add-master`
- `startWorker()`: Chiama `docker-manager.ps1 add-worker`
- `stopAll()`: Chiama `docker-manager.ps1 stop`
- `restartCluster()`: Chiama `docker-manager.ps1 reset`

### 3. Interfaccia Utente Migliorata

#### Tooltip Informativi
- Ogni pulsante ha un tooltip che spiega cosa fa
- Messaggi di conferma dettagliati prima dell'esecuzione
- Notifiche di stato durante l'operazione

#### Conferme Dettagliate
- **Add Master**: Spiega che aggiungerà un master e forzerà elezione leader
- **Add Worker**: Spiega che aumenterà la capacità di processing
- **Reset Cluster**: Avvisa che tutti i dati correnti saranno persi
- **Stop All**: Avvisa che tutti i job correnti saranno interrotti

### 4. Gestione Errori e Feedback

- Notifiche di stato durante l'esecuzione
- Gestione errori con messaggi dettagliati
- Auto-refresh della pagina dopo operazioni di successo
- Timeout appropriati per operazioni lunghe

## Come Testare

### 1. Avvia il Sistema
```bash
# Avvia il cluster di default
.\scripts\docker-manager.ps1 start

# Avvia il dashboard
go run src/main.go
```

### 2. Testa le Funzionalità

#### A. Aggiungi Master
1. Vai su http://localhost:8080
2. Clicca "Add Master" nel pannello di controllo
3. Conferma l'azione
4. Verifica che il nuovo master sia aggiunto al cluster
5. Controlla che sia avvenuta una nuova elezione del leader

#### B. Aggiungi Worker
1. Clicca "Add Worker" nel pannello di controllo
2. Conferma l'azione
3. Verifica che il nuovo worker sia aggiunto
4. Controlla che il worker sia attivo e processi task

#### C. Reset Cluster
1. Clicca "Reset Cluster" nel pannello di controllo
2. Conferma l'azione (ATTENZIONE: perderai tutti i dati!)
3. Verifica che il cluster sia riavviato con configurazione default
4. Controlla che tutti i servizi siano attivi

#### D. Stop All
1. Clicca "Stop All" nel pannello di controllo
2. Conferma l'azione
3. Verifica che tutti i servizi siano fermati

### 3. Verifica Log

Controlla i log del docker-manager.ps1 per verificare che i comandi siano eseguiti correttamente:

```powershell
# Verifica lo stato del cluster
.\scripts\docker-manager.ps1 status

# Controlla i container attivi
docker ps
```

## Note Importanti

1. **Permessi PowerShell**: Assicurati che PowerShell possa eseguire script
2. **Docker Running**: Docker deve essere in esecuzione
3. **Path Script**: Lo script `docker-manager.ps1` deve essere nella cartella `scripts/`
4. **Backup**: Prima di usare "Reset Cluster", fai backup dei dati importanti

## Risoluzione Problemi

### Errore "ExecutionPolicy"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Errore "Script not found"
Verifica che il file `scripts/docker-manager.ps1` esista

### Errore "Docker not running"
Avvia Docker Desktop o Docker daemon

### Errore "Permission denied"
Esegui il dashboard come amministratore o verifica i permessi delle cartelle
