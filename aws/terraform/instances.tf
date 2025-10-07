# MapReduce EC2 Instances Configuration
# Crea istanze separate per master e worker

# Data source per AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Key Pair (deve esistere)
resource "aws_key_pair" "mapreduce_key" {
  key_name   = var.key_pair_name
  public_key = var.public_key
}

# Master Instances (3 istanze)
resource "aws_instance" "mapreduce_masters" {
  count = var.master_count

  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.master_instance_type
  key_name      = aws_key_pair.mapreduce_key.key_name

  vpc_security_group_ids = [aws_security_group.mapreduce_sg.id]
  subnet_id              = aws_subnet.public_subnets[count.index % length(aws_subnet.public_subnets)].id

  # User data per configurazione automatica
  user_data = templatefile("${path.module}/user_data.sh", {
    INSTANCE_ROLE = "MASTER"
    MASTER_ID     = "master-${count.index + 1}"
    PROJECT_NAME  = var.project_name
    S3_BUCKET     = aws_s3_bucket.mapreduce_bucket.bucket
    AWS_REGION    = var.aws_region
    REPO_URL      = var.repo_url
    REPO_BRANCH   = var.repo_branch
  })

  # IAM instance profile per accesso S3
  iam_instance_profile = aws_iam_instance_profile.mapreduce_profile.name

  tags = {
    Name         = "mapreduce-master-${count.index + 1}"
    Project      = var.project_name
    Environment  = var.environment
    INSTANCE_ROLE = "MASTER"
    MASTER_ID    = "master-${count.index + 1}"
    Type         = "master"
  }

  # Assicura che l'istanza sia completamente inizializzata
  depends_on = [aws_s3_bucket.mapreduce_bucket]
}

# Worker Instances (3 istanze)
resource "aws_instance" "mapreduce_workers" {
  count = var.worker_count

  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.worker_instance_type
  key_name      = aws_key_pair.mapreduce_key.key_name

  vpc_security_group_ids = [aws_security_group.mapreduce_sg.id]
  subnet_id              = aws_subnet.public_subnets[count.index % length(aws_subnet.public_subnets)].id

  # User data per configurazione automatica
  user_data = templatefile("${path.module}/user_data.sh", {
    INSTANCE_ROLE = "WORKER"
    WORKER_ID     = "worker-${count.index + 1}"
    PROJECT_NAME  = var.project_name
    S3_BUCKET     = aws_s3_bucket.mapreduce_bucket.bucket
    AWS_REGION    = var.aws_region
    REPO_URL      = var.repo_url
    REPO_BRANCH   = var.repo_branch
  })

  # IAM instance profile per accesso S3
  iam_instance_profile = aws_iam_instance_profile.mapreduce_profile.name

  tags = {
    Name         = "mapreduce-worker-${count.index + 1}"
    Project      = var.project_name
    Environment  = var.environment
    INSTANCE_ROLE = "WORKER"
    WORKER_ID    = "worker-${count.index + 1}"
    Type         = "worker"
  }

  # Assicura che l'istanza sia completamente inizializzata
  depends_on = [aws_s3_bucket.mapreduce_bucket]
}

# Load Balancer Target Group per Master
resource "aws_lb_target_group" "master_tg" {
  name     = "${var.project_name}-master-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.mapreduce_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "${var.project_name}-master-tg"
  }
}

# Target Group Attachments per Master
resource "aws_lb_target_group_attachment" "master_attachments" {
  count            = var.master_count
  target_group_arn = aws_lb_target_group.master_tg.arn
  target_id        = aws_instance.mapreduce_masters[count.index].id
  port             = 8080
}

# Load Balancer Listener
resource "aws_lb_listener" "mapreduce_listener" {
  load_balancer_arn = aws_lb.mapreduce_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.master_tg.arn
  }
}

# Output delle informazioni delle istanze
output "master_instances" {
  description = "Informazioni delle istanze master"
  value = {
    for i, instance in aws_instance.mapreduce_masters : "master-${i + 1}" => {
      id         = instance.id
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
      dns_name   = instance.public_dns
    }
  }
}

output "worker_instances" {
  description = "Informazioni delle istanze worker"
  value = {
    for i, instance in aws_instance.mapreduce_workers : "worker-${i + 1}" => {
      id         = instance.id
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
      dns_name   = instance.public_dns
    }
  }
}

output "load_balancer_dns" {
  description = "DNS del Load Balancer"
  value       = aws_lb.mapreduce_alb.dns_name
}

output "s3_bucket_name" {
  description = "Nome del bucket S3"
  value       = aws_s3_bucket.mapreduce_bucket.bucket
}
