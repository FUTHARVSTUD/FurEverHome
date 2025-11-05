pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
    }

    environment {
        GIT_REPO   = 'https://github.com/FUTHARVSTUD/FurEverHome.git'
        EC2_HOST   = 'ubuntu@50.16.32.19'       // SSH user@host for the EC2 instance
        REMOTE_DIR = '/fureverhome'         // Location of the project on the EC2 host
        COMPOSE_FILE = 'docker-compose.prod.yml'
        PUBLIC_URL   = 'http://50.16.32.19'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate Compose Config') {
            steps {
                sh '''
                    set -euo pipefail
                    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
                        docker compose -f docker-compose.prod.yml config -q
                    else
                        echo "Skipping docker compose validation (docker compose not available on agent)."
                    fi
                '''
            }
        }

        stage('Deploy to EC2') {
            steps {
                sshagent(['ec2-deployer']) {
                    withCredentials([file(credentialsId: 'fureverhome-prod-env', variable: 'ENV_FILE_PATH')]) {
                        sh '''
                            set -euo pipefail
                            chmod +x scripts/deploy.sh
                            EC2_HOST="${EC2_HOST}" \
                            REMOTE_DIR="${REMOTE_DIR}" \
                            COMPOSE_FILE="${COMPOSE_FILE}" \
                            GIT_REPO="${GIT_REPO}" \
                            ENV_FILE_PATH="${ENV_FILE_PATH}" \
                            scripts/deploy.sh
                        '''
                    }
                }
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    set -euo pipefail
                    curl -fsS "${PUBLIC_URL}/api/health"
                '''
            }
        }
    }

    post {
        success {
            echo '✅ Deployment completed successfully!'
        }
        failure {
            echo '❌ Deployment failed.'
        }
    }
}
