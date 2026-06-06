# Docker Wine Keil C51

A guide for installing and using the Keil C51 compiler on Linux using Docker and Wine.

## Overview

This project provides a way to run the Keil C51 compiler (for 8051 microcontrollers) on Linux without needing a Windows installation. It uses:

- **Docker**: To create an isolated container environment
- **Wine**: To run Windows applications on Linux

## Files

| File | Description |
|------|-------------|
| `docker-wine` | Modified driver script for managing the Docker+Wine container |
| `compile-c51.sh` | Wrapper script to compile 8051 C files |
| `launch-uvision.sh` | Script to launch Keil uVision IDE |
| `c51v960a.exe` | Keil C51 compiler installer (v9.60a) |
| `KeilMDK5Addon.exe` | Keil MDK5 Addon installer |

## Quick Start

### 1. Initial Setup

The first time you run any script, it will:
- Pull the Docker Wine image
- Create a persistent home volume at `~/.wine-docker`
- Initialize Wine

**No PulseAudio required** — sound is disabled by default.

### 2. Install Keil C51

```bash
./docker-wine --sound=none --notty --force-owner --volume="$(pwd):/workspace" sh -c "wine /workspace/c51v960a.exe /S"
```

This runs the installer in silent mode. The C51 compiler will be installed to `~/.wine-docker/.wine/drive_c/Keil_v5/`.

### 3. Install Keil MDK5 Addon

```bash
docker cp KeilMDK5Addon.exe keil-wine:/home/wineuser/KeilMDK5Addon.exe
docker exec keil-wine sh -c "wine /home/wineuser/KeilMDK5Addon.exe /S"
```

### 4. Launch Keil uVision IDE

```bash
./launch-uvision.sh
```

The script automatically:
- Creates a persistent container (if not exists)
- Enables X11 forwarding (`xhost +local:docker`)
- Launches Keil uVision

### 5. Compile a Program

```bash
./compile-c51.sh your_program.c
```

## Script Details

### `docker-wine`

Modified version of [scottyhardy/docker-wine](https://github.com/scottyhardy/docker-wine) with:
- Persistent home volume at `~/.wine-docker` by default
- PulseAudio skipped when `--sound=none`
- Container runs as your user for proper file permissions
- `--rm` flag only removes container, volume persists

**Common options:**

| Option | Description |
|--------|-------------|
| `--sound=none` | Disable sound (avoids PulseAudio issues) |
| `--notty` | Non-interactive mode (for scripts) |
| `--force-owner` | Take ownership of existing volume |
| `--name=NAME` | Set container name |
| `--volume=SRC:DST` | Mount a directory into the container |

### `compile-c51.sh`

Compiles 8051 C source files using the Keil C51 compiler.

**Usage:**

```bash
./compile-c51.sh <source.c> [options]
```

**Examples:**

```bash
# Basic compilation
./compile-c51.sh test.c

# With optimization
./compile-c51.sh test.c -O2

# With define
./compile-c51.sh test.c -DDEBUG
```

**Output files:**
- `.hex` - Intel HEX format for programming
- `.obj` - Object file
- `.lst` - Listing file with assembly output

### `launch-uvision.sh`

Launches the Keil uVision IDE for project-based development.

**Usage:**

```bash
./launch-uvision.sh
```

The script automatically handles X11 forwarding. You should see the Keil uVision window on your desktop.

## Container Management

### Persistent CID

The container CID remains the same across runs and reboots:

```bash
# Check current CID
docker inspect --format '{{.Id}}' keil-wine | cut -c1-12

# Check restart policy
docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' keil-wine
```

### Entering the Container

```bash
# Open a shell in the running container
docker exec -it keil-wine bash

# Run a specific command
docker exec keil-wine wine notepad
```

### Stopping/Starting

```bash
# Stop the container
docker stop keil-wine

# Start the container
docker start keil-wine

# Remove the container (volume persists)
docker rm -f keil-wine
```

## Persistent Storage

The Wine prefix (including Keil installation) is stored at:

```
~/.wine-docker/.wine/
```

This directory persists across container rebuilds and reboots. The volume serial number remains constant as long as this directory exists.

**To backup your installation:**

```bash
tar -czf keil-backup.tar.gz ~/.wine-docker
```

**To restore:**

```bash
tar -xzf keil-backup.tar.gz -C ~/
```

## Troubleshooting

### Display issues / Keil not visible

Make sure X11 forwarding is enabled:

```bash
xhost +local:docker
```

The `launch-uvision.sh` script does this automatically.

### Container name conflicts

If you see "container name is already in use":

```bash
docker rm -f keil-wine
```

### Permission issues

If you see "User's home is currently owned by UNKNOWN:UNKNOWN":

```bash
./docker-wine --sound=none --notty --force-owner bash
```

### Wine initialization

To reinitialize Wine:

```bash
./docker-wine --sound=none --notty --force-owner wineboot --init
```

## License

This project uses the Keil C51 evaluation version. For production use, purchase a license from ARM/Keil.
