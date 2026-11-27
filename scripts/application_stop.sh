
#!/bin/bash
set -euo pipefail

if docker container inspect django-v3 >/dev/null 2>&1; then
    docker rm -f django-v3
fi
