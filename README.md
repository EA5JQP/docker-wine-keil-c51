# Docker Wine Keil C51

Run the Keil C51 compiler (8051) on Linux using Docker + Wine 8.4.

## Prerequisites

- Docker
- X11 display server
- `c51v960a.exe` installer (Keil C51 v9.60)
- `KeilMDK5Addon.exe` (optional)

## Quick Start

### 1. Install Keil C51

```bash
./install-keil.sh
```

This creates a Docker container with Wine 8.4 and copies the installers. Then run the GUI installer visually:

```bash
docker exec -it -e DISPLAY=:0 --user wineuser keil-wine wine /home/wineuser/c51v960a.exe
```

### 2. Copy projects into the container

```bash
docker cp YourProject/ keil-wine:/home/wineuser/YourProject/
docker exec --user root keil-wine chown -R wineuser:wineuser /home/wineuser/YourProject/
```

### 3. Build a project

```bash
./build.sh YourProject/
```

For a clean rebuild:

```bash
./build.sh YourProject/ --rebuild
```

Output files (`.hex`, `.obj`, `.lst`, `.map`) appear in `YourProject/Objects/`.

### 4. Launch Keil uVision IDE

```bash
./launch-uvision.sh
```

## Files

| File | Description |
|------|-------------|
| `install-keil.sh` | Sets up container and copies installers |
| `build.sh` | Build an 8051 project via UV4 batch mode |
| `launch-uvision.sh` | Launches Keil uVision IDE with X11 |
| `c51v960a.exe` | Keil C51 compiler installer (v9.60) |
| `KeilMDK5Addon.exe` | Keil MDK5 Addon installer |

## Container Management

```bash
# Check container status
docker ps | grep keil-wine

# Open a shell
docker exec -it -e DISPLAY=:0 --user wineuser keil-wine bash

# Stop/start
docker stop keil-wine
docker start keil-wine

# Full rebuild (destroys Wine prefix)
./install-keil.sh
```

## Persistent Storage

The Wine prefix (including Keil installation) is stored at `~/.wine-docker/`.

**Backup:**
```bash
tar -czf keil-backup.tar.gz ~/.wine-docker
```

**Restore:**
```bash
tar -xzf keil-backup.tar.gz -C ~/
```

## Troubleshooting

### `nodrv_CreateWindow` — Wine can't create windows

X11 socket permission issue. Fix before each session:

```bash
chmod 777 /tmp/.X11-unix/X*
```

Or use `launch-uvision.sh` which does this automatically.

### `cannot create command input file` — Build fails with permission error

Files copied with `docker cp` are owned by root. Fix:

```bash
docker exec --user root keil-wine chown -R wineuser:wineuser /home/wineuser/YourProject/
```

### `C51 FATAL-ERROR: UNKNOWN CONTROL`

The C51 command line is being parsed incorrectly. Use `UV4.exe -b` (batch mode) instead of invoking C51 directly — UV4 handles the toolchain invocation internally.

## Notes

- **Wine 8.4** is required (Wine 11 has `CreateProcess` path resolution bugs that break UV4 subprocess spawning)
- **License required** — C51 runs in evaluation mode without a valid license, which limits the generated binary size (2 KB for the code segment). Register a valid Keil C51 license to remove this limitation for production use.
- X11 socket must be chmod 777 before running Wine GUI apps as the container user
