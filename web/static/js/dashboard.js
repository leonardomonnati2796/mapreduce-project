// MapReduce Dashboard - Common JavaScript Functions

// Global variables
let refreshInterval;
let isAutoRefreshEnabled = true;
let showAllWorkers = false;
const DEFAULT_WORKERS_LIMIT = 20;

// WebSocket variables
let websocket = null;
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 5;
const RECONNECT_DELAY = 3000; // 3 seconds

// Initialize dashboard
function initDashboard() {
    console.log('Initializing MapReduce Dashboard...');
    
    // Initialize WebSocket connection
    initWebSocket();
    
    // Start auto-refresh (will be disabled when WebSocket is active)
    startAutoRefresh();
    
    // Add fade-in animations
    addFadeInAnimations();
    
    // Initialize tooltips
    initTooltips();
    
    // Setup event listeners
    setupEventListeners();
    
    console.log('Dashboard initialized successfully');
}

// ===== WEBSOCKET FUNCTIONS =====

// Initialize WebSocket connection
function initWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws`;
    
    try {
        websocket = new WebSocket(wsUrl);
        
        websocket.onopen = function(event) {
            console.log('WebSocket connected');
            reconnectAttempts = 0;
            
            // Disable auto-refresh when WebSocket is active
            stopAutoRefresh();
            
            // Update real-time indicator
            const indicator = document.querySelector('.real-time-indicator');
            if (indicator) {
                indicator.innerHTML = '<i class="fas fa-circle"></i> Live Data (WebSocket)';
                indicator.style.opacity = '1';
            }
        };
        
        websocket.onmessage = function(event) {
            try {
                const data = JSON.parse(event.data);
                handleWebSocketMessage(data);
            } catch (error) {
                console.error('Error parsing WebSocket message:', error);
            }
        };
        
        websocket.onclose = function(event) {
            console.log('WebSocket disconnected');
            
            // Update real-time indicator
            const indicator = document.querySelector('.real-time-indicator');
            if (indicator) {
                indicator.innerHTML = '<i class="fas fa-circle"></i> Disconnected';
                indicator.style.opacity = '0.5';
            }
            
            // Attempt to reconnect
            if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                setTimeout(() => {
                    reconnectAttempts++;
                    console.log(`Attempting to reconnect (${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})...`);
                    initWebSocket();
                }, RECONNECT_DELAY);
            } else {
                console.log('Max reconnection attempts reached. Falling back to polling.');
                // Fallback to auto-refresh
                startAutoRefresh();
            }
        };
        
        websocket.onerror = function(error) {
            console.error('WebSocket error:', error);
        };
        
    } catch (error) {
        console.error('Failed to initialize WebSocket:', error);
        // Fallback to auto-refresh
        startAutoRefresh();
    }
}

// Handle WebSocket messages
function handleWebSocketMessage(data) {
    console.log('Received WebSocket message:', data.type);
    
    switch (data.type) {
        case 'initial_data':
            handleInitialData(data.data);
            break;
        case 'realtime_update':
            handleRealtimeUpdate(data.data);
            break;
        case 'master_added':
        case 'worker_added':
        case 'system_stopped':
        case 'cluster_restarted':
        case 'leader_elected':
            handleSystemNotification(data.type, data.data);
            break;
        default:
            console.log('Unknown message type:', data.type);
    }
}

// Handle initial data from WebSocket
function handleInitialData(data) {
    console.log('Received initial data from WebSocket');
    
    // Update all dashboard components
    if (data.masters) {
        updateMastersTable(data.masters);
    }
    if (data.workers) {
        window.__lastWorkersData = data.workers;
        updateWorkersTable(data.workers);
    }
    if (data.health) {
        updateHealthIndicators(data.health);
    }
    
    // Update last update time
    const now = new Date();
    const lastUpdateElement = document.getElementById('lastUpdate');
    if (lastUpdateElement) {
        lastUpdateElement.textContent = now.toLocaleTimeString();
    }
}

// Handle real-time updates from WebSocket
function handleRealtimeUpdate(data) {
    console.log('Received real-time update from WebSocket');
    
    // Update tables with new data
    if (data.masters) {
        updateMastersTable(data.masters);
    }
    if (data.workers) {
        window.__lastWorkersData = data.workers;
        updateWorkersTable(data.workers);
    }
    if (data.health) {
        updateHealthIndicators(data.health);
    }
    
    // Update last update time
    const now = new Date();
    const lastUpdateElement = document.getElementById('lastUpdate');
    if (lastUpdateElement) {
        lastUpdateElement.textContent = now.toLocaleTimeString();
    }
}

// Handle system notifications
function handleSystemNotification(type, data) {
    console.log(`Received system notification: ${type}`, data);
    
    // Show notification to user
    const message = data.message || `System event: ${type}`;
    showNotification(message, 'info', 5000);
    
    // Force refresh of data after a short delay
    setTimeout(() => {
        if (websocket && websocket.readyState === WebSocket.OPEN) {
            // WebSocket is active, data will come automatically
            return;
        } else {
            // Fallback to manual refresh
            refreshData();
        }
    }, 2000);
}

// Auto-refresh functionality (fallback when WebSocket is not available)
function startAutoRefresh() {
    if (refreshInterval) {
        clearInterval(refreshInterval);
    }
    
    refreshInterval = setInterval(() => {
        if (isAutoRefreshEnabled && (!websocket || websocket.readyState !== WebSocket.OPEN)) {
            refreshData();
        }
    }, 30000); // 30 seconds
}

function stopAutoRefresh() {
    if (refreshInterval) {
        clearInterval(refreshInterval);
        refreshInterval = null;
    }
}

function toggleAutoRefresh() {
    isAutoRefreshEnabled = !isAutoRefreshEnabled;
    const indicator = document.querySelector('.real-time-indicator');
    
    if (isAutoRefreshEnabled) {
        startAutoRefresh();
        indicator.style.opacity = '1';
        indicator.innerHTML = '<i class="fas fa-circle"></i> Live Data';
    } else {
        stopAutoRefresh();
        indicator.style.opacity = '0.5';
        indicator.innerHTML = '<i class="fas fa-circle"></i> Paused';
    }
}

// Refresh data function
async function refreshData() {
    const refreshBtn = document.querySelector('.floating-action i');
    if (refreshBtn) {
        refreshBtn.className = 'fas fa-spinner fa-spin';
    }
    
    try {
        // Fetch fresh data from APIs
        const [mastersData, workersData, healthData] = await Promise.all([
            fetchAPI('masters'),
            fetchAPI('workers'),
            fetchAPI('health')
        ]);
        
        // Update Masters table
        updateMastersTable(mastersData);
        
        // Cache and update Workers table
        window.__lastWorkersData = workersData;
        updateWorkersTable(workersData);
        
        // Update health indicators
        updateHealthIndicators(healthData);
        
        // Update last update time
        const now = new Date();
        const lastUpdateElement = document.getElementById('lastUpdate');
        if (lastUpdateElement) {
            lastUpdateElement.textContent = now.toLocaleTimeString();
        }
        
        console.log('Dashboard data refreshed successfully');
        
    } catch (error) {
        console.error('Error refreshing dashboard data:', error);
        showNotification('Failed to refresh data', 'danger');
    } finally {
        if (refreshBtn) {
            refreshBtn.className = 'fas fa-sync-alt';
        }
    }
}

// Add fade-in animations
function addFadeInAnimations() {
    const elements = document.querySelectorAll('.fade-in');
    elements.forEach((el, index) => {
        setTimeout(() => {
            el.style.opacity = '1';
            el.style.transform = 'translateY(0)';
        }, index * 100);
    });
}

// Initialize Bootstrap tooltips
function initTooltips() {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
}

// Setup event listeners
function setupEventListeners() {
    // Pause auto-refresh when page is not visible
    document.addEventListener('visibilitychange', function() {
        if (document.hidden) {
            stopAutoRefresh();
        } else if (isAutoRefreshEnabled) {
            startAutoRefresh();
        }
    });
    
    // Smooth scrolling for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth'
                });
            }
        });
    });
    
    // Real-time indicator click to toggle auto-refresh
    const realtimeIndicator = document.querySelector('.real-time-indicator');
    if (realtimeIndicator) {
        realtimeIndicator.addEventListener('click', toggleAutoRefresh);
        realtimeIndicator.style.cursor = 'pointer';
        realtimeIndicator.title = 'Click to toggle auto-refresh';
    }
    
    // Toggle Workers view (show all / show less)
    const toggleWorkersBtn = document.getElementById('toggleWorkersView');
    if (toggleWorkersBtn) {
        toggleWorkersBtn.addEventListener('click', function() {
            showAllWorkers = !showAllWorkers;
            this.textContent = showAllWorkers ? 'Show less' : 'Show all';
            if (window.__lastWorkersData) {
                updateWorkersTable(window.__lastWorkersData);
            } else {
                refreshData();
            }
        });
    }
    
    // Setup button handlers
    setupButtonHandlers();
}

// Utility functions
function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';
    
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

function formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);
    
    if (hours > 0) {
        return `${hours}h ${minutes}m ${secs}s`;
    } else if (minutes > 0) {
        return `${minutes}m ${secs}s`;
    } else {
        return `${secs}s`;
    }
}

function formatPercentage(value, decimals = 1) {
    return `${parseFloat(value).toFixed(decimals)}%`;
}

// Chart utility functions
function createGradient(ctx, color1, color2) {
    const gradient = ctx.createLinearGradient(0, 0, 0, 400);
    gradient.addColorStop(0, color1);
    gradient.addColorStop(1, color2);
    return gradient;
}

function getChartColors() {
    return {
        primary: '#3498db',
        success: '#27ae60',
        warning: '#f39c12',
        danger: '#e74c3c',
        info: '#17a2b8',
        light: '#f8f9fa',
        dark: '#343a40'
    };
}

// Status indicator functions
function getStatusColor(status) {
    const colors = {
        'healthy': '#27ae60',
        'unhealthy': '#e74c3c',
        'degraded': '#f39c12',
        'unknown': '#6c757d'
    };
    return colors[status.toLowerCase()] || colors['unknown'];
}

function getStatusIcon(status) {
    const icons = {
        'healthy': 'fas fa-check-circle',
        'unhealthy': 'fas fa-times-circle',
        'degraded': 'fas fa-exclamation-triangle',
        'unknown': 'fas fa-question-circle'
    };
    return icons[status.toLowerCase()] || icons['unknown'];
}

// Notification system
function showNotification(message, type = 'info', duration = 3000) {
    const notification = document.createElement('div');
    notification.className = `alert alert-${type} alert-dismissible fade show position-fixed`;
    notification.style.cssText = `
        top: 20px;
        right: 20px;
        z-index: 9999;
        min-width: 300px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    `;
    
    notification.innerHTML = `
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    
    document.body.appendChild(notification);
    
    // Auto-remove after duration
    setTimeout(() => {
        if (notification.parentNode) {
            notification.remove();
        }
    }, duration);
}

