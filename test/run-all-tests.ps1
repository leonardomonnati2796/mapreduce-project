# Comprehensive test runner for MapReduce project
# Optimized, parallel, and covers all aspects of the system

param(
    [string]$BaseUrl = "http://localhost:8080",
    [switch]$Verbose,
    [switch]$Performance,
    [switch]$FaultTolerance,
    [switch]$S3,
    [switch]$Parallel,
    [string]$Categories = "all",
    [string]$OutputFormat = "console",
    [string]$OutputFile = "",
    [int]$TimeoutSeconds = 300,
    [int]$MaxParallelJobs = 5,
    [switch]$Cleanup,
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host @"
MapReduce Test Suite - Optimized Test Runner

USAGE:
    .\test\run-all-tests.ps1 [OPTIONS]

OPTIONS:
    -BaseUrl <url>           Dashboard base URL (default: http://localhost:8080)
    -Verbose                 Enable verbose output
    -Performance             Enable performance testing
    -FaultTolerance          Enable fault tolerance testing
    -S3                      Enable S3 integration testing
    -Parallel                Enable parallel test execution
    -Categories <list>       Test categories to run (default: all)
                            Available: core, raft, integration, api, dashboard, cluster
    -OutputFormat <format>   Output format: console, json, xml (default: console)
    -OutputFile <path>       Output file path (optional)
    -TimeoutSeconds <sec>    Test timeout in seconds (default: 300)
    -MaxParallelJobs <num>   Maximum parallel jobs (default: 5)
    -Cleanup                 Clean up test environment after completion
    -Help                    Show this help message

EXAMPLES:
    # Run all tests
    .\test\run-all-tests.ps1

    # Run specific categories
    .\test\run-all-tests.ps1 -Categories "core,api" -Verbose

    # Run with performance testing
    .\test\run-all-tests.ps1 -Performance -Parallel

    # Run with fault tolerance
    .\test\run-all-tests.ps1 -FaultTolerance -S3

    # Run with custom output
    .\test\run-all-tests.ps1 -OutputFormat json -OutputFile "test-results.json"

TEST CATEGORIES:
    core         - Core MapReduce functions (Map, Reduce, hashing, file ops)
    raft         - Raft consensus algorithm and leader election
    integration  - Complete MapReduce pipeline and job processing
    api          - All API endpoints and error handling
    dashboard    - Web interface and real-time updates
    cluster      - Dynamic cluster management and scaling

PERFORMANCE OPTIMIZATIONS:
    - Parallel test execution for independent tests
    - Service warmup before testing
    - Optimized HTTP requests with retry logic
    - Comprehensive error handling and reporting
    - Memory and resource cleanup
"@
    exit 0
}

# Import common test utilities
. "$PSScriptRoot\test-common.ps1" -Verbose:$Verbose -BaseUrl $BaseUrl -TimeoutSeconds $TimeoutSeconds

Write-TestHeader "MAPREDUCE COMPREHENSIVE TEST SUITE"

# Test categories configuration
$testCategories = @{
    "core" = @{
        Name = "Core Functions"
        Script = "test-core-functions.ps1"
        Parameters = @{ Verbose = $Verbose; Performance = $Performance }
        Parallel = $false
        Dependencies = @()
    }
    "raft" = @{
        Name = "Raft Consensus"
        Script = "test-raft-consensus.ps1"
        Parameters = @{ Verbose = $Verbose; FaultTolerance = $FaultTolerance }
        Parallel = $false
        Dependencies = @("core")
    }
    "integration" = @{
        Name = "Integration Tests"
        Script = "test-integration.ps1"
        Parameters = @{ Verbose = $Verbose; Performance = $Performance; S3 = $S3 }
        Parallel = $false
        Dependencies = @("core", "raft")
    }
    "api" = @{
        Name = "API Tests"
        Script = "test-api-comprehensive.ps1"
        Parameters = @{ Verbose = $Verbose; Performance = $Performance }
        Parallel = $true
        Dependencies = @("core")
    }
    "dashboard" = @{
        Name = "Dashboard Tests"
        Script = "test-dashboard-comprehensive.ps1"
        Parameters = @{ Verbose = $Verbose }
        Parallel = $true
        Dependencies = @("api")
    }
    "cluster" = @{
        Name = "Cluster Management"
        Script = "test-cluster-management.ps1"
        Parameters = @{ Verbose = $Verbose; FaultTolerance = $FaultTolerance }
        Parallel = $false
        Dependencies = @("raft", "api")
    }
}

# Determine which categories to run
function Get-TestCategories {
    param([string]$Categories)
    
    if ($Categories -eq "all") {
        return $testCategories.Keys
    } else {
        $requested = $Categories -split ',' | ForEach-Object { $_.Trim() }
        $valid = @()
        foreach ($cat in $requested) {
            if ($testCategories.ContainsKey($cat)) {
                $valid += $cat
            } else {
                Write-TestWarning "Unknown test category: $cat"
            }
        }
        return $valid
    }
}

# Resolve dependencies
function Resolve-TestDependencies {
    param([string[]]$Categories)
    
    $resolved = @()
    $toResolve = $Categories.Clone()
    
    while ($toResolve.Count -gt 0) {
        $category = $toResolve[0]
        $toResolve = $toResolve[1..($toResolve.Count-1)]
        
        if ($resolved -notcontains $category) {
            $dependencies = $testCategories[$category].Dependencies
            foreach ($dep in $dependencies) {
                if ($resolved -notcontains $dep -and $toResolve -notcontains $dep) {
                    $toResolve += $dep
                }
            }
            $resolved += $category
        }
    }
    
    return $resolved
}

# Run a single test category
function Invoke-TestCategory {
    param(
        [string]$Category,
        [hashtable]$Config
    )
    
    $scriptPath = Join-Path $PSScriptRoot $Config.Script
    
    if (-not (Test-Path $scriptPath)) {
        Write-TestError "Test script not found: $scriptPath"
        return @{ Success = $false; Message = "Script not found"; Duration = 0 }
    }
    
    $startTime = Get-Date
    
    try {
        # Build parameter string
        $paramString = ""
        foreach ($param in $Config.Parameters.GetEnumerator()) {
            if ($param.Value -is [bool]) {
                if ($param.Value) {
                    $paramString += " -$($param.Key)"
                }
            } else {
                $paramString += " -$($param.Key) '$($param.Value)'"
            }
        }
        
        # Execute the test script
        $command = "& '$scriptPath'$paramString"
        $result = Invoke-Expression $command
        
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        return @{
            Success = $result
            Message = "Completed in $($duration.ToString('F2')) seconds"
            Duration = $duration
        }
    }
    catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        return @{
            Success = $false
            Message = "Error: $($_.Exception.Message)"
            Duration = $duration
        }
    }
}

