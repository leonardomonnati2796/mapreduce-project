#!/bin/bash

# S3 Configuration Script for MapReduce on AWS
# Questo script configura S3 come storage per il sistema MapReduce

# Parametri di default
BUCKET_NAME="mapreduce-storage"
REGION="us-east-1"
BACKUP_BUCKET="mapreduce-backup"
CREATE_BUCKETS=false
SETUP_IAM=false
TEST_CONNECTION=false

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Funzione per stampare header
print_header() {
    echo -e "${CYAN}🗄️ CONFIGURAZIONE S3 STORAGE PER MAPREDUCE${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# Funzione per stampare sezione
print_section() {
    echo -e "\n${YELLOW}$1${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
}

# Funzione per stampare successo
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Funzione per stampare errore
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Funzione per stampare warning
print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# Parsing parametri
while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --backup-bucket)
            BACKUP_BUCKET="$2"
            shift 2
            ;;
        --create-buckets)
            CREATE_BUCKETS=true
            shift
            ;;
        --setup-iam)
            SETUP_IAM=true
            shift
            ;;
        --test-connection)
            TEST_CONNECTION=true
            shift
            ;;
        -h|--help)
            echo "Uso: $0 [opzioni]"
            echo "Opzioni:"
            echo "  --bucket-name NOME     Nome bucket principale (default: mapreduce-storage)"
            echo "  --region REGIONE       Regione AWS (default: us-east-1)"
            echo "  --backup-bucket NOME   Nome bucket backup (default: mapreduce-backup)"
            echo "  --create-buckets       Crea bucket S3"
            echo "  --setup-iam           Configura policy IAM"
            echo "  --test-connection      Testa connessione S3"
            echo "  -h, --help            Mostra questo help"
            exit 0
            ;;
        *)
            echo "Opzione sconosciuta: $1"
            exit 1
            ;;
    esac
done

print_header

# 1. Verifica AWS CLI
print_section "📋 1. Verifica AWS CLI"

if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version)
    print_success "AWS CLI installato: $AWS_VERSION"
else
    print_error "AWS CLI non installato"
    echo "Installa AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi

# 2. Verifica credenziali AWS
print_section "🔐 2. Verifica Credenziali AWS"

if aws sts get-caller-identity &> /dev/null; then
    IDENTITY=$(aws sts get-caller-identity --output json)
    ACCOUNT=$(echo $IDENTITY | jq -r '.Account')
    ARN=$(echo $IDENTITY | jq -r '.Arn')
    print_success "AWS Account: $ACCOUNT"
    print_success "User/Role: $ARN"
else
    print_error "Credenziali AWS non configurate"
    echo "Configura con: aws configure"
    exit 1
fi

# 3. Crea bucket S3 se richiesto
if [ "$CREATE_BUCKETS" = true ]; then
    print_section "🪣 3. Creazione Bucket S3"
    
    # Crea bucket principale
    if aws s3 mb "s3://$BUCKET_NAME" --region $REGION &> /dev/null; then
        print_success "Bucket principale creato: $BUCKET_NAME"
    else
        print_error "Errore creazione bucket principale"
    fi
    
    # Crea bucket backup
    if aws s3 mb "s3://$BACKUP_BUCKET" --region $REGION &> /dev/null; then
        print_success "Bucket backup creato: $BACKUP_BUCKET"
    else
        print_error "Errore creazione bucket backup"
    fi
    
    # Abilita versioning
    if aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled &> /dev/null; then
        print_success "Versioning abilitato per bucket principale"
    else
        print_error "Errore abilitazione versioning bucket principale"
    fi
    
    if aws s3api put-bucket-versioning --bucket $BACKUP_BUCKET --versioning-configuration Status=Enabled &> /dev/null; then
        print_success "Versioning abilitato per bucket backup"
    else
        print_error "Errore abilitazione versioning bucket backup"
    fi
fi

