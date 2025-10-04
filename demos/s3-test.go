package main

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// Test S3 Configuration
func main() {
	fmt.Println("🧪 TEST CONFIGURAZIONE S3")
	fmt.Println("============================================================")

	// 1. Verifica variabili d'ambiente
	fmt.Println("\n📋 1. Verifica Variabili d'Ambiente")
	fmt.Println("----------------------------------------")

	envVars := []string{
		"AWS_REGION",
		"AWS_S3_BUCKET",
		"S3_SYNC_ENABLED",
		"S3_SYNC_INTERVAL",
	}

	for _, envVar := range envVars {
		value := os.Getenv(envVar)
		if value == "" {
			fmt.Printf("   ❌ %s: NON IMPOSTATA\n", envVar)
		} else {
			fmt.Printf("   ✅ %s: %s\n", envVar, value)
		}
	}

	// 2. Test configurazione S3
	fmt.Println("\n🔧 2. Test Configurazione S3")
	fmt.Println("----------------------------------------")

	s3Config := GetS3ConfigFromEnv()
	fmt.Printf("   Bucket: %s\n", s3Config.Bucket)
	fmt.Printf("   Region: %s\n", s3Config.Region)
	fmt.Printf("   Enabled: %v\n", s3Config.Enabled)
	fmt.Printf("   Sync Interval: %v\n", s3Config.SyncInterval)

	// 3. Test creazione client S3
	fmt.Println("\n🌐 3. Test Connessione S3")
	fmt.Println("----------------------------------------")

	client, err := NewS3Client(s3Config)
	if err != nil {
		fmt.Printf("   ❌ Errore creazione client S3: %v\n", err)
		fmt.Println("\n💡 SOLUZIONI:")
		fmt.Println("   1. Verifica AWS credentials")
		fmt.Println("   2. Controlla permessi IAM")
		fmt.Println("   3. Verifica bucket esistente")
		return
	}
	fmt.Println("   ✅ Client S3 creato con successo")

	// 4. Test operazioni S3
	fmt.Println("\n📁 4. Test Operazioni S3")
	fmt.Println("----------------------------------------")

	// Test upload file
	testFile := "/tmp/s3-test.txt"
	testContent := fmt.Sprintf("Test S3 - %s", time.Now().Format(time.RFC3339))

	err = os.WriteFile(testFile, []byte(testContent), 0644)
	if err != nil {
		fmt.Printf("   ❌ Errore creazione file test: %v\n", err)
		return
	}
	fmt.Println("   ✅ File test creato")

	// Test upload
	s3Key := fmt.Sprintf("test/s3-test-%d.txt", time.Now().Unix())
	err = client.UploadFile(testFile, s3Key)
	if err != nil {
		fmt.Printf("   ❌ Errore upload: %v\n", err)
	} else {
		fmt.Println("   ✅ Upload completato")
	}

	// Test list files
	files, err := client.ListFiles("test/")
	if err != nil {
		fmt.Printf("   ❌ Errore list files: %v\n", err)
	} else {
		fmt.Printf("   ✅ File trovati: %d\n", len(files))
		for _, file := range files {
			fmt.Printf("      - %s\n", file)
		}
	}

	// Test download
	downloadFile := "/tmp/s3-downloaded.txt"
	err = client.DownloadFile(s3Key, downloadFile)
	if err != nil {
		fmt.Printf("   ❌ Errore download: %v\n", err)
	} else {
		fmt.Println("   ✅ Download completato")

		// Verifica contenuto
		content, err := os.ReadFile(downloadFile)
		if err != nil {
			fmt.Printf("   ❌ Errore lettura file scaricato: %v\n", err)
		} else if string(content) == testContent {
			fmt.Println("   ✅ Contenuto file verificato")
		} else {
			fmt.Println("   ❌ Contenuto file non corrisponde")
		}
	}

	// Test delete
	err = client.DeleteFile(s3Key)
	if err != nil {
		fmt.Printf("   ❌ Errore eliminazione: %v\n", err)
	} else {
		fmt.Println("   ✅ File eliminato")
	}

	// 5. Test S3 Storage Manager
	fmt.Println("\n🔄 5. Test S3 Storage Manager")
	fmt.Println("----------------------------------------")

	storageManager, err := NewS3StorageManager(s3Config)
	if err != nil {
		fmt.Printf("   ❌ Errore creazione storage manager: %v\n", err)
		return
	}
	fmt.Println("   ✅ Storage manager creato")

	// Test statistiche
	stats := storageManager.GetStorageStats()
	fmt.Printf("   📊 Statistiche Storage:\n")
	for key, value := range stats {
		fmt.Printf("      %s: %v\n", key, value)
	}

	// 6. Test backup
	fmt.Println("\n💾 6. Test Backup S3")
	fmt.Println("----------------------------------------")

	// Crea directory test per backup
	testDir := "/tmp/mapreduce-test"
	err = os.MkdirAll(testDir, 0755)
	if err != nil {
		fmt.Printf("   ❌ Errore creazione directory test: %v\n", err)
		return
	}

	// Crea file test
	testFiles := []string{"output/test1.txt", "intermediate/test2.txt", "logs/test3.txt"}
	for _, file := range testFiles {
		filePath := fmt.Sprintf("%s/%s", testDir, file)
		err = os.MkdirAll(fmt.Sprintf("%s/%s", testDir, file[:len(file)-len(file[strings.LastIndex(file, "/"):])]), 0755)
		if err != nil {
			continue
		}
		err = os.WriteFile(filePath, []byte(fmt.Sprintf("Test content for %s", file)), 0644)
		if err != nil {
			fmt.Printf("   ❌ Errore creazione file %s: %v\n", file, err)
		}
	}
	fmt.Println("   ✅ File test creati per backup")

	// Test backup
	err = storageManager.BackupClusterData()
	if err != nil {
		fmt.Printf("   ❌ Errore backup: %v\n", err)
	} else {
		fmt.Println("   ✅ Backup completato")
	}

	// Test list backups
	backups, err := storageManager.ListBackups()
	if err != nil {
		fmt.Printf("   ❌ Errore list backups: %v\n", err)
	} else {
		fmt.Printf("   ✅ Backup trovati: %d\n", len(backups))
		for _, backup := range backups {
			fmt.Printf("      - %s\n", backup)
		}
	}

	// 7. Cleanup
	fmt.Println("\n🧹 7. Cleanup")
	fmt.Println("----------------------------------------")

	// Rimuovi file test
	os.Remove(testFile)
	os.Remove(downloadFile)
	os.RemoveAll(testDir)
	fmt.Println("   ✅ File test rimossi")

	// 8. Risultato finale
	fmt.Println("\n🎉 RISULTATO FINALE")
	fmt.Println("============================================================")

	if s3Config.Enabled && s3Config.Bucket != "" {
		fmt.Println("✅ S3 Storage configurato correttamente")
		fmt.Printf("   Bucket: %s\n", s3Config.Bucket)
		fmt.Printf("   Region: %s\n", s3Config.Region)
		fmt.Printf("   Sync Interval: %v\n", s3Config.SyncInterval)
	} else {
		fmt.Println("❌ S3 Storage non configurato")
		fmt.Println("   Imposta le variabili d'ambiente necessarie")
	}

	fmt.Println("\n💡 PROSSIMI PASSI:")
	fmt.Println("   1. Configura AWS credentials")
	fmt.Println("   2. Crea bucket S3")
	fmt.Println("   3. Imposta permessi IAM")
	fmt.Println("   4. Avvia servizio MapReduce")
	fmt.Println("   5. Verifica dashboard S3")
}
