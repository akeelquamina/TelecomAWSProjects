#!/bin/bash

set -e
set -o pipefail

# Configuration Variables
CLUSTER_NAME="QuamTel"
REGION="us-east-2"
VPC_NAME="QuamTel_Headend"
SUBNET_NAME="QuamTel_N1"
SECURITY_GROUP_NAME="EKS-QuamTel-SG"
NODEGROUP_NAME="TAS"
INSTANCE_TYPE="t3.medium"
JENKINS_KEY_PAIR_NAME="quamtel_jenkins"
JENKINS_AMI_ID="ami-06d4b7182ac3480fa"
LOG_FILE="setup.log"

# CIDR Block Variables for Subnets
SUBNET_CIDR_1="10.0.1.0/24"
SUBNET_CIDR_2="10.0.2.0/24"
SUBNET_CIDR_3="10.0.3.0/24"

# IAM Role Names
CLUSTER_ROLE_NAME="eks-cluster-role"
WORKER_ROLE_NAME="eks-worker-node-role"
JENKINS_ROLE_NAME="jenkins-role"

# Logging function for easy tracking
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "Starting setup script for $CLUSTER_NAME environment..."

# Fetch AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "Using AWS account ID: $ACCOUNT_ID"

# Create or Get IAM Role Function
create_or_get_role() {
    local role_name=$1
    local policy_arn=$2

    local role_arn=$(aws iam list-roles --query "Roles[?RoleName=='$role_name'].Arn" --output text)
    if [ -z "$role_arn" ]; then
        log "Creating IAM role: $role_name"
        aws iam create-role --role-name $role_name --assume-role-policy-document file://${role_name}-trust-policy.json
        aws iam attach-role-policy --role-name $role_name --policy-arn $policy_arn
        role_arn=$(aws iam get-role --role-name $role_name --query 'Role.Arn' --output text)
        log "Created IAM role with ARN: $role_arn"
    else
        log "IAM role $role_name already exists"
    fi
    echo $role_arn
}

# Create required IAM roles
EKS_CLUSTER_ROLE_ARN=$(create_or_get_role $CLUSTER_ROLE_NAME "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy")
EKS_WORKER_NODE_ROLE_ARN=$(create_or_get_role $WORKER_ROLE_NAME "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy")
aws iam attach-role-policy --role-name $WORKER_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name $WORKER_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

# Create VPC
log "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
log "VPC ID: $VPC_ID"

# Create Subnet Function
create_subnet() {
    local cidr=$1
    local az=$2
    local subnet_id=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $cidr --availability-zone $az --query 'Subnet.SubnetId' --output text)
    aws ec2 create-tags --resources $subnet_id --tags Key=Name,Value=$SUBNET_NAME
    echo $subnet_id
}

log "Creating subnets..."
SUBNET_ID_1=$(create_subnet $SUBNET_CIDR_1 ${REGION}a)
SUBNET_ID_2=$(create_subnet $SUBNET_CIDR_2 ${REGION}b)
SUBNET_ID_3=$(create_subnet $SUBNET_CIDR_3 ${REGION}c)
log "Subnet IDs: $SUBNET_ID_1, $SUBNET_ID_2, $SUBNET_ID_3"

# Create Internet Gateway
log "Creating and attaching Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
log "Internet Gateway ID: $IGW_ID"

# Create Route Table and Routes
log "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
log "Route Table ID: $ROUTE_TABLE_ID"

log "Creating route to IGW..."
aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# Associate Route Table with Subnets
associate_route_table() {
    local subnet_id=$1
    aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $subnet_id
    log "Associated Route Table $ROUTE_TABLE_ID with Subnet $subnet_id"
}

for subnet in $SUBNET_ID_1 $SUBNET_ID_2 $SUBNET_ID_3; do
    associate_route_table $subnet
done

# Enable Public IP on Subnets
enable_public_ip() {
    local subnet_id=$1
    aws ec2 modify-subnet-attribute --subnet-id $subnet_id --map-public-ip-on-launch
    log "Enabled Public IP on Subnet $subnet_id"
}