# Run tests with dependency resolution
function Start-TestExecution {
    param([string[]]$Categories)
    
    Write-TestHeader "Starting Test Execution"
    
    # Resolve dependencies
    $resolvedCategories = Resolve-TestDependencies -Categories $Categories
    Write-TestInfo "Test execution order: $($resolvedCategories -join ' -> ')"
    
    $results = @()
    
    foreach ($category in $resolvedCategories) {
        $config = $testCategories[$category]
        Write-TestInfo "Running $($config.Name)..."
        
        $result = Invoke-TestCategory -Category $category -Config $config
        $results += @{
            Category = $category
            Name = $config.Name
            Success = $result.Success
            Message = $result.Message
            Duration = $result.Duration
        }
        
        Add-TestResult -TestName $config.Name -Success $result.Success -Message $result.Message -Duration $result.Duration
        
        # If a critical test fails, stop execution
        if (-not $result.Success -and $category -in @("core", "raft")) {
            Write-TestError "Critical test failed: $($config.Name). Stopping execution."
            break
        }
    }
    
    return $results
}

# Generate output in specified format
function Export-TestResults {
    param(
        [array]$Results,
        [string]$Format,
        [string]$FilePath
    )
    
    switch ($Format.ToLower()) {
        "json" {
            $json = $Results | ConvertTo-Json -Depth 10
            if ($FilePath) {
                $json | Out-File -FilePath $FilePath -Encoding UTF8
                Write-TestInfo "Results exported to: $FilePath"
            } else {
                Write-Output $json
            }
        }
        "xml" {
            $xml = $Results | ConvertTo-Xml -Depth 10
            if ($FilePath) {
                $xml | Out-File -FilePath $FilePath -Encoding UTF8
                Write-TestInfo "Results exported to: $FilePath"
            } else {
                Write-Output $xml
            }
        }
        default {
            # Console output is handled by Get-TestSummary
            if ($FilePath) {
                $summary = Get-TestSummary
                $summary | Out-File -FilePath $FilePath -Encoding UTF8
                Write-TestInfo "Results exported to: $FilePath"
            }
        }
    }
}

