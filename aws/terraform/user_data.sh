#!/bin/bash

# User Data Script for MapReduce EC2 Instances
# This script is executed when an EC2 instance first launches

set -e

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting MapReduce instance initialization..."

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

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

REPO_URL="${REPO_URL}"
REPO_BRANCH="${REPO_BRANCH}"

# Create application directory
mkdir -p /opt
cd /opt

# Install Git
yum install -y git

# Clone repository
git clone -b "${REPO_BRANCH}" "${REPO_URL}" app || {
  echo "Git clone failed; ensure repo_url/repo_branch are set";
  exit 1;
}

cd /opt/app

# Build Docker images from repository
docker build -f docker/Dockerfile.aws -t mapreduce-master:latest --build-arg BUILD_TARGET=master .
docker build -f docker/Dockerfile.aws -t mapreduce-worker:latest --build-arg BUILD_TARGET=worker .

# Use production docker-compose
cd /opt/app/aws/docker

# Ensure CloudWatch config is available alongside compose
cp -f ../../monitoring/cloudwatch-config.json ./cloudwatch-config.json || true

/usr/local/bin/docker-compose -f docker-compose.production.yml up -d

cat > nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    upstream mapreduce_master {
        server mapreduce-master:8082;
        keepalive 32;
    }

    upstream mapreduce_worker {
        server mapreduce-worker:8081;
        keepalive 32;
    }

    upstream mapreduce_dashboard {
        server mapreduce-master:3000;
        keepalive 32;
    }

    server {
        listen 80;
        server_name _;

        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy "strict-origin-when-cross-origin";

        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        location /dashboard {
            proxy_pass http://mapreduce_dashboard;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /dashboard/ws {
            proxy_pass http://mapreduce_dashboard;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api/master {
            proxy_pass http://mapreduce_master;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api/worker {
            proxy_pass http://mapreduce_worker;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api/health {
            proxy_pass http://mapreduce_master/health;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

cat > cloudwatch-config.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "MapReduce/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ],
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/mapreduce/master.log",
            "log_group_name": "/aws/ec2/mapreduce/master",
            "log_stream_name": "{instance_id}-master",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/mapreduce/worker.log",
            "log_group_name": "/aws/ec2/mapreduce/worker",
            "log_stream_name": "{instance_id}-worker",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/mapreduce/nginx-access",
            "log_stream_name": "{instance_id}-nginx-access",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

# Create log directories
mkdir -p /var/log/mapreduce
mkdir -p /var/log/nginx
mkdir -p /tmp/mapreduce

# Set permissions
chown -R ec2-user:ec2-user /opt/mapreduce
chown -R ec2-user:ec2-user /var/log/mapreduce
chown -R ec2-user:ec2-user /tmp/mapreduce

# Create systemd service for MapReduce
cat > /etc/systemd/system/mapreduce.service << 'EOF'
[Unit]
Description=MapReduce Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/mapreduce
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
User=ec2-user
Group=ec2-user

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable mapreduce.service
systemctl start mapreduce.service

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/mapreduce/cloudwatch-config.json \
    -s

echo "MapReduce instance initialization completed successfully!"