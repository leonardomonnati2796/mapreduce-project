package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
)

// S3Client gestisce le operazioni S3 per MapReduce
type S3Client struct {
	bucket     string
	region     string
	s3Client   *s3.S3
	uploader   *s3manager.Uploader
	downloader *s3manager.Downloader
}

// S3Config configurazione per S3
type S3Config struct {
	Bucket       string
	Region       string
	Enabled      bool
	SyncInterval time.Duration
}

// NewS3Client crea un nuovo client S3
func NewS3Client(config S3Config) (*S3Client, error) {
	if !config.Enabled {
		return nil, fmt.Errorf("S3 non abilitato")
	}

	if config.Bucket == "" {
		return nil, fmt.Errorf("bucket S3 non specificato")
	}

	if config.Region == "" {
		config.Region = "us-east-1"
	}

	// Crea sessione AWS
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(config.Region),
	})
	if err != nil {
		return nil, fmt.Errorf("errore creazione sessione AWS: %v", err)
	}

	s3Client := s3.New(sess)
	uploader := s3manager.NewUploader(sess)
	downloader := s3manager.NewDownloader(sess)

	return &S3Client{
		bucket:     config.Bucket,
		region:     config.Region,
		s3Client:   s3Client,
		uploader:   uploader,
		downloader: downloader,
	}, nil
}

// UploadFile carica un file su S3
func (s *S3Client) UploadFile(localPath, s3Key string) error {
	file, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("errore apertura file %s: %v", localPath, err)
	}
	defer file.Close()

	_, err = s.uploader.Upload(&s3manager.UploadInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(s3Key),
		Body:   file,
	})

	if err != nil {
		return fmt.Errorf("errore upload %s: %v", s3Key, err)
	}

	fmt.Printf("File caricato su S3: %s -> s3://%s/%s\n", localPath, s.bucket, s3Key)
	return nil
}

// DownloadFile scarica un file da S3
func (s *S3Client) DownloadFile(s3Key, localPath string) error {
	// Crea la directory locale se non esiste
	if err := os.MkdirAll(filepath.Dir(localPath), 0755); err != nil {
		return err
	}

	file, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer file.Close()

	_, err = s.downloader.Download(file, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(s3Key),
	})

	if err != nil {
		return fmt.Errorf("errore download %s: %v", s3Key, err)
	}

	fmt.Printf("File scaricato da S3: s3://%s/%s -> %s\n", s.bucket, s3Key, localPath)
	return nil
}

// SyncDirectory sincronizza una directory locale con S3
func (s *S3Client) SyncDirectory(localPath, s3Prefix string) error {
	if _, err := os.Stat(localPath); os.IsNotExist(err) {
		fmt.Printf("Directory %s non esiste, salto sincronizzazione\n", localPath)
		return nil
	}

	return filepath.Walk(localPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			return nil
		}

		// Calcola il percorso relativo
		relPath, err := filepath.Rel(localPath, path)
		if err != nil {
			return err
		}

		// Crea la chiave S3
		s3Key := s3Prefix + strings.ReplaceAll(relPath, "\\", "/")

		// Upload del file
		return s.UploadFile(path, s3Key)
	})
}

// BackupToS3 crea un backup completo su S3
func (s *S3Client) BackupToS3(localPath string) error {
	timestamp := time.Now().Format("2006-01-02-15-04-05")
	backupPrefix := fmt.Sprintf("backups/%s/", timestamp)

	fmt.Printf("Iniziando backup su S3 con prefisso: %s\n", backupPrefix)
	return s.SyncDirectory(localPath, backupPrefix)
}

// ListFiles elenca i file in S3 con un prefisso
func (s *S3Client) ListFiles(prefix string) ([]string, error) {
	var files []string

	err := s.s3Client.ListObjectsV2Pages(&s3.ListObjectsV2Input{
		Bucket: aws.String(s.bucket),
		Prefix: aws.String(prefix),
	}, func(page *s3.ListObjectsV2Output, lastPage bool) bool {
		for _, obj := range page.Contents {
			files = append(files, *obj.Key)
		}
		return true
	})

	if err != nil {
		return nil, fmt.Errorf("errore list files: %v", err)
	}

	return files, nil
}

