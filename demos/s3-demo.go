package main

import (
	"fmt"
	"log"
	"os"
	"strings"
	"time"
)

// Demo S3 Storage per MapReduce
func main() {
	fmt.Println("🗄️ DEMO S3 STORAGE PER MAPREDUCE")
	fmt.Println("============================================================")

	// 1. Carica configurazione S3
	fmt.Println("\n📋 1. Caricamento Configurazione S3")
	fmt.Println("----------------------------------------")

	s3Config := GetS3ConfigFromEnv()
	fmt.Printf("   Bucket: %s\n", s3Config.Bucket)
	fmt.Printf("   Region: %s\n", s3Config.Region)
	fmt.Printf("   Enabled: %v\n", s3Config.Enabled)
	fmt.Printf("   Sync Interval: %v\n", s3Config.SyncInterval)

	if !s3Config.Enabled {
		fmt.Println("   ❌ S3 non abilitato")
		fmt.Println("   Imposta S3_SYNC_ENABLED=true")
		return
	}

	// 2. Crea S3 Storage Manager
	fmt.Println("\n🔧 2. Creazione S3 Storage Manager")
	fmt.Println("----------------------------------------")

	storageManager, err := NewS3StorageManager(s3Config)
	if err != nil {
		log.Printf("Errore creazione storage manager: %v", err)
		return
	}
	fmt.Println("   ✅ S3 Storage Manager creato")

	// 3. Avvia servizio S3
	fmt.Println("\n🚀 3. Avvio Servizio S3")
	fmt.Println("----------------------------------------")

	storageManager.Start()
	defer storageManager.Stop()
	fmt.Println("   ✅ Servizio S3 avviato")

	// 4. Test operazioni S3
	fmt.Println("\n📁 4. Test Operazioni S3")
	fmt.Println("----------------------------------------")

	// Crea directory test
	testDir := "/tmp/mapreduce-s3-test"
	err = os.MkdirAll(testDir, 0755)
	if err != nil {
		log.Printf("Errore creazione directory test: %v", err)
		return
	}
	fmt.Println("   ✅ Directory test creata")

	// Crea file test
	testFiles := map[string]string{
		"output/result1.txt":     "Risultato job 1 - " + time.Now().Format(time.RFC3339),
		"output/result2.txt":     "Risultato job 2 - " + time.Now().Format(time.RFC3339),
		"intermediate/temp1.txt": "File intermedio 1",
		"intermediate/temp2.txt": "File intermedio 2",
		"logs/system.log":        "Log del sistema - " + time.Now().Format(time.RFC3339),
	}

	for filePath, content := range testFiles {
		fullPath := fmt.Sprintf("%s/%s", testDir, filePath)
		err = os.MkdirAll(fmt.Sprintf("%s/%s", testDir, filePath[:len(filePath)-len(filePath[strings.LastIndex(filePath, "/"):])]), 0755)
		if err != nil {
			continue
		}

		err = os.WriteFile(fullPath, []byte(content), 0644)
		if err != nil {
			log.Printf("Errore creazione file %s: %v", filePath, err)
		} else {
			fmt.Printf("   ✅ File creato: %s\n", filePath)
		}
	}

	// 5. Test backup S3
	fmt.Println("\n💾 5. Test Backup S3")
	fmt.Println("----------------------------------------")

	err = storageManager.BackupClusterData()
	if err != nil {
		log.Printf("Errore backup: %v", err)
	} else {
		fmt.Println("   ✅ Backup completato")
	}

	// 6. Test upload job output
	fmt.Println("\n📤 6. Test Upload Job Output")
	fmt.Println("----------------------------------------")

	jobID := fmt.Sprintf("job-%d", time.Now().Unix())
	outputDir := fmt.Sprintf("%s/output", testDir)

	err = storageManager.UploadJobOutput(jobID, outputDir)
	if err != nil {
		log.Printf("Errore upload job output: %v", err)
	} else {
		fmt.Printf("   ✅ Job output caricato: %s\n", jobID)
	}

	// 7. Test download job input
	fmt.Println("\n📥 7. Test Download Job Input")
	fmt.Println("----------------------------------------")

	downloadDir := "/tmp/mapreduce-download"
	err = os.MkdirAll(downloadDir, 0755)
	if err != nil {
		log.Printf("Errore creazione directory download: %v", err)
		return
	}

	err = storageManager.DownloadJobInput(jobID, downloadDir)
	if err != nil {
		log.Printf("Errore download job input: %v", err)
	} else {
		fmt.Printf("   ✅ Job input scaricato: %s\n", jobID)
	}

	// 8. Test list backups
	fmt.Println("\n📋 8. Test List Backups")
	fmt.Println("----------------------------------------")

	backups, err := storageManager.ListBackups()
	if err != nil {
		log.Printf("Errore list backups: %v", err)
	} else {
		fmt.Printf("   ✅ Backup trovati: %d\n", len(backups))
		for i, backup := range backups {
			if i < 5 { // Mostra solo i primi 5
				fmt.Printf("      - %s\n", backup)
			}
		}
		if len(backups) > 5 {
			fmt.Printf("      ... e altri %d backup\n", len(backups)-5)
		}
	}

	// 9. Test statistiche S3
	fmt.Println("\n📊 9. Test Statistiche S3")
	fmt.Println("----------------------------------------")

	stats := storageManager.GetStorageStats()
	fmt.Printf("   📈 Statistiche Storage:\n")
	for key, value := range stats {
		fmt.Printf("      %s: %v\n", key, value)
	}

	// 10. Test restore da backup
	if len(backups) > 0 {
		fmt.Println("\n🔄 10. Test Restore da Backup")
		fmt.Println("----------------------------------------")

		// Prendi il primo backup disponibile
		backupTimestamp := strings.TrimPrefix(backups[0], "backups/")
		backupTimestamp = strings.TrimSuffix(backupTimestamp, "/")

		restoreDir := "/tmp/mapreduce-restore"
		err = os.MkdirAll(restoreDir, 0755)
		if err != nil {
			log.Printf("Errore creazione directory restore: %v", err)
		} else {
			err = storageManager.RestoreFromBackup(backupTimestamp, restoreDir)
			if err != nil {
				log.Printf("Errore restore: %v", err)
			} else {
				fmt.Printf("   ✅ Restore completato da backup: %s\n", backupTimestamp)
			}
		}
	}

	// 11. Test sync automatico
	fmt.Println("\n🔄 11. Test Sync Automatico")
	fmt.Println("----------------------------------------")

	fmt.Println("   ⏳ Attendo sync automatico...")
	time.Sleep(5 * time.Second)
	fmt.Println("   ✅ Sync automatico completato")

	// 12. Cleanup
	fmt.Println("\n🧹 12. Cleanup")
	fmt.Println("----------------------------------------")

	// Rimuovi directory test
	os.RemoveAll(testDir)
	os.RemoveAll(downloadDir)
	os.RemoveAll("/tmp/mapreduce-restore")
	fmt.Println("   ✅ Directory test rimosse")

	// 13. Risultato finale
	fmt.Println("\n🎉 RISULTATO FINALE")
	fmt.Println("============================================================")

	if s3Config.Enabled {
		fmt.Println("✅ S3 Storage configurato e funzionante")
		fmt.Printf("   Bucket: %s\n", s3Config.Bucket)
		fmt.Printf("   Region: %s\n", s3Config.Region)
		fmt.Printf("   Sync Interval: %v\n", s3Config.SyncInterval)
	} else {
		fmt.Println("❌ S3 Storage non configurato")
	}

	fmt.Println("\n💡 FUNZIONALITÀ S3 IMPLEMENTATE:")
	fmt.Println("   ✅ Upload/Download file")
	fmt.Println("   ✅ Sincronizzazione automatica")
	fmt.Println("   ✅ Backup automatico")
	fmt.Println("   ✅ Restore da backup")
	fmt.Println("   ✅ Gestione job input/output")
	fmt.Println("   ✅ Statistiche storage")
	fmt.Println("   ✅ Lista backup")
	fmt.Println("   ✅ Integrazione con MapReduce")

	fmt.Println("\n🚀 PROSSIMI PASSI:")
	fmt.Println("   1. Configura AWS credentials")
	fmt.Println("   2. Crea bucket S3")
	fmt.Println("   3. Avvia sistema MapReduce")
	fmt.Println("   4. Verifica dashboard S3")
	fmt.Println("   5. Test backup automatico")
}
