# Common test utilities and functions
# Eliminates code duplication across all test files

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$ApiUrl = "http://localhost:8080/api/v1",
    [int]$TimeoutSeconds = 30,
    [switch]$Verbose
)

# Global test configuration
$Global:TestConfig = @{
    BaseUrl = $BaseUrl
    ApiUrl = $ApiUrl
    TimeoutSeconds = $TimeoutSeconds
    Verbose = $Verbose
    StartTime = Get-Date
    TestResults = @()
    ParallelJobs = @()
}

# Color output functions
function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Blue
}

function Write-TestSuccess {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-TestError {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-TestInfo {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Cyan
}

function Write-TestWarning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

# Enhanced HTTP request function with retry logic
function Invoke-TestRequest {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [object]$Body = $null,
        [int]$ExpectedStatus = 200,
        [int]$RetryCount = 3,
        [int]$RetryDelay = 2
    )
    
    for ($i = 0; $i -le $RetryCount; $i++) {
        try {
            $params = @{
                Uri = $Url
                Method = $Method
                UseBasicParsing = $true
                TimeoutSec = $Global:TestConfig.TimeoutSeconds
            }
            
            if ($Body) {
                $params.Body = ($Body | ConvertTo-Json -Depth 10)
                $params.ContentType = "application/json"
            }
            
            $response = Invoke-WebRequest @params
            
            if ($response.StatusCode -eq $ExpectedStatus) {
                if ($Global:TestConfig.Verbose) {
                    Write-TestInfo "$Method $Url - Status: $($response.StatusCode)"
                }
                return $response
            } else {
                throw "Unexpected status code: $($response.StatusCode)"
            }
        }
        catch {
            if ($i -eq $RetryCount) {
                Write-TestError "$Method $Url - Failed after $($RetryCount + 1) attempts: $($_.Exception.Message)"
                return $null
            }
            if ($Global:TestConfig.Verbose) {
                Write-TestWarning "$Method $Url - Attempt $($i + 1) failed, retrying in $RetryDelay seconds..."
            }
            Start-Sleep -Seconds $RetryDelay
        }
    }
}

# Parallel test execution
function Start-ParallelTest {
    param(
        [string]$TestName,
        [scriptblock]$TestScript,
        [int]$TimeoutSeconds = 60
    )
    
    $job = Start-Job -Name $TestName -ScriptBlock $TestScript
    $Global:TestConfig.ParallelJobs += $job
    
    if ($Global:TestConfig.Verbose) {
        Write-TestInfo "Started parallel test: $TestName"
    }
    
    return $job
}

function Wait-ForParallelTests {
    param([int]$TimeoutSeconds = 300)
    
    Write-TestInfo "Waiting for $($Global:TestConfig.ParallelJobs.Count) parallel tests to complete..."
    
    $results = @()
    foreach ($job in $Global:TestConfig.ParallelJobs) {
        try {
            $result = Wait-Job -Job $job -Timeout $TimeoutSeconds
            if ($result) {
                $jobResult = Receive-Job -Job $job
                $results += @{
                    Name = $job.Name
                    Success = $jobResult.Success
                    Message = $jobResult.Message
                    Duration = $jobResult.Duration
                }
                Remove-Job -Job $job
            } else {
                Write-TestError "Test $($job.Name) timed out"
                Stop-Job -Job $job
                Remove-Job -Job $job
            }
        }
        catch {
            Write-TestError "Error in parallel test $($job.Name): $($_.Exception.Message)"
        }
    }
    
    $Global:TestConfig.ParallelJobs = @()
    return $results
}

# Docker management functions
function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-DockerContainers {
    param([string]$Filter = "")
    
    if ($Filter) {
        return docker ps --filter $Filter --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"
    } else {
        return docker ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"
    }
}

function Wait-ForService {
    param(
        [string]$Url,
        [int]$MaxWaitSeconds = 60,
        [int]$CheckInterval = 2
    )
    
    $startTime = Get-Date
    Write-TestInfo "Waiting for service at $Url (max $MaxWaitSeconds seconds)..."
    
    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($MaxWaitSeconds)) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-TestSuccess "Service is available at $Url"
                return $true
            }
        }
        catch {
            # Service not ready yet
        }
        
        Start-Sleep -Seconds $CheckInterval
    }
    
    Write-TestError "Service at $Url not available after $MaxWaitSeconds seconds"
    return $false
}

