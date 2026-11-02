pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        // Replace with your Docker Hub username.
        DOCKERHUB_USERNAME = 'YOUR_DOCKERHUB_USERNAME'
        IMAGE_NAME = "devops-flask-lab"
        K8S_NAMESPACE = "devops-lab"
        IMAGE_TAG = "${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'git rev-parse --short HEAD'
            }
        }

        stage('Test') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --no-cache-dir -r requirements.txt
                    pip install --no-cache-dir pytest
                    pytest -v
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build --pull -t ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG} .
                    docker tag ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG} \
                        ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:latest
                '''
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_TOKEN'
                )]) {
                    sh '''
                        echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:latest
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    kubectl apply -f k8s/namespace.yaml
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl set image deployment/flask-app \
                      flask-app=${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG} \
                      -n ${K8S_NAMESPACE}
                    kubectl rollout status deployment/flask-app \
                      -n ${K8S_NAMESPACE} --timeout=180s
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    kubectl get pods -n ${K8S_NAMESPACE} -o wide
                    kubectl get svc -n ${K8S_NAMESPACE}
                    curl --fail --retry 10 --retry-delay 3 \
                      http://127.0.0.1:30080/health
                '''
            }
        }
    }

    post {
        success {
            echo "Deployment successful: ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline failed. Review the failed stage and Jenkins console output.'
        }
        always {
            sh 'docker image prune -f || true'
        }
    }
}