# 4. Configura IAM se richiesto
if [ "$SETUP_IAM" = true ]; then
    print_section "👤 4. Configurazione IAM"
    
    # Crea policy document
    cat > mapreduce-s3-policy.json << EOF
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
                "arn:aws:s3:::$BUCKET_NAME",
                "arn:aws:s3:::$BUCKET_NAME/*",
                "arn:aws:s3:::$BACKUP_BUCKET",
                "arn:aws:s3:::$BACKUP_BUCKET/*"
            ]
        }
    ]
}
EOF
    
    if aws iam create-policy --policy-name MapReduceS3Policy --policy-document file://mapreduce-s3-policy.json &> /dev/null; then
        print_success "Policy IAM creata: MapReduceS3Policy"
    else
        print_warning "Policy IAM già esistente o errore creazione"
    fi
    
    rm -f mapreduce-s3-policy.json
fi

# 5. Configura variabili d'ambiente
print_section "⚙️ 5. Configurazione Variabili d'Ambiente"

ENV_FILE="aws/config/loadbalancer-s3.env"
if [ -f "$ENV_FILE" ]; then
    print_success "File configurazione trovato: $ENV_FILE"
    
    # Backup del file originale
    cp "$ENV_FILE" "$ENV_FILE.backup"
    
    # Aggiorna configurazione
    sed -i "s/^AWS_S3_BUCKET=.*/AWS_S3_BUCKET=$BUCKET_NAME/" "$ENV_FILE"
    sed -i "s/^AWS_REGION=.*/AWS_REGION=$REGION/" "$ENV_FILE"
    sed -i "s/^S3_SYNC_ENABLED=.*/S3_SYNC_ENABLED=true/" "$ENV_FILE"
    
    print_success "Configurazione aggiornata"
else
    print_error "File configurazione non trovato: $ENV_FILE"
fi

# 6. Test connessione S3
if [ "$TEST_CONNECTION" = true ]; then
    print_section "🧪 6. Test Connessione S3"
    
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        print_success "Connessione S3 funzionante"
        
        # Test upload file
        TEST_FILE="s3-test.txt"
        echo "Test S3 - $(date)" > "$TEST_FILE"
        
        if aws s3 cp "$TEST_FILE" "s3://$BUCKET_NAME/test/" &> /dev/null; then
            print_success "Upload test completato"
        else
            print_error "Errore upload test"
        fi
        
        # Test download file
        if aws s3 cp "s3://$BUCKET_NAME/test/$TEST_FILE" "s3-downloaded.txt" &> /dev/null; then
            print_success "Download test completato"
        else
            print_error "Errore download test"
        fi
        
        # Cleanup
        rm -f "$TEST_FILE" "s3-downloaded.txt"
        aws s3 rm "s3://$BUCKET_NAME/test/$TEST_FILE" &> /dev/null
    else
        print_error "Errore test connessione S3"
    fi
fi

# 7. Configurazione Docker
print_section "🐳 7. Configurazione Docker"

DOCKER_COMPOSE_FILE="docker/docker-compose.aws.yml"
if [ -f "$DOCKER_COMPOSE_FILE" ]; then
    print_success "Docker Compose file trovato"
    
    if grep -q "S3_SYNC_ENABLED" "$DOCKER_COMPOSE_FILE"; then
        print_success "S3 già configurato in Docker Compose"
    else
        print_warning "S3 non configurato in Docker Compose"
        echo "Aggiungi variabili S3 al file Docker Compose"
    fi
else
    print_error "Docker Compose file non trovato"
fi

# 8. Verifica configurazione finale
print_section "✅ 8. Verifica Configurazione Finale"

echo -e "${CYAN}📋 Configurazione S3:${NC}"
echo -e "   Bucket Principale: $BUCKET_NAME"
echo -e "   Bucket Backup: $BACKUP_BUCKET"
echo -e "   Region: $REGION"
echo -e "   Sync Abilitato: true"

echo -e "\n${CYAN}📋 Prossimi Passi:${NC}"
echo -e "   1. Avvia il sistema MapReduce"
echo -e "   2. Verifica dashboard S3"
echo -e "   3. Test backup automatico"
echo -e "   4. Monitora metriche S3"

echo -e "\n${GREEN}🎉 CONFIGURAZIONE S3 COMPLETATA!${NC}"
echo -e "${GREEN}============================================================${NC}"
