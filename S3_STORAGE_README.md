# 🗄️ S3 Storage per MapReduce su AWS

## 📋 Panoramica

Questo documento descrive come configurare e utilizzare Amazon S3 come servizio di storage per il sistema MapReduce deployato su AWS. Il sistema include funzionalità avanzate di sincronizzazione, backup automatico e gestione dei dati.

## 🏗️ Architettura S3

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS S3 Storage                          │
├─────────────────────────────────────────────────────────────┤
│  📁 mapreduce-storage/                                     │
│  ├── 📁 output/          # Output dei job MapReduce        │
│  ├── 📁 intermediate/    # File intermedi dei task        │
│  ├── 📁 logs/            # Log del sistema                 │
│  ├── 📁 backups/         # Backup automatici              │
│  │   └── 📁 2024-01-15-10-30-00/                          │
│  └── 📁 jobs/            # Dati specifici per job         │
│      ├── 📁 job-001/input/                                │
│      └── 📁 job-001/output/                               │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Configurazione Rapida

### 1. Prerequisiti

- AWS CLI installato e configurato
- Credenziali AWS configurate
- Bucket S3 creato
- Permessi IAM appropriati

### 2. Configurazione Automatica

**Windows PowerShell:**
```powershell
# Configura S3 con bucket personalizzati
.\scripts\configure-s3-aws.ps1 -BucketName "my-mapreduce-storage" -Region "eu-west-1" -CreateBuckets -SetupIAM -TestConnection

# Configurazione di default
.\scripts\configure-s3-aws.ps1 -CreateBuckets -SetupIAM -TestConnection
```

**Linux/macOS:**
```bash
# Configura S3 con bucket personalizzati
./scripts/configure-s3-aws.sh --bucket-name "my-mapreduce-storage" --region "eu-west-1" --create-buckets --setup-iam --test-connection

# Configurazione di default
./scripts/configure-s3-aws.sh --create-buckets --setup-iam --test-connection
```

### 3. Configurazione Manuale

**Crea bucket S3:**
```bash
# Bucket principale
aws s3 mb s3://mapreduce-storage --region us-east-1

# Bucket backup
aws s3 mb s3://mapreduce-backup --region us-east-1

# Abilita versioning
aws s3api put-bucket-versioning --bucket mapreduce-storage --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket mapreduce-backup --versioning-configuration Status=Enabled
```

**Configura variabili d'ambiente:**
```bash
export AWS_S3_BUCKET=mapreduce-storage
export AWS_REGION=us-east-1
export S3_SYNC_ENABLED=true
export S3_SYNC_INTERVAL=60s
```

## 🔧 Funzionalità S3

### 1. Sincronizzazione Automatica

Il sistema include sincronizzazione automatica per:

- **Output Files**: Risultati dei job MapReduce
- **Intermediate Files**: File intermedi dei task
- **Log Files**: Log del sistema
- **Backup Files**: Backup automatici

### 2. Backup Automatico

```bash
# Backup manuale
curl -X POST http://localhost:8080/api/backup

# Lista backup disponibili
curl http://localhost:8080/api/backups

# Ripristino da backup
curl -X POST http://localhost:8080/api/restore \
  -d "backup_timestamp=2024-01-15-10-30-00"
```

### 3. Gestione Job

```bash
# Upload output job
curl -X POST http://localhost:8080/api/s3/upload-job \
  -d "job_id=job-001&local_path=/tmp/output"

# Download input job
curl -X POST http://localhost:8080/api/s3/download-job \
  -d "job_id=job-001&local_path=/tmp/input"
```

## 📊 Monitoraggio S3

### 1. Dashboard S3

Il dashboard include sezioni dedicate a S3:

- **Storage Usage**: Utilizzo spazio S3
- **Sync Status**: Stato sincronizzazione
- **Backup History**: Cronologia backup
- **File Statistics**: Statistiche file

### 2. Metriche CloudWatch

```bash
# Abilita metriche S3
aws s3api put-bucket-metrics-configuration \
    --bucket mapreduce-storage \
    --id EntireBucket \
    --metrics-configuration Id=EntireBucket,Status=Enabled
```

### 3. Alerting

Configura alert per:

- **Storage Usage > 80%**
- **Sync Failures**
- **Backup Failures**
- **Access Denied Errors**

## 🔒 Sicurezza S3

### 1. Encryption

```bash
# Abilita encryption server-side
aws s3api put-bucket-encryption \
    --bucket mapreduce-storage \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
```

### 2. Access Control

```bash
# Policy bucket per accesso limitato
aws s3api put-bucket-policy \
    --bucket mapreduce-storage \
    --policy '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": "arn:aws:s3:::mapreduce-storage/*",
            "Condition": {
                "StringNotEquals": {
                    "aws:SourceVpce": "vpce-xxxxxxxxx"
                }
            }
        }]
    }'
```

### 3. Lifecycle Policies

```bash
# Configura lifecycle per cleanup automatico
aws s3api put-bucket-lifecycle-configuration \
    --bucket mapreduce-storage \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "DeleteOldBackups",
            "Status": "Enabled",
            "Filter": {"Prefix": "backups/"},
            "Expiration": {"Days": 30}
        }]
    }'
```

## 🚀 Comandi Utili

### 1. Gestione File S3

```bash
# Lista file in S3
aws s3 ls s3://mapreduce-storage/ --recursive

# Sincronizza directory locale con S3
aws s3 sync ./data/ s3://mapreduce-storage/data/

# Download file da S3
aws s3 cp s3://mapreduce-storage/output/result.txt ./result.txt
```

