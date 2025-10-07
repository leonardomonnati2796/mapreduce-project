# 🚀 MapReduce AWS Deployment Guide

Guida completa per il deployment del progetto MapReduce su AWS con istanze separate per master e worker.

## 📋 **Panoramica**

Questo deployment crea:
- ✅ **3 istanze Master** (t3.medium)
- ✅ **3 istanze Worker** (t3.small)  
- ✅ **Load Balancer** per distribuire il traffico
- ✅ **S3 Bucket** per storage distribuito
- ✅ **Service Discovery** automatico tra istanze
- ✅ **CloudWatch** per monitoring

## 🏗️ **Architettura**

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Master-1  │  │   Master-2  │  │   Master-3  │        │
│  │  (t3.medium)│  │  (t3.medium)│  │  (t3.medium)│        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Worker-1  │  │   Worker-2  │  │   Worker-3  │        │
│  │  (t3.small) │  │  (t3.small) │  │  (t3.small) │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │                │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Application Load Balancer                  ││
│  └─────────────────────────────────────────────────────────┘│
│         │                                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    S3 Bucket                           ││
│  │              (Storage + Input Data)                     ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## 🔧 **Configurazione**

### **1. Prerequisiti**

```bash
# Installa AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Installa Terraform
# Segui le istruzioni su: https://developer.hashicorp.com/terraform/downloads

# Configura credenziali AWS
aws configure
```

### **2. Setup Iniziale**

```bash
# 1. Clona il repository
git clone <your-repo-url>
cd mapreduce-project

# 2. Configura Terraform
cd aws/terraform/
cp terraform.tfvars.example terraform.tfvars

# 3. Personalizza terraform.tfvars
nano terraform.tfvars
```

**Contenuto `terraform.tfvars`:**
```hcl
# Configurazione base
project_name = "mapreduce"
aws_region = "us-east-1"

# Repository Git
repo_url = "https://github.com/your-username/mapreduce-project.git"
repo_branch = "main"

# Istanze
master_count = 3
worker_count = 3
master_instance_type = "t3.medium"
worker_instance_type = "t3.small"

# SSH Key (IMPORTANTE: sostituisci con la tua chiave pubblica)
key_pair_name = "mapreduce-key"
public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-email@example.com"

# S3
s3_bucket_name = "mapreduce-storage"
s3_backup_bucket = "mapreduce-backup"
```

### **3. Crea SSH Key Pair**

```bash
# Crea key pair AWS
aws ec2 create-key-pair --key-name mapreduce-key --query 'KeyMaterial' --output text > ~/.ssh/mapreduce-key.pem
chmod 600 ~/.ssh/mapreduce-key.pem

# Ottieni chiave pubblica per terraform.tfvars
ssh-keygen -y -f ~/.ssh/mapreduce-key.pem
```

## 🚀 **Deployment**

### **Metodo 1: Script Automatico**

```bash
# Esegui script di setup completo
chmod +x scripts/setup-aws-deployment.sh
./scripts/setup-aws-deployment.sh
```

### **Metodo 2: Manuale**

```bash
# 1. Inizializza Terraform
cd aws/terraform/
terraform init

# 2. Valida configurazione
terraform validate

# 3. Pianifica deployment
terraform plan

# 4. Applica configurazione
terraform apply
```

## ✅ **Verifica Deployment**

### **1. Controlla Istanze**

```bash
# Conta le istanze per tipo
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=mapreduce" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Type:Tags[?Key==`Type`].Value|[0]}' \
  --output table

# Risultato atteso:
# | Name                | Type   |
# |---------------------|--------|
# | mapreduce-master-1  | master |
# | mapreduce-master-2  | master |
# | mapreduce-master-3  | master |
# | mapreduce-worker-1  | worker |
# | mapreduce-worker-2  | worker |
# | mapreduce-worker-3  | worker |
```

### **2. Test SSH**

```bash
# Ottieni IP delle istanze
cd aws/terraform/
terraform output master_instances
terraform output worker_instances

# Test SSH su ogni istanza
ssh -i ~/.ssh/mapreduce-key.pem ec2-user@<PUBLIC_IP>

# Controlla i container
sudo docker ps
```