// Loading spinner
function showLoading(element) {
    if (element) {
        element.innerHTML = '<div class="loading-spinner"></div>';
    }
}

function hideLoading(element, originalContent) {
    if (element && originalContent) {
        element.innerHTML = originalContent;
    }
}

// API helper functions
async function fetchAPI(endpoint) {
    try {
        const response = await fetch(`/api/v1/${endpoint}`);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        return await response.json();
    } catch (error) {
        console.error(`Error fetching ${endpoint}:`, error);
        showNotification(`Failed to fetch ${endpoint}`, 'danger');
        throw error;
    }
}

// ===== BUTTON ACTION FUNCTIONS =====

// Make API call with POST method
async function makeApiCall(url, method = 'POST', data = {}) {
    try {
        const response = await fetch(url, {
            method: method,
            headers: {
                'Content-Type': 'application/json',
            },
            body: method === 'POST' ? JSON.stringify(data) : undefined
        });
        
        const result = await response.json();
        return result;
    } catch (error) {
        console.error('API call failed:', error);
        return { success: false, message: 'Network error occurred' };
    }
}

// Job Actions
function showJobDetails(jobId) {
    makeApiCall(`/api/v1/jobs/${jobId}/details`)
        .then(result => {
            if (result.success) {
                const details = result.data;
                const modalHtml = `
                    <div class="modal fade" id="jobDetailsModal" tabindex="-1">
                        <div class="modal-dialog modal-lg">
                            <div class="modal-content">
                                <div class="modal-header">
                                    <h5 class="modal-title">Job Details: ${details.id}</h5>
                                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                                </div>
                                <div class="modal-body">
                                    <div class="row mb-3">
                                        <div class="col-6"><strong>Status:</strong> ${details.status}</div>
                                        <div class="col-6"><strong>Phase:</strong> ${details.phase}</div>
                                    </div>
                                    <div class="row mb-3">
                                        <div class="col-6"><strong>Progress:</strong> ${details.progress}%</div>
                                        <div class="col-6"><strong>Duration:</strong> ${Math.floor((Date.now() - new Date(details.start_time)) / 1000)}s</div>
                                    </div>
                                    <div class="mb-3">
                                        <h6>Map Tasks</h6>
                                        <div class="row">
                                            <div class="col-3">Total: ${details.map_tasks.total}</div>
                                            <div class="col-3">Completed: ${details.map_tasks.completed}</div>
                                            <div class="col-3">In Progress: ${details.map_tasks.in_progress}</div>
                                            <div class="col-3">Failed: ${details.map_tasks.failed}</div>
                                        </div>
                                    </div>
                                    <div class="mb-3">
                                        <h6>Reduce Tasks</h6>
                                        <div class="row">
                                            <div class="col-3">Total: ${details.reduce_tasks.total}</div>
                                            <div class="col-3">Completed: ${details.reduce_tasks.completed}</div>
                                            <div class="col-3">In Progress: ${details.reduce_tasks.in_progress}</div>
                                            <div class="col-3">Failed: ${details.reduce_tasks.failed}</div>
                                        </div>
                                    </div>
                                    <div class="mb-3">
                                        <h6>Input Files</h6>
                                        <ul>${details.input_files.map(file => `<li>${file}</li>`).join('')}</ul>
                                    </div>
                                    ${details.error_log.length > 0 ? `
                                    <div class="mb-3">
                                        <h6>Error Log</h6>
                                        <ul class="text-danger">${details.error_log.map(error => `<li>${error}</li>`).join('')}</ul>
                                    </div>
                                    ` : ''}
                                </div>
                                <div class="modal-footer">
                                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                                </div>
                            </div>
                        </div>
                    </div>
                `;
                document.body.insertAdjacentHTML('beforeend', modalHtml);
                const modal = new bootstrap.Modal(document.getElementById('jobDetailsModal'));
                modal.show();
                
                // Clean up modal after it's hidden
                document.getElementById('jobDetailsModal').addEventListener('hidden.bs.modal', function() {
                    this.remove();
                });
            } else {
                showNotification(result.message, 'danger');
            }
        });
}