// DeleteFile elimina un file da S3
func (s *S3Client) DeleteFile(s3Key string) error {
	_, err := s.s3Client.DeleteObject(&s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(s3Key),
	})

	if err != nil {
		return fmt.Errorf("errore eliminazione %s: %v", s3Key, err)
	}

	fmt.Printf("File eliminato da S3: s3://%s/%s\n", s.bucket, s3Key)
	return nil
}

// GetS3ConfigFromEnv ottiene la configurazione S3 dalle variabili d'ambiente
func GetS3ConfigFromEnv() S3Config {
	config := S3Config{
		Bucket:  os.Getenv("AWS_S3_BUCKET"),
		Region:  os.Getenv("AWS_REGION"),
		Enabled: os.Getenv("S3_SYNC_ENABLED") == "true",
	}

	// Parse sync interval
	if intervalStr := os.Getenv("S3_SYNC_INTERVAL"); intervalStr != "" {
		if interval, err := time.ParseDuration(intervalStr); err == nil {
			config.SyncInterval = interval
		} else {
			config.SyncInterval = 60 * time.Second // default
		}
	} else {
		config.SyncInterval = 60 * time.Second // default
	}

	return config
}

// S3SyncService gestisce la sincronizzazione periodica con S3
type S3SyncService struct {
	client   *S3Client
	config   S3Config
	stopChan chan bool
}

// S3StorageManager gestisce l'integrazione S3 con MapReduce
type S3StorageManager struct {
	client      *S3Client
	config      S3Config
	syncService *S3SyncService
	enabled     bool
}

// NewS3SyncService crea un nuovo servizio di sincronizzazione S3
func NewS3SyncService(config S3Config) (*S3SyncService, error) {
	client, err := NewS3Client(config)
	if err != nil {
		return nil, err
	}

	return &S3SyncService{
		client:   client,
		config:   config,
		stopChan: make(chan bool),
	}, nil
}

// Start avvia il servizio di sincronizzazione
func (s *S3SyncService) Start() {
	if !s.config.Enabled {
		fmt.Println("S3 sync non abilitato, salto avvio servizio")
		return
	}

	fmt.Printf("Avviando S3 sync service con intervallo %v\n", s.config.SyncInterval)

	ticker := time.NewTicker(s.config.SyncInterval)
	defer ticker.Stop()

	// Sincronizza immediatamente all'avvio
	s.performSync()

	for {
		select {
		case <-ticker.C:
			s.performSync()
		case <-s.stopChan:
			fmt.Println("S3 sync service fermato")
			return
		}
	}
}

// Stop ferma il servizio di sincronizzazione
func (s *S3SyncService) Stop() {
	close(s.stopChan)
}

// performSync esegue la sincronizzazione
func (s *S3SyncService) performSync() {
	fmt.Printf("Iniziando sincronizzazione S3 alle %s\n", time.Now().Format(time.RFC3339))

	// Sincronizza file di output
	if err := s.client.SyncDirectory("/tmp/mapreduce/output", "output/"); err != nil {
		fmt.Printf("Errore sincronizzazione output: %v\n", err)
	}

	// Sincronizza file intermedi
	if err := s.client.SyncDirectory("/tmp/mapreduce/intermediate", "intermediate/"); err != nil {
		fmt.Printf("Errore sincronizzazione intermediate: %v\n", err)
	}

	// Sincronizza file di log
	if err := s.client.SyncDirectory("/var/log/mapreduce", "logs/"); err != nil {
		fmt.Printf("Errore sincronizzazione logs: %v\n", err)
	}

	fmt.Println("Sincronizzazione S3 completata")
}

// BackupNow esegue un backup immediato
func (s *S3SyncService) BackupNow() error {
	if !s.config.Enabled {
		return fmt.Errorf("S3 non abilitato")
	}

	fmt.Println("Eseguendo backup immediato su S3...")
	return s.client.BackupToS3("/tmp/mapreduce")
}

