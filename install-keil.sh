#!/bin/bash
# Install Keil C51 v9.60 in Docker Wine 8.4 (GUI installer)
set -e

CONTAINER="keil-wine"
IMAGE="scottyhardy/docker-wine:devel-8.4"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/c51v960a.exe"
ADDON="$SCRIPT_DIR/KeilMDK5Addon.exe"
WINE_VOLUME="${HOME}/.wine-docker"

echo "=== Keil C51 Installer (GUI) for Docker + Wine 8.4 ==="

# Check installers exist
for f in "$INSTALLER"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: $f not found"
        exit 1
    fi
done

# Stop and remove existing container
echo "[1/5] Removing old container..."
docker rm -f "$CONTAINER" 2>/dev/null || true

# Clean old wine prefix
echo "[2/5] Cleaning Wine prefix..."
docker run --rm -v "${WINE_VOLUME}":/data --entrypoint="" "$IMAGE" rm -rf /data/* 2>/dev/null || true
mkdir -p "${WINE_VOLUME}"

# Fix X11 socket permissions
chmod 777 /tmp/.X11-unix/X* 2>/dev/null || true

# Create container with X11
echo "[3/5] Creating Wine 8.4 container with X11..."
docker run -d --name "$CONTAINER" --platform linux/amd64 --shm-size 1g --restart=always \
    -e FORCED_OWNERSHIP=yes \
    -e DISPLAY="${DISPLAY}" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
    -v "${WINE_VOLUME}":/home/wineuser \
    "$IMAGE" sleep infinity

sleep 3
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "ERROR: Container failed to start"
    docker logs "$CONTAINER"
    exit 1
fi

# Init Wine prefix
echo "[4/5] Initializing Wine prefix..."
docker exec --user wineuser "$CONTAINER" wineboot --init 2>&1 | grep -v "fixme:" | tail -2

# Copy installers
echo "[5/5] Copying installers..."
docker cp "$INSTALLER" "$CONTAINER:/home/wineuser/c51v960a.exe"
docker exec --user root "$CONTAINER" chown wineuser:wineuser /home/wineuser/c51v960a.exe
if [ -f "$ADDON" ]; then
    docker cp "$ADDON" "$CONTAINER:/home/wineuser/KeilMDK5Addon.exe"
    docker exec --user root "$CONTAINER" chown wineuser:wineuser /home/wineuser/KeilMDK5Addon.exe
fi

echo ""
echo "=== Container ready ==="
echo "Now run the installer visually:"
echo ""
echo "  docker exec -it -e DISPLAY=:0 --user wineuser $CONTAINER wine /home/wineuser/c51v960a.exe"
echo ""
echo "After Keil C51 installs, optionally install MDK5Addon:"
echo ""
echo "  docker exec -it -e DISPLAY=:0 --user wineuser $CONTAINER wine /home/wineuser/KeilMDK5Addon.exe"
echo ""
echo "Then test with: bash launch-uvision.sh"
