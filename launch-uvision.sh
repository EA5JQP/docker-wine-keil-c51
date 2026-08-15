#!/bin/bash
# Launch Keil uVision IDE via Docker + Wine 8.4

CONTAINER="keil-wine"
WINE_VOLUME="${HOME}/.wine-docker"
DISPLAY="${DISPLAY}"

# Allow Docker to access X11 display
xhost +local:docker 2>/dev/null || true

# Fix X11 socket permissions so container user (uid 1010) can connect
chmod 777 /tmp/.X11-unix/X* 2>/dev/null || true

# Create container if it doesn't exist
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Creating persistent Docker container..."
    docker run -d --name "${CONTAINER}" --platform linux/amd64 --shm-size 1g --restart=always \
        -e FORCED_OWNERSHIP=yes \
        -e DISPLAY="${DISPLAY}" \
        -v "/tmp/.X11-unix:/tmp/.X11-unix:ro" \
        -v "${WINE_VOLUME}":/home/wineuser \
        scottyhardy/docker-wine:devel-8.4 sleep infinity
fi

# Start container if not running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Starting container..."
    docker start "${CONTAINER}"
fi

echo "Launching Keil uVision (CID: $(docker inspect --format '{{.Id}}' ${CONTAINER} | cut -c1-12))..."
docker exec -e DISPLAY="${DISPLAY}" --user wineuser "${CONTAINER}" \
    wine /home/wineuser/.wine/drive_c/Keil_v5/UV4/UV4.exe
