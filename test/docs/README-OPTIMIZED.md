# Test Suite Ottimizzata MapReduce

## 🚀 Panoramica

Questa è la versione ottimizzata della test suite per il sistema MapReduce, completamente riorganizzata per massima efficienza e mantenibilità.

## 📁 Struttura Ottimizzata

```
test/
├── 🧪 test-suites/           # Test eseguibili
│   ├── test-common.ps1              # Funzioni comuni
│   ├── test-core-functions.ps1      # Test core MapReduce
│   ├── test-raft-consensus.ps1      # Test consenso Raft
│   ├── test-integration.ps1         # Test integrazione
│   ├── test-dashboard-optimized.ps1     # Dashboard (14 test)
│   ├── test-websocket-optimized.ps1     # WebSocket (9 test)
│   └── test-cluster-optimized.ps1        # Cluster (12 test)
│
├── ⚙️ config/                # Configurazioni
│   ├── test-config.json             # Config base
│   └── test-config-optimized.json  # Config avanzata
│
├── 📚 docs/                 # Documentazione
│   ├── README-OPTIMIZED.md          # Questa guida
│   ├── DASHBOARD_OPTIMIZATION_SUMMARY.md
│   ├── FINAL_STRUCTURE.md
│   ├── test-dashboard-cluster-management.md
│   └── test-websocket-realtime.md
│
├── 📊 reports/              # Report generati
│   └── test-report-*.json
│
└── 🚀 run-tests-optimized.ps1      # Test runner principale
```

## 🎯 Test Disponibili

### **Core Functions** (`test-core-functions.ps1`)
- Test funzioni Map e Reduce
- Test algoritmi di hashing
- Test operazioni su file
- Test gestione errori

### **Raft Consensus** (`test-raft-consensus.ps1`)
- Test elezione leader
- Test tolleranza ai guasti
- Test consistenza dati
- Test recovery automatico

### **Integration** (`test-integration.ps1`)
- Test pipeline completa
- Test S3 integration
- Test job submission
- Test output generation

### **Dashboard** (`test-dashboard-optimized.ps1`)
- Test API REST (14 test)
- Test interfaccia web
- Test real-time updates
- Test performance e sicurezza

### **WebSocket** (`test-websocket-optimized.ps1`)
- Test connessioni real-time (9 test)
- Test data consistency
- Test performance under load
- Test long running stability

### **Cluster** (`test-cluster-optimized.ps1`)
- Test gestione dinamica (12 test)
- Test scaling automatico
- Test health monitoring
- Test fault tolerance

## 🚀 Utilizzo

### **Esecuzione Completa**
```powershell
# Tutti i test con configurazione ottimale
.\run-tests-optimized.ps1

# Test specifici
.\run-tests-optimized.ps1 -Categories @("core", "dashboard")

# Esecuzione parallela
.\run-tests-optimized.ps1 -Parallel -MaxConcurrentTests 3

# Ambiente specifico
.\run-tests-optimized.ps1 -Environment "docker"
```

### **Test Singoli**
```powershell
# Test dashboard
.\test-suites\test-dashboard-optimized.ps1

# Test WebSocket
.\test-suites\test-websocket-optimized.ps1

# Test cluster
.\test-suites\test-cluster-optimized.ps1
```

### **Configurazione Avanzata**
```powershell
# Con parametri personalizzati
.\run-tests-optimized.ps1 -Environment "aws" -Timeout 60 -Verbose -GenerateReport
```

## ⚙️ Configurazione

### **File di Configurazione**
- `config/test-config.json` - Configurazione base
- `config/test-config-optimized.json` - Configurazione avanzata

### **Ambienti Supportati**
- **local**: http://localhost:8080
- **docker**: http://localhost:8080 (con timeout esteso)
- **aws**: http://ec2-instance:8080

### **Categorie Test**
- **core**: Test funzioni core
- **raft**: Test consenso Raft
- **integration**: Test integrazione
- **dashboard**: Test dashboard web
- **websocket**: Test WebSocket
- **cluster**: Test gestione cluster

## 📊 Report e Metriche

### **Formati Output**
- **Console**: Output colorato in tempo reale
- **JSON**: Report strutturato per CI/CD
- **HTML**: Report visuale (futuro)

### **Metriche Incluse**
- Durata totale esecuzione
- Tasso di successo per categoria
- Performance metrics
- Coverage statistics
- Error details

### **Esempio Report**
```json
{
  "StartTime": "2024-12-01T14:30:00Z",
  "TotalDuration": 45.2,
  "TotalTests": 35,
  "PassedTests": 34,
  "FailedTests": 1,
  "SuccessRate": 97.1,
  "Categories": {
    "core": { "Passed": 5, "Total": 5, "Duration": 12.3 },
    "dashboard": { "Passed": 13, "Total": 14, "Duration": 18.7 }
  }
}
```

## 🔧 Parametri Avanzati

### **Esecuzione**
- `-Environment`: Ambiente di test (local/docker/aws)
- `-Categories`: Categorie da eseguire
- `-Parallel`: Esecuzione parallela
- `-MaxConcurrentTests`: Numero max test concorrenti
- `-Timeout`: Timeout globale in secondi

### **Output**
- `-Verbose`: Output dettagliato
- `-GenerateReport`: Genera report JSON
- `-OutputFormat`: Formato output (console/json/html)

### **Performance**
- `-MaxResponseTime`: Tempo max risposta (default: 2.0s)
- `-MaxMemoryUsage`: Uso max memoria (default: 100MB)
- `-ConcurrentUsers`: Utenti concorrenti simulati

## 🎯 Benefici Ottimizzazione

### **Organizzazione**
- ✅ Struttura modulare e scalabile
- ✅ Separazione logica dei componenti
- ✅ Configurazione centralizzata
- ✅ Documentazione organizzata

### **Performance**
- ✅ Esecuzione parallela intelligente
- ✅ Timeout ottimizzati per categoria
- ✅ Retry logic automatico
- ✅ Gestione memoria migliorata

### **Mantenibilità**
- ✅ Codice centralizzato e riutilizzabile
- ✅ Configurazione flessibile
- ✅ Report dettagliati e strutturati
- ✅ Integrazione CI/CD ready

### **Coverage**
- ✅ 35 test completi
- ✅ 6 categorie specializzate
- ✅ Test real-time e performance
- ✅ Test sicurezza e fault tolerance

## 🚀 Prossimi Passi

1. **Esegui test completi**: `.\run-tests-optimized.ps1`
2. **Verifica report**: Controlla cartella `reports/`
3. **Integra CI/CD**: Usa report JSON per automazione
4. **Monitora performance**: Analizza metriche dettagliate

## 📞 Supporto

Per problemi o domande:
- Controlla log dettagliati con `-Verbose`
- Verifica configurazione in `config/`
- Consulta documentazione in `docs/`
- Analizza report in `reports/`

---

**Test Suite MapReduce v2.0.0** - Completamente ottimizzata e pronta per produzione! 🎉