function pauseJob(jobId) {
    makeApiCall(`/api/v1/jobs/${jobId}/pause`)
        .then(result => {
            showNotification(result.message, result.success ? 'success' : 'danger');
        });
}

function resumeJob(jobId) {
    makeApiCall(`/api/v1/jobs/${jobId}/resume`)
        .then(result => {
            showNotification(result.message, result.success ? 'success' : 'danger');
        });
}

function cancelJob(jobId) {
    if (confirm('Are you sure you want to cancel this job?')) {
        makeApiCall(`/api/v1/jobs/${jobId}/cancel`)
            .then(result => {
                showNotification(result.message, result.success ? 'success' : 'danger');
            });
    }
}

// Worker Actions
function showWorkerDetails(workerId) {
    makeApiCall(`/api/v1/workers/${workerId}/details`)
        .then(result => {
            if (result.success) {
                const details = result.data;
                const modalHtml = `
                    <div class="modal fade" id="workerDetailsModal" tabindex="-1">
                        <div class="modal-dialog modal-lg">
                            <div class="modal-content">
                                <div class="modal-header">
                                    <h5 class="modal-title">Worker Details: ${details.id}</h5>
                                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                                </div>
                                <div class="modal-body">
                                    <div class="row mb-3">
                                        <div class="col-6"><strong>Status:</strong> ${details.status}</div>
                                        <div class="col-6"><strong>Tasks Completed:</strong> ${details.tasks_completed}</div>
                                    </div>
                                    <div class="mb-3">
                                        <h6>Current Task</h6>
                                        <div class="row">
                                            <div class="col-4">Type: ${details.current_task.type}</div>
                                            <div class="col-4">ID: ${details.current_task.id}</div>
                                            <div class="col-4">Progress: ${details.current_task.progress}%</div>
                                        </div>
                                    </div>
                                    <div class="mb-3">
                                        <h6>Performance</h6>
                                        <div class="row">
                                            <div class="col-3">CPU: ${details.performance.cpu_usage}%</div>
                                            <div class="col-3">Memory: ${details.performance.memory_usage}MB</div>
                                            <div class="col-3">Disk: ${details.performance.disk_usage}MB</div>
                                            <div class="col-3">Network: ${details.performance.network_io}KB/s</div>
                                        </div>
                                    </div>
                                    <div class="mb-3">
                                        <h6>Task History</h6>
                                        <table class="table table-sm">
                                            <thead>
                                                <tr><th>Task ID</th><th>Type</th><th>Duration</th><th>Status</th></tr>
                                            </thead>
                                            <tbody>
                                                ${details.task_history.map(task => 
                                                    `<tr><td>${task.task_id}</td><td>${task.type}</td><td>${task.duration}</td><td>${task.status}</td></tr>`
                                                ).join('')}
                                            </tbody>
                                        </table>
                                    </div>
                                    <div class="mb-3">
                                        <h6>Health Checks</h6>
                                        <div class="row">
                                            <div class="col-3">Disk: <span class="badge bg-success">${details.health_checks.disk_space}</span></div>
                                            <div class="col-3">Memory: <span class="badge bg-success">${details.health_checks.memory}</span></div>
                                            <div class="col-3">Network: <span class="badge bg-success">${details.health_checks.network}</span></div>
                                            <div class="col-3">Heartbeat: ${Math.floor((Date.now() - new Date(details.health_checks.last_heartbeat)) / 1000)}s ago</div>
                                        </div>
                                    </div>
                                </div>
                                <div class="modal-footer">
                                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                                </div>
                            </div>
                        </div>
                    </div>
                `;
                document.body.insertAdjacentHTML('beforeend', modalHtml);
                const modal = new bootstrap.Modal(document.getElementById('workerDetailsModal'));
                modal.show();
                
                // Clean up modal after it's hidden
                document.getElementById('workerDetailsModal').addEventListener('hidden.bs.modal', function() {
                    this.remove();
                });
            } else {
                showNotification(result.message, 'danger');
            }
        });
}

