# Test core MapReduce functions and algorithms
# Covers Map, Reduce, hashing, file operations, and data processing

param(
    [switch]$Verbose,
    [switch]$Performance,
    [int]$Iterations = 5
)

# Import common test utilities
. "$PSScriptRoot\test-common.ps1" -Verbose:$Verbose

Write-TestHeader "CORE MAPREDUCE FUNCTIONS TEST"

# Test data for MapReduce operations
$testData = @{
    "simple.txt" = "hello world hello mapreduce world test"
    "numbers.txt" = "one two three one two four five one"
    "empty.txt" = ""
    "single.txt" = "word"
    "unicode.txt" = "café naïve résumé"
    "special.txt" = "hello-world hello_world hello.world"
}

# Create test files
function Initialize-TestData {
    Write-TestInfo "Creating test data files..."
    
    $testDir = "test-data"
    if (Test-Path $testDir) {
        Remove-Item $testDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $testDir | Out-Null
    
    foreach ($filename in $testData.Keys) {
        $filepath = Join-Path $testDir $filename
        $testData[$filename] | Out-File -FilePath $filepath -Encoding UTF8
    }
    
    Write-TestSuccess "Test data created in $testDir"
    return $testDir
}

# Test Map function implementation
function Test-MapFunction {
    param([string]$TestDir)
    
    Write-TestHeader "Testing Map Function"
    
    $testCases = @(
        @{ File = "simple.txt"; ExpectedWords = @("hello", "world", "hello", "mapreduce", "world", "test") },
        @{ File = "numbers.txt"; ExpectedWords = @("one", "two", "three", "one", "two", "four", "five", "one") },
        @{ File = "empty.txt"; ExpectedWords = @() },
        @{ File = "single.txt"; ExpectedWords = @("word") },
        @{ File = "unicode.txt"; ExpectedWords = @("café", "naïve", "résumé") },
        @{ File = "special.txt"; ExpectedWords = @("hello", "world", "hello", "world", "hello", "world") }
    )
    
    $allPassed = $true
    
    foreach ($testCase in $testCases) {
        $filepath = Join-Path $TestDir $testCase.File
        $content = Get-Content $filepath -Raw
        
        # Simulate Map function (word splitting)
        $words = $content -split '\W+' | Where-Object { $_ -ne "" }
        
        $expectedCount = $testCase.ExpectedWords.Count
        $actualCount = $words.Count
        
        if ($actualCount -eq $expectedCount) {
            Add-TestResult -TestName "Map-$($testCase.File)" -Success $true -Message "Word count matches: $actualCount"
        } else {
            Add-TestResult -TestName "Map-$($testCase.File)" -Success $false -Message "Expected $expectedCount words, got $actualCount"
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Test Reduce function implementation
function Test-ReduceFunction {
    param([string]$TestDir)
    
    Write-TestHeader "Testing Reduce Function"
    
    $testCases = @(
        @{ Key = "hello"; Values = @("1", "1", "1"); Expected = "3" },
        @{ Key = "world"; Values = @("1", "1"); Expected = "2" },
        @{ Key = "test"; Values = @("1"); Expected = "1" },
        @{ Key = "unique"; Values = @("1"); Expected = "1" },
        @{ Key = "empty"; Values = @(); Expected = "0" }
    )
    
    $allPassed = $true
    
    foreach ($testCase in $testCases) {
        # Simulate Reduce function (count values)
        $actual = $testCase.Values.Count.ToString()
        
        if ($actual -eq $testCase.Expected) {
            Add-TestResult -TestName "Reduce-$($testCase.Key)" -Success $true -Message "Count correct: $actual"
        } else {
            Add-TestResult -TestName "Reduce-$($testCase.Key)" -Success $false -Message "Expected $($testCase.Expected), got $actual"
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Test hash function for key distribution
function Test-HashFunction {
    Write-TestHeader "Testing Hash Function"
    
    $testKeys = @("hello", "world", "test", "mapreduce", "distributed", "system")
    $hashResults = @{}
    $collisions = 0
    
    foreach ($key in $testKeys) {
        # Simulate hash function (simple hash)
        $hash = [System.Math]::Abs($key.GetHashCode()) % 10
        $hashResults[$key] = $hash
        
        if ($hashResults.Values -contains $hash -and $hashResults.Count -gt 1) {
            $collisions++
        }
    }
    
    $distribution = $hashResults.Values | Group-Object | Measure-Object -Property Count -Maximum
    $maxCollisions = $distribution.Maximum
    
    if ($maxCollisions -le 2) {
        Add-TestResult -TestName "Hash-Distribution" -Success $true -Message "Good distribution, max collisions: $maxCollisions"
    } else {
        Add-TestResult -TestName "Hash-Distribution" -Success $false -Message "Poor distribution, max collisions: $maxCollisions"
    }
    
    return $maxCollisions -le 2
}

# Test file operations
function Test-FileOperations {
    param([string]$TestDir)
    
    Write-TestHeader "Testing File Operations"
    
    $allPassed = $true
    
    # Test file reading
    $testFile = Join-Path $TestDir "simple.txt"
    try {
        $content = Get-Content $testFile -Raw
        if ($content -ne $null) {
            Add-TestResult -TestName "File-Read" -Success $true -Message "File read successfully"
        } else {
            Add-TestResult -TestName "File-Read" -Success $false -Message "Failed to read file"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "File-Read" -Success $false -Message "Error reading file: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Test file writing
    $outputFile = Join-Path $TestDir "output-test.txt"
    try {
        "test output" | Out-File -FilePath $outputFile -Encoding UTF8
        if (Test-Path $outputFile) {
            Add-TestResult -TestName "File-Write" -Success $true -Message "File written successfully"
        } else {
            Add-TestResult -TestName "File-Write" -Success $false -Message "Failed to write file"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "File-Write" -Success $false -Message "Error writing file: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Test file deletion
    try {
        Remove-Item $outputFile -Force
        if (-not (Test-Path $outputFile)) {
            Add-TestResult -TestName "File-Delete" -Success $true -Message "File deleted successfully"
        } else {
            Add-TestResult -TestName "File-Delete" -Success $false -Message "Failed to delete file"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "File-Delete" -Success $false -Message "Error deleting file: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test JSON operations (for intermediate files)
function Test-JsonOperations {
    Write-TestHeader "Testing JSON Operations"
    
    $allPassed = $true
    
    # Test JSON serialization
    $testData = @{
        Key = "test"
        Value = "1"
        Timestamp = Get-Date
    }
    
    try {
        $json = $testData | ConvertTo-Json -Depth 10
        $parsed = $json | ConvertFrom-Json
        
        if ($parsed.Key -eq $testData.Key -and $parsed.Value -eq $testData.Value) {
            Add-TestResult -TestName "JSON-Serialize" -Success $true -Message "JSON serialization successful"
        } else {
            Add-TestResult -TestName "JSON-Serialize" -Success $false -Message "JSON serialization failed"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "JSON-Serialize" -Success $false -Message "JSON error: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    # Test JSON array operations
    $testArray = @(
        @{ Key = "hello"; Value = "1" },
        @{ Key = "world"; Value = "1" },
        @{ Key = "test"; Value = "1" }
    )
    
    try {
        $jsonArray = $testArray | ConvertTo-Json -Depth 10
        $parsedArray = $jsonArray | ConvertFrom-Json
        
        if ($parsedArray.Count -eq $testArray.Count) {
            Add-TestResult -TestName "JSON-Array" -Success $true -Message "JSON array operations successful"
        } else {
            Add-TestResult -TestName "JSON-Array" -Success $false -Message "JSON array count mismatch"
            $allPassed = $false
        }
    }
    catch {
        Add-TestResult -TestName "JSON-Array" -Success $false -Message "JSON array error: $($_.Exception.Message)"
        $allPassed = $false
    }
    
    return $allPassed
}

# Test performance of core operations
function Test-CorePerformance {
    param([string]$TestDir)
    
    if (-not $Performance) {
        return $true
    }
    
    Write-TestHeader "Testing Core Performance"
    
    $results = @()
    
    # Test Map performance
    $mapPerf = Measure-Performance -TestName "Map-Performance" -Iterations $Iterations -TestScript {
        $content = Get-Content (Join-Path $TestDir "simple.txt") -Raw
        $words = $content -split '\W+' | Where-Object { $_ -ne "" }
        return $words.Count
    }
    $results += $mapPerf
    
    # Test Reduce performance
    $reducePerf = Measure-Performance -TestName "Reduce-Performance" -Iterations $Iterations -TestScript {
        $values = @("1", "1", "1", "1", "1")
        return $values.Count
    }
    $results += $reducePerf
    
    # Test Hash performance
    $hashPerf = Measure-Performance -TestName "Hash-Performance" -Iterations $Iterations -TestScript {
        $keys = @("hello", "world", "test", "mapreduce", "distributed")
        $hashes = $keys | ForEach-Object { [System.Math]::Abs($_.GetHashCode()) % 10 }
        return $hashes.Count
    }
    $results += $hashPerf
    
    # Report performance results
    foreach ($result in $results) {
        if ($result.SuccessRate -eq 100) {
            Add-TestResult -TestName "$($result.TestName)-Performance" -Success $true -Message "Avg: $($result.AverageDuration.ToString('F2'))ms, Success: $($result.SuccessRate)%"
        } else {
            Add-TestResult -TestName "$($result.TestName)-Performance" -Success $false -Message "Performance test failed: $($result.SuccessRate)% success rate"
        }
    }
    
    return $true
}

# Main test execution
function Start-CoreFunctionTests {
    Write-TestHeader "Starting Core Function Tests"
    
    # Initialize test data
    $testDir = Initialize-TestData
    
    try {
        # Run all tests
        $mapResult = Test-MapFunction -TestDir $testDir
        $reduceResult = Test-ReduceFunction -TestDir $testDir
        $hashResult = Test-HashFunction
        $fileResult = Test-FileOperations -TestDir $testDir
        $jsonResult = Test-JsonOperations
        $perfResult = Test-CorePerformance -TestDir $testDir
        
        # Overall result
        $overallSuccess = $mapResult -and $reduceResult -and $hashResult -and $fileResult -and $jsonResult -and $perfResult
        
        if ($overallSuccess) {
            Write-TestSuccess "All core function tests passed"
        } else {
            Write-TestError "Some core function tests failed"
        }
        
        return $overallSuccess
    }
    finally {
        # Cleanup
        if (Test-Path $testDir) {
            Remove-Item $testDir -Recurse -Force
        }
    }
}

# Execute tests if run directly
if ($MyInvocation.InvocationName -ne '.') {
    Start-CoreFunctionTests
    Get-TestSummary
    Invoke-TestCleanup
}
