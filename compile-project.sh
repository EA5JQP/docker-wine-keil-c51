#!/bin/bash
# Direct Keil C51 toolchain builder (bypasses UV4)
# Usage: ./compile-project.sh <project_folder> [rebuild]

set -e

PROJECT_DIR="$(realpath "$1")"
REBUILD="${2:-}"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Directory not found: $PROJECT_DIR"
    exit 1
fi

UVPROJ=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.uvproj" | head -1)
if [ -z "$UVPROJ" ]; then
    echo "Error: No .uvproj file found in $PROJECT_DIR"
    exit 1
fi

PROJECT_NAME=$(basename "$UVPROJ" .uvproj)
echo "Project: $PROJECT_NAME"
echo "Source:  $PROJECT_DIR"

CONTAINER_NAME="keil-wine"
CONTAINER_WORK="/home/wineuser/work"
C51_BIN="/home/wineuser/.wine/drive_c/Keil_v5/C51/BIN"

# Ensure container exists
if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Error: Container '$CONTAINER_NAME' not found. Run launch-uvision.sh first."
    exit 1
fi

# Copy project to container
echo "Copying project to container..."
docker exec "$CONTAINER_NAME" mkdir -p "$CONTAINER_WORK"
docker cp "$PROJECT_DIR/." "$CONTAINER_NAME:$CONTAINER_WORK/$PROJECT_NAME/"

# Write the build script into the container
docker exec "$CONTAINER_NAME" sh -c "cat > $CONTAINER_WORK/build.sh << 'BUILDEOF'
#!/bin/sh
set -e

PROJECT_DIR=\"\$1\"
C51_BIN=\"\$2\"

cd \"\$PROJECT_DIR\"

echo \"=== Compiling STARTUP.A51 ===\"
wine \"\$C51_BIN/A51.EXE\" STARTUP.A51

echo \"=== Compiling C sources ===\"
for src in c/*.c; do
    name=\$(basename \"\$src\" .c)
    echo \"  Compiling \$src ...\"
    wine \"\$C51_BIN/C51.EXE\" \"\$src\" INCLUDE(H/) INCLUDE(H/SC95F761x_C.H) INCLUDE(H/Function_Init.H) INCLUDE(H/Multiplication_Division.H) OPTIMIZE(8) DEBUG OBJECTEXTEND CODE
done

echo \"=== Linking ===\"
OBJS=\"\"
for obj in *.OBJ c/*.OBJ; do
    if [ -f \"\$obj\" ]; then
        OBJS=\"\$OBJS \$obj\"
    fi
done

wine \"\$C51_BIN/BL51.EXE\" \$OBJS TO Demo MAP

echo \"=== Generating HEX ===\"
wine \"\$C51_BIN/OH51.EXE\" Demo

echo \"=== Build complete ===\"
BUILDEOF
chmod +x $CONTAINER_WORK/build.sh"

echo "Building..."
docker exec "$CONTAINER_NAME" sh "$CONTAINER_WORK/build.sh" \
    "$CONTAINER_WORK/$PROJECT_NAME" "$C51_BIN" \
    2>&1 | grep -v "^00c0:\|^003c:\|^0024:\|fixme:" || true

# Copy back output files
OUTPUT_DIR="$PROJECT_DIR/Objects"
LISTINGS_DIR="$PROJECT_DIR/Listings"
mkdir -p "$OUTPUT_DIR" "$LISTINGS_DIR"

echo ""
echo "Copying output files..."
docker cp "$CONTAINER_NAME:$CONTAINER_WORK/$PROJECT_NAME/Objects/." "$OUTPUT_DIR/" 2>/dev/null || true
docker cp "$CONTAINER_NAME:$CONTAINER_WORK/$PROJECT_NAME/Listings/." "$LISTINGS_DIR/" 2>/dev/null || true

# Also copy .hex, .OBJ, .map from project root (C51 outputs here)
for ext in hex HEX OBJ obj map MAP LST lst; do
    docker cp "$CONTAINER_NAME:$CONTAINER_WORK/$PROJECT_NAME/."$ext "$OUTPUT_DIR/" 2>/dev/null || true
done

# Show results
echo ""
echo "Build output:"
for f in "$OUTPUT_DIR"/*; do
    [ -f "$f" ] && echo "  $(basename "$f")"
done

# Clean up container copy
docker exec "$CONTAINER_NAME" rm -rf "$CONTAINER_WORK/$PROJECT_NAME" 2>/dev/null || true
docker exec "$CONTAINER_NAME" rm -f "$CONTAINER_WORK/build.sh" 2>/dev/null || true

echo "Done."
