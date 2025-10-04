# MapReduce Load Balancer & S3 Integration Guide

## 🚀 Overview

This guide covers the enhanced MapReduce system with **Load Balancer** for fault tolerance and **S3 integration** for distributed storage.

## ✨ New Features

### 🔄 Load Balancer
- **Health-based routing** - Routes traffic to healthiest servers
- **Multiple strategies** - Round Robin, Weighted, Least Connections, Random
- **Automatic failover** - Removes unhealthy servers from rotation
- **Real-time monitoring** - Tracks server health and performance
- **Dynamic server management** - Add/remove servers at runtime

### ☁️ S3 Storage Integration
- **Automatic synchronization** - Syncs data to S3 periodically
- **Backup management** - Creates timestamped backups
- **Data restoration** - Restore from any backup point
- **Lifecycle management** - Automatic data archiving
- **Encryption** - Server-side encryption for data security

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │────│   MapReduce     │────│   S3 Storage    │
│   (AWS ALB)     │    │   Cluster       │    │   (AWS S3)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
    ┌─────────┐              ┌─────────┐              ┌─────────┐
    │ Health  │              │ Master  │              │ Backup  │
    │ Check   │              │ Nodes   │              │ System  │
    └─────────┘              └─────────┘              └─────────┘
```

## 🚀 Quick Start

### 1. Prerequisites
```bash
# Install required tools
aws --version
terraform --version
docker --version
go version
```

### 2. Configure Environment
```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-east-1

# Set S3 configuration
export S3_SYNC_ENABLED=true
export AWS_S3_BUCKET=mapreduce-storage
export S3_SYNC_INTERVAL=60s

# Set Load Balancer configuration
export LOAD_BALANCER_ENABLED=true
export LOAD_BALANCER_STRATEGY=HealthBased
```

### 3. Deploy Infrastructure
```bash
# Deploy with Load Balancer and S3
./scripts/deploy-with-loadbalancer-s3.sh
```

### 4. Verify Deployment
```bash
# Check health
curl http://your-alb-dns/health

# Check load balancer stats
curl http://your-alb-dns/api/v1/loadbalancer/stats

# Check S3 stats
curl http://your-alb-dns/api/v1/s3/stats
```

## 🔧 Configuration

### Load Balancer Configuration
```bash
# Load balancer settings
LOAD_BALANCER_ENABLED=true
LOAD_BALANCER_STRATEGY=HealthBased  # HealthBased, RoundRobin, WeightedRoundRobin, LeastConnections, Random
LOAD_BALANCER_HEALTH_CHECK_INTERVAL=10s
LOAD_BALANCER_TIMEOUT=5s
LOAD_BALANCER_MAX_RETRIES=3

# Server weights
LB_MASTER_WEIGHT=10
LB_WORKER_WEIGHT=5
```

### S3 Configuration
```bash
# S3 settings
S3_SYNC_ENABLED=true
S3_SYNC_INTERVAL=60s
AWS_S3_BUCKET=mapreduce-storage
AWS_REGION=us-east-1

# S3 features
S3_ENCRYPTION_ENABLED=true
S3_VERSIONING_ENABLED=true
S3_LIFECYCLE_ENABLED=true

# Backup settings
S3_BACKUP_SCHEDULE=0 2 * * *
S3_BACKUP_RETENTION_DAYS=30
S3_BACKUP_ENCRYPTION=true
```

## 📊 API Endpoints

### Load Balancer APIs
```bash
# Get load balancer statistics
GET /api/v1/loadbalancer/stats

# Add server to load balancer
POST /api/v1/loadbalancer/server/add
{
  "id": "server-1",
  "address": "192.168.1.100",
  "port": 8080,
  "weight": 10
}

# Remove server from load balancer
POST /api/v1/loadbalancer/server/remove
{
  "server_id": "server-1"
}
```

### S3 Storage APIs
```bash
# Get S3 statistics
GET /api/v1/s3/stats

# Create backup
POST /api/v1/s3/backup

# List backups
GET /api/v1/s3/backups

# Restore from backup
POST /api/v1/s3/restore
{
  "backup_timestamp": "2024-01-01-12-00-00",
  "local_path": "/tmp/restore"
}
```

## 🔍 Monitoring

### Load Balancer Metrics
- **Server Health** - Real-time health status
- **Request Distribution** - Traffic distribution across servers
- **Error Rates** - Failed requests per server
- **Response Times** - Average response times
- **Active Connections** - Current connection counts

### S3 Storage Metrics
- **Sync Status** - Last sync time and status
- **Storage Usage** - Data stored in S3
- **Backup Count** - Number of backups available
- **Transfer Rates** - Upload/download speeds
- **Error Rates** - Failed sync operations

## 🛠️ Troubleshooting

### Load Balancer Issues
```bash
# Check server health
curl http://your-alb-dns/api/v1/loadbalancer/stats

