#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Prevents errors in a pipeline from being masked

# Configuration
CLUSTER_NAME="QuamTel"
REGION="us-east-2"
VPC_NAME="QuamTel_Headend"
SUBNET_NAME="QuamTel_N1"
SECURITY_GROUP_NAME="EKS-QuamTel-SG"
NODEGROUP_NAME="TAS"
JENKINS_KEY_PAIR_NAME="quamtel_jenkins"
JENKINS_AMI_ID="ami-06d4b7182ac3480fa"
INSTANCE_TYPE="t3.medium"
LOG_FILE="setup.log"

# Logging function
log() {
    echo "$1" | tee -a $LOG_FILE
}

# Error handling function
error_exit() {
    log "Error on line $1"
    exit 1
}

trap 'error_exit $LINENO' ERR

log "Starting setup script..."

# Fetch AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "Using AWS account ID: $ACCOUNT_ID"

# Create IAM roles if not exists
eks_cluster_role_arn=$(aws iam list-roles --query "Roles[?RoleName=='eks-cluster-role'].Arn" --output text)
if [ -z "$eks_cluster_role_arn" ]; then
    log "Creating IAM role: eks-cluster-role"
    aws iam create-role --role-name eks-cluster-role --assume-role-policy-document file://eks-cluster-role-trust-policy.json
    aws iam attach-role-policy --role-name eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
    eks_cluster_role_arn=$(aws iam get-role --role-name eks-cluster-role --query 'Role.Arn' --output text)
    log "Created IAM role arn: $eks_cluster_role_arn"
fi

eks_worker_node_role_arn=$(aws iam list-roles --query "Roles[?RoleName=='eks-worker-node-role'].Arn" --output text)
if [ -z "$eks_worker_node_role_arn" ]; then
    log "Creating IAM role: eks-worker-node-role"
    aws iam create-role --role-name eks-worker-node-role --assume-role-policy-document file://eks-worker-node-role-trust-policy.json
    aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    eks_worker_node_role_arn=$(aws iam get-role --role-name eks-worker-node-role --query 'Role.Arn' --output text)
    log "Created IAM role arn: $eks_worker_node_role_arn"
fi

# Create VPC
log "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
log "VPC ID: $VPC_ID"

# Create Subnets
log "Creating Subnets..."
SUBNET_ID_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
log "Subnet 1 ID: $SUBNET_ID_1"
SUBNET_ID_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)
log "Subnet 2 ID: $SUBNET_ID_2"
SUBNET_ID_3=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone ${REGION}c --query 'Subnet.SubnetId' --output text)
log "Subnet 3 ID: $SUBNET_ID_3"
aws ec2 create-tags --resources $SUBNET_ID_1 $SUBNET_ID_2 $SUBNET_ID_3 --tags Key=Name,Value=$SUBNET_NAME
log "Subnets created and tagged"

# Create Internet Gateway
log "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
log "Internet Gateway ID: $IGW_ID"

# Create Route Table and Routes
log "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
log "Route Table ID: $ROUTE_TABLE_ID"

# Debug: Check if Route Table and Internet Gateway IDs are correctly assigned
if [[ -z "$ROUTE_TABLE_ID" || -z "$IGW_ID" ]]; then
    log "Route Table ID or Internet Gateway ID is empty. Exiting..."
    exit 1
fi

log "Creating Route..."
create_route_output=$(aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID 2>&1)
create_route_exit_code=$?
log "Create Route Output: $create_route_output"
if [ $create_route_exit_code -ne 0 ]; then
    log "Failed to create route. Exiting..."
    exit 1
fi
log "Route created successfully"

log "Associating Route Table with Subnets..."
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $SUBNET_ID_1
log "Subnet 1 associated with route table"
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $SUBNET_ID_2
log "Subnet 2 associated with route table"
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $SUBNET_ID_3
log "Subnet 3 associated with route table"

# Enable Public IP on Subnets
log "Enabling Public IP on Subnets..."
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID_1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID_2 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID_3 --map-public-ip-on-launch
log "Public IP enabled on Subnets"