# Test result tracking
function Add-TestResult {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Message = "",
        [string]$Category = "General",
        [double]$Duration = 0
    )
    
    $result = @{
        TestName = $TestName
        Success = $Success
        Message = $Message
        Category = $Category
        Duration = $Duration
        Timestamp = Get-Date
    }
    
    $Global:TestConfig.TestResults += $result
    
    if ($Success) {
        Write-TestSuccess "$TestName - $Message"
    } else {
        Write-TestError "$TestName - $Message"
    }
}

function Get-TestSummary {
    $total = $Global:TestConfig.TestResults.Count
    $passed = ($Global:TestConfig.TestResults | Where-Object { $_.Success }).Count
    $failed = $total - $passed
    $duration = (Get-Date) - $Global:TestConfig.StartTime
    
    Write-TestHeader "TEST SUMMARY"
    Write-Host "Total Tests: $total" -ForegroundColor White
    Write-Host "Passed: $passed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor Red
    Write-Host "Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Cyan
    
    if ($failed -gt 0) {
        Write-TestHeader "FAILED TESTS"
        $Global:TestConfig.TestResults | Where-Object { -not $_.Success } | ForEach-Object {
            Write-TestError "$($_.TestName): $($_.Message)"
        }
    }
    
    return @{
        Total = $total
        Passed = $passed
        Failed = $failed
        Duration = $duration
    }
}

# Performance testing utilities
function Measure-Performance {
    param(
        [string]$TestName,
        [scriptblock]$TestScript,
        [int]$Iterations = 1
    )
    
    $results = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        $startTime = Get-Date
        try {
            $result = & $TestScript
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalMilliseconds
            
            $results += @{
                Iteration = $i
                Success = $true
                Duration = $duration
                Result = $result
            }
            
            if ($Global:TestConfig.Verbose) {
                Write-TestInfo "$TestName - Iteration $i completed in $($duration.ToString('F2'))ms"
            }
        }
        catch {
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalMilliseconds
            
            $results += @{
                Iteration = $i
                Success = $false
                Duration = $duration
                Error = $_.Exception.Message
            }
            
            Write-TestError "$TestName - Iteration $i failed: $($_.Exception.Message)"
        }
    }
    
    $avgDuration = ($results | Where-Object { $_.Success } | Measure-Object -Property Duration -Average).Average
    $successRate = (($results | Where-Object { $_.Success }).Count / $results.Count) * 100
    
    return @{
        TestName = $TestName
        Iterations = $Iterations
        AverageDuration = $avgDuration
        SuccessRate = $successRate
        Results = $results
    }
}

# Cleanup function
function Invoke-TestCleanup {
    Write-TestInfo "Cleaning up test environment..."
    
    # Stop any running parallel jobs
    if ($Global:TestConfig.ParallelJobs.Count -gt 0) {
        $Global:TestConfig.ParallelJobs | ForEach-Object {
            Stop-Job -Job $_ -ErrorAction SilentlyContinue
            Remove-Job -Job $_ -ErrorAction SilentlyContinue
        }
        $Global:TestConfig.ParallelJobs = @()
    }
    
    # Clean up any temporary files
    Get-ChildItem -Path "." -Filter "test-*" -File | Remove-Item -Force -ErrorAction SilentlyContinue
    
    Write-TestSuccess "Cleanup completed"
}

# Export functions for use in other test files
Export-ModuleMember -Function @(
    'Write-TestHeader', 'Write-TestSuccess', 'Write-TestError', 'Write-TestInfo', 'Write-TestWarning',
    'Invoke-TestRequest', 'Start-ParallelTest', 'Wait-ForParallelTests',
    'Test-DockerRunning', 'Get-DockerContainers', 'Wait-ForService',
    'Add-TestResult', 'Get-TestSummary', 'Measure-Performance', 'Invoke-TestCleanup'
)
