# MapReduce S3 Integration Guide

## 🎯 **Panoramica**

Il progetto MapReduce è stato configurato per utilizzare Amazon S3 come storage distribuito per l'ambiente AWS. Questa guida spiega come utilizzare correttamente l'integrazione S3.

## 🏗️ **Architettura S3**

### **Struttura Bucket S3**
```
s3://mapreduce-storage/
├── data/                    # File di input
│   ├── Words.txt
│   ├── Words2.txt
│   └── Words3.txt
├── intermediate/            # Dati intermedi (map output)
│   ├── job-001/
│   │   ├── map-0/
│   │   ├── map-1/
│   │   └── map-2/
│   └── job-002/
├── output/                  # Risultati finali
│   ├── job-001/
│   │   ├── reduce-0
│   │   ├── reduce-1
│   │   └── reduce-2
│   └── job-002/
├── logs/                    # Log distribuiti
│   ├── master-1/
│   ├── master-2/
│   ├── master-3/
│   ├── worker-1/
│   ├── worker-2/
│   └── worker-3/
└── backups/                 # Backup automatici
    ├── 2024-01-15-10-30-00/
    └── 2024-01-15-11-30-00/
```

## 🔧 **Configurazione**

### **1. Variabili d'Ambiente**

```bash
# File .env
S3_BUCKET_NAME=mapreduce-storage
S3_SYNC_ENABLED=true
S3_SYNC_INTERVAL=60s
AWS_REGION=us-east-1
```

### **2. Docker Compose AWS**

I file `aws/docker/docker-compose.*.yml` sono già configurati con:
- ✅ `S3_SYNC_ENABLED=true`
- ✅ `S3_SYNC_INTERVAL=60s`
- ✅ `MAPREDUCE_INPUT_GLOB=s3://${S3_BUCKET_NAME}/data/*.txt`

## 🚀 **Utilizzo**

### **1. Caricamento File di Input**

#### **Metodo 1: AWS CLI**
```bash
# Carica file di input su S3
aws s3 cp data/Words.txt s3://mapreduce-storage/data/
aws s3 cp data/Words2.txt s3://mapreduce-storage/data/
aws s3 cp data/Words3.txt s3://mapreduce-storage/data/

# Oppure sincronizza tutta la directory
aws s3 sync data/ s3://mapreduce-storage/data/
```

#### **Metodo 2: Dashboard API**
```bash
# Upload tramite API
curl -X POST http://localhost:8080/api/s3/upload-input \
  -H "Content-Type: application/json" \
  -d '{"local_path": "/path/to/input/files"}'
```

### **2. Avvio del Sistema**

#### **Locale (con S3 simulato)**
```bash
# Configura le variabili
export S3_SYNC_ENABLED=true
export S3_BUCKET_NAME=mapreduce-storage
export MAPREDUCE_INPUT_GLOB=s3://mapreduce-storage/data/*.txt

# Avvia il sistema
cd docker/
docker-compose up -d
```

#### **AWS (produzione)**
```bash
# Su ogni istanza master
cd aws/docker/
docker-compose -f docker-compose.master.yml up -d

# Su ogni istanza worker
cd aws/docker/
docker-compose -f docker-compose.worker.yml up -d
```

### **3. Monitoraggio S3**

#### **Dashboard API**
```bash
# Statistiche S3
curl http://localhost:8080/api/s3/stats

# Lista file di input
curl http://localhost:8080/api/s3/input-files

# Lista backup
curl http://localhost:8080/api/s3/backups
```

#### **AWS CLI**
```bash
# Lista file su S3
aws s3 ls s3://mapreduce-storage/ --recursive

# Statistiche bucket
aws s3api list-objects-v2 --bucket mapreduce-storage --query 'Contents[].{Key:Key,Size:Size}'
```

## 🔄 **Flusso di Lavoro**

### **1. Fase di Input**
1. **Upload**: I file di input vengono caricati su `s3://bucket/data/`
2. **Download**: I master scaricano automaticamente i file all'avvio
3. **Elaborazione**: I file vengono processati localmente

