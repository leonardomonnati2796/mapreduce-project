# S3 Configuration Script for MapReduce on AWS
# Questo script configura S3 come storage per il sistema MapReduce

param(
    [string]$BucketName = "mapreduce-storage",
    [string]$Region = "us-east-1",
    [string]$BackupBucket = "mapreduce-backup",
    [switch]$CreateBuckets,
    [switch]$SetupIAM,
    [switch]$TestConnection
)

Write-Host "🗄️ CONFIGURAZIONE S3 STORAGE PER MAPREDUCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Verifica AWS CLI
Write-Host "`n📋 1. Verifica AWS CLI" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

try {
    $awsVersion = aws --version
    Write-Host "✅ AWS CLI installato: $awsVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ AWS CLI non installato" -ForegroundColor Red
    Write-Host "   Installa AWS CLI: https://aws.amazon.com/cli/" -ForegroundColor Yellow
    exit 1
}

# 2. Verifica credenziali AWS
Write-Host "`n🔐 2. Verifica Credenziali AWS" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "✅ AWS Account: $($identity.Account)" -ForegroundColor Green
    Write-Host "✅ User/Role: $($identity.Arn)" -ForegroundColor Green
} catch {
    Write-Host "❌ Credenziali AWS non configurate" -ForegroundColor Red
    Write-Host "   Configura con: aws configure" -ForegroundColor Yellow
    exit 1
}

# 3. Crea bucket S3 se richiesto
if ($CreateBuckets) {
    Write-Host "`n🪣 3. Creazione Bucket S3" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    
    # Crea bucket principale
    try {
        aws s3 mb "s3://$BucketName" --region $Region
        Write-Host "✅ Bucket principale creato: $BucketName" -ForegroundColor Green
    } catch {
        Write-Host "❌ Errore creazione bucket principale" -ForegroundColor Red
    }
    
    # Crea bucket backup
    try {
        aws s3 mb "s3://$BackupBucket" --region $Region
        Write-Host "✅ Bucket backup creato: $BackupBucket" -ForegroundColor Green
    } catch {
        Write-Host "❌ Errore creazione bucket backup" -ForegroundColor Red
    }
    
    # Abilita versioning
    try {
        aws s3api put-bucket-versioning --bucket $BucketName --versioning-configuration Status=Enabled
        aws s3api put-bucket-versioning --bucket $BackupBucket --versioning-configuration Status=Enabled
        Write-Host "✅ Versioning abilitato" -ForegroundColor Green
    } catch {
        Write-Host "❌ Errore abilitazione versioning" -ForegroundColor Red
    }
}

# 4. Configura IAM se richiesto
if ($SetupIAM) {
    Write-Host "`n👤 4. Configurazione IAM" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    
    $policyDocument = @"
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
                "arn:aws:s3:::$BucketName",
                "arn:aws:s3:::$BucketName/*",
                "arn:aws:s3:::$BackupBucket",
                "arn:aws:s3:::$BackupBucket/*"
            ]
        }
    ]
}
"@
    
    $policyFile = "mapreduce-s3-policy.json"
    $policyDocument | Out-File -FilePath $policyFile -Encoding UTF8
    
    try {
        aws iam create-policy --policy-name MapReduceS3Policy --policy-document file://$policyFile
        Write-Host "✅ Policy IAM creata: MapReduceS3Policy" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Policy IAM già esistente o errore creazione" -ForegroundColor Yellow
    }
    
    Remove-Item $policyFile -ErrorAction SilentlyContinue
}

# 5. Configura variabili d'ambiente
Write-Host "`n⚙️ 5. Configurazione Variabili d'Ambiente" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

$envFile = "aws/config/loadbalancer-s3.env"
if (Test-Path $envFile) {
    Write-Host "✅ File configurazione trovato: $envFile" -ForegroundColor Green
    
    # Aggiorna configurazione
    $content = Get-Content $envFile
    $updatedContent = $content | ForEach-Object {
        if ($_ -match "^AWS_S3_BUCKET=") {
            "AWS_S3_BUCKET=$BucketName"
        } elseif ($_ -match "^AWS_REGION=") {
            "AWS_REGION=$Region"
        } elseif ($_ -match "^S3_SYNC_ENABLED=") {
            "S3_SYNC_ENABLED=true"
        } else {
            $_
        }
    }
    
    $updatedContent | Set-Content $envFile
    Write-Host "✅ Configurazione aggiornata" -ForegroundColor Green
} else {
    Write-Host "❌ File configurazione non trovato: $envFile" -ForegroundColor Red
}

# 6. Test connessione S3
if ($TestConnection) {
    Write-Host "`n🧪 6. Test Connessione S3" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    
    try {
        # Test list bucket
        aws s3 ls "s3://$BucketName"
        Write-Host "✅ Connessione S3 funzionante" -ForegroundColor Green
        
        # Test upload file
        $testFile = "s3-test.txt"
        "Test S3 - $(Get-Date)" | Out-File -FilePath $testFile -Encoding UTF8
        
        aws s3 cp $testFile "s3://$BucketName/test/"
        Write-Host "✅ Upload test completato" -ForegroundColor Green
        
        # Test download file
        aws s3 cp "s3://$BucketName/test/$testFile" "s3-downloaded.txt"
        Write-Host "✅ Download test completato" -ForegroundColor Green
        
        # Cleanup
        Remove-Item $testFile -ErrorAction SilentlyContinue
        Remove-Item "s3-downloaded.txt" -ErrorAction SilentlyContinue
        aws s3 rm "s3://$BucketName/test/$testFile"
        
    } catch {
        Write-Host "❌ Errore test connessione S3" -ForegroundColor Red
    }
}

# 7. Configurazione Docker
Write-Host "`n🐳 7. Configurazione Docker" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

$dockerComposeFile = "docker/docker-compose.aws.yml"
if (Test-Path $dockerComposeFile) {
    Write-Host "✅ Docker Compose file trovato" -ForegroundColor Green
    
    # Verifica se S3 è configurato nel Docker Compose
    $dockerContent = Get-Content $dockerComposeFile -Raw
    if ($dockerContent -match "S3_SYNC_ENABLED") {
        Write-Host "✅ S3 già configurato in Docker Compose" -ForegroundColor Green
    } else {
        Write-Host "⚠️ S3 non configurato in Docker Compose" -ForegroundColor Yellow
        Write-Host "   Aggiungi variabili S3 al file Docker Compose" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ Docker Compose file non trovato" -ForegroundColor Red
}

# 8. Verifica configurazione finale
Write-Host "`n✅ 8. Verifica Configurazione Finale" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

Write-Host "📋 Configurazione S3:" -ForegroundColor Cyan
Write-Host "   Bucket Principale: $BucketName" -ForegroundColor White
Write-Host "   Bucket Backup: $BackupBucket" -ForegroundColor White
Write-Host "   Region: $Region" -ForegroundColor White
Write-Host "   Sync Abilitato: true" -ForegroundColor White

Write-Host "`n📋 Prossimi Passi:" -ForegroundColor Cyan
Write-Host "   1. Avvia il sistema MapReduce" -ForegroundColor White
Write-Host "   2. Verifica dashboard S3" -ForegroundColor White
Write-Host "   3. Test backup automatico" -ForegroundColor White
Write-Host "   4. Monitora metriche S3" -ForegroundColor White

Write-Host "`n🎉 CONFIGURAZIONE S3 COMPLETATA!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
