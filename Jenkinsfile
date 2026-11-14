
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        AWS_REGION = 'ap-south-1'
        AWS_ACCOUNT_ID = '545931886180'
        ECR_REPOSITORY = 'techcake-django-app-v3'
        INSTANCE_ID = 'i-0ec6e6efcabac1611'
        HEALTH_URL = 'https://djangov2.tc-0054.nixlabs.in/health'
        REGISTRY = '545931886180.dkr.ecr.ap-south-1.amazonaws.com'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_URI = "${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

                    echo "Commit SHA: ${IMAGE_TAG}"
                    echo "Image: ${IMAGE_URI}"
                }
            }
        }

        stage('Test') {
            steps {
                sh '''
                    docker run --rm \
                      -v "$WORKSPACE:/app" \
                      -w /app \
                      -e DB_ENGINE=sqlite \
                      python:3.11-slim \
                      sh -c "pip install -r requirements.txt && python manage.py test"
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    docker build \
                      --build-arg APP_VERSION="$IMAGE_TAG" \
                      -t "$IMAGE_URI" .
                '''
            }
        }

        stage('Scan') {
            steps {
                sh '''
                    mkdir -p "$WORKSPACE/trivy-cache"

                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      -v "$WORKSPACE:/work" \
                      -v "$WORKSPACE/trivy-cache:/root/.cache/" \
                      aquasec/trivy:0.76.2 \
                      image --format json \
                      --output /work/trivy-report.json \
                      --severity HIGH,CRITICAL \
                      --exit-code 0 \
                      "$IMAGE_URI"

                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      -v "$WORKSPACE/trivy-cache:/root/.cache/" \
                      aquasec/trivy:0.76.2 \
                      image --format table \
                      --severity CRITICAL \
                      --exit-code 1 \
                      "$IMAGE_URI"
                '''
            }
        }

        stage('Push') {
            steps {
                sh '''
                    aws ecr get-login-password --region "$AWS_REGION" |
                    docker login \
                      --username AWS \
                      --password-stdin "$REGISTRY"

                    if aws ecr describe-images \
                      --repository-name "$ECR_REPOSITORY" \
                      --image-ids imageTag="$IMAGE_TAG" \
                      --region "$AWS_REGION" >/dev/null 2>&1; then
                        echo "Image tag already exists in ECR. Skipping push: $IMAGE_TAG"
                    else
                        docker push "$IMAGE_URI"
                    fi
                '''
            }
        }

        stage('Deploy') {
            steps {
                script {
                    def remoteScript = '''
#!/bin/bash
set -Eeuo pipefail

GIT_SHA="__GIT_SHA__"
IMAGE_URI="__IMAGE_URI__"
REGISTRY="545931886180.dkr.ecr.ap-south-1.amazonaws.com"
COMPOSE="/root/docker-compose-v3.yml"
ROLLBACK_IMAGE="django-v2:rollback-${GIT_SHA}"
HEALTH_URL="https://djangov2.tc-0054.nixlabs.in/health"

if [ ! -f /root/.env ]; then
    echo "Missing /root/.env"
    exit 1
fi

if ! docker inspect django-v2 >/dev/null 2>&1; then
    echo "Existing django-v2 container not found"
    exit 1
fi

if ! docker inspect nginx-proxy >/dev/null 2>&1; then
    echo "nginx-proxy container not found"
    exit 1
fi

OLD_IMAGE_ID=$(docker inspect -f '{{.Image}}' django-v2)
docker tag "$OLD_IMAGE_ID" "$ROLLBACK_IMAGE"

rollback() {
    echo "Deployment failed. Rolling back..."
    set +e
    docker rm -f django-v2
    IMAGE_URI="$ROLLBACK_IMAGE" docker compose -f "$COMPOSE" -p root up -d --no-deps django
    docker exec nginx-proxy nginx -s reload
    exit 1
}

trap rollback ERR

curl -fsSL \
  "https://raw.githubusercontent.com/adhilwork/techcake-django-app-v3/${GIT_SHA}/docker-compose.yml" \
  -o "$COMPOSE"

aws ecr get-login-password --region ap-south-1 |
docker login --username AWS --password-stdin "$REGISTRY"

docker pull "$IMAGE_URI"

IMAGE_URI="$IMAGE_URI" docker compose -f "$COMPOSE" -p root up -d --no-deps django

docker exec nginx-proxy nginx -s reload

for i in $(seq 1 18); do
    RESPONSE=$(curl -fsS "$HEALTH_URL" || true)

    VERSION=$(printf '%s' "$RESPONSE" | python3 -c '
import json,sys
try:
    print(json.load(sys.stdin).get("version", ""))
except Exception:
    print("")
')

    if [ "$VERSION" = "$GIT_SHA" ]; then
        echo "Deployment successful: $VERSION"
        trap - ERR
        exit 0
    fi

    sleep 5
done

echo "Health check failed or version mismatch"
false
'''

                    remoteScript = remoteScript
                        .replace('__GIT_SHA__', env.IMAGE_TAG)
                        .replace('__IMAGE_URI__', env.IMAGE_URI)

                    writeFile(
                        file: 'remote-deploy.sh',
                        text: remoteScript
                    )

                    def commandJson = groovy.json.JsonOutput.toJson([
                        DocumentName: 'AWS-RunShellScript',
                        InstanceIds: [env.INSTANCE_ID],
                        Parameters: [
                            commands: [remoteScript]
                        ],
                        Comment: "Jenkins deployment ${env.IMAGE_TAG}",
                        TimeoutSeconds: 900
                    ])

                    writeFile(
                        file: 'ssm-command.json',
                        text: commandJson
                    )

                    sh '''
                        COMMAND_ID=$(aws ssm send-command \
                          --cli-input-json file://ssm-command.json \
                          --region "$AWS_REGION" \
                          --query 'Command.CommandId' \
                          --output text)

                        echo "SSM Command ID: $COMMAND_ID"

                        for i in $(seq 1 60); do
                            STATUS=$(aws ssm get-command-invocation \
                              --command-id "$COMMAND_ID" \
                              --instance-id "$INSTANCE_ID" \
                              --region "$AWS_REGION" \
                              --query 'Status' \
                              --output text 2>/dev/null || true)

                            echo "SSM Status: $STATUS"

                            if [ "$STATUS" = "Success" ]; then
                                aws ssm get-command-invocation \
                                  --command-id "$COMMAND_ID" \
                                  --instance-id "$INSTANCE_ID" \
                                  --region "$AWS_REGION" \
                                  --query 'StandardOutputContent' \
                                  --output text
                                exit 0
                            fi

                            if [ "$STATUS" = "Failed" ] || \
                               [ "$STATUS" = "Cancelled" ] || \
                               [ "$STATUS" = "TimedOut" ]; then
                                aws ssm get-command-invocation \
                                  --command-id "$COMMAND_ID" \
                                  --instance-id "$INSTANCE_ID" \
                                  --region "$AWS_REGION" \
                                  --output json
                                exit 1
                            fi

                            sleep 10
                        done

                        echo "SSM command timed out"
                        exit 1
                    '''
                }
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    RESPONSE=$(curl -fsS --retry 5 --retry-delay 5 "$HEALTH_URL")

                    echo "$RESPONSE" | python3 -c '
import json,sys
data=json.load(sys.stdin)
expected=sys.argv[1]
actual=data.get("version", "")
print("Expected version:", expected)
print("Actual version:", actual)
if actual != expected:
    raise SystemExit("Version verification failed")
' "$IMAGE_TAG"

                    echo "Application health and version verified."
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts(
                artifacts: 'trivy-report.json',
                allowEmptyArchive: true
            )
        }

        success {
            echo 'Jenkins pipeline completed successfully.'
        }

        failure {
            echo 'Jenkins pipeline failed. Check the failed stage and console output.'
        }
    }
}