### **2. Fase di Map**
1. **Output Intermedio**: I worker scrivono su `s3://bucket/intermediate/job-id/`
2. **Sincronizzazione**: Automatica ogni 60 secondi
3. **Distribuzione**: I file intermedi sono accessibili a tutti i worker

### **3. Fase di Reduce**
1. **Input**: I worker leggono i file intermedi da S3
2. **Elaborazione**: Riduzione locale
3. **Output**: I risultati finali vengono scritti su `s3://bucket/output/job-id/`

### **4. Backup e Logs**
1. **Logs**: Sincronizzati automaticamente su `s3://bucket/logs/`
2. **Backup**: Backup completi su `s3://bucket/backups/`
3. **Retention**: Gestione automatica della retention

## 🧪 **Test e Validazione**

### **Script di Test**
```bash
# Esegui tutti i test
./scripts/test-s3-integration.sh

# Test specifici
./scripts/test-s3-integration.sh upload    # Test upload
./scripts/test-s3-integration.sh verify    # Test verifica
./scripts/test-s3-integration.sh dashboard # Test API
./scripts/test-s3-integration.sh sync      # Test sincronizzazione
```

### **Test Manuali**
```bash
# 1. Carica file di test
aws s3 cp test-file.txt s3://mapreduce-storage/data/

# 2. Verifica che il master li rilevi
docker logs mapreduce-master-1 | grep "Downloaded.*input files"

# 3. Controlla la sincronizzazione
aws s3 ls s3://mapreduce-storage/output/ --recursive
```

## 🐛 **Troubleshooting**

### **Problemi Comuni**

#### **1. File di Input Non Trovati**
```bash
# Verifica che i file siano su S3
aws s3 ls s3://mapreduce-storage/data/

# Controlla i log del master
docker logs mapreduce-master-1 | grep -i "input"
```

#### **2. Errori di Autenticazione AWS**
```bash
# Verifica le credenziali
aws sts get-caller-identity

# Controlla le variabili d'ambiente
echo $AWS_REGION
echo $S3_BUCKET_NAME
```

#### **3. Sincronizzazione Non Funzionante**
```bash
# Verifica che S3_SYNC_ENABLED=true
docker exec mapreduce-master-1 env | grep S3_SYNC

# Controlla i log di sincronizzazione
docker logs mapreduce-master-1 | grep -i "sync"
```

### **Log di Debug**
```bash
# Abilita log dettagliati
export LOG_LEVEL=debug

# Controlla i log S3
docker logs mapreduce-master-1 | grep -i "s3"
```

## 📊 **Monitoraggio e Metriche**

### **CloudWatch Metrics**
- **S3 Requests**: Numero di richieste S3
- **S3 Data Transfer**: Dati trasferiti
- **S3 Errors**: Errori di accesso

### **Dashboard Metrics**
- **File Count**: Numero di file per categoria
- **Storage Usage**: Utilizzo dello storage
- **Sync Status**: Stato della sincronizzazione

## 🔒 **Sicurezza**

### **IAM Permissions**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::mapreduce-storage",
                "arn:aws:s3:::mapreduce-storage/*"
            ]
        }
    ]
}
```

### **Encryption**
- **Server-Side Encryption**: Abilitata di default
- **KMS**: Opzionale per crittografia avanzata
- **Client-Side**: Per dati sensibili

## 📚 **Risorse Aggiuntive**

- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS CLI S3 Commands](https://docs.aws.amazon.com/cli/latest/reference/s3/)
- [Docker Compose Environment Variables](https://docs.docker.com/compose/environment-variables/)

## ✅ **Checklist di Deployment**

### **Pre-Deployment**
- [ ] Bucket S3 creato e configurato
- [ ] Credenziali AWS configurate
- [ ] File di input caricati su S3
- [ ] Variabili d'ambiente impostate

### **Post-Deployment**
- [ ] Master scarica correttamente i file da S3
- [ ] Sincronizzazione funzionante
- [ ] Dashboard mostra statistiche S3
- [ ] Backup automatici attivi

### **Monitoring**
- [ ] Logs S3 visibili nel dashboard
- [ ] Metriche CloudWatch attive
- [ ] Alerting configurato per errori S3
