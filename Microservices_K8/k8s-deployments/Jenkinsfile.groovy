pipeline {
    agent any

    environment {
        DOCKERHUB_CREDENTIALS = credentials('DockerHub_Connection')
        AWS_DEFAULT_REGION = 'us-east-2'
        EKS_CLUSTER_NAME = 'QuamTel'
        PYTHON_VERSION = '3.9'
    }

    stages {
        stage('Install Dependencies') {
            steps {
                script {
                    try {
                        sh """
                            python${PYTHON_VERSION} -m venv venv
                            . venv/bin/activate
                            pip install urllib3
                        """
                    } catch (Exception e) {
                        echo "Error installing dependencies: ${e.getMessage()}"
                        currentBuild.result = 'FAILURE'
                        error("Failed to install dependencies")
                    }
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
                    def services = ['billing-service', 'call-routing-service', 'sms-notification-service']
                    services.each { service ->
                        try {
                            def imageTag = "v1"
                            def fullImageName = "akeelquamina/${service}:${imageTag}"
                            
                            sh "docker pull ${fullImageName} || true"
                            sh "docker build -t ${fullImageName} ./Microservices_K8/${service}"
                            sh "echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login -u ${DOCKERHUB_CREDENTIALS_USR} --password-stdin"
                            sh "docker push ${fullImageName}"
                        } catch (Exception e) {
                            echo "Error building/pushing ${service}: ${e.getMessage()}"
                            currentBuild.result = 'FAILURE'
                            error("Failed to build/push ${service}")
                        }
                    }
                }
            }
        }

        stage('Update EKS Cluster Configuration') {
            steps {
                withAWS(region: "${AWS_DEFAULT_REGION}", credentials: 'AWS_Credentials') {
                    script {
                        try {
                            sh "aws eks --region ${AWS_DEFAULT_REGION} update-kubeconfig --name ${EKS_CLUSTER_NAME}"
                            
                            def services = ['billing-service', 'call-routing-service', 'sms-notification-service']
                            services.each { service ->
                                sh "kubectl apply -f Microservices_K8/${service}/k8s-manifest.yaml"
                                sh "kubectl rollout status deployment ${service} --timeout=300s"
                            }
                        } catch (Exception e) {
                            echo "Error updating EKS configuration: ${e.getMessage()}"
                            currentBuild.result = 'FAILURE'
                            error("Failed to update EKS configuration")
                        }
                    }
                }
            }
        }

        stage('Expose Services') {
            steps {
                withAWS(region: "${AWS_DEFAULT_REGION}", credentials: 'AWS_Credentials') {
                    script {
                        try {
                            sh "kubectl apply -f Microservices_K8/k8s-deployments/services.yaml"
                        } catch (Exception e) {
                            echo "Error exposing services: ${e.getMessage()}"
                            currentBuild.result = 'FAILURE'
                            error("Failed to expose services")
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            sh "docker logout"
        }
    }
}
