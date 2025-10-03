# Test Raft consensus algorithm and leader election
# Covers leader election, consensus, fault tolerance, and cluster management

param(
    [switch]$Verbose,
    [switch]$FaultTolerance,
    [int]$TimeoutSeconds = 120
)

# Import common test utilities
. "$PSScriptRoot\test-common.ps1" -Verbose:$Verbose

Write-TestHeader "RAFT CONSENSUS TEST"

# Test Raft cluster initialization
function Test-RaftInitialization {
    Write-TestHeader "Testing Raft Initialization"
    
    # Check if Docker is running
    if (-not (Test-DockerRunning)) {
        Add-TestResult -TestName "Raft-Docker" -Success $false -Message "Docker is not running"
        return $false
    }
    
    # Check if cluster is running
    $containers = Get-DockerContainers -Filter "name=mapreduce-master"
    $masterCount = ($containers | Measure-Object).Count
    
    if ($masterCount -ge 3) {
        Add-TestResult -TestName "Raft-Initialization" -Success $true -Message "Found $masterCount master containers"
    } else {
        Add-TestResult -TestName "Raft-Initialization" -Success $false -Message "Expected at least 3 masters, found $masterCount"
        return $false
    }
    
    return $true
}

# Test leader election
function Test-LeaderElection {
    Write-TestHeader "Testing Leader Election"
    
    $allPassed = $true
    
    # Test current leader status
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/masters" -Method "GET"
        if ($response) {
            $masters = $response.Content | ConvertFrom-Json
            
            $leaders = $masters | Where-Object { $_.leader -eq $true }
            $followers = $masters | Where-Object { $_.leader -eq $false }
            
            if ($leaders.Count -eq 1) {
                Add-TestResult -TestName "Raft-Leader" -Success $true -Message "Single leader found: $($leaders[0].id)"
            } else {
                Add-TestResult -TestName "Raft-Leader" -Success $false -Message "Expected 1 leader, found $($leaders.Count)"
                $allPassed = $false
            }
            
            if ($followers.Count -ge 2) {
                Add-TestResult -TestName "Raft-Followers" -Success $true -Message "Found $($followers.Count) followers"
            } else {
                Add-TestResult -TestName "Raft-Followers" -Success $false -Message "Expected at least 2 followers, found $($followers.Count)"
                $allPassed = $false
            }
        } else {
            Add-TestResult -TestName "Raft-Leader" -Success $false -Message "Failed to get master information"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "Raft-Leader" -Success $false -Message "Error getting leader info: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test leader election API
function Test-LeaderElectionAPI {
    Write-TestHeader "Testing Leader Election API"
    
    $allPassed = $true
    
    # Test elect-leader endpoint
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/system/elect-leader" -Method "POST"
        if ($response) {
            $result = $response.Content | ConvertFrom-Json
            
            if ($result.success) {
                Add-TestResult -TestName "Raft-ElectLeader" -Success $true -Message "Leader election successful: $($result.message)"
            } else {
                Add-TestResult -TestName "Raft-ElectLeader" -Success $false -Message "Leader election failed: $($result.message)"
                $allPassed = $false
            }
        } else {
            Add-TestResult -TestName "Raft-ElectLeader" -Success $false -Message "No response from elect-leader API"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "Raft-ElectLeader" -Success $false -Message "Error calling elect-leader API: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Wait for election to complete
    Start-Sleep -Seconds 5
    
    # Verify new leader
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/masters" -Method "GET"
        if ($response) {
            $masters = $response.Content | ConvertFrom-Json
            $leaders = $masters | Where-Object { $_.leader -eq $true }
            
            if ($leaders.Count -eq 1) {
                Add-TestResult -TestName "Raft-NewLeader" -Success $true -Message "New leader confirmed: $($leaders[0].id)"
            } else {
                Add-TestResult -TestName "Raft-NewLeader" -Success $false -Message "Leader election may have failed"
                $allPassed = $false
            }
        }
    }
    catch {
        Add-TestResult -TestName "Raft-NewLeader" -Success $false -Message "Error verifying new leader: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test consensus consistency
function Test-ConsensusConsistency {
    Write-TestHeader "Testing Consensus Consistency"
    
    $allPassed = $true
    
    # Test multiple reads to ensure consistency
    $responses = @()
    for ($i = 1; $i -le 5; $i++) {
        try {
            $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/masters" -Method "GET"
            if ($response) {
                $masters = $response.Content | ConvertFrom-Json
                $responses += $masters
            }
            Start-Sleep -Seconds 1
        }
        catch {
            Write-TestWarning "Consistency test iteration $i failed: $($_.Exception.Message)"
        }
    }
    
    if ($responses.Count -ge 3) {
        # Check if all responses show the same leader
        $leaders = $responses | ForEach-Object { ($_ | Where-Object { $_.leader -eq $true }).id }
        $uniqueLeaders = $leaders | Sort-Object -Unique
        
        if ($uniqueLeaders.Count -eq 1) {
            Add-TestResult -TestName "Raft-Consistency" -Success $true -Message "Consistent leader across $($responses.Count) reads: $($uniqueLeaders[0])"
        } else {
            Add-TestResult -TestName "Raft-Consistency" -Success $false -Message "Inconsistent leader: $($uniqueLeaders -join ', ')"
            $allPassed = $false
        }
    } else {
        Add-TestResult -TestName "Raft-Consistency" -Success $false -Message "Insufficient responses for consistency test"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test fault tolerance
function Test-FaultTolerance {
    if (-not $FaultTolerance) {
        Write-TestInfo "Fault tolerance tests skipped (use -FaultTolerance to enable)"
        return $true
    }
    
    Write-TestHeader "Testing Fault Tolerance"
    
    $allPassed = $true
    
    # Get current cluster state
    $containers = Get-DockerContainers -Filter "name=mapreduce-master"
    $masterContainers = $containers | Where-Object { $_ -match "mapreduce-master" }
    
    if ($masterContainers.Count -ge 3) {
        # Simulate master failure by stopping one container
        $containerToStop = $masterContainers[0] -split '\t' | Select-Object -First 1
        Write-TestInfo "Simulating failure of master: $containerToStop"
        
        try {
            docker stop $containerToStop
            Start-Sleep -Seconds 10
            
            # Check if cluster still has a leader
            $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/masters" -Method "GET"
            if ($response) {
                $masters = $response.Content | ConvertFrom-Json
                $leaders = $masters | Where-Object { $_.leader -eq $true }
                
                if ($leaders.Count -eq 1) {
                    Add-TestResult -TestName "Raft-FaultTolerance" -Success $true -Message "Cluster maintained leader after failure: $($leaders[0].id)"
                } else {
                    Add-TestResult -TestName "Raft-FaultTolerance" -Success $false -Message "No leader after failure"
                    $allPassed = $false
                }
            } else {
                Add-TestResult -TestName "Raft-FaultTolerance" -Success $false -Message "Failed to get cluster state after failure"
                $allPassed = $false
            }
        }
        catch {
            Add-TestResult -TestName "Raft-FaultTolerance" -Success $false -Message "Error during fault tolerance test: $($_.Exception.Message)"
            $allPassed = $false
        }
        finally {
            # Restart the container
            Write-TestInfo "Restarting failed master: $containerToStop"
            docker start $containerToStop
            Start-Sleep -Seconds 15
        }
    } else {
        Add-TestResult -TestName "Raft-FaultTolerance" -Success $false -Message "Insufficient masters for fault tolerance test"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test cluster management
function Test-ClusterManagement {
    Write-TestHeader "Testing Cluster Management"
    
    $allPassed = $true
    
    # Test adding a master
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/system/start-master" -Method "POST"
        if ($response) {
            $result = $response.Content | ConvertFrom-Json
            
            if ($result.success -or $result.message) {
                Add-TestResult -TestName "Raft-AddMaster" -Success $true -Message "Master addition: $($result.message)"
            } else {
                Add-TestResult -TestName "Raft-AddMaster" -Success $false -Message "Failed to add master"
                $allPassed = $false
            }
        } else {
            Add-TestResult -TestName "Raft-AddMaster" -Success $false -Message "No response from add-master API"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "Raft-AddMaster" -Success $false -Message "Error adding master: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Wait for new master to join
    Start-Sleep -Seconds 10
    
    # Verify cluster state
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/masters" -Method "GET"
        if ($response) {
            $masters = $response.Content | ConvertFrom-Json
            
            if ($masters.Count -ge 4) {
                Add-TestResult -TestName "Raft-ClusterSize" -Success $true -Message "Cluster has $($masters.Count) masters"
            } else {
                Add-TestResult -TestName "Raft-ClusterSize" -Success $false -Message "Expected at least 4 masters, found $($masters.Count)"
                $allPassed = $false
            }
        }
    }
    catch {
        Add-TestResult -TestName "Raft-ClusterSize" -Success $false -Message "Error verifying cluster size: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test Raft performance
function Test-RaftPerformance {
    Write-TestHeader "Testing Raft Performance"
    
    $allPassed = $true
    
    # Test leader election performance
    $electionTimes = @()
    for ($i = 1; $i -le 3; $i++) {
        $startTime = Get-Date
        try {
            $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/system/elect-leader" -Method "POST"
            $endTime = Get-Date
            
            if ($response) {
                $duration = ($endTime - $startTime).TotalMilliseconds
                $electionTimes += $duration
                Write-TestInfo "Election $i completed in $($duration.ToString('F2'))ms"
            }
        }
        catch {
            Write-TestWarning "Election $i failed: $($_.Exception.Message)"
        }
        
        Start-Sleep -Seconds 5
    }
    
    if ($electionTimes.Count -gt 0) {
        $avgElectionTime = ($electionTimes | Measure-Object -Average).Average
        
        if ($avgElectionTime -lt 5000) { # Less than 5 seconds
            Add-TestResult -TestName "Raft-Performance" -Success $true -Message "Average election time: $($avgElectionTime.ToString('F2'))ms"
        } else {
            Add-TestResult -TestName "Raft-Performance" -Success $false -Message "Slow election time: $($avgElectionTime.ToString('F2'))ms"
            $allPassed = $false
        }
    } else {
        Add-TestResult -TestName "Raft-Performance" -Success $false -Message "No successful elections to measure"
        $allPassed = $false
    }
    
    return $allPassed
}

# Main test execution
function Start-RaftConsensusTests {
    Write-TestHeader "Starting Raft Consensus Tests"
    
    # Wait for services to be ready
    if (-not (Wait-ForService -Url $Global:TestConfig.BaseUrl -MaxWaitSeconds 60)) {
        Write-TestError "Services not ready, aborting tests"
        return $false
    }
    
    # Run all tests
    $initResult = Test-RaftInitialization
    $electionResult = Test-LeaderElection
    $electionAPIResult = Test-LeaderElectionAPI
    $consistencyResult = Test-ConsensusConsistency
    $faultResult = Test-FaultTolerance
    $clusterResult = Test-ClusterManagement
    $perfResult = Test-RaftPerformance
    
    # Overall result
    $overallSuccess = $initResult -and $electionResult -and $electionAPIResult -and $consistencyResult -and $faultResult -and $clusterResult -and $perfResult
    
    if ($overallSuccess) {
        Write-TestSuccess "All Raft consensus tests passed"
    } else {
        Write-TestError "Some Raft consensus tests failed"
    }
    
    return $overallSuccess
}

# Execute tests if run directly
if ($MyInvocation.InvocationName -ne '.') {
    Start-RaftConsensusTests
    Get-TestSummary
    Invoke-TestCleanup
}
