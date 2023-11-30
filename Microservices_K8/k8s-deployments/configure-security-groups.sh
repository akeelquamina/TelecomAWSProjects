#!/bin/bash

# Get EKS Control Plane Security Group ID
eksControlPlaneSGID=$(aws eks describe-cluster --name QuamTel --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Get Node Group Security Group ID
nodeGroupSGID=$(aws eks describe-nodegroup --cluster-name QuamTel --nodegroup-name TAS --query "nodegroup.resources[0].securityGroups" --output text)

# Inbound rule for EKS API Server
aws ec2 authorize-security-group-ingress --group-id $eksControlPlaneSGID --protocol tcp --port 443 --source-security-group $nodeGroupSGID

# Inbound rule for Node-to-Node communication
aws ec2 authorize-security-group-ingress --group-id $nodeGroupSGID --protocol -1 --source-security-group $nodeGroupSGID

# Inbound rule for Control Plane Communication
aws ec2 authorize-security-group-ingress --group-id $nodeGroupSGID --protocol tcp --port 443 --source-security-group $eksControlPlaneSGID

# Outbound rule for Node-to-Node communication
aws ec2 authorize-security-group-egress --group-id $eksControlPlaneSGID --protocol -1 --destination-security-group $nodeGroupSGID

# Outbound rule for Control Plane Communication
aws ec2 authorize-security-group-egress --group-id $nodeGroupSGID --protocol tcp --port 443 --destination-security-group $eksControlPlaneSGID
