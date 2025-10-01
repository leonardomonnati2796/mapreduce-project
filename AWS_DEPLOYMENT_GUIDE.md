# Guida al Deployment su AWS

Questa guida descrive come deployare il progetto MapReduce su AWS EC2 con S3 storage e Application Load Balancer.

## Architettura

Il deployment su AWS include:

- **EC2 Instances**: Auto Scaling Group con istanze t3.medium
- **Application Load Balancer**: Distribuzione del traffico e health checks
- **S3 Bucket**: Storage persistente per dati e backup
- **VPC**: Rete privata con subnets pubbliche e private
- **CloudWatch**: Monitoring e logging
- **IAM Roles**: Permessi per accesso a S3 e CloudWatch

## Prerequisiti

### Software Richiesto

1. **AWS CLI v2**
   ```bash
   # Linux/macOS
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   
   # Windows
   # Scarica e installa da: https://aws.amazon.com/cli/
   ```

2. **Terraform**
   ```bash
   # Linux/macOS
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   
   # Windows
   # Scarica da: https://www.terraform.io/downloads.html
   ```

3. **Docker e Docker Compose**
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install docker.io docker-compose
   
   # Windows/macOS
   # Installa Docker Desktop
   ```

### Configurazione AWS

1. **Configura AWS CLI**
   ```bash
   aws configure
   ```
   Inserisci:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (es. us-east-1)
   - Default output format (json)

2. **Verifica configurazione**
   ```bash
   aws sts get-caller-identity
   ```

## Deployment

### 1. Preparazione

Clona il repository e naviga nella directory:
```bash
git clone <repository-url>
cd mapreduce-project
```

### 2. Configurazione

Copia e modifica il file di configurazione:
```bash
cp aws/terraform/terraform.tfvars.example aws/terraform/terraform.tfvars
```

Modifica `aws/terraform/terraform.tfvars`:
```hcl
aws_region = "us-east-1"
project_name = "mapreduce"
instance_type = "t3.medium"
min_instances = 1
max_instances = 5
desired_instances = 2
```

### 3. Deployment Automatico

#### Linux/macOS
```bash
# Pianifica il deployment
./scripts/deploy-aws.sh plan

# Esegui il deployment
./scripts/deploy-aws.sh deploy
```

#### Windows PowerShell
```powershell
# Pianifica il deployment
.\scripts\deploy-aws.ps1 -Action plan

# Esegui il deployment
.\scripts\deploy-aws.ps1 -Action deploy
```

### 4. Deployment Manuale

Se preferisci eseguire i comandi manualmente:

```bash
# 1. Inizializza Terraform
cd aws/terraform
terraform init
terraform validate

# 2. Pianifica il deployment
terraform plan -out=tfplan

# 3. Esegui il deployment
terraform apply tfplan

# 4. Ottieni gli output
terraform output
```

## Configurazione Post-Deployment

### 1. Verifica Deployment

Dopo il deployment, verifica che tutto funzioni:

```bash
# Ottieni l'URL del load balancer
ALB_DNS=$(cd aws/terraform && terraform output -raw load_balancer_dns)

# Test health check
curl http://$ALB_DNS/health

# Test dashboard
curl http://$ALB_DNS
```

### 2. Configurazione S3

Il bucket S3 viene creato automaticamente. Per configurare il backup:

```bash
# Ottieni il nome del bucket
S3_BUCKET=$(cd aws/terraform && terraform output -raw s3_bucket_name)

# Verifica il bucket
aws s3 ls s3://$S3_BUCKET
```

### 3. Monitoring

#### CloudWatch Logs
```bash
# Visualizza i log
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/mapreduce"
```

#### CloudWatch Metrics
```bash
# Visualizza le metriche
aws cloudwatch list-metrics --namespace "MapReduce/EC2"
```

## Utilizzo

### 1. Accesso al Dashboard

Il dashboard è disponibile all'URL del load balancer:
```
http://<ALB_DNS>
```

### 2. Health Checks

- **Health Check**: `http://<ALB_DNS>/health`
- **Liveness Probe**: `http://<ALB_DNS>/health/live`
- **Readiness Probe**: `http://<ALB_DNS>/health/ready`
- **Metrics**: `http://<ALB_DNS>/health/metrics`