### 2. Backup e Restore

```bash
# Backup completo
aws s3 sync /tmp/mapreduce/ s3://mapreduce-backup/$(date +%Y-%m-%d)/

# Restore da backup
aws s3 sync s3://mapreduce-backup/2024-01-15/ /tmp/mapreduce/
```

### 3. Monitoraggio

```bash
# Controlla utilizzo storage
aws s3api list-objects-v2 \
    --bucket mapreduce-storage \
    --query 'sum(Contents[].Size)' \
    --output text

# Controlla sync status
curl http://localhost:8080/api/s3/status
```

## 🧪 Test S3

### 1. Test Configurazione

```bash
# Test configurazione S3
go run s3-test.go

# Test demo S3
go run s3-demo.go
```

### 2. Test Connessione

```bash
# Test connessione S3
aws s3 ls s3://mapreduce-storage/

# Test upload/download
echo "Test S3" > test.txt
aws s3 cp test.txt s3://mapreduce-storage/test/
aws s3 cp s3://mapreduce-storage/test/test.txt downloaded.txt
rm test.txt downloaded.txt
```

### 3. Test Integrazione

```bash
# Test integrazione con MapReduce
curl http://localhost:8080/api/s3/status
curl http://localhost:8080/api/s3/stats
curl http://localhost:8080/api/s3/backups
```

## 🔧 Troubleshooting

### 1. Problemi Comuni

**Errore: Access Denied**
```bash
# Verifica permessi IAM
aws sts get-caller-identity
aws s3api get-bucket-policy --bucket mapreduce-storage
```

**Errore: Bucket non esiste**
```bash
# Verifica bucket esistente
aws s3 ls s3://mapreduce-storage
```

**Errore: Sync fallisce**
```bash
# Controlla log
tail -f /var/log/mapreduce/s3-sync.log

# Riavvia servizio S3
systemctl restart mapreduce-s3-sync
```

### 2. Debug S3

```bash
# Abilita debug AWS SDK
export AWS_SDK_LOAD_CONFIG=true
export AWS_PROFILE=mapreduce

# Test connessione S3
aws s3 ls s3://mapreduce-storage/
```

## 📈 Ottimizzazione Performance

### 1. Configurazione S3

```bash
# Abilita transfer acceleration
aws s3api put-bucket-accelerate-configuration \
    --bucket mapreduce-storage \
    --accelerate-configuration Status=Enabled
```

### 2. Parallel Upload

Il sistema usa upload paralleli per file grandi:

```go
// Configurazione uploader
uploader := s3manager.NewUploader(sess, func(u *s3manager.Uploader) {
    u.PartSize = 64 * 1024 * 1024 // 64MB
    u.Concurrency = 5
})
```

### 3. Compressione

```bash
# Abilita compressione S3
aws s3api put-bucket-encryption \
    --bucket mapreduce-storage \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
```

## 🎯 Best Practices

### 1. Organizzazione File

- **Prefix Structure**: Usa prefissi logici (`output/`, `intermediate/`, `logs/`)
- **Naming Convention**: Usa timestamp e job ID nei nomi file
- **Directory Structure**: Mantieni struttura coerente

### 2. Backup Strategy

- **Incremental Backups**: Solo file modificati
- **Retention Policy**: Mantieni backup per 30 giorni
- **Cross-Region**: Replica backup in region diverse

### 3. Monitoring

- **CloudWatch Metrics**: Monitora utilizzo e performance
- **Cost Optimization**: Usa classi di storage appropriate
- **Access Logs**: Abilita logging accessi S3

## 🚀 Deploy Production

### 1. Terraform Configuration

```hcl
# aws/terraform/s3-storage.tf
resource "aws_s3_bucket" "mapreduce_storage" {
  bucket = "mapreduce-storage"
  
  versioning {
    enabled = true
  }
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  
  lifecycle_rule {
    id      = "DeleteOldBackups"
    prefix  = "backups/"
    enabled = true
    
    expiration {
      days = 30
    }
  }
}
```

### 2. Docker Configuration

```yaml
# docker-compose.aws.yml
version: '3.8'
services:
  mapreduce:
    environment:
      - S3_SYNC_ENABLED=true
      - AWS_S3_BUCKET=mapreduce-storage
      - AWS_REGION=us-east-1
    volumes:
      - /tmp/mapreduce:/tmp/mapreduce
```

## ✅ Verifica Configurazione

### 1. Test Connessione

```bash
# Test configurazione S3
go run s3-test.go

# Verifica sync automatico
curl http://localhost:8080/api/s3/status

# Test backup manuale
curl -X POST http://localhost:8080/api/backup
```

### 2. Verifica Dashboard

Accedi al dashboard web e controlla:

- **S3 Status**: Stato connessione S3
- **Storage Usage**: Utilizzo spazio
- **Sync Status**: Stato sincronizzazione
- **Backup History**: Cronologia backup

## 🎉 Risultato Finale

Con questa configurazione avrai:

✅ **Storage S3 Integrato**: Backup automatico e sincronizzazione  
✅ **Fault Tolerance**: Recovery da S3 in caso di fallimenti  
✅ **Monitoring Completo**: Dashboard con metriche S3  
✅ **Sicurezza**: Encryption e access control  
✅ **Performance**: Upload paralleli e ottimizzazioni  
✅ **Backup Strategy**: Backup automatici con retention  

Il tuo sistema MapReduce ora usa S3 come storage principale con tutte le funzionalità avanzate implementate!
