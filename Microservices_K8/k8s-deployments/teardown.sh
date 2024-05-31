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
LOG_FILE="teardown.log"

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

log "Starting teardown script..."

# Fetch AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "Using AWS account ID: $ACCOUNT_ID"

# Delete Jenkins EC2 Instance
log "Deleting Jenkins EC2 Instance..."
JENKINS_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=JenkinsServer" --query 'Reservations[0].Instances[0].InstanceId' --output text)
if [ "$JENKINS_INSTANCE_ID" != "None" ]; then
    aws ec2 terminate-instances --instance-ids $JENKINS_INSTANCE_ID
    aws ec2 wait instance-terminated --instance-ids $JENKINS_INSTANCE_ID
    log "Jenkins EC2 Instance terminated: $JENKINS_INSTANCE_ID"
else
    log "Jenkins EC2 Instance not found."
fi

# Delete Key Pair
log "Deleting SSH Key Pair..."
aws ec2 delete-key-pair --key-name $JENKINS_KEY_PAIR_NAME
rm -f $JENKINS_KEY_PAIR_NAME.pem
log "SSH Key Pair deleted: $JENKINS_KEY_PAIR_NAME"

# Delete Node Group
log "Deleting Node Group..."
NODEGROUP_EXISTS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --query "nodegroups" --output text)
if [ -n "$NODEGROUP_EXISTS" ]; then
    aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME
    log "Waiting for Node Group to be deleted..."
    aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME
    log "Node Group deleted"
else
    log "Node Group not found."
fi

# Delete EKS Cluster
log "Deleting EKS Cluster..."
CLUSTER_EXISTS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.name" --output text || echo "None")
if [ "$CLUSTER_EXISTS" != "None" ]; then
    aws eks delete-cluster --name $CLUSTER_NAME
    log "Waiting for EKS Cluster to be deleted..."
    aws eks wait cluster-deleted --name $CLUSTER_NAME
    log "EKS Cluster deleted"
else
    log "EKS Cluster not found."
fi

# Delete Security Group
log "Deleting Security Group..."
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group --group-id $SG_ID
    log "Security Group deleted: $SG_ID"
else
    log "Security Group not found."
fi

# Delete Route Table Associations
log "Deleting Route Table Associations..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[0].RouteTableId' --output text)
ASSOCIATION_IDS=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text)
for ASSOCIATION_ID in $ASSOCIATION_IDS; do
    aws ec2 disassociate-route-table --association-id $ASSOCIATION_ID
    log "Route Table Association deleted: $ASSOCIATION_ID"
done

# Delete Route Table
log "Deleting Route Table..."
aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID
log "Route Table deleted: $ROUTE_TABLE_ID"

# Unmap and release Elastic IP addresses
log "Disassociating and releasing Elastic IP addresses..."
EIP_ALLOCATIONS=$(aws ec2 describe-addresses --filters "Name=domain,Values=vpc" --query "Addresses[?AssociationId].AllocationId" --output text)
if [ -n "$EIP_ALLOCATIONS" ]; then
    for ALLOCATION_ID in $EIP_ALLOCATIONS; do
        ASSOCIATION_ID=$(aws ec2 describe-addresses --allocation-ids $ALLOCATION_ID --query "Addresses[0].AssociationId" --output text)
        if [ "$ASSOCIATION_ID" != "None" ]; then
            log "Disassociating Elastic IP $ALLOCATION_ID (Association ID: $ASSOCIATION_ID)"
            aws ec2 disassociate-address --association-id $ASSOCIATION_ID
        fi
        log "Releasing Elastic IP $ALLOCATION_ID"
        aws ec2 release-address --allocation-id $ALLOCATION_ID
    done
else
    log "No Elastic IP addresses associated with the VPC."
fi

# Detach and Delete Internet Gateway
log "Deleting Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text)
if [ "$IGW_ID" != "None" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
    log "Internet Gateway deleted: $IGW_ID"
else
    log "Internet Gateway not found."
fi

# Delete Subnets
log "Deleting Subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text)
for SUBNET_ID in $SUBNET_IDS; do
    aws ec2 delete-subnet --subnet-id $SUBNET_ID
    log "Subnet deleted: $SUBNET_ID"
done

# Delete VPC
log "Deleting VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID
log "VPC deleted: $VPC_ID"

# Delete IAM Roles
log "Deleting IAM roles..."
ROLE_EXISTS=$(aws iam get-role --role-name eks-cluster-role --query "Role.RoleName" --output text || echo "None")
if [ "$ROLE_EXISTS" != "None" ]; then
    aws iam detach-role-policy --role-name eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
    aws iam delete-role --role-name eks-cluster-role
    log "IAM role deleted: eks-cluster-role"
else
    log "IAM role eks-cluster-role not found."
fi

ROLE_EXISTS=$(aws iam get-role --role-name eks-worker-node-role --query "Role.RoleName" --output text || echo "None")
if [ "$ROLE_EXISTS" != "None" ]; then
    aws iam detach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    aws iam detach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam detach-role-policy --role-name eks-worker-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    aws iam delete-role --role-name eks-worker-node-role
    log "IAM role deleted: eks-worker-node-role"
else
    log "IAM role eks-worker-node-role not found."
fi

log "Teardown completed successfully."