### **3. Test S3 Integration**

```bash
# Carica file di input
aws s3 cp data/Words.txt s3://$(terraform output -raw s3_bucket_name)/data/
aws s3 cp data/Words2.txt s3://$(terraform output -raw s3_bucket_name)/data/
aws s3 cp data/Words3.txt s3://$(terraform output -raw s3_bucket_name)/data/

# Verifica che i master li rilevino
ssh -i ~/.ssh/mapreduce-key.pem ec2-user@<MASTER_IP>
sudo docker logs mapreduce-master | grep "Downloaded.*input files"
```

### **4. Test Dashboard**

```bash
# Ottieni DNS del Load Balancer
cd aws/terraform/
LB_DNS=$(terraform output -raw load_balancer_dns)

# Test dashboard
curl http://$LB_DNS/health
curl http://$LB_DNS/dashboard
curl http://$LB_DNS/api/s3/stats
```

## 🔍 **Script di Verifica Automatica**

```bash
# Esegui verifica completa
chmod +x scripts/verify-deployment.sh
./scripts/verify-deployment.sh

# Verifiche specifiche
./scripts/verify-deployment.sh instances  # Solo conteggio istanze
./scripts/verify-deployment.sh config     # Solo configurazione
./scripts/verify-deployment.sh s3         # Solo S3
./scripts/verify-deployment.sh lb         # Solo Load Balancer
./scripts/verify-deployment.sh test       # Solo test funzionalità
```

## 📊 **Monitoring e Logs**

### **CloudWatch Logs**

```bash
# Visualizza log delle istanze
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/mapreduce"

# Log specifici
aws logs tail /aws/ec2/mapreduce/master --follow
aws logs tail /aws/ec2/mapreduce/worker --follow
```

### **Dashboard Monitoring**

```bash
# Accedi al dashboard
LB_DNS=$(cd aws/terraform && terraform output -raw load_balancer_dns)
open http://$LB_DNS/dashboard
```

## 🧹 **Cleanup**

```bash
# Rimuovi tutto (ATTENZIONE: cancella tutte le risorse!)
cd aws/terraform/
terraform destroy

# Oppure usa lo script
./scripts/setup-aws-deployment.sh cleanup
```

## 🔧 **Troubleshooting**

### **Problema: Istanze non si trovano**

```bash
# Verifica service discovery
ssh -i ~/.ssh/mapreduce-key.pem ec2-user@<INSTANCE_IP>
sudo docker exec mapreduce-master env | grep -E "(RAFT_ADDRESSES|RPC_ADDRESSES|WORKER_ADDRESSES)"
```

### **Problema: S3 non accessibile**

```bash
# Verifica IAM role
aws iam get-role --role-name mapreduce-role

# Verifica bucket
aws s3 ls s3://$(cd aws/terraform && terraform output -raw s3_bucket_name)
```

### **Problema: Load Balancer non funziona**

```bash
# Verifica target group
aws elbv2 describe-target-groups --names mapreduce-master-tg

# Verifica health check
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
```

## 📈 **Scaling**

### **Aumenta Istanze**

```bash
# Modifica terraform.tfvars
master_count = 5  # Aumenta master
worker_count = 5  # Aumenta worker

# Applica modifiche
terraform plan
terraform apply
```

### **Auto Scaling (Futuro)**

Il sistema è progettato per supportare auto scaling tramite:
- CloudWatch metrics
- Target tracking policies
- Lifecycle hooks

## 💰 **Costi Stimati**

**Configurazione Base (3 master + 3 worker):**
- Master (t3.medium): ~$30/mese
- Worker (t3.small): ~$15/mese  
- Load Balancer: ~$20/mese
- S3 Storage: ~$5/mese
- **Totale: ~$70/mese**

## 📚 **Risorse Utili**

- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [S3 Integration Guide](./S3-INTEGRATION.md)

---

**🎉 Il tuo cluster MapReduce distribuito è pronto!**