function pauseWorker(workerId) {
    makeApiCall(`/api/v1/workers/${workerId}/pause`)
        .then(result => {
            showNotification(result.message, result.success ? 'success' : 'danger');
        });
}

function resumeWorker(workerId) {
    makeApiCall(`/api/v1/workers/${workerId}/resume`)
        .then(result => {
            showNotification(result.message, result.success ? 'success' : 'danger');
        });
}

function restartWorker(workerId) {
    if (confirm('Are you sure you want to restart this worker?')) {
        makeApiCall(`/api/v1/workers/${workerId}/restart`)
            .then(result => {
                showNotification(result.message, result.success ? 'success' : 'danger');
            });
    }
}

// System Actions
function startMaster() {
    if (confirm('Are you sure you want to add a new master to the cluster?\n\nThis will:\n• Add a new master to the cluster\n• Trigger a new leader election\n• Update the cluster configuration')) {
        showNotification('Adding new master to cluster...', 'info', 5000);
        makeApiCall('/api/v1/system/start-master')
            .then(async result => {
                showNotification(result.message, result.success ? 'success' : 'danger');
                if (result.success) {
                    // Immediately refresh data and then poll briefly until the new master appears
                    try {
                        await refreshData();
                        const startTime = Date.now();
                        const timeoutMs = 20000; // 20s max wait
                        let initialCount = (window.__lastMastersCount ?? null);

                        // Capture current count from DOM
                        const countFromDom = () => document.querySelectorAll('#mastersTableBody tr').length;
                        if (initialCount === null) initialCount = countFromDom();

                        const poll = async () => {
                            await refreshData();
                            const current = countFromDom();
                            if (current > initialCount) return true;
                            if (Date.now() - startTime > timeoutMs) return false;
                            return new Promise(resolve => setTimeout(async () => resolve(await poll()), 2000));
                        };

                        const appeared = await poll();
                        if (!appeared) {
                            showNotification('Master added, waiting for cluster to recognize it...', 'warning');
                        }
                    } catch (_) {
                        // Fallback: soft reload if anything goes wrong
                        setTimeout(() => location.reload(), 3000);
                    }
                }
            });
    }
}

function startWorker() {
    if (confirm('Are you sure you want to add a new worker to the cluster?\n\nThis will:\n• Add a new worker to increase processing capacity\n• Update the cluster configuration\n• The worker will start processing tasks immediately')) {
        showNotification('Adding new worker to cluster...', 'info', 5000);
        makeApiCall('/api/v1/system/start-worker')
            .then(async result => {
                showNotification(result.message, result.success ? 'success' : 'danger');
                if (result.success) {
                    // Immediately refresh data and then poll briefly until the new worker appears
                    try {
                        await refreshData();
                        const startTime = Date.now();
                        const timeoutMs = 20000; // 20s max wait
                        let initialCount = (window.__lastWorkersCount ?? null);

                        // Capture current count from DOM
                        const countFromDom = () => document.querySelectorAll('#workersTableBody tr').length;
                        if (initialCount === null) initialCount = countFromDom();

                        const poll = async () => {
                            await refreshData();
                            const current = countFromDom();
                            if (current > initialCount) return true;
                            if (Date.now() - startTime > timeoutMs) return false;
                            return new Promise(resolve => setTimeout(async () => resolve(await poll()), 2000));
                        };

                        const appeared = await poll();
                        if (!appeared) {
                            showNotification('Worker added, waiting for cluster to recognize it...', 'warning');
                        }
                    } catch (_) {
                        // Fallback: soft reload if anything goes wrong
                        setTimeout(() => location.reload(), 3000);
                    }
                }
            });
    }
}

