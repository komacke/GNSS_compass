#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Ensure ~/.local/bin is in PATH if arduino-cli is installed there
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

BUILD_DIR="$REPO_ROOT/build"
SCRATCH_DIR="$BUILD_DIR/tmp/gps_compass"
OUTPUT_BIN="$REPO_ROOT/gps_compass.ino.esp32s3.bin"
PARTITIONS_BIN="$REPO_ROOT/gps_compass.ino.partitions.bin"
SERIAL_PORT="${SERIAL_PORT:-/dev/ttyACM0}"

echo "Building the binary..."
echo

# Prepare scratch folder for arduino-cli
rm -rf "$SCRATCH_DIR"
mkdir -p "$SCRATCH_DIR"
cp -r "$REPO_ROOT/gps_compass.ino" "$REPO_ROOT/partitions.csv" "$REPO_ROOT/src" "$SCRATCH_DIR/"

# Inject Git short hash into scratch config.h for local dev identification
GIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo 'dev')"
DIRTY=""
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    DIRTY="-dirty"
fi
sed -i "s/#define FW_VERSION .*/#define FW_VERSION           \"v0.3-dev+${GIT_HASH}${DIRTY}\"/" "$SCRATCH_DIR/src/config.h"

# Compile using modern --output-dir (replaces deprecated --export-binaries)
arduino-cli compile \
    --fqbn esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,CDCOnBoot=cdc \
    --output-dir "$BUILD_DIR" \
    "$SCRATCH_DIR"

if [ -f "$BUILD_DIR/gps_compass.ino.bin" ]; then
    cp "$BUILD_DIR/gps_compass.ino.bin" "$OUTPUT_BIN"
fi
if [ -f "$BUILD_DIR/gps_compass.ino.partitions.bin" ]; then
    cp "$BUILD_DIR/gps_compass.ino.partitions.bin" "$PARTITIONS_BIN"
fi

# Clean ONLY intermediate compiler artifacts; preserve build/ and this script!
rm -rf "$BUILD_DIR/tmp" \
       "$BUILD_DIR/gps_compass.ino.bin" \
       "$BUILD_DIR/gps_compass.ino.partitions.bin" \
       "$BUILD_DIR/gps_compass.ino.bootloader.bin" \
       "$BUILD_DIR/gps_compass.ino.elf" \
       "$BUILD_DIR/gps_compass.ino.map"

if [ -f "$OUTPUT_BIN" ]; then
    echo
    echo "Firmware binary:   $(basename "$OUTPUT_BIN")"
    if [ -f "$PARTITIONS_BIN" ]; then
        echo "Partition table:   $(basename "$PARTITIONS_BIN")"
    fi
else
    echo "Something went wrong. There's no binary here."
    exit 1
fi

echo
read -p "Do you want to install the binary to port $SERIAL_PORT? [Y/n] " resp
resp="${resp,,}"
resp="${resp:-y}"

if [[ "$resp" == "y" ]]; then
    if [ -f "$PARTITIONS_BIN" ]; then
        esptool --chip esp32s3 --port "$SERIAL_PORT" --baud 921600 write-flash 0x8000 "$PARTITIONS_BIN" 0x100000 "$OUTPUT_BIN"
    else
        esptool --chip esp32s3 --port "$SERIAL_PORT" --baud 921600 write-flash 0x100000 "$OUTPUT_BIN"
    fi
else
    echo "Skipping install."
fi

