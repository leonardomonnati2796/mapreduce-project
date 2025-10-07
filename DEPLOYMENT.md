# MapReduce Project - Deployment Guide

## 🏗️ Architettura del Progetto

### **Locale (Sviluppo)**
- **File**: `docker/docker-compose.yml`
- **Descrizione**: Tutti i servizi su un singolo host per sviluppo e test
- **Servizi**: master0, master1, master2, worker1, worker2, worker3, dashboard

### **AWS (Produzione Distribuita)**
- **File Master**: `aws/docker/docker-compose.master.yml`
- **File Worker**: `aws/docker/docker-compose.worker.yml`
- **File Production**: `aws/docker/docker-compose.production.yml`
- **Descrizione**: Ogni master e worker su istanza EC2 separata

## 🚀 Utilizzo

### **1. Ambiente Locale**

```bash
# Copia le variabili d'ambiente
cp env.example .env

# Personalizza le variabili in .env se necessario
# Poi avvia l'ambiente locale
cd docker/
docker-compose up -d
```

**Servizi disponibili:**
- Dashboard: http://localhost:8080
- Master0: http://localhost:1234 (Raft), http://localhost:8000 (RPC)
- Master1: http://localhost:1235 (Raft), http://localhost:8001 (RPC)
- Master2: http://localhost:1236 (Raft), http://localhost:8002 (RPC)
- Worker1: http://localhost:8081
- Worker2: http://localhost:8082
- Worker3: http://localhost:8083

### **2. Ambiente AWS**

#### **Configurazione Terraform**
```bash
cd aws/terraform/
terraform init
terraform plan
terraform apply
```

#### **Deploy su Istanze Master**
```bash
# Su ogni istanza master
cd aws/docker/
docker-compose -f docker-compose.master.yml up -d
```

#### **Deploy su Istanze Worker**
```bash
# Su ogni istanza worker
cd aws/docker/
docker-compose -f docker-compose.worker.yml up -d
```

## 📋 Variabili d'Ambiente

### **File .env Unificato**
Il file `env.example` contiene tutte le variabili necessarie per:
- ✅ Configurazione AWS
- ✅ Porte e networking
- ✅ Service discovery
- ✅ Monitoring e logging
- ✅ Performance tuning

### **Variabili Principali**

| Variabile | Locale | AWS | Descrizione |
|-----------|--------|-----|-------------|
| `S3_BUCKET_NAME` | mapreduce-storage | mapreduce-storage | Bucket S3 per i dati |
| `MASTER_PORT` | 8082 | 8082 | Porta del master |
| `WORKER_PORT` | 8081 | 8081 | Porta del worker |
| `DASHBOARD_PORT` | 8080 | 8080 | Porta del dashboard |
| `RAFT_ADDRESSES` | master0:1234,master1:1234,master2:1234 | Dinamico | Indirizzi Raft |
| `RPC_ADDRESSES` | master0:8000,master1:8001,master2:8002 | Dinamico | Indirizzi RPC |

## 🔧 Service Discovery

### **Locale**
Le variabili sono hardcoded nel `docker-compose.yml`:
```yaml
RAFT_ADDRESSES: "master0:1234,master1:1234,master2:1234"
RPC_ADDRESSES: "master0:8000,master1:8001,master2:8002"
```

### **AWS**
Le variabili sono popolate dinamicamente dal `user_data.sh`:
```bash
# Service discovery dinamico
MASTER_IPS=$(aws ec2 describe-instances ...)
WORKER_IPS=$(aws ec2 describe-instances ...)
RAFT_ADDRESSES=$(build_raft_addresses $MASTER_IPS)
RPC_ADDRESSES=$(build_rpc_addresses $MASTER_IPS)
```

## 🏷️ Struttura Istanze AWS

```
AWS Environment:
├── EC2 Master-1 (istanza separata)
│   └── docker-compose.master.yml
├── EC2 Master-2 (istanza separata)  
│   └── docker-compose.master.yml
├── EC2 Master-3 (istanza separata)
│   └── docker-compose.master.yml
├── EC2 Worker-1 (istanza separata)
│   └── docker-compose.worker.yml
├── EC2 Worker-2 (istanza separata)
│   └── docker-compose.worker.yml
└── EC2 Worker-3 (istanza separata)
    └── docker-compose.worker.yml
```

## ✅ Checklist Deployment

### **Locale**
- [ ] Copiare `env.example` in `.env`
- [ ] Personalizzare variabili se necessario
- [ ] Eseguire `docker-compose up -d`
- [ ] Verificare dashboard su http://localhost:8080

### **AWS**
- [ ] Configurare credenziali AWS
- [ ] Eseguire `terraform apply`
- [ ] Verificare che le 6 istanze EC2 siano create
- [ ] Verificare che i container siano in esecuzione su ogni istanza
- [ ] Testare la comunicazione tra master e worker

## 🐛 Troubleshooting

### **Problemi Comuni**

1. **Service Discovery Fallito**
   - Verificare che le variabili `RAFT_ADDRESSES`, `RPC_ADDRESSES` siano corrette
   - Controllare la connettività di rete tra le istanze

2. **Container Non Si Avvia**
   - Verificare i log: `docker-compose logs <service-name>`
   - Controllare le variabili d'ambiente

3. **Problemi AWS**
   - Verificare le credenziali AWS
   - Controllare i security groups e VPC
   - Verificare che le istanze abbiano accesso a S3

## 📚 Risorse Aggiuntive

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [S3 Integration Guide](S3-INTEGRATION.md) - Guida completa per l'utilizzo di S3
- [S3 Test Script](scripts/test-s3-integration.sh) - Script per testare l'integrazione S3
