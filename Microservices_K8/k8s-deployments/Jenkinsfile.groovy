pipeline {
    agent any

    environment {
        DOCKERHUB_CREDENTIALS = credentials('DockerHub_Connection')
        AWS_DEFAULT_REGION = 'us-east-2'
        EKS_CLUSTER_NAME = 'QuamTel'
        PYTHON_VERSION = '3.9'
        SERVICES_YAML = 'services.yaml'
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
                                echo "Deploying ${service}"
                                sh "kubectl apply -f Microservices_K8/${service}/k8s-manifest.yaml"
                        
                                echo "Waiting for ${service} deployment to complete"
                                def rolloutSuccess = sh(script: "kubectl rollout status deployment ${service} --timeout=900s", returnStatus: true)
                        
                                if (rolloutSuccess != 0) {
                                    echo "Deployment of ${service} failed or timed out. Collecting debug information:"
                                    sh """
                                        kubectl get deployment ${service} -o wide
                                        kubectl describe deployment ${service}
                                        kubectl get pods -l app=${service}
                                        kubectl describe pods -l app=${service}
                                        kubectl logs -l app=${service} --tail=100
                                        kubectl describe nodes | grep -A 5 'Allocated resources'
                                        kubectl get pods --field-selector=status.phase=Pending
                                    """
                                    error("Deployment of ${service} failed or timed out")
                                } else {
                                    echo "${service} deployed successfully"
                                }
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
                            echo "Applying services exposure configuration"
                            sh "kubectl apply -f Microservices_K8/${SERVICES_YAML}"
                            
                            echo "Waiting for services to be exposed"
                            sh "kubectl get services"
                            
                            echo "Services exposed successfully"
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
