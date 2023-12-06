pipeline {
    agent any

    environment {
        DOCKERHUB_USERNAME = credentials('DockerHub_Connection')
        AWS_ACCESS_KEY_ID     = credentials('AWS_Access_Key_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_Secret_Access_Key')
        AWS_DEFAULT_REGION    = 'us-east-2'
        EKS_CLUSTER_NAME      = 'QuamTel'
        JENKINS_SECURITY_GROUP_ID = 'Jenkins-SG'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Pull and Build Docker Images') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'DockerHub_Connection', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_PASSWORD'),
                                     string(credentialsId: 'AWS_Access_Key_ID', variable: 'AWS_ACCESS_KEY_ID'),
                                     string(credentialsId: 'AWS_Secret_Access_Key', variable: 'AWS_SECRET_ACCESS_KEY')]) {

                        def services = ['billing-service', 'call-routing-service', 'sms-notification-service']

                        // Iterate over services
                        services.each { service ->
                            def imageTag = "v1"
                            def fullImageName = "akeelquamina/${service}:${imageTag}"

                            // Pull Docker image or ignore failure
                            sh "docker pull ${fullImageName} || true"

                            // Build and push Docker image
                            sh "docker buildx build -t ${fullImageName} ./Microservices_K8/${service}"
                            sh "docker login -u ${DOCKERHUB_USERNAME} -p ${DOCKERHUB_PASSWORD}"
                            sh "docker push ${fullImageName}"
                        }
                    }
                }
            }
        }

        stage('Create EKS Cluster') {
            steps {
                script {
                    // CloudFormation Stack Creation
                    sh "aws cloudformation create-stack --stack-name eks-cluster-stack --template-body file://Microservices_K8/k8s-deployments/eks-cluster.yml --parameters ParameterKey=ClusterName,ParameterValue=${EKS_CLUSTER_NAME} --region ${AWS_DEFAULT_REGION}"
                    sh "aws cloudformation wait stack-create-complete --stack-name eks-cluster-stack --region ${AWS_DEFAULT_REGION}"

                    // EKS Cluster Configuration
                    sh "aws eks --region ${AWS_DEFAULT_REGION} update-kubeconfig --name ${EKS_CLUSTER_NAME}"

                    def services = ['billing-service', 'call-routing-service', 'sms-notification-service']

                    services.each { service ->
                        sh "kubectl apply -f Microservices_K8/${service}/k8s-manifest.yaml"
                    }

                    services.each { service ->
                        sh "kubectl rollout status deployment ${service}"
                    }
                }
            }
        }
    }
}