function stopAll() {
    if (confirm('Are you sure you want to stop all system components?\n\nThis will:\n• Stop all master and worker services\n• Stop the dashboard\n• All running jobs will be interrupted')) {
        showNotification('Stopping all cluster services...', 'warning', 5000);
        makeApiCall('/api/v1/system/stop-all')
            .then(result => {
                showNotification(result.message, result.success ? 'success' : 'danger');
            });
    }
}

function restartCluster() {
    if (confirm('Are you sure you want to reset the cluster to default configuration?\n\nThis will:\n• Stop all current services\n• Reset to default configuration (3 masters, 3 workers)\n• Clean all Raft data\n• Restart with fresh cluster state\n\nAll current jobs and data will be lost!')) {
        showNotification('Resetting cluster to default configuration...', 'warning', 8000);
        makeApiCall('/api/v1/system/restart-cluster')
            .then(result => {
                showNotification(result.message, result.success ? 'success' : 'danger');
                if (result.success) {
                    // Refresh the page after a longer delay to allow cluster restart
                    setTimeout(() => {
                        location.reload();
                    }, 5000);
                }
            });
    }
}

function electLeader() {
    if (confirm('Are you sure you want to force a new leader election?\n\nThis will:\n• Trigger a new leader election in the Raft cluster\n• The current leader will be replaced\n• All masters will participate in the election\n• The cluster will continue operating with the new leader\n\nThis operation is safe and will not interrupt running jobs.')) {
        showNotification('Starting leader election...', 'info', 5000);
        makeApiCall('/api/v1/system/elect-leader')
            .then(result => {
                if (result.success) {
                    const leaderInfo = result.leader_info;
                    const message = `Leader election completed! New leader: ${leaderInfo.leader_id}`;
                    showNotification(message, 'success', 8000);
                    
                    // Show detailed election results
                    const modalHtml = `
                        <div class="modal fade" id="leaderElectionModal" tabindex="-1">
                            <div class="modal-dialog modal-lg">
                                <div class="modal-content">
                                    <div class="modal-header">
                                        <h5 class="modal-title">
                                            <i class="fas fa-vote-yea"></i> Leader Election Results
                                        </h5>
                                        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                                    </div>
                                    <div class="modal-body">
                                        <div class="alert alert-success">
                                            <i class="fas fa-check-circle"></i>
                                            <strong>Election Successful!</strong>
                                        </div>
                                        <div class="row mb-3">
                                            <div class="col-6">
                                                <strong>Previous Leader:</strong><br>
                                                <span class="badge bg-secondary">master-${leaderInfo.old_leader}</span>
                                            </div>
                                            <div class="col-6">
                                                <strong>New Leader:</strong><br>
                                                <span class="badge bg-warning">${leaderInfo.leader_id}</span>
                                            </div>
                                        </div>
                                        <div class="row mb-3">
                                            <div class="col-6">
                                                <strong>Election Time:</strong><br>
                                                <small class="text-muted">${new Date(leaderInfo.election_time).toLocaleString()}</small>
                                            </div>
                                            <div class="col-6">
                                                <strong>Total Masters:</strong><br>
                                                <span class="badge bg-info">${leaderInfo.total_masters}</span>
                                            </div>
                                        </div>
                                        <div class="alert alert-info">
                                            <i class="fas fa-info-circle"></i>
                                            <strong>Note:</strong> The cluster will continue operating normally with the new leader. 
                                            All running jobs will be preserved and the cluster will maintain consistency.
                                        </div>
                                    </div>
                                    <div class="modal-footer">
                                        <button type="button" class="btn btn-primary" data-bs-dismiss="modal">Close</button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    `;
                    document.body.insertAdjacentHTML('beforeend', modalHtml);
                    const modal = new bootstrap.Modal(document.getElementById('leaderElectionModal'));
                    modal.show();
                    
                    // Clean up modal after it's hidden
                    document.getElementById('leaderElectionModal').addEventListener('hidden.bs.modal', function() {
                        this.remove();
                    });
                    
                    // Refresh the page after a short delay to show updated cluster state
                    setTimeout(() => {
                        location.reload();
                    }, 3000);
                } else {
                    showNotification(result.message, 'danger');
                }
            });
    }
}

