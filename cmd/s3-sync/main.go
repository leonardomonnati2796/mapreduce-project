package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
)

type S3SyncConfig struct {
	Bucket     string
	Region     string
	LocalPath  string
	Interval   time.Duration
	BackupMode bool
}

func main() {
	var config S3SyncConfig

	flag.StringVar(&config.Bucket, "bucket", os.Getenv("AWS_S3_BUCKET"), "S3 bucket name")
	flag.StringVar(&config.Region, "region", os.Getenv("AWS_REGION"), "AWS region")
	flag.StringVar(&config.LocalPath, "path", "/tmp/mapreduce", "Local path to sync")
	flag.DurationVar(&config.Interval, "interval", 60*time.Second, "Sync interval")
	flag.BoolVar(&config.BackupMode, "backup", false, "Enable backup mode")
	flag.Parse()

	if config.Bucket == "" {
		log.Fatal("S3 bucket not specified")
	}

	if config.Region == "" {
		config.Region = "us-east-1"
	}

	fmt.Printf("S3 Sync Service starting...\n")
	fmt.Printf("Bucket: %s\n", config.Bucket)
	fmt.Printf("Region: %s\n", config.Region)
	fmt.Printf("Local Path: %s\n", config.LocalPath)
	fmt.Printf("Interval: %v\n", config.Interval)
	fmt.Printf("Backup Mode: %v\n", config.BackupMode)

	// Crea sessione AWS
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(config.Region),
	})
	if err != nil {
		log.Fatalf("Failed to create AWS session: %v", err)
	}

	s3Client := s3.New(sess)
	uploader := s3manager.NewUploader(sess)
	downloader := s3manager.NewDownloader(sess)

	syncService := &S3SyncService{
		config:     config,
		s3Client:   s3Client,
		uploader:   uploader,
		downloader: downloader,
	}

	if config.BackupMode {
		// Modalità backup - esegui una volta e esci
		if err := syncService.BackupToS3(); err != nil {
			log.Fatalf("Backup failed: %v", err)
		}
		fmt.Println("Backup completed successfully")
		return
	}

	// Modalità continua - sincronizza periodicamente
	ticker := time.NewTicker(config.Interval)
	defer ticker.Stop()

	// Sincronizza immediatamente all'avvio
	if err := syncService.SyncToS3(); err != nil {
		log.Printf("Initial sync failed: %v", err)
	}

	fmt.Println("Starting periodic sync...")
	for range ticker.C {
		if err := syncService.SyncToS3(); err != nil {
			log.Printf("Sync failed: %v", err)
		}
	}
}

type S3SyncService struct {
	config     S3SyncConfig
	s3Client   *s3.S3
	uploader   *s3manager.Uploader
	downloader *s3manager.Downloader
}

func (s *S3SyncService) SyncToS3() error {
	fmt.Printf("Starting sync to S3 at %s\n", time.Now().Format(time.RFC3339))

	// Sincronizza file di output
	if err := s.syncDirectory("output", "output/"); err != nil {
		return fmt.Errorf("failed to sync output: %v", err)
	}

	// Sincronizza file intermedi
	if err := s.syncDirectory("intermediate", "intermediate/"); err != nil {
		return fmt.Errorf("failed to sync intermediate: %v", err)
	}

	// Sincronizza file di log
	if err := s.syncDirectory("logs", "logs/"); err != nil {
		return fmt.Errorf("failed to sync logs: %v", err)
	}

	fmt.Println("Sync completed successfully")
	return nil
}

func (s *S3SyncService) BackupToS3() error {
	fmt.Printf("Starting backup to S3 at %s\n", time.Now().Format(time.RFC3339))

	// Crea un backup con timestamp
	timestamp := time.Now().Format("2006-01-02-15-04-05")
	backupPrefix := fmt.Sprintf("backups/%s/", timestamp)

	// Backup completo della directory
	return s.syncDirectoryWithPrefix("", backupPrefix)
}

func (s *S3SyncService) syncDirectory(localSubDir, s3Prefix string) error {
	localPath := filepath.Join(s.config.LocalPath, localSubDir)
	
	// Verifica se la directory locale esiste
	if _, err := os.Stat(localPath); os.IsNotExist(err) {
		fmt.Printf("Directory %s does not exist, skipping\n", localPath)
		return nil
	}

	return s.syncDirectoryWithPrefix(localSubDir, s3Prefix)
}

func (s *S3SyncService) syncDirectoryWithPrefix(localSubDir, s3Prefix string) error {
	localPath := filepath.Join(s.config.LocalPath, localSubDir)
	
	// Verifica se la directory locale esiste
	if _, err := os.Stat(localPath); os.IsNotExist(err) {
		fmt.Printf("Directory %s does not exist, skipping\n", localPath)
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
		relPath, err := filepath.Rel(s.config.LocalPath, path)
		if err != nil {
			return err
		}

		// Crea la chiave S3
		s3Key := s3Prefix + strings.ReplaceAll(relPath, "\\", "/")

		// Upload del file
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()

		_, err = s.uploader.Upload(&s3manager.UploadInput{
			Bucket: aws.String(s.config.Bucket),
			Key:    aws.String(s3Key),
			Body:   file,
		})

		if err != nil {
			return fmt.Errorf("failed to upload %s: %v", s3Key, err)
		}

		fmt.Printf("Uploaded: %s -> s3://%s/%s\n", path, s.config.Bucket, s3Key)
		return nil
	})
}

func (s *S3SyncService) DownloadFromS3(s3Key, localPath string) error {
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
		Bucket: aws.String(s.config.Bucket),
		Key:    aws.String(s3Key),
	})

	if err != nil {
		return fmt.Errorf("failed to download %s: %v", s3Key, err)
	}

	fmt.Printf("Downloaded: s3://%s/%s -> %s\n", s.config.Bucket, s3Key, localPath)
	return nil
}
