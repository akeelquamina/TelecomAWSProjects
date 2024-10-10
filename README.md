# QuamTel AWS Environment Setup

This repository contains Bash scripts to set up and tear down an AWS environment for **QuamTel**. The setup involves creating an EKS (Elastic Kubernetes Service) cluster, configuring VPC, subnets, security groups, IAM roles, and deploying a Jenkins server on an EC2 instance.

## Table of Contents

- [Overview](#overview)
- [Pre-requisites](#pre-requisites)
- [Setup Script](#setup-script)
- [Teardown Script](#teardown-script)
- [Configuration](#configuration)
- [Logging](#logging)
- [FAQ](#faq)

## Overview

The **QuamTel AWS Environment** includes:
- Amazon EKS Cluster
- VPC, Subnets, and Security Groups
- IAM Roles for the EKS Cluster, Worker Nodes, and Jenkins
- Jenkins Server running on an EC2 instance

The repository provides two primary scripts:
1. `setup.sh`: Automates the process of setting up all necessary AWS resources.
2. `teardown.sh`: Cleans up and deletes all the resources created during the setup.

## Pre-requisites

Before running the scripts, ensure the following:

1. **AWS CLI**: Install and configure the AWS CLI with appropriate credentials.
   ```bash
   aws configure

   
Ensure you have sufficient IAM permissions to create and delete EKS, EC2, IAM roles, VPC, and other related AWS resources.

2. kubectl: Install kubectl for interacting with the EKS cluster.

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

3.Install jq for parsing JSON in the shell scripts.

sudo apt-get install jq

4.eksctl: Install eksctl to manage EKS clusters.

curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/0.111.0/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin


**Setup Script**
The setup.sh script creates the following AWS resources:

VPC: A dedicated Virtual Private Cloud for QuamTel.
Subnets: Public and private subnets.
Security Groups: For both the EKS cluster and Jenkins EC2 instance.
EKS Cluster: A fully managed Kubernetes service on AWS.
IAM Roles: For the EKS cluster, worker nodes, and Jenkins.
EC2 Instance: A Jenkins server running on a t3.micro EC2 instance.


**Usage**
1.Clone the repository:

git clone https://github.com/yourusername/quamtel-aws-setup.git
cd quamtel-aws-setup

2.Make the script executable:

chmod +x setup.sh

3.Run the script:

./setup.sh

**What Happens During Setup**

Creates a VPC with the appropriate subnets and security groups.
Provisions an EKS Cluster with a managed node group.
Configures IAM roles with the necessary permissions for the EKS cluster and worker nodes.
Launches a Jenkins server on an EC2 instance, with its security group allowing SSH and HTTP access.


**Post-Setup Steps**
After the setup is complete, you can use the following command to configure kubectl to communicate with the EKS cluster:

aws eks --region us-east-2 update-kubeconfig --name QuamTel

Teardown Script
The teardown.sh script safely deletes all AWS resources created during setup.

Usage
Make the script executable:

bash
Copy code
chmod +x teardown.sh
Run the script:

bash
Copy code
./teardown.sh
What Happens During Teardown
Terminates the Jenkins EC2 instance.
Deletes the EKS Node Group and EKS Cluster.
Detaches and deletes IAM roles used for the cluster, worker nodes, and Jenkins.
Deletes security groups, subnets, and the VPC.
The teardown script ensures that AWS waits for each resource to be fully deleted before proceeding to the next one, avoiding conflicts and ensuring smooth operation.

Configuration
The following variables can be configured in both setup.sh and teardown.sh to match your requirements:

CLUSTER_NAME: The name of the EKS cluster.
REGION: The AWS region where resources are created (default: us-east-2).
VPC_NAME: The name of the VPC.
JENKINS_KEY_PAIR_NAME: The name of the SSH key pair for the Jenkins EC2 instance.
IAM Role Names: Modify these if you want to use different role names for the EKS cluster, worker nodes, and Jenkins.
Logging
Both setup.sh and teardown.sh scripts log their actions to setup.log and teardown.log, respectively. You can check these files for detailed output during and after the execution of the scripts.

FAQ
1. What happens if the script fails during execution?

The scripts use the set -e option, which causes them to exit immediately if any command returns a non-zero status. Check the log files for errors and re-run the script after fixing the issue.
2. Can I re-run the setup script?

Yes, but make sure to run the teardown.sh script first to avoid resource conflicts.
3. How do I access the Jenkins server?

After setup, you can SSH into the EC2 instance using the key pair you specified:
bash
Copy code
ssh -i path/to/key.pem ec2-user@<public-ip-address>
License
This project is licensed under the MIT License - see the LICENSE file for details.

markdown
Copy code

### Key Sections:
- **Pre-requisites**: Lists the tools you need before running the scripts.
- **Setup Script**: Details how to run the `setup.sh` script, what it does, and post-setup instructions.
- **Teardown Script**: Instructions for running the `teardown.sh` script to clean up resources.
- **Configuration**: Explains how to customize variables.
- **Logging**: Mentions where logs are saved for troubleshooting.
- **FAQ**: Answers some common questions.

This should serve as a solid `README` for your GitHub repository.