// Setup button click handlers
function setupButtonHandlers() {
    document.addEventListener('click', function(e) {
        const button = e.target.closest('button');
        if (!button) return;
        
        const action = button.getAttribute('data-action');
        const id = button.getAttribute('data-id');
        
        if (action === 'job-details') {
            showJobDetails(id);
        } else if (action === 'pause-job') {
            pauseJob(id);
        } else if (action === 'resume-job') {
            resumeJob(id);
        } else if (action === 'cancel-job') {
            cancelJob(id);
        } else if (action === 'worker-details') {
            showWorkerDetails(id);
        } else if (action === 'pause-worker') {
            pauseWorker(id);
        } else if (action === 'resume-worker') {
            resumeWorker(id);
        } else if (action === 'restart-worker') {
            restartWorker(id);
        } else if (action === 'start-master') {
            startMaster();
        } else if (action === 'start-worker') {
            startWorker();
        } else if (action === 'stop-all') {
            stopAll();
        } else if (action === 'restart-cluster') {
            restartCluster();
        } else if (action === 'elect-leader') {
            electLeader();
        }
    });
}

// Update Masters table dynamically
function updateMastersTable(mastersData) {
    const tbody = document.getElementById('mastersTableBody');
    if (!tbody) return;
    
    tbody.innerHTML = '';
    
    mastersData.forEach(master => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${master.id}</strong></td>
            <td>
                ${master.leader ? 
                    '<span class="badge bg-warning"><i class="fas fa-crown"></i> Leader</span>' :
                    '<span class="badge bg-secondary"><i class="fas fa-user"></i> Follower</span>'
                }
            </td>
            <td>
                <span class="status-indicator status-healthy"></span>
                ${master.state}
            </td>
            <td>
                <small class="text-muted">${new Date(master.last_seen).toLocaleTimeString()}</small>
            </td>
        `;
        tbody.appendChild(row);
    });
}

// Update Workers table dynamically
function updateWorkersTable(workersData) {
    const tbody = document.getElementById('workersTableBody');
    if (!tbody) return;
    
    tbody.innerHTML = '';
    
    const visibleWorkers = showAllWorkers ? workersData : workersData.slice(0, DEFAULT_WORKERS_LIMIT);
    visibleWorkers.forEach(worker => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${worker.id}</strong></td>
            <td>
                <span class="badge bg-success">
                    <i class="fas fa-circle"></i> ${worker.status}
                </span>
            </td>
            <td>
                <span class="badge bg-info">${worker.tasks_done}</span>
            </td>
            <td>
                <small class="text-muted">${new Date(worker.last_seen).toLocaleTimeString()}</small>
            </td>
        `;
        tbody.appendChild(row);
    });
    
    const toggleBtn = document.getElementById('toggleWorkersView');
    if (toggleBtn) {
        toggleBtn.style.display = (workersData && workersData.length > DEFAULT_WORKERS_LIMIT) ? 'inline-block' : 'none';
        toggleBtn.textContent = showAllWorkers ? 'Show less' : 'Show all';
    }
}

