param(
    [string]$DashboardUrl = "http://localhost:8080"
)

function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Ok($msg) { Write-Host $msg -ForegroundColor Green }

function Get-JsonWithRetry {
    param(
        [string]$Url,
        [int]$Retries = 5,
        [int]$InitialDelayMs = 500
    )
    $attempt = 0
    $delay = $InitialDelayMs
    while ($attempt -lt $Retries) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -UseBasicParsing
            if ($resp -and $resp.Content) {
                return ($resp.Content | ConvertFrom-Json)
            }
        } catch {
            # swallow, we'll retry
        }
        Start-Sleep -Milliseconds $delay
        $delay = [Math]::Min($delay * 2, 5000)
        $attempt++
    }
    throw "Failed to GET JSON from $Url after $Retries attempts"
}

try {
    Write-Info "[Step] Lettura metrics per stato Raft iniziale"
    $metrics = Get-JsonWithRetry -Url "$DashboardUrl/api/v1/metrics"
    $raft = $metrics.raft_state
    $initialTerm = ("{0}" -f $raft.term)
    Write-Host ("Raft state: {0}, term: {1}, peers: [{2}]" -f $raft.state, $initialTerm, ($raft.peers -join ', ')) -ForegroundColor Cyan
} catch {
    Write-Warn "Metrics non disponibili: $_"
}

$victim = $null
try {
    Write-Info "[Step] Identificazione leader corrente via API"
    # Prova endpoint dedicato raft/leader prima
    $leaderResp = Get-JsonWithRetry -Url "$DashboardUrl/api/v1/raft/leader" -Retries 8 -InitialDelayMs 500
    if ($leaderResp -and $leaderResp.leader -eq $true -and $leaderResp.rpc_addr) {
        $leaderIdStr = ("master-{0}" -f $leaderResp.id)
        $victim = ("master{0}" -f $leaderResp.id)
        Write-Host ("Leader corrente: {0} (servizio: {1}, rpc: {2})" -f $leaderIdStr, $victim, $leaderResp.rpc_addr) -ForegroundColor Cyan
    } else {
        # Fallback alle masters API
        $masters = Get-JsonWithRetry -Url "$DashboardUrl/api/v1/masters" -Retries 12 -InitialDelayMs 750
        $leader = $masters | Where-Object { $_.Leader -eq $true } | Select-Object -First 1
        if ($leader) {
            $victim = ($leader.ID -replace 'master-','master')
            Write-Host ("Leader corrente: {0} (servizio: {1})" -f $leader.ID, $victim) -ForegroundColor Cyan
        } else {
            throw "Leader non esposto via API"
        }
    }
} catch {
    if ($_.Exception.Message -match 'Failed to GET JSON') {
        Write-Warn "API masters non disponibili: $($_.Exception.Message)"
    } else {
        Write-Warn "Leader non esposto via API: $($_.Exception.Message)"
    }
    Write-Info "[Fallback] Rilevazione leader dai log dei master"
    $candidates = @('master0','master1','master2')
    $found = $false
    foreach ($m in $candidates) {
        try {
            $log = docker-compose -f docker/docker-compose.yml logs --tail=200 $m 2>$null
            if ($log -and ($log | Select-String -Pattern '(?i)leadership acquired|state:\s*leader|become leader|leader elected' -Quiet)) {
                $victim = $m
                Write-Ok ("Leader corrente da log: {0}" -f $victim)
                $found = $true
                break
            }
        } catch {}
    }
    if (-not $found) {
        $victim = 'master0'
        Write-Warn ("Leader non determinabile dai log; uso fallback: {0}" -f $victim)
    }
}

Write-Info ("[Step] Stop del leader corrente: {0}" -f $victim)
docker-compose -f docker/docker-compose.yml stop $victim | Out-Null
Start-Sleep -Seconds 8

Write-Info "[Step] Health post-stop"
powershell -ExecutionPolicy Bypass -File scripts/docker-manager.ps1 health | Out-Null

Write-Info "[Step] Ricerca nuovo leader (API con retry, poi fallback log)"
$newLeaderId = $null
$newLeaderSvc = $null

# Tentativo via API con retry
try {
    # Endpoint dedicato
    $leaderResp2 = Get-JsonWithRetry -Url "$DashboardUrl/api/v1/raft/leader" -Retries 8 -InitialDelayMs 750
    if ($leaderResp2 -and $leaderResp2.leader -eq $true) {
        $newLeaderId = ("master-{0}" -f $leaderResp2.id)
        $newLeaderSvc = ("master{0}" -f $leaderResp2.id)
    } else {
        # fallback
        $masters2 = Get-JsonWithRetry -Url "$DashboardUrl/api/v1/masters" -Retries 8 -InitialDelayMs 750
        $leader2 = $masters2 | Where-Object { $_.Leader -eq $true } | Select-Object -First 1
        if ($leader2) {
            $newLeaderId = $leader2.ID
            $newLeaderSvc = ($leader2.ID -replace 'master-','master')
        }
    }
} catch {}

# Fallback via log se API non determinano il leader
if (-not $newLeaderId) {
    $candidates2 = @('master0','master1','master2') | Where-Object { $_ -ne $victim }
    Start-Sleep -Seconds 3
    foreach ($m in $candidates2) {
        try {
            $log2 = docker-compose -f docker/docker-compose.yml logs --tail=200 $m 2>$null
            if ($log2 -and ($log2 | Select-String -Pattern '(?i)leadership acquired|state:\s*leader|become leader|leader elected' -Quiet)) {
                $newLeaderSvc = $m
                $newLeaderId = ($m -replace 'master','master-')
                break
            }
        } catch {}
    }
}

if ($newLeaderId) {
    if ($newLeaderSvc -eq $victim) {
        Write-Warn ("Il leader non è cambiato: {0}" -f $newLeaderId)
    } else {
        Write-Ok ("Nuovo leader eletto: {0} (servizio: {1})" -f $newLeaderId, $newLeaderSvc)
    }
} else {
    Write-Warn "Nuovo leader non determinabile"
}

try {
    Write-Info "[Step] Metrics post-elezione"
    $metrics2 = Get-JsonWithRetry -Url "$DashboardUrl/api/v1/metrics"
    $raft2 = $metrics2.raft_state
    $finalTerm = ("{0}" -f $raft2.term)
    Write-Host ("Raft state: {0}, term: {1}, peers: [{2}]" -f $raft2.state, $finalTerm, ($raft2.peers -join ', ')) -ForegroundColor Cyan
    if ($initialTerm -and $finalTerm) {
        if ($initialTerm -ne $finalTerm) {
            Write-Ok ("Term cambiato: {0} -> {1}" -f $initialTerm, $finalTerm)
        } else {
            Write-Warn ("Term invariato: {0}" -f $finalTerm)
        }
    }
} catch {
    Write-Warn "Metrics non disponibili: $_"
}

Write-Info ("[Step] Start del master fermato: {0}" -f $victim)
docker-compose -f docker/docker-compose.yml start $victim | Out-Null
Start-Sleep -Seconds 8

Write-Ok "Leader-test via API completato"



