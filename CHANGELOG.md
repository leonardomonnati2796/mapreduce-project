# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-10-04

### 🎉 Major Release - Complete System Overhaul

### Added
- **Structured Logging System** (`logger.go`)
  - DEBUG, INFO, WARN, ERROR levels
  - File and console output
  - Timestamp and context tracking
  - Color-coded messages
  - Replaced all 299 print statements

- **Advanced Load Balancer** (`loadbalancer.go`)
  - 5 balancing strategies (RoundRobin, WeightedRoundRobin, LeastConnections, Random, HealthBased)
  - Unified health checking system
  - Advanced fault tolerance mechanisms
  - Real-time statistics and monitoring
  - Server management (add, remove, update)

- **Enhanced Fault Tolerance**
  - Mapper failure recovery with data verification
  - Reducer failure recovery with checkpointing
  - Task verification and retry logic
  - Data integrity checks
  - Partial output cleanup

- **Infrastructure Health Monitoring** (`health.go`)
  - Disk space monitoring
  - Network connectivity checks
  - S3 connection status
  - Raft cluster health
  - Docker environment detection
  - System resource tracking
  - Performance metrics

- **S3 Storage Integration** (`s3.go`)
  - Automatic sync service
  - Backup and restore functionality
  - Job input/output management
  - Storage statistics
  - AWS deployment guides

- **Centralized Constants** (`constants.go`)
  - All timeouts and intervals
  - Task types and states
  - Job phases
  - Log levels
  - Default paths and network addresses

- **Comprehensive Test Suite**
  - Load balancer tests (`loadbalancer_test.go`)
  - Advanced fault tolerance tests (`advanced_fault_tolerance_test.go`)
  - System integration tests (`test_system.go`)
  - Test execution scripts (PowerShell and Bash)

- **Documentation**
  - AWS EC2 deployment guide
  - AWS S3 storage guide
  - Load balancer S3 integration guide
  - Fault tolerance optimization guide
  - Health vs Load balancer differentiation
  - Test guides and error resolution
  - Project structure documentation

- **Deployment Resources**
  - AWS Terraform configurations
  - Docker Compose files for AWS
  - Deployment automation scripts
  - S3 configuration scripts

- **Demo Files**
  - Fault tolerance demonstrations
  - Health monitoring demonstrations
  - S3 integration demonstrations

### Changed
- **Complete Logging Overhaul**
  - Replaced all `fmt.Print*` with structured logging in:
    - `main.go` (20 replacements)
    - `mapreduce.go` (18 replacements)
    - `master.go` (150 replacements)
    - `dashboard.go` (41 replacements)
    - `health.go` (1 replacement)
    - `loadbalancer.go` (49 replacements)
    - `s3.go` (20 replacements)

- **Code Organization**
  - Created `src/` directory structure
  - Moved all demo files to `demos/` directory
  - Centralized constants and configuration
  - Improved file organization
  - Added `.gitignore` for professional development

- **Configuration System** (`config.go`)
  - Enhanced with helper functions
  - Environment variable support
  - Validation and error handling
  - S3 configuration integration

- **RPC System** (`rpc.go`)
  - Updated with new types
  - Enhanced with global configuration
  - Improved address management

### Fixed
- Compilation errors with undefined functions
- Import organization and dependencies
- Cross-platform compatibility issues
- Linter errors and warnings
- File path handling for different environments

### Removed
- All `fmt.Print*` statements (299 total)
- Deprecated `startHealthChecking()` function
- Duplicate and temporary files
- Unused binary files

### Optimized
- Import statements across all files
- Go module dependencies (`go mod tidy`)
- Code formatting (`go fmt`)
- Code verification (`go vet`)
- Function organization and structure

### Security
- Added `.gitignore` to prevent credential leaks
- Removed hardcoded paths and credentials
- Environment variable configuration

## [1.0.0] - 2025-09-XX

### Added
- Initial MapReduce implementation
- Raft consensus for master nodes
- Basic fault tolerance
- Docker deployment
- Web dashboard
- Prometheus metrics

### Features
- Map and Reduce task distribution
- Worker node management
- Basic health checking
- Job submission and monitoring

## Version History

- **2.0.0** (2025-10-04): Complete system overhaul with logging, load balancing, and fault tolerance
- **1.0.0** (2025-09-XX): Initial release with basic MapReduce functionality

## Migration Guide

### From 1.x to 2.x

1. **Logging**: All print statements have been replaced. If you have custom code using `fmt.Print*`, replace with:
   ```go
   LogInfo("message", args...)    // Informational
   LogWarn("message", args...)    // Warnings
   LogError("message", args...)   // Errors
   LogDebug("message", args...)   // Debug info
   ```

2. **Configuration**: Update config files to use new structure in `config.go`

3. **Health Checking**: Update health check endpoints to use new `health.go` system

4. **Load Balancer**: Integrate with new load balancer if using custom worker management

5. **S3 Integration**: Configure S3 environment variables if using AWS deployment

## Contributors

- Leonardo Monnati (@leonardomonnati2796)

## License

See LICENSE file for details.

