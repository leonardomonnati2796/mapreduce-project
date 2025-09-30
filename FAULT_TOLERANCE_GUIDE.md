# Guida Rapida ai Test di Fault Tolerance

## Comandi Makefile per Testare Tutti i Fallimenti

### 🚀 **Test Rapidi (Integrati nel docker-manager.ps1)**

```bash
# Test completo di fault tolerance
make fault-test

# Test specifici per tipo di fallimento
make leader-test      # Test elezione leader e recovery stato
make worker-test      # Test fallimenti worker e heartbeat  
make mapper-test      # Test fallimenti mapper e recovery
make reduce-test      # Test fallimenti reduce e recovery
make recovery-test    # Test recovery completo del sistema
```

### 🔬 **Test Avanzati (Script dedicato)**

```bash
# Test completi avanzati
make fault-advanced           # Tutti i test di fault tolerance

# Test specifici avanzati
make fault-leader-advanced    # Test elezione leader avanzato
make fault-worker-advanced    # Test worker avanzato con heartbeat
make fault-mapper-advanced    # Test mapper avanzato con recovery
make fault-reduce-advanced    # Test reduce avanzato con recovery
make fault-network-advanced   # Test fallimenti di rete
make fault-storage-advanced   # Test corruzione dati e recovery
make fault-stress-advanced    # Test stress con fallimenti multipli
```

### 📊 **Monitoraggio e Diagnostica**

```bash
# Controllo salute del cluster
make health

# Visualizzazione stato
make status

# Log in tempo reale
make logs

# Dashboard web
make dashboard
```

## 🎯 **Scenari di Test Coperti**

### 1. **Elezione Leader e Recovery Stato**
- ✅ Fallimento del master leader
- ✅ Elezione automatica di nuovo leader
- ✅ Recovery completo dello stato
- ✅ Verifica consistenza dati

### 2. **Fallimenti Worker e Heartbeat**
- ✅ Rilevamento worker morti (30s timeout)
- ✅ Reset automatico task assegnati
- ✅ Riassegnazione a worker attivi
- ✅ Recovery heartbeat

### 3. **Fallimenti Mapper**
- ✅ Fallimento prima del completamento
- ✅ Fallimento dopo completamento
- ✅ Verifica validità file intermedi
- ✅ Recovery automatico e riassegnazione

### 4. **Fallimenti Reduce**
- ✅ Fallimento prima di ricevere dati
- ✅ Fallimento durante computazione
- ✅ Verifica validità file di output
- ✅ Recovery automatico e riassegnazione

### 5. **Fallimenti di Rete**
- ✅ Isolamento master dal cluster
- ✅ Elezione leader con minoranza
- ✅ Recovery connettività
- ✅ Sincronizzazione stato

### 6. **Corruzione Dati**
- ✅ Corruzione file intermedi
- ✅ Corruzione file di output
- ✅ Rilevamento automatico
- ✅ Recovery e rigenerazione

### 7. **Stress Test**
- ✅ Fallimenti multipli simultanei
- ✅ Test con minoranza di nodi
- ✅ Recovery completo del sistema
- ✅ Verifica operatività continua

## 🔧 **Comandi di Gestione**

```bash
# Avvio cluster
make start

# Fermata cluster  
make stop

# Riavvio cluster
make restart

# Pulizia completa
make clean

# Backup dati
make backup

# Copia output
make copy-output
```

## 📈 **Interpretazione Risultati**

### ✅ **Test Superati**
- Sistema fault tolerance operativo
- Recovery automatico funzionante
- Consistenza dati garantita

### ❌ **Test Falliti**
- Verificare configurazione Docker
- Controllare connettività di rete
- Verificare risorse sistema
- Controllare log per dettagli

## 🚨 **Troubleshooting**

### Problemi Comuni:
1. **Docker non in esecuzione**: Avviare Docker Desktop
2. **Porte occupate**: Verificare che 8000-8002, 8080, 9090 siano libere
3. **Risorse insufficienti**: Aumentare memoria Docker
4. **Rete isolata**: Verificare configurazione Docker network

### Log Utili:
```bash
# Log completi
make logs

# Log specifici container
docker-compose -f docker/docker-compose.yml logs master0
docker-compose -f docker/docker-compose.yml logs worker1
```

## 🎯 **Workflow Consigliato**

1. **Avvio**: `make start`
2. **Test Base**: `make fault-test`
3. **Test Avanzati**: `make fault-advanced`
4. **Monitoraggio**: `make dashboard`
5. **Cleanup**: `make clean`

---

**Nota**: Tutti i test sono progettati per essere non-distruttivi e ripristinano automaticamente lo stato del cluster.
