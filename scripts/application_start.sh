
#!/bin/bash
set -euo pipefail

AWS_REGION="ap-south-1"
ECR_REGISTRY="545931886180.dkr.ecr.ap-south-1.amazonaws.com"
IMAGE_FILE="/opt/techcake-deploy/image_uri.txt"
ENV_FILE="/run/techcake/app.env"

if [ ! -f "$IMAGE_FILE" ]; then
    echo "ERROR: Image URI file not found: $IMAGE_FILE"
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Application environment file not found: $ENV_FILE"
    exit 1
fi

IMAGE_URI="$(tr -d '[:space:]' < "$IMAGE_FILE")"

if [[ ! "$IMAGE_URI" =~ ^545931886180\.dkr\.ecr\.ap-south-1\.amazonaws\.com/techcake-django-app-v3:[a-f0-9]{40}$ ]]; then
    echo "ERROR: Invalid ECR image URI: $IMAGE_URI"
    exit 1
fi

systemctl start docker

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker pull "$IMAGE_URI"

docker rm -f django-v3 2>/dev/null || true

docker run -d \
    --name django-v3 \
    --restart unless-stopped \
    --env-file "$ENV_FILE" \
    -p 8000:8000 \
    "$IMAGE_URI"

echo "Application container started: $IMAGE_URI"
