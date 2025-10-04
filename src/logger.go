package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"
)

// LogLevel è definito in constants.go

// Logger gestisce il logging strutturato
type Logger struct {
	level    LogLevel
	infoLog  *log.Logger
	warnLog  *log.Logger
	errorLog *log.Logger
	debugLog *log.Logger
}

var globalLogger *Logger

// InitLogger inizializza il logger globale
func InitLogger(level LogLevel, logFile string) error {
	var writers []io.Writer

	// Output su console
	writers = append(writers, os.Stdout)

	// Output su file se specificato
	if logFile != "" {
		// Crea directory se non esiste
		if err := os.MkdirAll(filepath.Dir(logFile), 0755); err != nil {
			return fmt.Errorf("errore creazione directory log: %v", err)
		}

		file, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
		if err != nil {
			return fmt.Errorf("errore apertura file log: %v", err)
		}
		writers = append(writers, file)
	}

	multiWriter := io.MultiWriter(writers...)

	globalLogger = &Logger{
		level:    level,
		infoLog:  log.New(multiWriter, "[INFO] ", log.LstdFlags|log.Lshortfile),
		warnLog:  log.New(multiWriter, "[WARN] ", log.LstdFlags|log.Lshortfile),
		errorLog: log.New(multiWriter, "[ERROR] ", log.LstdFlags|log.Lshortfile),
		debugLog: log.New(multiWriter, "[DEBUG] ", log.LstdFlags|log.Lshortfile),
	}

	return nil
}

// GetLogger restituisce il logger globale
func GetLogger() *Logger {
	if globalLogger == nil {
		// Logger di default
		InitLogger(INFO, "")
	}
	return globalLogger
}

// Debug logga un messaggio di debug
func (l *Logger) Debug(format string, v ...interface{}) {
	if l.level <= DEBUG {
		l.debugLog.Printf(format, v...)
	}
}

// Info logga un messaggio informativo
func (l *Logger) Info(format string, v ...interface{}) {
	if l.level <= INFO {
		l.infoLog.Printf(format, v...)
	}
}

// Warn logga un messaggio di warning
func (l *Logger) Warn(format string, v ...interface{}) {
	if l.level <= WARN {
		l.warnLog.Printf(format, v...)
	}
}

// Error logga un messaggio di errore
func (l *Logger) Error(format string, v ...interface{}) {
	if l.level <= ERROR {
		l.errorLog.Printf(format, v...)
	}
}

// Fatal logga un messaggio fatale e termina
func (l *Logger) Fatal(format string, v ...interface{}) {
	l.errorLog.Printf(format, v...)
	os.Exit(1)
}

// Funzioni globali per compatibilità
func LogDebug(format string, v ...interface{}) {
	GetLogger().Debug(format, v...)
}

func LogInfo(format string, v ...interface{}) {
	GetLogger().Info(format, v...)
}

func LogWarn(format string, v ...interface{}) {
	GetLogger().Warn(format, v...)
}

func LogError(format string, v ...interface{}) {
	GetLogger().Error(format, v...)
}

func LogFatal(format string, v ...interface{}) {
	GetLogger().Fatal(format, v...)
}

// LogStructured logga un messaggio strutturato
func LogStructured(level LogLevel, component, message string, fields map[string]interface{}) {
	logger := GetLogger()

	// Crea messaggio strutturato
	structuredMsg := fmt.Sprintf("[%s] %s", component, message)

	// Aggiungi campi se presenti
	if len(fields) > 0 {
		structuredMsg += " | "
		first := true
		for key, value := range fields {
			if !first {
				structuredMsg += ", "
			}
			structuredMsg += fmt.Sprintf("%s=%v", key, value)
			first = false
		}
	}

	// Logga con il livello appropriato
	switch level {
	case DEBUG:
		logger.Debug(structuredMsg)
	case INFO:
		logger.Info(structuredMsg)
	case WARN:
		logger.Warn(structuredMsg)
	case ERROR:
		logger.Error(structuredMsg)
	}
}

// LogPerformance logga metriche di performance
func LogPerformance(operation string, duration time.Duration, fields map[string]interface{}) {
	if fields == nil {
		fields = make(map[string]interface{})
	}
	fields["duration_ms"] = duration.Milliseconds()
	fields["operation"] = operation

	LogStructured(INFO, "PERFORMANCE", fmt.Sprintf("Operation %s completed", operation), fields)
}

// LogError logga un errore con contesto
func LogErrorWithContext(err error, component, operation string, fields map[string]interface{}) {
	if fields == nil {
		fields = make(map[string]interface{})
	}
	fields["error"] = err.Error()
	fields["component"] = component
	fields["operation"] = operation

	LogStructured(ERROR, component, fmt.Sprintf("Error in %s: %v", operation, err), fields)
}
