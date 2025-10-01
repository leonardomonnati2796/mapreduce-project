#!/bin/bash

# User data script per EC2 instances
set -e

# Log everything
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting MapReduce deployment on EC2..."

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install additional tools
yum install -y git htop tree jq

# Create application directory
mkdir -p /opt/mapreduce
cd /opt/mapreduce

# Clone the repository (you'll need to replace this with your actual repo)
# git clone https://github.com/your-username/mapreduce-project.git .

# For now, we'll create a placeholder structure
mkdir -p docker data scripts

# Create environment file
cat > .env << EOF
# AWS Configuration
AWS_REGION=${aws_region}
AWS_S3_BUCKET=${s3_bucket}

# MapReduce Configuration
RAFT_ADDRESSES=master0:1234,master1:1234,master2:1234
RPC_ADDRESSES=master0:8000,master1:8001,master2:8002
TMP_PATH=/tmp/mapreduce

# Performance Settings
METRICS_ENABLED=true
METRICS_PORT=9090
MAPREDUCE_MASTER_TASK_TIMEOUT=300s
MAPREDUCE_MASTER_HEARTBEAT_INTERVAL=10s
MAPREDUCE_WORKER_RETRY_INTERVAL=5s

# Health Check Settings
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_INTERVAL=30s
HEALTH_CHECK_TIMEOUT=10s

# S3 Sync Settings
S3_SYNC_ENABLED=true
S3_SYNC_INTERVAL=60s
S3_BACKUP_ENABLED=true
EOF

# Create sample data
mkdir -p data
cat > data/Words.txt << EOF
hello world
mapreduce distributed
aws cloud computing
docker containers
terraform infrastructure
kubernetes orchestration
microservices architecture
serverless computing
big data analytics
machine learning
EOF

# Create startup script
cat > start-mapreduce.sh << 'EOF'
#!/bin/bash

# Start MapReduce cluster
cd /opt/mapreduce

# Pull latest images
docker-compose -f docker/docker-compose.aws.yml pull

# Start services
docker-compose -f docker/docker-compose.aws.yml up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Check health
docker-compose -f docker/docker-compose.aws.yml ps

echo "MapReduce cluster started successfully!"
echo "Dashboard available at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
EOF

chmod +x start-mapreduce.sh

# Create systemd service
cat > /etc/systemd/system/mapreduce.service << EOF
[Unit]
Description=MapReduce Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/mapreduce
ExecStart=/opt/mapreduce/start-mapreduce.sh
ExecStop=/usr/local/bin/docker-compose -f docker/docker-compose.aws.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable mapreduce.service

# Create monitoring script
cat > /opt/mapreduce/monitor.sh << 'EOF'
#!/bin/bash

# Monitor MapReduce cluster health
cd /opt/mapreduce

while true; do
    echo "=== MapReduce Cluster Status $(date) ==="
    
    # Check Docker containers
    docker-compose -f docker/docker-compose.aws.yml ps
    
    # Check disk space
    df -h /tmp/mapreduce
    
    # Check memory usage
    free -h
    
    # Check if services are responding
    curl -f http://localhost:8080/health || echo "Dashboard not responding"
    curl -f http://localhost:9090/health || echo "Metrics not responding"
    
    echo "=========================================="
    sleep 60
done
EOF

chmod +x /opt/mapreduce/monitor.sh

# Create log rotation configuration
cat > /etc/logrotate.d/mapreduce << EOF
/var/log/user-data.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}

/opt/mapreduce/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

# Set up CloudWatch agent (optional)
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Create CloudWatch config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/mapreduce",
                        "log_stream_name": "{instance_id}/user-data.log"
                    },
                    {
                        "file_path": "/opt/mapreduce/logs/*.log",
                        "log_group_name": "/aws/ec2/mapreduce",
                        "log_stream_name": "{instance_id}/application.log"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "MapReduce/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

echo "User data script completed successfully!"
echo "MapReduce cluster will start automatically on boot."
