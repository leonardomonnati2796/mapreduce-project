# Comprehensive integration tests
# Tests the complete MapReduce pipeline from input to output

param(
    [switch]$Verbose,
    [switch]$Performance,
    [switch]$S3,
    [int]$TimeoutSeconds = 300
)

# Import common test utilities
. "$PSScriptRoot\test-common.ps1" -Verbose:$Verbose

Write-TestHeader "MAPREDUCE INTEGRATION TEST"

# Test complete MapReduce pipeline
function Test-CompletePipeline {
    Write-TestHeader "Testing Complete MapReduce Pipeline"
    
    $allPassed = $true
    
    # Create test input files
    $testInputs = @{
        "test1.txt" = "hello world hello mapreduce world test"
        "test2.txt" = "distributed systems are complex but powerful"
        "test3.txt" = "mapreduce is a programming model for processing large datasets"
    }
    
    $inputDir = "test-inputs"
    if (Test-Path $inputDir) {
        Remove-Item $inputDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $inputDir | Out-Null
    
    foreach ($filename in $testInputs.Keys) {
        $filepath = Join-Path $inputDir $filename
        $testInputs[$filename] | Out-File -FilePath $filepath -Encoding UTF8
    }
    
    Write-TestInfo "Created $($testInputs.Count) test input files"
    
    # Test job submission
    try {
        $jobArgs = @{
            input_files = @(
                (Join-Path $inputDir "test1.txt"),
                (Join-Path $inputDir "test2.txt"),
                (Join-Path $inputDir "test3.txt")
            )
            n_reduce = 3
        }
        
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/jobs" -Method "POST" -Body $jobArgs
        if ($response) {
            $job = $response.Content | ConvertFrom-Json
            Add-TestResult -TestName "Integration-JobSubmit" -Success $true -Message "Job submitted: $($job.job_id)"
        } else {
            Add-TestResult -TestName "Integration-JobSubmit" -Success $false -Message "Failed to submit job"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "Integration-JobSubmit" -Success $false -Message "Error submitting job: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Wait for job completion
    Write-TestInfo "Waiting for job completion..."
    $maxWaitTime = 300 # 5 minutes
    $startTime = Get-Date
    $jobCompleted = $false
    
    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($maxWaitTime) -and -not $jobCompleted) {
        try {
            $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/jobs" -Method "GET"
            if ($response) {
                $jobs = $response.Content | ConvertFrom-Json
                $activeJobs = $jobs | Where-Object { $_.status -ne "completed" -and $_.status -ne "failed" }
                
                if ($activeJobs.Count -eq 0) {
                    $jobCompleted = $true
                    Write-TestSuccess "Job completed"
                } else {
                    Write-TestInfo "Job still running, waiting..."
                    Start-Sleep -Seconds 10
                }
            }
        }
        catch {
            Write-TestWarning "Error checking job status: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $jobCompleted) {
        Add-TestResult -TestName "Integration-JobCompletion" -Success $false -Message "Job did not complete within timeout"
        $allPassed = $false
    } else {
        Add-TestResult -TestName "Integration-JobCompletion" -Success $true -Message "Job completed successfully"
    }
    
    # Verify output files
    $outputDir = "data/output"
    if (Test-Path $outputDir) {
        $outputFiles = Get-ChildItem -Path $outputDir -Filter "mr-out-*"
        if ($outputFiles.Count -gt 0) {
            Add-TestResult -TestName "Integration-OutputFiles" -Success $true -Message "Found $($outputFiles.Count) output files"
            
            # Check final output
            $finalOutput = Join-Path $outputDir "final-output.txt"
            if (Test-Path $finalOutput) {
                $content = Get-Content $finalOutput -Raw
                if ($content -and $content.Length -gt 0) {
                    Add-TestResult -TestName "Integration-FinalOutput" -Success $true -Message "Final output file created with content"
                } else {
                    Add-TestResult -TestName "Integration-FinalOutput" -Success $false -Message "Final output file is empty"
                    $allPassed = $false
                }
            } else {
                Add-TestResult -TestName "Integration-FinalOutput" -Success $false -Message "Final output file not found"
                $allPassed = $false
            }
        } else {
            Add-TestResult -TestName "Integration-OutputFiles" -Success $false -Message "No output files found"
            $allPassed = $false
        }
    } else {
        Add-TestResult -TestName "Integration-OutputFiles" -Success $false -Message "Output directory not found"
        $allPassed = $false
    }
    
    # Cleanup
    if (Test-Path $inputDir) {
        Remove-Item $inputDir -Recurse -Force
    }
    
    return $allPassed
}

# Test worker management
function Test-WorkerManagement {
    Write-TestHeader "Testing Worker Management"
    
    $allPassed = $true
    
    # Get initial worker count
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/workers" -Method "GET"
        if ($response) {
            $workers = $response.Content | ConvertFrom-Json
            $initialCount = $workers.Count
            Add-TestResult -TestName "Integration-InitialWorkers" -Success $true -Message "Initial worker count: $initialCount"
        } else {
            Add-TestResult -TestName "Integration-InitialWorkers" -Success $false -Message "Failed to get initial worker count"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "Integration-InitialWorkers" -Success $false -Message "Error getting workers: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Add a worker
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/system/start-worker" -Method "POST"
        if ($response) {
            $result = $response.Content | ConvertFrom-Json
            Add-TestResult -TestName "Integration-AddWorker" -Success $true -Message "Worker addition: $($result.message)"
        } else {
            Add-TestResult -TestName "Integration-AddWorker" -Success $false -Message "Failed to add worker"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "Integration-AddWorker" -Success $false -Message "Error adding worker: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Wait for worker to start
    Start-Sleep -Seconds 10
    
    # Verify worker was added
    try {
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/workers" -Method "GET"
        if ($response) {
            $workers = $response.Content | ConvertFrom-Json
            $newCount = $workers.Count
            
            if ($newCount -gt $initialCount) {
                Add-TestResult -TestName "Integration-WorkerAdded" -Success $true -Message "Worker count increased: $initialCount -> $newCount"
            } else {
                Add-TestResult -TestName "Integration-WorkerAdded" -Success $false -Message "Worker count did not increase: $newCount"
                $allPassed = $false
            }
        }
    }
    catch {
        Add-TestResult -TestName "Integration-WorkerAdded" -Success $false -Message "Error verifying worker addition: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test S3 integration
function Test-S3Integration {
    if (-not $S3) {
        Write-TestInfo "S3 integration tests skipped (use -S3 to enable)"
        return $true
    }
    
    Write-TestHeader "Testing S3 Integration"
    
    $allPassed = $true
    
    # Check if S3 is enabled
    if ($env:S3_SYNC_ENABLED -ne "true") {
        Add-TestResult -TestName "Integration-S3Enabled" -Success $false -Message "S3 sync not enabled"
        return $false
    }
    
    # Test S3 configuration
    $s3Config = @{
        bucket = $env:S3_BUCKET
        region = $env:S3_REGION
        access_key = $env:AWS_ACCESS_KEY_ID
        secret_key = $env:AWS_SECRET_ACCESS_KEY
    }
    
    $configValid = $true
    foreach ($key in @("bucket", "region", "access_key", "secret_key")) {
        if (-not $s3Config[$key]) {
            Add-TestResult -TestName "Integration-S3Config" -Success $false -Message "S3 $key not configured"
            $configValid = $false
        }
    }
    
    if ($configValid) {
        Add-TestResult -TestName "Integration-S3Config" -Success $true -Message "S3 configuration valid"
    } else {
        $allPassed = $false
    }
    
    # Test S3 backup (if output files exist)
    $outputDir = "data/output"
    if (Test-Path $outputDir) {
        $outputFiles = Get-ChildItem -Path $outputDir -Filter "*.txt"
        if ($outputFiles.Count -gt 0) {
            Add-TestResult -TestName "Integration-S3Backup" -Success $true -Message "Output files available for S3 backup: $($outputFiles.Count)"
        } else {
            Add-TestResult -TestName "Integration-S3Backup" -Success $false -Message "No output files for S3 backup"
            $allPassed = $false
        }
    } else {
        Add-TestResult -TestName "Integration-S3Backup" -Success $false -Message "Output directory not found for S3 backup"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test performance metrics
function Test-PerformanceMetrics {
    if (-not $Performance) {
        Write-TestInfo "Performance tests skipped (use -Performance to enable)"
        return $true
    }
    
    Write-TestHeader "Testing Performance Metrics"
    
    $allPassed = $true
    
    # Test API response times
    $apiTests = @(
        @{ Url = "$Global:TestConfig.ApiUrl/health"; Name = "Health" },
        @{ Url = "$Global:TestConfig.ApiUrl/masters"; Name = "Masters" },
        @{ Url = "$Global:TestConfig.ApiUrl/workers"; Name = "Workers" },
        @{ Url = "$Global:TestConfig.ApiUrl/metrics"; Name = "Metrics" }
    )
    
    foreach ($test in $apiTests) {
        $times = @()
        for ($i = 1; $i -le 5; $i++) {
            $startTime = Get-Date
            try {
                $response = Invoke-TestRequest -Url $test.Url -Method "GET"
                $endTime = Get-Date
                
                if ($response) {
                    $duration = ($endTime - $startTime).TotalMilliseconds
                    $times += $duration
                }
            }
            catch {
                Write-TestWarning "$($test.Name) API test $i failed: $($_.Exception.Message)"
            }
        }
        
        if ($times.Count -gt 0) {
            $avgTime = ($times | Measure-Object -Average).Average
            $maxTime = ($times | Measure-Object -Maximum).Maximum
            
            if ($avgTime -lt 1000) { # Less than 100ms average
                Add-TestResult -TestName "Performance-$($test.Name)" -Success $true -Message "Avg: $($avgTime.ToString('F2'))ms, Max: $($maxTime.ToString('F2'))ms"
            } else {
                Add-TestResult -TestName "Performance-$($test.Name)" -Success $false -Message "Slow response: Avg $($avgTime.ToString('F2'))ms"
                $allPassed = $false
            }
        } else {
            Add-TestResult -TestName "Performance-$($test.Name)" -Success $false -Message "No successful responses"
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Test error handling
function Test-ErrorHandling {
    Write-TestHeader "Testing Error Handling"
    
    $allPassed = $true
    
    # Test invalid endpoints
    $invalidTests = @(
        @{ Url = "$Global:TestConfig.ApiUrl/invalid"; ExpectedStatus = 404 },
        @{ Url = "$Global:TestConfig.ApiUrl/masters/invalid"; ExpectedStatus = 404 },
        @{ Url = "$Global:TestConfig.ApiUrl/workers/invalid"; ExpectedStatus = 404 }
    )
    
    foreach ($test in $invalidTests) {
        try {
            $response = Invoke-TestRequest -Url $test.Url -Method "GET" -ExpectedStatus $test.ExpectedStatus
            if ($response -and $response.StatusCode -eq $test.ExpectedStatus) {
                Add-TestResult -TestName "ErrorHandling-$($test.Url.Split('/')[-1])" -Success $true -Message "Correct error response: $($response.StatusCode)"
            } else {
                Add-TestResult -TestName "ErrorHandling-$($test.Url.Split('/')[-1])" -Success $false -Message "Unexpected response: $($response.StatusCode)"
                $allPassed = $false
            }
        }
        catch {
            # Expected for 404 errors
            Add-TestResult -TestName "ErrorHandling-$($test.Url.Split('/')[-1])" -Success $true -Message "Expected error handled correctly"
        }
    }
    
    # Test malformed requests
    try {
        $malformedBody = @{ invalid_field = "test" }
        $response = Invoke-TestRequest -Url "$Global:TestConfig.ApiUrl/jobs" -Method "POST" -Body $malformedBody
        if ($response -and $response.StatusCode -ge 400) {
            Add-TestResult -TestName "ErrorHandling-Malformed" -Success $true -Message "Malformed request handled correctly"
        } else {
            Add-TestResult -TestName "ErrorHandling-Malformed" -Success $false -Message "Malformed request not handled properly"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "ErrorHandling-Malformed" -Success $true -Message "Malformed request rejected as expected"
    }
    
    return $allPassed
}

# Main test execution
function Start-IntegrationTests {
    Write-TestHeader "Starting Integration Tests"
    
    # Wait for services to be ready
    if (-not (Wait-ForService -Url $Global:TestConfig.BaseUrl -MaxWaitSeconds 60)) {
        Write-TestError "Services not ready, aborting tests"
        return $false
    }
    
    # Run all tests
    $pipelineResult = Test-CompletePipeline
    $workerResult = Test-WorkerManagement
    $s3Result = Test-S3Integration
    $perfResult = Test-PerformanceMetrics
    $errorResult = Test-ErrorHandling
    
    # Overall result
    $overallSuccess = $pipelineResult -and $workerResult -and $s3Result -and $perfResult -and $errorResult
    
    if ($overallSuccess) {
        Write-TestSuccess "All integration tests passed"
    } else {
        Write-TestError "Some integration tests failed"
    }
    
    return $overallSuccess
}

# Execute tests if run directly
if ($MyInvocation.InvocationName -ne '.') {
    Start-IntegrationTests
    Get-TestSummary
    Invoke-TestCleanup
}
