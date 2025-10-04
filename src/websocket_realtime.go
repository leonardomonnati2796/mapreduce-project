package main

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// WebSocketManager gestisce le connessioni WebSocket e gli aggiornamenti real-time
type WebSocketManager struct {
	// Connessioni attive
	clients      map[*websocket.Conn]*WebSocketClient
	clientsMutex sync.RWMutex
	
	// Canali per comunicazione
	broadcast    chan []byte
	register     chan *WebSocketClient
	unregister   chan *WebSocketClient
	
	// Configurazione
	upgrader     websocket.Upgrader
	pingPeriod   time.Duration
	pongWait     time.Duration
	writeWait    time.Duration
	
	// Metriche
	messageCount    int64
	connectionCount int64
	errorCount      int64
	
	// Sottoscrizioni per tipi di messaggi
	subscriptions map[string]map[*websocket.Conn]bool
	subMutex      sync.RWMutex
}

// WebSocketClient rappresenta un client WebSocket connesso
type WebSocketClient struct {
	conn     *websocket.Conn
	send     chan []byte
	manager  *WebSocketManager
	userID   string
	lastPing time.Time
	subscribedTo []string
}

// WebSocketMessage rappresenta un messaggio WebSocket
type WebSocketMessage struct {
	Type      string                 `json:"type"`
	Timestamp time.Time              `json:"timestamp"`
	Data      interface{}            `json:"data"`
	UserID    string                 `json:"user_id,omitempty"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// NewWebSocketManager crea un nuovo manager WebSocket
func NewWebSocketManager() *WebSocketManager {
	return &WebSocketManager{
		clients:      make(map[*websocket.Conn]*WebSocketClient),
		broadcast:    make(chan []byte, 256),
		register:     make(chan *WebSocketClient),
		unregister:   make(chan *WebSocketClient),
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				return true // In produzione, implementare controllo origin
			},
		},
		pingPeriod: 54 * time.Second,
		pongWait:   60 * time.Second,
		writeWait:  10 * time.Second,
		subscriptions: make(map[string]map[*websocket.Conn]bool),
	}
}

// Start avvia il manager WebSocket
func (wm *WebSocketManager) Start() {
	LogInfo("WebSocket Manager started")
	
	for {
		select {
		case client := <-wm.register:
			wm.registerClient(client)
			
		case client := <-wm.unregister:
			wm.unregisterClient(client)
			
		case message := <-wm.broadcast:
			wm.broadcastMessage(message)
		}
	}
}

// registerClient registra un nuovo client
func (wm *WebSocketManager) registerClient(client *WebSocketClient) {
	wm.clientsMutex.Lock()
	defer wm.clientsMutex.Unlock()
	
	wm.clients[client.conn] = client
	wm.connectionCount++
	
	LogInfo("WebSocket client registered. Total clients: %d", len(wm.clients))
	
	// Invia messaggio di benvenuto
	welcomeMsg := WebSocketMessage{
		Type:      "welcome",
		Timestamp: time.Now(),
		Data: map[string]interface{}{
			"message": "Connected to MapReduce Dashboard",
			"version": "1.0.0",
			"features": []string{"realtime_updates", "metrics", "jobs", "workers", "masters"},
		},
	}
	
	wm.sendToClient(client, welcomeMsg)
}

// unregisterClient rimuove un client
func (wm *WebSocketManager) unregisterClient(client *WebSocketClient) {
	wm.clientsMutex.Lock()
	defer wm.clientsMutex.Unlock()
	
	if _, ok := wm.clients[client.conn]; ok {
		delete(wm.clients, client.conn)
		close(client.send)
		wm.connectionCount--
		
		// Rimuovi dalle sottoscrizioni
		wm.subMutex.Lock()
		for _, topic := range client.subscribedTo {
			if subs, exists := wm.subscriptions[topic]; exists {
				delete(subs, client.conn)
			}
		}
		wm.subMutex.Unlock()
		
		LogInfo("WebSocket client unregistered. Total clients: %d", len(wm.clients))
	}
}

// broadcastMessage invia un messaggio a tutti i client
func (wm *WebSocketManager) broadcastMessage(message []byte) {
	wm.clientsMutex.RLock()
	defer wm.clientsMutex.RUnlock()
	
	for _, client := range wm.clients {
		select {
		case client.send <- message:
		default:
			// Se il canale è pieno, chiudi la connessione
			close(client.send)
			delete(wm.clients, client.conn)
		}
	}
}

// BroadcastToTopic invia un messaggio a client sottoscritti a un topic specifico
func (wm *WebSocketManager) BroadcastToTopic(topic string, message WebSocketMessage) {
	wm.subMutex.RLock()
	subscribers, exists := wm.subscriptions[topic]
	wm.subMutex.RUnlock()
	
	if !exists || len(subscribers) == 0 {
		return
	}
	
	messageBytes, err := json.Marshal(message)
	if err != nil {
		LogError("Error marshaling WebSocket message: %v", err)
		return
	}
	
	wm.clientsMutex.RLock()
	defer wm.clientsMutex.RUnlock()
	
	for conn := range subscribers {
		if client, exists := wm.clients[conn]; exists {
			select {
			case client.send <- messageBytes:
			default:
				// Client non risponde, rimuovilo
				delete(wm.clients, conn)
			}
		}
	}
}

// sendToClient invia un messaggio a un client specifico
func (wm *WebSocketManager) sendToClient(client *WebSocketClient, message WebSocketMessage) {
	messageBytes, err := json.Marshal(message)
	if err != nil {
		LogError("Error marshaling WebSocket message: %v", err)
		return
	}
	
	select {
	case client.send <- messageBytes:
	default:
		// Client non risponde, chiudi connessione
		close(client.send)
	}
}

// SubscribeToTopic sottoscrive un client a un topic
func (wm *WebSocketManager) SubscribeToTopic(client *WebSocketClient, topic string) {
	wm.subMutex.Lock()
	defer wm.subMutex.Unlock()
	
	if wm.subscriptions[topic] == nil {
		wm.subscriptions[topic] = make(map[*websocket.Conn]bool)
	}
	
	wm.subscriptions[topic][client.conn] = true
	client.subscribedTo = append(client.subscribedTo, topic)
	
	LogDebug("Client subscribed to topic: %s", topic)
}

// UnsubscribeFromTopic rimuove la sottoscrizione di un client da un topic
func (wm *WebSocketManager) UnsubscribeFromTopic(client *WebSocketClient, topic string) {
	wm.subMutex.Lock()
	defer wm.subMutex.Unlock()
	
	if subs, exists := wm.subscriptions[topic]; exists {
		delete(subs, client.conn)
	}
	
	// Rimuovi dal slice delle sottoscrizioni del client
	for i, t := range client.subscribedTo {
		if t == topic {
			client.subscribedTo = append(client.subscribedTo[:i], client.subscribedTo[i+1:]...)
			break
		}
	}
	
	LogDebug("Client unsubscribed from topic: %s", topic)
}

// GetStats restituisce le statistiche del WebSocket manager
func (wm *WebSocketManager) GetStats() map[string]interface{} {
	wm.clientsMutex.RLock()
	defer wm.clientsMutex.RUnlock()
	
	wm.subMutex.RLock()
	topicCount := len(wm.subscriptions)
	wm.subMutex.RUnlock()
	
	return map[string]interface{}{
		"active_connections": len(wm.clients),
		"total_connections":  wm.connectionCount,
		"message_count":     wm.messageCount,
		"error_count":       wm.errorCount,
		"topics_count":      topicCount,
		"uptime":           time.Since(time.Now()).String(), // Sarebbe meglio tracciare il tempo di avvio
	}
}

// BroadcastRealtimeUpdate invia un aggiornamento real-time
func (wm *WebSocketManager) BroadcastRealtimeUpdate(updateType string, data interface{}) {
	message := WebSocketMessage{
		Type:      updateType,
		Timestamp: time.Now(),
		Data:      data,
		Metadata: map[string]interface{}{
			"source": "dashboard",
			"version": "1.0.0",
		},
	}
	
	messageBytes, err := json.Marshal(message)
	if err != nil {
		LogError("Error marshaling realtime update: %v", err)
		return
	}
	
	select {
	case wm.broadcast <- messageBytes:
		wm.messageCount++
	default:
		// Canale pieno, salta questo aggiornamento
		LogWarn("WebSocket broadcast channel full, skipping update")
	}
}

// BroadcastMetricsUpdate invia un aggiornamento delle metriche
func (wm *WebSocketManager) BroadcastMetricsUpdate(metrics map[string]interface{}) {
	wm.BroadcastToTopic("metrics", WebSocketMessage{
		Type:      "metrics_update",
		Timestamp: time.Now(),
		Data:      metrics,
	})
}

// BroadcastJobUpdate invia un aggiornamento dei job
func (wm *WebSocketManager) BroadcastJobUpdate(jobs []JobInfo) {
	wm.BroadcastToTopic("jobs", WebSocketMessage{
		Type:      "jobs_update",
		Timestamp: time.Now(),
		Data:      jobs,
	})
}

// BroadcastWorkerUpdate invia un aggiornamento dei worker
func (wm *WebSocketManager) BroadcastWorkerUpdate(workers []WorkerInfoDashboard) {
	wm.BroadcastToTopic("workers", WebSocketMessage{
		Type:      "workers_update",
		Timestamp: time.Now(),
		Data:      workers,
	})
}

// BroadcastMasterUpdate invia un aggiornamento dei master
func (wm *WebSocketManager) BroadcastMasterUpdate(masters []MasterInfo) {
	wm.BroadcastToTopic("masters", WebSocketMessage{
		Type:      "masters_update",
		Timestamp: time.Now(),
		Data:      masters,
	})
}

// BroadcastSystemHealthUpdate invia un aggiornamento dello stato di salute
func (wm *WebSocketManager) BroadcastSystemHealthUpdate(health HealthStatus) {
	wm.BroadcastToTopic("health", WebSocketMessage{
		Type:      "health_update",
		Timestamp: time.Now(),
		Data:      health,
	})
}

// BroadcastPerformanceUpdate invia un aggiornamento delle performance
func (wm *WebSocketManager) BroadcastPerformanceUpdate(performance map[string]interface{}) {
	wm.BroadcastToTopic("performance", WebSocketMessage{
		Type:      "performance_update",
		Timestamp: time.Now(),
		Data:      performance,
	})
}