# Main execution function
function Start-ComprehensiveTestSuite {
    Write-TestHeader "Starting Comprehensive Test Suite"
    
    # Get categories to run
    $categoriesToRun = Get-TestCategories -Categories $Categories
    
    if ($categoriesToRun.Count -eq 0) {
        Write-TestError "No valid test categories specified"
        return $false
    }
    
    Write-TestInfo "Running test categories: $($categoriesToRun -join ', ')"
    Write-TestInfo "Parallel execution: $Parallel"
    Write-TestInfo "Performance testing: $Performance"
    Write-TestInfo "Fault tolerance: $FaultTolerance"
    Write-TestInfo "S3 integration: $S3"
    
    # Pre-warm services for better performance
    Write-TestInfo "Warming up services..."
    Start-ServiceWarmup
    
    # Execute tests
    $results = Start-TestExecution -Categories $categoriesToRun
    
    # Generate comprehensive report
    $summary = Get-TestSummary
    
    # Performance analysis
    if ($Performance) {
        Write-TestHeader "Performance Analysis"
        
        $totalDuration = $summary.Duration.TotalSeconds
        $testsPerSecond = if ($summary.Total -gt 0) { $summary.Total / $totalDuration } else { 0 }
        
        Write-TestInfo "Total execution time: $($totalDuration.ToString('F2')) seconds"
        Write-TestInfo "Tests per second: $($testsPerSecond.ToString('F2'))"
        Write-TestInfo "Success rate: $(($summary.Passed / $summary.Total * 100).ToString('F1'))%"
    }
    
    # Export results
    if ($OutputFormat -ne "console" -or $OutputFile) {
        Export-TestResults -Results $results -Format $OutputFormat -FilePath $OutputFile
    }
    
    # Recommendations
    if ($summary.Failed -gt 0) {
        Write-TestHeader "Recommendations"
        Write-TestWarning "Some tests failed. Consider:"
        Write-TestWarning "- Checking service status and logs"
        Write-TestWarning "- Verifying Docker containers are running"
        Write-TestWarning "- Running individual test categories for debugging"
        Write-TestWarning "- Checking system resources (CPU, memory, disk)"
    }
    
    # Cleanup if requested
    if ($Cleanup) {
        Write-TestInfo "Cleaning up test environment..."
        Invoke-TestCleanup
    }
    
    return $summary.Failed -eq 0
}

# Execute if run directly
if ($MyInvocation.InvocationName -ne '.') {
    $success = Start-ComprehensiveTestSuite
    
    if ($success) {
        Write-TestSuccess "All tests completed successfully"
        exit 0
    } else {
        Write-TestError "Some tests failed"
        exit 1
    }
}
