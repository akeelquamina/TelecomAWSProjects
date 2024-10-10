#!/bin/bash

set -e
set -o pipefail

# Configuration
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

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "Starting setup script..."

# Fetch AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "Using AWS account ID: $ACCOUNT_ID"

# Create or get IAM roles
create_or_get_role() {
    local role_name=$1
    local policy_arn=$2
    local role_arn=$(aws iam list-roles --query "Roles[?RoleName=='$role_name'].Arn" --output text)
    if [ -z "$role_arn" ]; then
        log "Creating IAM role: $role_name"
        aws iam create-role --role-name $role_name --assume-role-policy-document file://${role_name}-trust-policy.json
        aws iam attach-role-policy --role-name $role_name --policy-arn $policy_arn
        role_arn=$(aws iam get-role --role-name $role_name --query 'Role.Arn' --output text)
        log "Created IAM role arn: $role_arn"
    else
        log "IAM role $role_name already exists"
    fi
    echo $role_arn
}

EKS_CLUSTER_ROLE_ARN=$(create_or_get_role "eks-cluster-role" "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy")
EKS_WORKER_NODE_ROLE_ARN=$(create_or_get_role "eks-worker-node-role" "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy")
aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

# Create VPC and Subnets
log "Creating VPC and Subnets..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
log "VPC ID: $VPC_ID"

create_subnet() {
    local cidr=$1
    local az=$2
    local subnet_id=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $cidr --availability-zone $az --query 'Subnet.SubnetId' --output text)
    aws ec2 create-tags --resources $subnet_id --tags Key=Name,Value=$SUBNET_NAME
    echo $subnet_id
}

SUBNET_ID_1=$(create_subnet 10.0.1.0/24 ${REGION}a)
SUBNET_ID_2=$(create_subnet 10.0.2.0/24 ${REGION}b)
SUBNET_ID_3=$(create_subnet 10.0.3.0/24 ${REGION}c)

log "Subnet IDs: $SUBNET_ID_1, $SUBNET_ID_2, $SUBNET_ID_3"

# Create and attach Internet Gateway
log "Creating and attaching Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
log "Internet Gateway ID: $IGW_ID"

# Disable AWS CLI pager
export AWS_PAGER=""

# Create Route Table and Routes
log "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
if [ -z "$ROUTE_TABLE_ID" ]; then
    log "Failed to create Route Table"
    exit 1
fi
log "Route Table ID: $ROUTE_TABLE_ID"

log "Creating Route..."
if ! aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID > /dev/null; then
    log "Failed to create route"
    exit 1
fi
log "Route created successfully"

log "Associating Route Table with Subnets..."
associate_route_table() {
    local subnet_id=$1
    local association_id=$(aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $subnet_id --query 'AssociationId' --output text)
    if [ -z "$association_id" ]; then
        log "Error associating subnet $subnet_id with route table"
        return 1
    fi
    log "Subnet $subnet_id associated with route table (Association ID: $association_id)"
}

for subnet_id in $SUBNET_ID_1 $SUBNET_ID_2 $SUBNET_ID_3; do
    if ! associate_route_table $subnet_id; then
        log "Failed to associate route table with subnet $subnet_id"
        exit 1
    fi
    sleep 2  # Add a small delay between API calls
done

# Enable Public IP on Subnets
log "Enabling Public IP on Subnets..."
enable_public_ip() {
    local subnet_id=$1
    if ! aws ec2 modify-subnet-attribute --subnet-id $subnet_id --map-public-ip-on-launch > /dev/null; then
        log "Failed to enable public IP on subnet $subnet_id"
        return 1
    fi
    log "Public IP enabled on subnet $subnet_id"
}

for subnet_id in $SUBNET_ID_1 $SUBNET_ID_2 $SUBNET_ID_3; do
    if ! enable_public_ip $subnet_id; then
        log "Failed to enable public IP on subnet $subnet_id"
        exit 1
    fi
    sleep 2  # Add a small delay between API calls
done

log "Route Table associated with Subnets and Public IPs enabled"


