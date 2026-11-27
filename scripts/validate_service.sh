
#!/bin/bash
set -euo pipefail

IMAGE_FILE="/opt/techcake-deploy/image_uri.txt"
HEALTH_URL="http://127.0.0.1:8000/health"

if [ ! -f "$IMAGE_FILE" ]; then
    echo "ERROR: Image URI file not found"
    exit 1
fi

IMAGE_URI="$(tr -d '[:space:]' < "$IMAGE_FILE")"
EXPECTED_VERSION="${IMAGE_URI##*:}"

if [[ ! "$EXPECTED_VERSION" =~ ^[a-f0-9]{40}$ ]]; then
    echo "ERROR: Invalid image version: $EXPECTED_VERSION"
    exit 1
fi

for attempt in $(seq 1 30); do
    if RESPONSE="$(curl -fsS --max-time 5 "$HEALTH_URL")" &&
       printf '%s' "$RESPONSE" | python3 -c '
import json
import sys

expected = sys.argv[1]
data = json.load(sys.stdin)

if data.get("status") != "ok":
    sys.exit(1)

if data.get("database") != "ok":
    sys.exit(1)

if data.get("version") != expected:
    sys.exit(1)
' "$EXPECTED_VERSION"; then
        echo "SUCCESS: Health check passed for version $EXPECTED_VERSION"
        exit 0
    fi

    echo "Health check attempt $attempt failed; retrying..."
    sleep 5
done

echo "ERROR: Application validation failed"
exit 1
