provider "aws" {
  region = "us-east-2"
}

variable "VpcBlock" {
  type    = string
  default = "10.0.0.0/16"
}

variable "PublicSubnet01Block" {
  type    = string
  default = "10.0.1.0/24"
}

variable "PublicSubnet02Block" {
  type    = string
  default = "10.0.2.0/24"
}

variable "PrivateSubnet01Block" {
  type    = string
  default = "10.0.3.0/24"
}

variable "PrivateSubnet02Block" {
  type    = string
  default = "10.0.4.0/24"
}

resource "aws_vpc" "vpc" {
  cidr_block = var.VpcBlock

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.AWSStackName}-VPC"
  }
}

resource "aws_iam_role" "cloudformation_execution_role" {
  name = "CloudFormationExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudformation.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_vpc_gateway_attachment" "vpc_gateway_attachment" {
  vpc_id             = aws_vpc.vpc.id
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name    = "Public Subnets"
    Network = "Public"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name    = "Private Subnets"
    Network = "Private"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id

  depends_on = [aws_vpc_gateway_attachment.vpc_gateway_attachment]
}

resource "aws_security_group" "jenkins_security_group" {
  name        = "JenkinsSecurityGroup"
  description = "Security group for Jenkins EC2 instance"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "public_subnet_01" {
  count = 2

  cidr_block = element(var.PublicSubnetBlocks, count.index)
  vpc_id     = aws_vpc.vpc.id

  map_public_ip_on_launch = true

  availability_zone = element(
    aws_vpc.vpc.availability_zones,
    count.index % length(aws_vpc.vpc.availability_zones)
  )

  tags = {
    Name = "${var.AWS::StackName}-PublicSubnet0${count.index + 1}"
    kubernetes.io/role/elb = 1
  }
}

resource "aws_instance" "jenkins_instance" {
  ami           = "ami-06d4b7182ac3480fa"
  instance_type = "t2.medium"  # Use the desired instance type
  key_name      = "jekins-key"  # Replace with your actual keypair name

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
    }
  }

  network_interface {
    subnet_id          = aws_subnet.public_subnet_01[0].id
    associate_public_ip_address = true
    security_groups    = [aws_security_group.jenkins_security_group.id]
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              sudo yum upgrade -y
              sudo dnf install java-17-amazon-corretto -y
              sudo yum install git -y
              sudo yum install jenkins -y
              sudo systemctl enable jenkins
              sudo systemctl start jenkins
              sudo systemctl status jenkins
              sudo yum install docker -y
              sudo usermod -a -G docker ec2-user
              newgrp docker
              sudo yum install python3.9-pip -y
              pip3 install --user docker-compose
              sudo systemctl enable docker.service
              sudo systemctl start docker.service
              sudo usermod -aG docker jenkins
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install
              sudo mkdir -p /var/lib/jenkins/.kube
              sudo cp /root/.kube/config /var/lib/jenkins/.kube/config
              sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
              chmod 600 /var/lib/jenkins/.kube/config
              sudo curl -LO https://dl.k8s.io/release/v1.28.4/bin/linux/amd64/kubectl
              sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
              sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
              curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
              sudo mv /tmp/eksctl /usr/local/bin
              sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube/
              sudo chmod -R 700 /var/lib/jenkins/.kube/
              sudo service jenkins restart
              EOF

  tags = {
    Name = "QuamTel-Pipeline"
  }
}

output "jenkins_server_public_ip" {
  description = "Public IP address of the Jenkins server"
  value       = aws_instance.jenkins_instance.public_ip
}
