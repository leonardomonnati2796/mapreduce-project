# Guida per Deploy su Amazon Linux 2023 EC2

## Prerequisiti
- Istanza EC2 Amazon Linux 2023
- Accesso SSH all'istanza
- Security Group configurato per permettere traffico sulla porta 8080

## Step 1: Connessione SSH
```bash
ssh -i your-key.pem ec2-user@YOUR_EC2_PUBLIC_IP
```

## Step 2: Installazione Docker
```bash
# Aggiorna il sistema
sudo dnf update -y

# Installa Docker
sudo dnf install -y docker

# Abilita e avvia Docker
sudo systemctl enable --now docker

# Aggiungi l'utente al gruppo docker
sudo usermod -aG docker $USER
newgrp docker

# Verifica installazione
docker --version
sudo systemctl status docker
```

## Step 3: Installazione Docker Compose v2
```bash
# Installa Docker Compose v2
DOCKER_COMPOSE_VERSION=v2.29.7
sudo mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64 -o docker-compose
sudo mv docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verifica installazione
docker compose version
```

## Step 4: Installazione Git
```bash
# Installa Git
sudo dnf install -y git

# Verifica installazione
git --version
```

## Step 5: Clonazione Repository
```bash
# Clona il repository (sostituisci con il tuo URL)
git clone https://github.com/your-username/mapreduce-project.git
cd mapreduce-project
```

## Step 6: Preparazione Directory
```bash
# Crea directory per i log
sudo mkdir -p /var/log/mapreduce
sudo chown -R $USER:$USER /var/log/mapreduce

# Crea directory per i dati
mkdir -p data
```

## Step 7: Configurazione Variabili d'Ambiente
```bash
# Configura le variabili richieste
export AWS_REGION=us-east-1
export S3_BUCKET=my-mapreduce-bucket  # opzionale, puoi lasciare vuoto se non usi S3
export INSTANCE_ID=local-$(hostname)
export INSTANCE_IP=$(hostname -I | awk '{print $1}')

# Verifica le variabili
echo "AWS_REGION: $AWS_REGION"
echo "S3_BUCKET: $S3_BUCKET"
echo "INSTANCE_ID: $INSTANCE_ID"
echo "INSTANCE_IP: $INSTANCE_IP"
```

## Step 8: Avvio del Progetto
```bash
# Avvia tutti i servizi
docker compose -f docker/docker-compose.aws.yml up -d --build
```

## Step 9: Verifica Deployment
```bash
# Controlla lo stato dei container
docker compose -f docker/docker-compose.aws.yml ps

# Testa l'endpoint di health
curl -f http://localhost:8080/health

# Visualizza i log della dashboard
docker compose -f docker/docker-compose.aws.yml logs -f --tail=100 mapreduce-dashboard
```

## Step 10: Configurazione Security Group

### Metodo 1: Dalla pagina Security Groups
1. Vai nella console AWS EC2
2. Clicca su **"Security Groups"** nel menu laterale
3. Seleziona il gruppo di sicurezza associato alla tua istanza (es. `launch-wizard-1` o `default`)
4. Clicca su **"Edit inbound rules"** o **"Modifica regole in entrata"**
5. Clicca **"Add rule"** o **"Aggiungi regola"**
6. Imposta:
   - **Type**: Custom TCP
   - **Port**: 8080
   - **Source**: 0.0.0.0/0 (o il tuo IP specifico per maggiore sicurezza)
7. Clicca **"Save rules"** o **"Salva regole"**

### Metodo 2: Dalla pagina Instances
1. Vai nella console AWS EC2
2. Seleziona la tua istanza
3. Vai su **"Security"** → **"Security groups"**
4. Clicca sul Security Group (es. `sg-xxxxxxxxx`)
5. Clicca su **"Edit inbound rules"**
6. Aggiungi la regola per la porta 8080 come sopra

## Step 11: Accesso alla Dashboard
- **URL Dashboard**: `http://YOUR_EC2_PUBLIC_IP:8080/dashboard`
- **URL Health Check**: `http://YOUR_EC2_PUBLIC_IP:8080/health`
- **URL API Master**: `http://YOUR_EC2_PUBLIC_IP:8080/api/master`
- **URL API Worker**: `http://YOUR_EC2_PUBLIC_IP:8080/api/worker`

## Step 12: Script per Aggiornamenti Automatici

