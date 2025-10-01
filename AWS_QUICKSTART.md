# Quick Start - MapReduce su AWS

Guida rapida per deployare MapReduce su AWS in 5 minuti.

## Prerequisiti

1. **AWS CLI configurato** con credenziali valide
2. **Terraform** installato
3. **Docker** installato

## Deployment Rapido

### 1. Clona e Configura

```bash
git clone <repository-url>
cd mapreduce-project
```

### 2. Deploy Automatico

```bash
# Linux/macOS
./scripts/deploy-aws.sh deploy

# Windows
.\scripts\deploy-aws.ps1 -Action deploy
```

### 3. Accedi al Dashboard

Dopo il deployment (2-3 minuti), accedi al dashboard:
```
http://<ALB_DNS>
```

## Verifica Deployment

```bash
# Ottieni l'URL del load balancer
ALB_DNS=$(cd aws/terraform && terraform output -raw load_balancer_dns)

# Test health check
curl http://$ALB_DNS/health

# Apri il dashboard nel browser
open http://$ALB_DNS
```

## Comandi Utili

```bash
# Stato dell'infrastruttura
./scripts/deploy-aws.sh status

# Distruggi l'infrastruttura
./scripts/deploy-aws.sh destroy
```

## Costi Stimati

- **2 istanze t3.medium**: ~$60/mese
- **Load Balancer**: ~$16/mese
- **S3 + CloudWatch**: ~$10/mese
- **Totale**: ~$86/mese

## Troubleshooting Rapido

### Dashboard non accessibile
```bash
# Verifica lo stato delle istanze
aws ec2 describe-instances --filters "Name=tag:Name,Values=*mapreduce*"
```

### Health check fallisce
```bash
# Verifica i log
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/mapreduce"
```

### S3 non funziona
```bash
# Verifica il bucket
aws s3 ls s3://$(cd aws/terraform && terraform output -raw s3_bucket_name)
```

## Cleanup

```bash
./scripts/deploy-aws.sh destroy
```

**Attenzione**: Questo elimina tutto l'infrastruttura e i dati.

---

Per informazioni dettagliate, consulta [AWS_DEPLOYMENT_GUIDE.md](AWS_DEPLOYMENT_GUIDE.md)
