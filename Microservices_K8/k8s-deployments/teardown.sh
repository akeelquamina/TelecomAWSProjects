#!/bin/bash

set -e
set -o pipefail

# Configuration
CLUSTER_NAME="QuamTel"
REGION="us-east-2"
VPC_NAME="QuamTel_Headend"
SECURITY_GROUP_NAME="EKS-QuamTel-SG"
NODEGROUP_NAME="TAS"
JENKINS_KEY_PAIR_NAME="quamtel_jenkins"

# IAM Role Names
CLUSTER_ROLE_NAME="eks-cluster-role"
WORKER_ROLE_NAME="eks-worker-node-role"
JENKINS_ROLE_NAME="QuamTel-jenkins-role"

# Logging function
LOG_FILE="teardown.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "Starting teardown script..."

# Delete Jenkins EC2 Instance
log "Terminating Jenkins EC2 Instance..."
JENKINS_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${CLUSTER_NAME}-JenkinsServer" --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$JENKINS_INSTANCE_ID" ]; then
    aws ec2 terminate-instances --instance-ids "$JENKINS_INSTANCE_ID"
    log "Waiting for Jenkins EC2 instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids "$JENKINS_INSTANCE_ID"
    log "Jenkins EC2 instance terminated"
else
    log "Jenkins EC2 instance not found"
fi

# Delete Node Group
log "Deleting EKS Node Group: $NODEGROUP_NAME"
if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" > /dev/null 2>&1; then
    aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME"
    log "Waiting for node group to be deleted..."
    aws eks wait nodegroup-deleted --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME"
    log "Node group $NODEGROUP_NAME deleted"
else
    log "Node group $NODEGROUP_NAME not found"
fi

# Delete EKS Cluster
log "Deleting EKS Cluster: $CLUSTER_NAME"
if aws eks describe-cluster --name "$CLUSTER_NAME" > /dev/null 2>&1; then
    aws eks delete-cluster --name "$CLUSTER_NAME"
    log "Waiting for cluster to be deleted..."
    aws eks wait cluster-deleted --name "$CLUSTER_NAME"
    log "EKS Cluster $CLUSTER_NAME deleted"
else
    log "EKS Cluster $CLUSTER_NAME not found"
fi

# Delete Security Groups
log "Deleting Security Groups..."
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text)
if [ -n "$SG_ID" ]; then
    aws ec2 delete-security-group --group-id "$SG_ID"
    log "Deleted security group: $SECURITY_GROUP_NAME"
else
    log "Security group $SECURITY_GROUP_NAME not found"
fi

# Delete Jenkins Security Group
JENKINS_SECURITY_GROUP_NAME="${CLUSTER_NAME}-jenkins-sg"
JENKINS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$JENKINS_SECURITY_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text)
if [ -n "$JENKINS_SG_ID" ]; then
    aws ec2 delete-security-group --group-id "$JENKINS_SG_ID"
    log "Deleted Jenkins security group: $JENKINS_SECURITY_GROUP_NAME"
else
    log "Jenkins security group $JENKINS_SECURITY_GROUP_NAME not found"
fi

# Delete Key Pair
log "Deleting Jenkins Key Pair..."
if aws ec2 describe-key-pairs --key-names "$JENKINS_KEY_PAIR_NAME" > /dev/null 2>&1; then
    aws ec2 delete-key-pair --key-name "$JENKINS_KEY_PAIR_NAME"
    rm -f "${JENKINS_KEY_PAIR_NAME}.pem"
    log "Deleted key pair: $JENKINS_KEY_PAIR_NAME"
else
    log "Key pair $JENKINS_KEY_PAIR_NAME not found"
fi

# Delete VPC and associated resources
log "Deleting VPC and associated resources..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)

if [ -n "$VPC_ID" ]; then
    # Detach and delete Internet Gateway
    log "Detaching and deleting Internet Gateway..."
    IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ -n "$IGW_ID" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
        aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
        log "Internet Gateway $IGW_ID deleted"
    else
        log "No Internet Gateway found for VPC $VPC_ID"
    fi

    # Delete Subnets
    log "Deleting subnets..."
    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text)
    for subnet_id in $SUBNET_IDS; do
        aws ec2 delete-subnet --subnet-id "$subnet_id"
        log "Deleted subnet: $subnet_id"
    done

    # Delete Route Table
    log "Deleting Route Table..."
    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    if [ -n "$ROUTE_TABLE_ID" ]; then
        aws ec2 delete-route-table --route-table-id "$ROUTE_TABLE_ID"
        log "Deleted Route Table: $ROUTE_TABLE_ID"
    else
        log "No non-main Route Table found"
    fi

    # Delete VPC
    aws ec2 delete-vpc --vpc-id "$VPC_ID"
    log "Deleted VPC: $VPC_ID"
else
    log "VPC $VPC_NAME not found"
fi

# Detach and Delete IAM Policies and Roles
log "Detaching and deleting IAM roles..."
delete_iam_role() {
    local role_name=$1
    log "Deleting IAM role: $role_name"
    if aws iam get-role --role-name "$role_name" > /dev/null 2>&1; then
        policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[*].PolicyArn' --output text)
        for policy_arn in $policies; do
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
        done
        aws iam delete-role --role-name "$role_name"
        log "Deleted IAM role: $role_name"
    else
        log "IAM role $role_name not found"
    fi
}

delete_iam_role "$CLUSTER_ROLE_NAME"
delete_iam_role "$WORKER_ROLE_NAME"
delete_iam_role "$JENKINS_ROLE_NAME"

log "Teardown complete. All resources deleted successfully."
