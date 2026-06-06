#!/bin/bash
# Wrapper script to compile 8051 C files using Keil C51 via Docker + Wine

CONTAINER_NAME="keil-wine"
WINE_PREFIX="${HOME}/.wine-docker/.wine"
USER_NAME="wineuser"
USER_UID="$(id -u)"
USER_GID="$(id -g)"

# Allow Docker to access X11 display
xhost +local:docker 2>/dev/null || true

if [ $# -eq 0 ]; then
    echo "Usage: $0 <source.c> [options]"
    echo "Example: $0 test.c"
    echo "Example: $0 test.c -O2"
    exit 1
fi

SOURCE_FILE="$1"
shift

# Get absolute path of source file
SOURCE_PATH="$(realpath "$SOURCE_FILE")"
SOURCE_NAME="$(basename "$SOURCE_FILE")"
SOURCE_DIR="$(dirname "$SOURCE_PATH")"

# Create container if it doesn't exist
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Creating persistent Docker container..."
    docker run -d --name "${CONTAINER_NAME}" --restart=always \
        -v "${SOURCE_DIR}:/workspace" \
        -v "${WINE_PREFIX}:/home/${USER_NAME}/.wine" \
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

# Start Xvfb if not running
docker exec -d "${CONTAINER_NAME}" Xvfb :99 -screen 0 1024x768x24 2>/dev/null || true

echo "Compiling $SOURCE_NAME (CID: $(docker inspect --format '{{.Id}}' ${CONTAINER_NAME} | cut -c1-12))..."
docker exec "${CONTAINER_NAME}" sh -c "export DISPLAY=:99 && wine /home/${USER_NAME}/.wine/drive_c/Keil_v5/C51/BIN/C51.exe /workspace/$SOURCE_NAME $*"

# Copy output files back to host
echo "Copying output files..."
docker cp "${CONTAINER_NAME}:/workspace/" /tmp/c51-output/ 2>/dev/null || true

# List compiled files
echo ""
echo "Compilation complete. Output files:"
ls -la /tmp/c51-output/*.hex /tmp/c51-output/*.obj /tmp/c51-output/*.lst 2>/dev/null || echo "No output files found"