# Create Security Group
log "Creating Security Group..."
SG_ID=$(aws ec2 create-security-group --group-name $SECURITY_GROUP_NAME --description "Security group for EKS cluster" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_ID --tags Key=Name,Value=$SECURITY_GROUP_NAME
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
log "Security Group ID: $SG_ID"

# Create EKS Cluster
log "Creating EKS Cluster..."
EKS_CLUSTER_ROLE_ARN=$(aws iam get-role --role-name eks-cluster-role --query 'Role.Arn' --output text)

if [ -z "$EKS_CLUSTER_ROLE_ARN" ]; then
    log "Failed to get EKS cluster role ARN"
    exit 1
fi

log "Using EKS cluster role ARN: $EKS_CLUSTER_ROLE_ARN"

if ! aws eks create-cluster \
    --name "$CLUSTER_NAME" \
    --role-arn "$EKS_CLUSTER_ROLE_ARN" \
    --resources-vpc-config "subnetIds=$SUBNET_ID_1,$SUBNET_ID_2,$SUBNET_ID_3,securityGroupIds=$SG_ID" \
    --kubernetes-version "1.27" \
    --output json > /dev/null; then
    log "Failed to create EKS cluster"
    exit 1
fi

log "EKS Cluster creation initiated. Waiting for cluster to become active..."

if ! aws eks wait cluster-active --name "$CLUSTER_NAME"; then
    log "EKS cluster did not become active in the expected time"
    exit 1
fi

log "EKS Cluster is now active"

# Update kubeconfig
log "Updating kubeconfig..."
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME

# Create SSH Key Pair for Jenkins Server
log "Creating SSH Key Pair for Jenkins Server..."

# Ensure JENKINS_KEY_PAIR_NAME is set
if [ -z "$JENKINS_KEY_PAIR_NAME" ]; then
    log "Error: JENKINS_KEY_PAIR_NAME is not set"
    exit 1
fi

# Create the key pair
if ! aws ec2 create-key-pair --key-name "$JENKINS_KEY_PAIR_NAME" --query 'KeyMaterial' --output text > "$JENKINS_KEY_PAIR_NAME.pem"; then
    log "Error: Failed to create key pair"
    exit 1
fi

# Set correct permissions for the key file
chmod 400 "$JENKINS_KEY_PAIR_NAME.pem"

log "SSH Key Pair created: $JENKINS_KEY_PAIR_NAME.pem"


# Create Jenkins Security Group
log "Creating Jenkins Security Group..."
JENKINS_SECURITY_GROUP_NAME="${CLUSTER_NAME}-jenkins-sg"
JENKINS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$JENKINS_SECURITY_GROUP_NAME" \
    --description "Security group for Jenkins EC2 instance" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

if [ -z "$JENKINS_SECURITY_GROUP_ID" ]; then
    log "Failed to create Jenkins Security Group"
    exit 1
fi

log "Jenkins Security Group ID: $JENKINS_SECURITY_GROUP_ID"

# Add inbound rules to Jenkins Security Group
log "Adding inbound rules to Jenkins Security Group..."
aws ec2 authorize-security-group-ingress --group-id "$JENKINS_SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$JENKINS_SECURITY_GROUP_ID" --protocol tcp --port 8080 --cidr 0.0.0.0/0

# Launch Jenkins EC2 Instance
log "Creating Jenkins EC2 Instance..."
JENKINS_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$JENKINS_AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$JENKINS_KEY_PAIR_NAME" \
    --security-group-ids "$JENKINS_SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID_1" \
    --user-data file://jenkins_userdata.sh \
    --iam-instance-profile "Name=$JENKINS_ROLE_NAME" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":50,\"VolumeType\":\"gp3\"}}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "$JENKINS_INSTANCE_ID" ]; then
    log "Failed to create Jenkins EC2 Instance"
    exit 1
fi

log "Jenkins EC2 Instance ID: $JENKINS_INSTANCE_ID"

# Tag the instance
aws ec2 create-tags --resources "$JENKINS_INSTANCE_ID" --tags Key=Name,Value="${CLUSTER_NAME}-JenkinsServer"

# Wait for the instance to be running
log "Waiting for Jenkins EC2 Instance to be running..."
aws ec2 wait instance-running --instance-ids "$JENKINS_INSTANCE_ID"
log "Jenkins EC2 Instance is now running"

# Wait for instance status checks to pass (indicates userdata script completion)
log "Waiting for instance status checks to pass (this may take several minutes)..."
aws ec2 wait instance-status-ok --instance-ids "$JENKINS_INSTANCE_ID"
log "Instance status checks passed. Userdata script execution likely completed."

# Get Jenkins instance public IP
JENKINS_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$JENKINS_INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

if [ -z "$JENKINS_PUBLIC_IP" ]; then
    log "Failed to get Jenkins instance public IP"
    exit 1
fi

log "Jenkins Server is running at: http://$JENKINS_PUBLIC_IP:8080"
log "Use the key pair ${JENKINS_KEY_PAIR_NAME}.pem to connect to the Jenkins server."

# Optional: Check if Jenkins is responding
log "Checking if Jenkins is responding..."
MAX_RETRIES=30
RETRY_INTERVAL=10
for i in $(seq 1 $MAX_RETRIES); do
    if curl -s -o /dev/null -w "%{http_code}" "http://$JENKINS_PUBLIC_IP:8080" | grep -q "200\|403"; then
        log "Jenkins is now accessible!"
        break
    elif [ $i -eq $MAX_RETRIES ]; then
        log "Jenkins did not become accessible within the expected time. Please check the instance manually."
    else
        log "Jenkins not yet accessible. Retrying in $RETRY_INTERVAL seconds..."
        sleep $RETRY_INTERVAL
    fi
done