# View server logs
docker logs mapreduce-master-1
docker logs mapreduce-worker-1

# Restart load balancer
docker-compose restart loadbalancer
```

### S3 Integration Issues
```bash
# Check S3 connectivity
aws s3 ls s3://your-bucket-name

# View sync logs
docker logs mapreduce-s3-sync

# Test S3 operations
curl -X POST http://your-alb-dns/api/v1/s3/backup
```

### Common Issues

#### 1. Load Balancer Not Routing Traffic
```bash
# Check server health
curl http://your-alb-dns/api/v1/loadbalancer/stats

# Verify server registration
docker exec mapreduce-master-1 ./mapreduce master 0 /data/input.txt
```

#### 2. S3 Sync Failures
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify S3 bucket permissions
aws s3 ls s3://your-bucket-name

# Check sync logs
docker logs mapreduce-s3-sync
```

#### 3. Health Check Failures
```bash
# Check health endpoints
curl http://server-ip:8080/health
curl http://server-ip:8081/health

# Verify service status
docker ps
docker logs container-name
```

## 🔒 Security

### Load Balancer Security
- **Health Checks** - Regular server health verification
- **SSL Termination** - HTTPS support at load balancer
- **Access Control** - IP-based access restrictions
- **Rate Limiting** - Request rate limiting per server

### S3 Security
- **Encryption** - Server-side encryption (SSE-S3)
- **Access Control** - IAM-based access control
- **Versioning** - Object versioning for data protection
- **Lifecycle Policies** - Automatic data archiving

## 📈 Performance Optimization

### Load Balancer Optimization
```bash
# Use health-based routing for best performance
LOAD_BALANCER_STRATEGY=HealthBased

# Optimize health check intervals
LOAD_BALANCER_HEALTH_CHECK_INTERVAL=5s
LOAD_BALANCER_TIMEOUT=3s

# Adjust server weights based on capacity
LB_MASTER_WEIGHT=10
LB_WORKER_WEIGHT=5
```

### S3 Optimization
```bash
# Optimize sync frequency
S3_SYNC_INTERVAL=30s

# Enable compression
S3_COMPRESSION_ENABLED=true

# Use appropriate storage classes
S3_STORAGE_CLASS=STANDARD_IA
```

## 🚀 Advanced Features

### Auto-Scaling
- **Dynamic Server Addition** - Add servers based on load
- **Automatic Failover** - Remove failed servers
- **Load-Based Routing** - Route to least loaded servers
- **Health-Based Selection** - Prefer healthiest servers

### Backup Management
- **Scheduled Backups** - Automatic backup creation
- **Incremental Backups** - Only sync changed data
- **Backup Retention** - Automatic old backup cleanup
- **Cross-Region Replication** - Backup to multiple regions

## 📚 Examples

### Example 1: Basic Load Balancer Setup
```bash
# Enable load balancer
export LOAD_BALANCER_ENABLED=true
export LOAD_BALANCER_STRATEGY=HealthBased

# Start services
docker-compose up -d
```

### Example 2: S3 Backup Configuration
```bash
# Enable S3 sync
export S3_SYNC_ENABLED=true
export AWS_S3_BUCKET=my-mapreduce-storage

# Create backup
curl -X POST http://localhost:8080/api/v1/s3/backup
```

### Example 3: Monitoring Setup
```bash
# Check load balancer stats
curl http://localhost:8080/api/v1/loadbalancer/stats

# Check S3 stats
curl http://localhost:8080/api/v1/s3/stats

# View health status
curl http://localhost:8080/health
```

## 🎯 Best Practices

### Load Balancer Best Practices
1. **Use Health-Based Routing** for optimal performance
2. **Monitor Server Health** regularly
3. **Set Appropriate Timeouts** for your workload
4. **Use Weighted Routing** for heterogeneous servers
5. **Implement Circuit Breakers** for fault tolerance

### S3 Best Practices
1. **Enable Encryption** for data security
2. **Use Lifecycle Policies** for cost optimization
3. **Monitor Storage Usage** regularly
4. **Test Backup/Restore** procedures
5. **Use Appropriate Storage Classes** for cost efficiency

## 🔗 Related Documentation

- [AWS Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## 🆘 Support

For issues and support:
1. Check the troubleshooting section above
2. Review the logs: `docker logs container-name`
3. Verify configuration: `curl http://localhost:8080/api/v1/loadbalancer/stats`
4. Test S3 connectivity: `aws s3 ls s3://your-bucket`

---

**🎉 Congratulations!** You now have a robust MapReduce system with Load Balancer and S3 integration for production use!