### 3. S3 Backup

I dati vengono automaticamente sincronizzati su S3:
- **Output files**: `s3://<bucket>/output/`
- **Intermediate files**: `s3://<bucket>/intermediate/`
- **Logs**: `s3://<bucket>/logs/`
- **Backups**: `s3://<bucket>/backups/<timestamp>/`

## Gestione

### Scaling

Per modificare il numero di istanze:

```bash
cd aws/terraform
terraform apply -var="desired_instances=3"
```

### Aggiornamento

Per aggiornare l'applicazione:

```bash
# 1. Builda la nuova immagine
docker build -f docker/Dockerfile.aws -t mapreduce:latest .

# 2. Riavvia le istanze
aws autoscaling start-instance-refresh --auto-scaling-group-name <asg-name>
```

### Backup

Per eseguire un backup manuale:

```bash
# Backup completo
aws s3 sync /tmp/mapreduce s3://<bucket>/backups/manual-$(date +%Y%m%d-%H%M%S)/
```

## Troubleshooting

### 1. Problemi di Connessione

```bash
# Verifica lo stato delle istanze
aws ec2 describe-instances --filters "Name=tag:Name,Values=*mapreduce*"

# Verifica i security groups
aws ec2 describe-security-groups --group-names "*mapreduce*"
```

### 2. Problemi di Load Balancer

```bash
# Verifica lo stato del target group
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

### 3. Problemi di S3

```bash
# Verifica i permessi S3
aws s3api get-bucket-policy --bucket <bucket-name>

# Test di accesso S3
aws s3 ls s3://<bucket-name>
```

### 4. Logs

```bash
# Logs dell'istanza
aws logs get-log-events --log-group-name "/aws/ec2/mapreduce" --log-stream-name "<instance-id>/user-data.log"

# Logs dell'applicazione
aws logs get-log-events --log-group-name "/aws/ec2/mapreduce" --log-stream-name "<instance-id>/application.log"
```

## Costi

### Stima dei Costi (us-east-1)

- **EC2 t3.medium**: ~$30/mese per istanza
- **Application Load Balancer**: ~$16/mese
- **S3 Storage**: ~$0.023/GB/mese
- **CloudWatch**: ~$0.50/mese per log group

**Totale stimato**: ~$80-100/mese per 2 istanze

### Ottimizzazione Costi

1. **Utilizza Spot Instances** per carichi di lavoro non critici
2. **Configura Auto Scaling** per ridurre le istanze durante i periodi di basso utilizzo
3. **Usa S3 Intelligent Tiering** per ottimizzare i costi di storage
4. **Configura CloudWatch Log Retention** per limitare i costi di logging

## Cleanup

Per distruggere l'infrastruttura:

```bash
# Automatico
./scripts/deploy-aws.sh destroy

# Manuale
cd aws/terraform
terraform destroy
```

**Attenzione**: Questo eliminerà tutti i dati e l'infrastruttura. Assicurati di aver fatto backup dei dati importanti.

## Sicurezza

### 1. Security Groups

I security groups sono configurati per permettere solo il traffico necessario:
- Porta 80/443: HTTP/HTTPS (Load Balancer)
- Porta 22: SSH (solo per debugging)
- Porte interne: Comunicazione tra servizi

### 2. IAM Roles

Le istanze EC2 utilizzano IAM roles con permessi minimi:
- Accesso in lettura/scrittura al bucket S3
- Invio di metriche a CloudWatch
- Scrittura di log in CloudWatch

### 3. VPC

L'infrastruttura è deployata in una VPC privata con:
- Subnets pubbliche per il Load Balancer
- Subnets private per le istanze EC2
- Internet Gateway per accesso esterno

## Supporto

Per problemi o domande:

1. Controlla i log in CloudWatch
2. Verifica lo stato dei servizi AWS
3. Consulta la documentazione AWS
4. Apri un issue nel repository

## Changelog

- **v1.0.0**: Deployment iniziale su AWS
- **v1.1.0**: Aggiunto supporto S3 e backup automatico
- **v1.2.0**: Implementato health checks e monitoring
- **v1.3.0**: Aggiunto Application Load Balancer e Auto Scaling