// Update health indicators
function updateHealthIndicators(healthData) {
    // Update health status in system overview
    const statusElement = document.querySelector('.status-indicator');
    if (statusElement && healthData.status) {
        statusElement.className = `status-indicator status-${healthData.status.toLowerCase()}`;
    }
    
    // Update health status text
    const statusTextElement = document.querySelector('.text-capitalize');
    if (statusTextElement && healthData.status) {
        statusTextElement.textContent = healthData.status.toLowerCase();
    }
}

// Export functions for global use
window.MapReduceDashboard = {
    init: initDashboard,
    refresh: refreshData,
    toggleAutoRefresh: toggleAutoRefresh,
    showNotification: showNotification,
    formatBytes: formatBytes,
    formatDuration: formatDuration,
    formatPercentage: formatPercentage,
    getStatusColor: getStatusColor,
    getStatusIcon: getStatusIcon,
    fetchAPI: fetchAPI,
    updateMastersTable: updateMastersTable,
    updateWorkersTable: updateWorkersTable,
    updateHealthIndicators: updateHealthIndicators,
    // Button actions
    showJobDetails: showJobDetails,
    pauseJob: pauseJob,
    resumeJob: resumeJob,
    cancelJob: cancelJob,
    showWorkerDetails: showWorkerDetails,
    pauseWorker: pauseWorker,
    resumeWorker: resumeWorker,
    restartWorker: restartWorker,
    startMaster: startMaster,
    startWorker: startWorker,
    stopAll: stopAll,
    restartCluster: restartCluster,
    electLeader: electLeader
};

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', initDashboard);

