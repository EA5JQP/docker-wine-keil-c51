#!/bin/bash
# Build an 8051 project using Keil UV4 batch mode in Docker
set -e

CONTAINER="keil-wine"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEIL_BIN="/home/wineuser/.wine/drive_c/Keil_v5/UV4"

usage() {
    echo "Usage: $0 <project_folder> [--rebuild]"
    exit 1
}

[ $# -lt 1 ] && usage

PROJECT_DIR="$(cd "$1" && pwd)"
REBUILD="${2:-}"

UVPROJ=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.uvproj" | head -1)
[ -z "$UVPROJ" ] && echo "ERROR: No .uvproj found in $PROJECT_DIR" && exit 1

PROJECT_NAME=$(basename "$UVPROJ" .uvproj)
echo "Project: $PROJECT_NAME"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Starting container..."
    docker start "$CONTAINER" 2>/dev/null || { echo "ERROR: Container not found."; exit 1; }
fi

chmod 777 /tmp/.X11-unix/X* 2>/dev/null || true

CONTAINER_DIR="/home/wineuser/build/${PROJECT_NAME}"
echo "Copying project..."
docker exec "$CONTAINER" rm -rf "$CONTAINER_DIR" 2>/dev/null || true
docker exec "$CONTAINER" mkdir -p "$CONTAINER_DIR"
docker cp "$PROJECT_DIR/." "${CONTAINER}:${CONTAINER_DIR}/"
docker exec --user root "$CONTAINER" chown -R wineuser:wineuser "$CONTAINER_DIR"

if [ "$REBUILD" = "--rebuild" ]; then
    echo "Cleaning..."
    docker exec --user wineuser "$CONTAINER" sh -c "rm -rf ${CONTAINER_DIR}/Objects/*"
fi

echo "Building..."
BUILD_LOG="/tmp/keil_build_${PROJECT_NAME}.log"
docker exec -e DISPLAY=:0 --user wineuser "$CONTAINER" \
    wine "${KEIL_BIN}/UV4.exe" \
    -b "Z:${CONTAINER_DIR}/${PROJECT_NAME}.uvproj" \
    -o "Z:/tmp/build.log" \
    2>&1 | grep -v "fixme:" || true

docker exec --user wineuser "$CONTAINER" cat /tmp/build.log > "$BUILD_LOG" 2>/dev/null || true

if grep -q "0 Error(s)" "$BUILD_LOG" 2>/dev/null; then
    echo "Build succeeded"
elif grep -q "Error(s)" "$BUILD_LOG" 2>/dev/null; then
    echo "Build FAILED:"
    grep "Error" "$BUILD_LOG"
fi

OUTPUT_DIR="${PROJECT_DIR}/Objects"
mkdir -p "$OUTPUT_DIR"

echo "Copying output..."
CONTAINER_OBJECTS="${CONTAINER_DIR}/Objects"
for ext in hex HEX obj OBJ lst LST map MAP lnp LNP; do
    for f in $(docker exec --user wineuser "$CONTAINER" sh -c "ls ${CONTAINER_OBJECTS}/*.${ext} 2>/dev/null" 2>/dev/null); do
        docker cp "${CONTAINER}:${f}" "$OUTPUT_DIR/" 2>/dev/null || true
    done
done
CONTAINER_LISTINGS="${CONTAINER_DIR}/Listings"
for ext in m51 M51 lst LST; do
    for f in $(docker exec --user wineuser "$CONTAINER" sh -c "ls ${CONTAINER_LISTINGS}/*.${ext} 2>/dev/null" 2>/dev/null); do
        docker cp "${CONTAINER}:${f}" "$OUTPUT_DIR/" 2>/dev/null || true
    done
done

for hexfile in "$OUTPUT_DIR"/*.hex "$OUTPUT_DIR"/*.HEX; do
    [ -f "$hexfile" ] || continue
    binfile="${hexfile%.*}.bin"
    objcopy -I ihex -O binary "$hexfile" "$binfile" 2>/dev/null && \
        echo "  $(basename "$hexfile") -> $(basename "$binfile")"
done

if [ -f "${PROJECT_DIR}/pad_bin.py" ]; then
    python3 "${PROJECT_DIR}/pad_bin.py"
fi

echo ""
echo "Output files:"
if [ -d "$OUTPUT_DIR" ]; then
    for f in "$OUTPUT_DIR"/*; do
        [ -f "$f" ] && echo "  $(basename "$f") ($(wc -c < "$f") bytes)"
    done
fi

echo ""
echo "Build log:"
cat "$BUILD_LOG"

docker exec --user wineuser "$CONTAINER" rm -rf "$CONTAINER_DIR" 2>/dev/null || true
rm -f "$BUILD_LOG"