// NewS3StorageManager crea un nuovo manager S3
func NewS3StorageManager(config S3Config) (*S3StorageManager, error) {
	client, err := NewS3Client(config)
	if err != nil {
		return nil, err
	}

	syncService, err := NewS3SyncService(config)
	if err != nil {
		return nil, err
	}

	return &S3StorageManager{
		client:      client,
		config:      config,
		syncService: syncService,
		enabled:     config.Enabled,
	}, nil
}

// Start avvia il servizio S3
func (sm *S3StorageManager) Start() {
	if !sm.enabled {
		fmt.Println("S3 storage non abilitato")
		return
	}

	fmt.Println("Avviando S3 storage manager...")
	go sm.syncService.Start()
}

// Stop ferma il servizio S3
func (sm *S3StorageManager) Stop() {
	if sm.syncService != nil {
		sm.syncService.Stop()
	}
}

// UploadJobOutput carica l'output di un job su S3
func (sm *S3StorageManager) UploadJobOutput(jobID string, localPath string) error {
	if !sm.enabled {
		return fmt.Errorf("S3 non abilitato")
	}

	s3Key := fmt.Sprintf("jobs/%s/output/", jobID)
	return sm.client.SyncDirectory(localPath, s3Key)
}

// DownloadJobInput scarica i file di input di un job da S3
func (sm *S3StorageManager) DownloadJobInput(jobID string, localPath string) error {
	if !sm.enabled {
		return fmt.Errorf("S3 non abilitato")
	}

	s3Prefix := fmt.Sprintf("jobs/%s/input/", jobID)
	files, err := sm.client.ListFiles(s3Prefix)
	if err != nil {
		return err
	}

	for _, file := range files {
		// Estrai il nome del file dalla chiave S3
		fileName := strings.TrimPrefix(file, s3Prefix)
		localFilePath := filepath.Join(localPath, fileName)

		if err := sm.client.DownloadFile(file, localFilePath); err != nil {
			fmt.Printf("Errore download %s: %v\n", file, err)
		}
	}

	return nil
}

// BackupClusterData esegue un backup completo dei dati del cluster
func (sm *S3StorageManager) BackupClusterData() error {
	if !sm.enabled {
		return fmt.Errorf("S3 non abilitato")
	}

	fmt.Println("Eseguendo backup completo del cluster su S3...")
	return sm.syncService.BackupNow()
}

// RestoreFromBackup ripristina i dati da un backup S3
func (sm *S3StorageManager) RestoreFromBackup(backupTimestamp string, localPath string) error {
	if !sm.enabled {
		return fmt.Errorf("S3 non abilitato")
	}

	backupPrefix := fmt.Sprintf("backups/%s/", backupTimestamp)
	files, err := sm.client.ListFiles(backupPrefix)
	if err != nil {
		return err
	}

	for _, file := range files {
		// Estrai il percorso relativo
		relPath := strings.TrimPrefix(file, backupPrefix)
		localFilePath := filepath.Join(localPath, relPath)

		if err := sm.client.DownloadFile(file, localFilePath); err != nil {
			fmt.Printf("Errore restore %s: %v\n", file, err)
		}
	}

	fmt.Printf("Ripristino completato da backup %s\n", backupTimestamp)
	return nil
}

// ListBackups elenca i backup disponibili
func (sm *S3StorageManager) ListBackups() ([]string, error) {
	if !sm.enabled {
		return nil, fmt.Errorf("S3 non abilitato")
	}

	return sm.client.ListFiles("backups/")
}

// GetStorageStats restituisce le statistiche dello storage S3
func (sm *S3StorageManager) GetStorageStats() map[string]interface{} {
	stats := map[string]interface{}{
		"enabled": sm.enabled,
		"bucket":  sm.config.Bucket,
		"region":  sm.config.Region,
	}

	if sm.enabled {
		// Conta i file per categoria
		outputFiles, _ := sm.client.ListFiles("output/")
		intermediateFiles, _ := sm.client.ListFiles("intermediate/")
		backupFiles, _ := sm.client.ListFiles("backups/")
		logFiles, _ := sm.client.ListFiles("logs/")

		stats["files"] = map[string]interface{}{
			"output":       len(outputFiles),
			"intermediate": len(intermediateFiles),
			"backups":      len(backupFiles),
			"logs":         len(logFiles),
		}
	}

	return stats
}
