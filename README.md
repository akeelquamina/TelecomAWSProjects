AWS EKS Environment Setup with Jenkins Server
This guide provides detailed steps to set up an AWS EKS (Elastic Kubernetes Service) environment along with a Jenkins server for CI/CD purposes. Follow the steps below to configure and manage your infrastructure.

Prerequisites
Before starting, ensure you have the following:

AWS CLI installed and configured with appropriate IAM permissions.
Docker installed and running.
Jenkins installed and running.
Necessary IAM roles and policies for EKS and EC2 instances.
Required credentials stored in Jenkins for DockerHub and AWS.
Initial Setup Script
Run the EKS Cluster Setup Script
Create a bash script setup.sh with the following content:
