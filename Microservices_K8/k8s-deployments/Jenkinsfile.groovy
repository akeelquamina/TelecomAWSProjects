pipeline {
    agent any

    environment {
        DOCKERHUB_USERNAME = credentials('DockerHub_Connection')
        AWS_DEFAULT_REGION = 'us-east-2'
        EKS_CLUSTER_NAME = 'QuamTel'
        PYTHON_VERSION = '3.9'  // Add Python version
    }

    stages {
        stage('Install Dependencies') {
            steps {
                script {
                    // Install dependencies, e.g., urllib3
                    sh "python${PYTHON_VERSION} -m venv venv"
                    sh "source venv/bin/activate"
                    sh "pip install urllib3"
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Pull and Build Docker Images') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'DockerHub_Connection', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_PASSWORD')]) {
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

        stage('Update EKS Cluster Configuration') {
            steps {
                withAWS(region: "${AWS_DEFAULT_REGION}", credentials: 'AWS_Credentials') {
                    script {
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

        stage('Expose Services') {
            steps {
                withAWS(region: "${AWS_DEFAULT_REGION}", credentials: 'AWS_Credentials') {
                    script {
                        // Apply service configurations
                        sh "kubectl apply -f Microservices_K8/k8s-deployments/services.yaml"
                    }
                }
            }
        }
    }
}