pipeline {
    agent any

    environment {
        DOCKERHUB_CREDENTIALS = credentials('DockerHub_Connection')
        AWS_CREDENTIALS = credentials('AWS_Credentials')
        AWS_DEFAULT_REGION = 'us-east-2'
        EKS_CLUSTER_NAME = 'QuamTel'
        PYTHON_VERSION = '3.9'
    }

    stages {
        stage('Install Dependencies') {
            steps {
                script {
                    sh """
                    python${PYTHON_VERSION} -m venv venv
                    source venv/bin/activate
                    pip install urllib3
                    """
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
                    withCredentials([usernamePassword(credentialsId: 'DockerHub_Connection', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_PASSWORD'),
                                     string(credentialsId: 'AWS_Access_Key_ID', variable: 'AWS_ACCESS_KEY_ID'),
                                     string(credentialsId: 'AWS_Secret_Access_Key', variable: 'AWS_SECRET_ACCESS_KEY')]) {

                        def services = ['billing-service', 'call-routing-service', 'sms-notification-service']
                        def imageTag = "v1"

                        services.each { service ->
                            def fullImageName = "akeelquamina/${service}:${imageTag}"

                            sh "docker pull ${fullImageName} || true"

                            sh """
                            docker buildx build -t ${fullImageName} ./Microservices_K8/${service}
                            docker login -u ${DOCKERHUB_USERNAME} -p ${DOCKERHUB_PASSWORD}
                            docker push ${fullImageName}
                            """
                        }
                    }
                }
            }
        }

        stage('Update EKS Cluster Configuration') {
            steps {
                script {
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

        stage('Expose Services') {
            steps {
                script {
                    sh "kubectl apply -f Microservices_K8/k8s-deployments/services.yaml"
                }
            }
        }
    }

    post {
        always {
            script {
                sh "deactivate || true"
            }
        }
    }
}
