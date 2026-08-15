#!/bin/bash
# Build nicFW using Keil uVision GUI in Docker
# The GUI properly handles assembly files (STARTUP.A51) in the link step
set -e

CONTAINER="keil-wine"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEIL_BIN="/home/wineuser/.wine/drive_c/Keil_v5/UV4"

usage() {
    echo "Usage: $0 <project_folder>"
    echo ""
    echo "  <project_folder>  Local folder containing .uvproj file"
    echo ""
    echo "Opens Keil uVision with the project. Click Build (F7) to compile."
    echo "Output will be in <project_folder>/Objects/"
    exit 1
}

[ $# -lt 1 ] && usage

PROJECT_DIR="$(cd "$1" && pwd)"

# Find .uvproj
UVPROJ=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.uvproj" | head -1)
[ -z "$UVPROJ" ] && echo "ERROR: No .uvproj found in $PROJECT_DIR" && exit 1

PROJECT_NAME=$(basename "$UVPROJ" .uvproj)
echo "Project: $PROJECT_NAME"

# Ensure container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Starting container..."
    docker start "$CONTAINER" 2>/dev/null || { echo "ERROR: Container not found. Run install-keil.sh first."; exit 1; }
fi

# Fix X11 permissions
chmod 777 /tmp/.X11-unix/X* 2>/dev/null || true
xhost +local:docker 2>/dev/null || true

# Copy project to container
CONTAINER_DIR="/home/wineuser/build/${PROJECT_NAME}"
echo "Copying project to container..."
docker exec "$CONTAINER" rm -rf "$CONTAINER_DIR" 2>/dev/null || true
docker exec "$CONTAINER" mkdir -p "$CONTAINER_DIR"
docker cp "$PROJECT_DIR/." "${CONTAINER}:${CONTAINER_DIR}/"
docker exec --user root "$CONTAINER" chown -R wineuser:wineuser "$CONTAINER_DIR"

# Launch UV4 with the project file
echo "Launching Keil uVision with ${PROJECT_NAME}.uvproj..."
echo "  Click Build (F7) to compile, then close uVision when done."
docker exec -e DISPLAY="${DISPLAY}" --user wineuser "$CONTAINER" \
    wine "${KEIL_BIN}/UV4.exe" "Z:${CONTAINER_DIR}/${PROJECT_NAME}.uvproj" &

UV4_PID=$!
echo "UV4 PID: $UV4_PID"

# Wait for user to close uVision
echo ""
echo "Waiting for uVision to close..."
wait $UV4_PID 2>/dev/null || true

# Copy output back
OUTPUT_DIR="${PROJECT_DIR}/Objects"
mkdir -p "$OUTPUT_DIR"

echo "Copying output..."
CONTAINER_OBJECTS="${CONTAINER_DIR}/Objects"
for ext in hex HEX obj OBJ lst LST map MAP lnp LNP bin BIN; do
    for f in $(docker exec --user wineuser "$CONTAINER" sh -c "ls ${CONTAINER_OBJECTS}/*.${ext} 2>/dev/null" 2>/dev/null); do
        docker cp "${CONTAINER}:${f}" "$OUTPUT_DIR/" 2>/dev/null || true
    done
done

# Convert .hex to .bin
for hexfile in "$OUTPUT_DIR"/*.hex "$OUTPUT_DIR"/*.HEX; do
    [ -f "$hexfile" ] || continue
    binfile="${hexfile%.*}.bin"
    objcopy -I ihex -O binary "$hexfile" "$binfile" 2>/dev/null && \
        echo "  $(basename "$hexfile") -> $(basename "$binfile")"
done

# Show results
echo ""
echo "Output files:"
if [ -d "$OUTPUT_DIR" ]; then
    for f in "$OUTPUT_DIR"/*; do
        [ -f "$f" ] && echo "  $(basename "$f") ($(wc -c < "$f") bytes)"
    done
fi

# Cleanup container
docker exec --user wineuser "$CONTAINER" rm -rf "$CONTAINER_DIR" 2>/dev/null || true
