# Guida ai Reducer Dinamici

## Panoramica

Il sistema MapReduce è stato modificato per utilizzare dinamicamente il numero di reducer uguale al numero di worker attivi. Questo ottimizza l'utilizzo delle risorse e migliora le prestazioni.

## Come Funziona

### 1. Calcolo Dinamico dei Reducer

Il sistema ora calcola automaticamente il numero di reducer in base al numero di worker:

```go
// Prima (hardcoded)
nReduce = 10

// Ora (dinamico)
nReduce := calculateDynamicReducerCount()
```

### 2. Priorità di Configurazione

1. **Variabile d'ambiente `WORKER_COUNT`** (priorità massima)
2. **Query ai master esistenti** per conteggio worker attivi
3. **Stima basata sui master** (1 worker per master)
4. **Default: 3 worker** (configurazione tipica docker-compose)

## Configurazione

### Docker Compose Standard

```yaml
# docker/docker-compose.yml
x-common-vars: &common-vars
  WORKER_COUNT: "3"  # 3 worker = 3 reducer
```

### Docker Compose AWS

```yaml
# docker/docker-compose.aws.yml
x-common-vars: &common-vars
  WORKER_COUNT: "${WORKER_COUNT:-3}"  # Override con variabile d'ambiente
```

### Variabile d'Ambiente

```bash
# Imposta il numero di worker (e quindi di reducer)
export WORKER_COUNT=5
./mapreduce master 0 "file1.txt,file2.txt"
```

## Esempi di Utilizzo

### Esempio 1: Configurazione Standard
```bash
# Usa 3 worker (default)
docker-compose up
# Risultato: 3 worker = 3 reducer
```

### Esempio 2: Configurazione Personalizzata
```bash
# Usa 5 worker
WORKER_COUNT=5 docker-compose up
# Risultato: 5 worker = 5 reducer
```

### Esempio 3: Configurazione AWS
```bash
# Deploy su AWS con 4 worker
WORKER_COUNT=4 docker-compose -f docker/docker-compose.aws.yml up
# Risultato: 4 worker = 4 reducer
```

## Vantaggi

### 1. Ottimizzazione delle Risorse
- **Prima**: 10 reducer fissi indipendentemente dal numero di worker
- **Ora**: Numero di reducer = numero di worker (utilizzo ottimale)

### 2. Scalabilità Dinamica
- Il sistema si adatta automaticamente quando si aggiungono/rimuovono worker
- Non è necessario riconfigurare manualmente i reducer

### 3. Compatibilità
- Mantiene la compatibilità con le configurazioni esistenti
- Fallback intelligente se la rilevazione automatica fallisce

## Monitoraggio

### Log del Sistema
Il sistema fornisce log dettagliati per il debug:

```
Numero di worker da variabile d'ambiente WORKER_COUNT: 5
Numero di worker rilevato dal master master0:8000: 3
Numero di worker stimato da configurazione master: 3
Usando numero di worker di default: 3
```

### Dashboard
Il dashboard web mostra:
- Numero di worker attivi
- Numero di reducer configurati
- Corrispondenza tra worker e reducer

## Troubleshooting

### Problema: Numero di Reducer Non Corretto
**Soluzione**: Verifica la variabile `WORKER_COUNT`
```bash
echo $WORKER_COUNT
```

### Problema: Worker Non Rilevati
**Soluzione**: Il sistema userà la stima basata sui master
- 3 master = 3 worker stimati
- 4 master = 4 worker stimati

### Problema: Fallback al Default
**Soluzione**: Il sistema userà 3 worker come default
- Questo è appropriato per la maggior parte dei deployment

## Configurazione Avanzata

### Per Deployment Personalizzati
```bash
# Crea un file .env
echo "WORKER_COUNT=6" > .env
docker-compose up
```

### Per Scaling Automatico
```bash
# Scala i worker e i reducer automaticamente
docker-compose up --scale worker=5
# Il sistema rileverà automaticamente 5 worker e userà 5 reducer
```

## Conclusioni

Il sistema di reducer dinamici:
- ✅ Ottimizza l'utilizzo delle risorse
- ✅ Si adatta automaticamente al numero di worker
- ✅ Mantiene la compatibilità con le configurazioni esistenti
- ✅ Fornisce fallback intelligenti
- ✅ Supporta configurazioni flessibili