for subnet in $SUBNET_ID_1 $SUBNET_ID_2 $SUBNET_ID_3; do
    enable_public_ip $subnet
done

# Security Group for EKS Cluster
log "Creating Security Group for EKS..."
SG_ID=$(aws ec2 create-security-group --group-name $SECURITY_GROUP_NAME --description "Security group for EKS cluster" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_ID --tags Key=Name,Value=$SECURITY_GROUP_NAME
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
log "Security Group ID: $SG_ID"

# EKS Cluster Creation
log "Creating EKS Cluster..."
aws eks create-cluster \
    --name $CLUSTER_NAME \
    --role-arn $EKS_CLUSTER_ROLE_ARN \
    --resources-vpc-config "subnetIds=$SUBNET_ID_1,$SUBNET_ID_2,$SUBNET_ID_3,securityGroupIds=$SG_ID" \
    --kubernetes-version "1.27"

log "Waiting for EKS cluster to become active..."
aws eks wait cluster-active --name $CLUSTER_NAME
log "EKS Cluster is now active"

# Node Group Creation
log "Creating EKS Node Group: $NODEGROUP_NAME"
aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --node-role $EKS_WORKER_NODE_ROLE_ARN \
    --subnets $SUBNET_ID_1 $SUBNET_ID_2 $SUBNET_ID_3 \
    --instance-types $INSTANCE_TYPE \
    --scaling-config minSize=2,maxSize=4,desiredSize=3

log "Waiting for node group to become active..."
aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME
log "Node group is now active"

# Update kubeconfig
log "Updating kubeconfig..."
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME

# SSH Key Pair Creation for Jenkins
log "Creating SSH Key Pair for Jenkins..."
aws ec2 create-key-pair --key-name $JENKINS_KEY_PAIR_NAME --query 'KeyMaterial' --output text > "$JENKINS_KEY_PAIR_NAME.pem"
chmod 400 "$JENKINS_KEY_PAIR_NAME.pem"
log "Created Jenkins EC2 key pair and saved it as $JENKINS_KEY_PAIR_NAME.pem"

# Create Jenkins EC2 instance
log "Launching Jenkins EC2 instance..."
JENKINS_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $JENKINS_AMI_ID \
    --count 1 \
    --instance-type t3.medium \
    --key-name $JENKINS_KEY_PAIR_NAME \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID_1 \
    --associate-public-ip-address \
    --iam-instance-profile Name=$JENKINS_ROLE_NAME \
    --query 'Instances[0].InstanceId' \
    --output text)

log "Waiting for Jenkins EC2 instance to become available..."
aws ec2 wait instance-running --instance-ids $JENKINS_INSTANCE_ID
log "Jenkins EC2 instance $JENKINS_INSTANCE_ID is running"

# Fetch Jenkins EC2 public IP address
JENKINS_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $JENKINS_INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

log "Jenkins EC2 instance is running with public IP: $JENKINS_PUBLIC_IP"

# Output summary of the environment setup
log "====================================================="
log "Environment setup complete!"
log "EKS Cluster Name: $CLUSTER_NAME"
log "VPC ID: $VPC_ID"
log "Subnets: $SUBNET_ID_1, $SUBNET_ID_2, $SUBNET_ID_3"
log "Security Group ID: $SG_ID"
log "EKS Node Group: $NODEGROUP_NAME"
log "Jenkins EC2 Instance ID: $JENKINS_INSTANCE_ID"
log "Jenkins Public IP: $JENKINS_PUBLIC_IP"
log "SSH Key Pair for Jenkins: $JENKINS_KEY_PAIR_NAME.pem"
log "====================================================="

log "You can now SSH into your Jenkins instance using the following command:"
log "ssh -i \"$JENKINS_KEY_PAIR_NAME.pem\" ec2-user@$JENKINS_PUBLIC_IP"