# Create Security Group
log "Creating Security Group..."
SG_ID=$(aws ec2 create-security-group --group-name $SECURITY_GROUP_NAME --description "Security group for EKS cluster" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_ID --tags Key=Name,Value=$SECURITY_GROUP_NAME
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
log "Security Group ID: $SG_ID"

# Create IAM Roles
log "Creating IAM Roles trust policies..."

cat > eks-cluster-role-trust-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOL

cat > eks-worker-node-role-trust-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOL

# Ensure roles are created
if [ -z "$eks_cluster_role_arn" ]; then
    log "Creating EKS Cluster Role..."
    aws iam create-role --role-name eks-cluster-role --assume-role-policy-document file://eks-cluster-role-trust-policy.json
    aws iam attach-role-policy --role-name eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
    log "EKS Cluster Role created"
else
    log "EKS Cluster Role already exists"
fi

eks_worker_node_role_arn=$(aws iam list-roles --query "Roles[?RoleName=='eks-worker-node-role'].Arn" --output text)
if [ -z "$eks_worker_node_role_arn" ]; then
    log "Creating IAM role: eks-worker-node-role"
    aws iam create-role --role-name eks-worker-node-role --assume-role-policy-document file://eks-worker-node-role-trust-policy.json
    aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    eks_worker_node_role_arn=$(aws iam get-role --role-name eks-worker-node-role --query 'Role.Arn' --output text)
    log "Created IAM role arn: $eks_worker_node_role_arn"
fi

# Create EKS Cluster
log "Creating EKS Cluster..."
aws eks create-cluster --name $CLUSTER_NAME --role-arn arn:aws:iam::$ACCOUNT_ID:role/eks-cluster-role --resources-vpc-config subnetIds=$SUBNET_ID_1,$SUBNET_ID_2,$SUBNET_ID_3,securityGroupIds=$SG_ID
log "Waiting for EKS Cluster to become ACTIVE..."
aws eks wait cluster-active --name $CLUSTER_NAME
log "EKS Cluster created successfully"

# Create Node Group
log "Creating Node Group..."
aws eks create-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --node-role arn:aws:iam::$ACCOUNT_ID:role/eks-worker-node-role --subnets $SUBNET_ID_1 $SUBNET_ID_2 $SUBNET_ID_3 --scaling-config minSize=1,maxSize=3,desiredSize=2
log "Node Group created"

# Update kubeconfig
log "Updating kubeconfig..."
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME

# Create SSH Key Pair for Jenkins Server
log "Creating SSH Key Pair for Jenkins Server..."
aws ec2 create-key-pair --key-name $JENKINS_KEY_PAIR_NAME --query 'KeyMaterial' --output text > $JENKINS_KEY_PAIR_NAME.pem
chmod 400 $JENKINS_KEY_PAIR_NAME.pem
log "SSH Key Pair created: $JENKINS_KEY_PAIR_NAME.pem"

# Create Jenkins Security Group
log "Creating Jenkins Security Group..."
JENKINS_SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name JenkinsSecurityGroup --description "Security group for Jenkins EC2 instance" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $JENKINS_SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $JENKINS_SECURITY_GROUP_ID --protocol tcp --port 8080 --cidr 0.0.0.0/0
log "Jenkins Security Group ID: $JENKINS_SECURITY_GROUP_ID"

# Create Jenkins EC2 Instance
log "Creating Jenkins EC2 Instance..."
JENKINS_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $JENKINS_AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name $JENKINS_KEY_PAIR_NAME \
    --security-group-ids $JENKINS_SECURITY_GROUP_ID \
    --subnet-id $SUBNET_ID_1 \
    --user-data file://jenkins_userdata.sh \
    --iam-instance-profile Name=$JENKINS_ROLE_NAME \
    --block-device-mappings DeviceName=/dev/xvda,Ebs={VolumeSize=50,VolumeType=gp3} \
    --query 'Instances[0].InstanceId' --output text)

aws ec2 create-tags --resources $JENKINS_INSTANCE_ID --tags Key=Name,Value=JenkinsServer
log "Waiting for Jenkins EC2 Instance to be running..."
aws ec2 wait instance-running --instance-ids $JENKINS_INSTANCE_ID
log "Jenkins EC2 Instance created: $JENKINS_INSTANCE_ID"

# Get Jenkins instance public IP
JENKINS_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $JENKINS_INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
log "Jenkins Server is running at: http://$JENKINS_PUBLIC_IP:8080"
log "Use the key pair $JENKINS_KEY_PAIR_NAME.pem to connect to the Jenkins server."

echo "Jenkins Server is running at: http://$JENKINS_PUBLIC_IP:8080"
echo "Use the key pair $JENKINS_KEY_PAIR_NAME.pem to connect to the Jenkins server."
