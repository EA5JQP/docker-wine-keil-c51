#!/bin/bash
# Launch Keil uVision IDE via Docker + Wine

CONTAINER_NAME="keil-wine"
WINE_PREFIX="${HOME}/.wine-docker/.wine"
USER_NAME="wineuser"
USER_UID="$(id -u)"
USER_GID="$(id -g)"

# Allow Docker to access X11 display
xhost +local:docker 2>/dev/null || true

# Create container if it doesn't exist
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Creating persistent Docker container..."
    docker run -d --name "${CONTAINER_NAME}" --restart=always \
        -v "${WINE_PREFIX}:/home/${USER_NAME}/.wine" \
        -v "/tmp/.X11-unix:/tmp/.X11-unix:ro" \
        --env="DISPLAY=${DISPLAY}" \
        --env="USER_NAME=${USER_NAME}" \
        --env="USER_UID=${USER_UID}" \
        --env="USER_GID=${USER_GID}" \
        --env="USER_HOME=/home/${USER_NAME}" \
        scottyhardy/docker-wine:latest sleep infinity
fi

# Start container if not running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting container..."
    docker start "${CONTAINER_NAME}"
fi

echo "Launching Keil uVision (CID: $(docker inspect --format '{{.Id}}' ${CONTAINER_NAME} | cut -c1-12))..."
docker exec "${CONTAINER_NAME}" sh -c "wine /home/${USER_NAME}/.wine/drive_c/Keil_v5/UV4/UV4.exe"
