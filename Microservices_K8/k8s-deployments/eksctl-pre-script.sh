#!/bin/bash

# Get the ID of the Jenkins security group
JENKINS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=Jenkins-SG" --query "SecurityGroups[0].GroupId" --output text)

# Get the ID of the EKS cluster control plane security group
EKS_CLUSTER_NAME="QuamTel"
EKS_SECURITY_GROUP_ID=$(eksctl get cluster --region us-east-2 --name "${EKS_CLUSTER_NAME}" -o json | jq -r '.[].ResourcesVpcConfig.ClusterSecurityGroupId')

# Authorize ingress for the Jenkins security group to the EKS control plane on port 6443
aws ec2 authorize-security-group-ingress --group-id "${JENKINS_SECURITY_GROUP_ID}" --protocol tcp --port 6443 --source "${EKS_SECURITY_GROUP_ID}"