### Opzione A: Crea lo script direttamente sull'EC2
```bash
# Crea lo script di aggiornamento
cat > update-project.sh << 'EOF'
#!/bin/bash
set -e
echo "Aggiornando il progetto MapReduce..."
cd ~/mapreduce-project
git pull origin main
docker compose -f docker/docker-compose.aws.yml down
docker compose -f docker/docker-compose.aws.yml up -d --build
sleep 10
docker compose -f docker/docker-compose.aws.yml ps
curl -f http://localhost:8080/health && echo "Health check OK" || echo "Health check failed"
echo "Aggiornamento completato!"
echo "Dashboard: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}'):8080/dashboard"
EOF

# Rendi eseguibile
chmod +x update-project.sh

# Testa lo script
./update-project.sh
```

### Step 2: Rendi eseguibile lo script
```bash
# Rendi eseguibile lo script
chmod +x update-project.sh
```

### Step 3: Esegui lo script
```bash
# Esegui lo script di aggiornamento
./update-project.sh
```

### Opzione B: Carica lo script dal tuo computer
```bash
# Dal tuo computer Windows (PowerShell)
scp -i your-key.pem update-project.sh ec2-user@YOUR_EC2_IP:~/

# Sull'EC2, rendi eseguibile
chmod +x update-project.sh

# Esegui lo script
./update-project.sh
```

### Workflow di Sviluppo:
1. **Sul tuo computer**: Modifica il codice
2. **Sul tuo computer**: `git add . && git commit -m "messaggio" && git push origin main`
3. **Sull'EC2**: `./update-project.sh`

## Comandi Utili per la Gestione

### Controllo Status
```bash
# Stato dei container
docker compose -f docker/docker-compose.aws.yml ps

# Log di tutti i servizi
docker compose -f docker/docker-compose.aws.yml logs

# Log di un servizio specifico
docker compose -f docker/docker-compose.aws.yml logs mapreduce-dashboard
```

### Riavvio Servizi
```bash
# Riavvia tutti i servizi
docker compose -f docker/docker-compose.aws.yml restart

# Riavvia un servizio specifico
docker compose -f docker/docker-compose.aws.yml restart mapreduce-dashboard
```

### Stop e Start
```bash
# Ferma tutti i servizi
docker compose -f docker/docker-compose.aws.yml down

# Avvia tutti i servizi
docker compose -f docker/docker-compose.aws.yml up -d
```

### Pulizia
```bash
# Ferma e rimuovi tutti i container e volumi
docker compose -f docker/docker-compose.aws.yml down -v

# Rimuovi immagini non utilizzate
docker system prune -a
```

## Troubleshooting

### Problema: Container non si avvia
```bash
# Controlla i log per errori
docker compose -f docker/docker-compose.aws.yml logs

# Verifica che le variabili d'ambiente siano impostate
env | grep -E "(AWS_REGION|S3_BUCKET|INSTANCE_ID|INSTANCE_IP)"
```

### Problema: Porta 8080 non accessibile
```bash
# Verifica che il servizio sia in ascolto
sudo netstat -tlnp | grep 8080

# Controlla i firewall locali
sudo iptables -L
```

### Problema: Permessi Docker
```bash
# Riapplica i permessi del gruppo docker
sudo usermod -aG docker $USER
newgrp docker

# Verifica i permessi
groups $USER
```

## Monitoraggio

### Log in Tempo Reale
```bash
# Tutti i servizi
docker compose -f docker/docker-compose.aws.yml logs -f

# Solo dashboard
docker compose -f docker/docker-compose.aws.yml logs -f mapreduce-dashboard

# Solo master
docker compose -f docker/docker-compose.aws.yml logs -f mapreduce-master-1
```

### Metriche di Sistema
```bash
# Utilizzo risorse
docker stats

# Spazio disco
df -h

# Memoria
free -h
```

## Backup e Restore

### Backup Dati
```bash
# Crea backup della directory data
tar -czf mapreduce-backup-$(date +%Y%m%d_%H%M%S).tar.gz data/

# Backup configurazione
cp docker/docker-compose.aws.yml docker-compose.backup.yml
```

### Restore Dati
```bash
# Estrai backup
tar -xzf mapreduce-backup-YYYYMMDD_HHMMSS.tar.gz

# Riavvia i servizi
docker compose -f docker/docker-compose.aws.yml restart
```

## Note Importanti
- Le variabili d'ambiente devono essere esportate in ogni nuova sessione SSH
- Per rendere permanenti le variabili, aggiungile al file `~/.bashrc`
- Il progetto include 3 master e 3 worker per alta disponibilità
- I log sono salvati in `/var/log/mapreduce/` e ruotati automaticamente
- Il servizio S3 sync è opzionale e richiede un bucket S3 configurato

## Supporto
Per problemi o domande, controlla:
1. I log dei container: `docker compose -f docker/docker-compose.aws.yml logs`
2. Lo stato dei servizi: `docker compose -f docker/docker-compose.aws.yml ps`
3. La configurazione delle variabili d'ambiente: `env | grep -E "(AWS|S3|INSTANCE)"`
