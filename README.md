# Quake 3 Arena Dedicated Server

[![Docker](https://img.shields.io/badge/docker-ioquake3--server-blue?logo=docker&logoColor=white)](Dockerfile)
[![Build](https://github.com/matuscvengros/quake3-arena-server/actions/workflows/build.yml/badge.svg)](https://github.com/matuscvengros/quake3-arena-server/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/github/license/matuscvengros/quake3-arena-server)](LICENSE)

A hardened, Docker-based Quake 3 Arena dedicated server built from source using the [ioquake3](https://github.com/ioquake/ioq3) engine.

## Architecture

```
Internet
  │
  │ UDP 27960
  ▼
┌──────────────────────── Firewall (DMZ) ────────────────────────┐
│                                                                │
│  ┌──────────────────── Dedicated VM ────────────────────────┐  │
│  │                                                          │  │
│  │  ┌──────────────── Docker Container ──────────────────┐  │  │
│  │  │                                                    │  │  │
│  │  │  ioq3ded (non-root, no capabilities)               │  │  │
│  │  │                                                    │  │  │
│  │  │  Filesystem: read-only                             │  │  │
│  │  │  Game data:  read-only bind mount                  │  │  │
│  │  │  Runtime:    tmpfs (RAM, ephemeral)                │  │  │
│  │  │  Resources:  1 CPU / 256MB max                     │  │  │
│  │  │                                                    │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

The recommended deployment is a dedicated VM (not LXC) for kernel-level
isolation, since this service is exposed to the internet. LXC containers share
the host kernel — a VM provides a stronger security boundary.

**Recommended VM specs:** Debian 12 minimal, 1 vCPU, 512MB RAM, 8GB disk.

## Prerequisites

- Docker and Docker Compose
- A legal copy of Quake 3 Arena (Steam, GOG, or original CD)

## Project Structure

```
.
├── Dockerfile           # Multi-stage build — compiles ioquake3 from source
├── docker-compose.yml   # Production config with security hardening
├── entrypoint.sh        # Startup script with validation
├── server.cfg           # Game server configuration
├── .env                 # Secrets (RCON password) — never commit this
├── .dockerignore        # Keeps secrets and game data out of build context
├── .gitignore           # Keeps secrets and game data out of git
└── baseq3/              # YOU CREATE THIS — mount point for game data
    ├── pak0.pk3          # Required — core game data (~480MB)
    ├── pak1.pk3          # Recommended — patch data
    ├── ...
    ├── pak8.pk3
    └── server.cfg        # Copied here from project root
```

## Quick Start

### 1. Prepare game data

Create a `baseq3/` directory and copy your Quake 3 Arena game files into it:

```bash
mkdir -p baseq3
cp /path/to/Quake\ 3\ Arena/baseq3/pak*.pk3 baseq3/
cp server.cfg baseq3/
```

Common source locations:
- **Steam:** `~/.steam/steam/steamapps/common/Quake 3 Arena/baseq3/`
- **GOG:** check your GOG install directory under `baseq3/`

At minimum, `pak0.pk3` must be present. Include `pak1.pk3` through `pak8.pk3`
for the full patched experience.

### 2. Set your RCON password

Edit `.env`:

```
Q3_RCON=your-secure-password-here
```

This is the remote administration password. If you don't need remote admin,
leave it empty to disable RCON entirely.

### 3. Build and start

```bash
docker compose up -d --build
```

This compiles ioquake3 from source (first build takes a few minutes) and
starts the server. Subsequent starts are instant unless you rebuild.

### 4. Verify

```bash
# Check container is running and healthy
docker compose ps

# Watch server logs
docker compose logs -f

# Expected output:
#   Starting Quake 3 Arena dedicated server...
#     Port:   27960
#     Map:    q3dm17
#     Config: server.cfg
#     RCON:   enabled
```

### 5. Connect

From Quake 3 Arena client, open the console (~) and type:

```
\connect YOUR_SERVER_IP
```

Or find the server in the server browser if `dedicated` is set to `2`.

## Configuration

### Environment Variables

Set these in `docker-compose.yml` under `environment:` or in `.env`:

| Variable    | Default      | Description                          |
|-------------|--------------|--------------------------------------|
| `Q3_PORT`   | `27960`      | UDP port for the game server         |
| `Q3_MAP`    | `q3dm17`     | Starting map                         |
| `Q3_CONFIG` | `server.cfg` | Server config file to load           |
| `Q3_RCON`   | *(empty)*    | RCON password (empty = RCON disabled)|

### Server Configuration

Edit `baseq3/server.cfg` to change gameplay settings. Key options:

```
// Game modes: 0=FFA, 1=Tournament, 3=TDM, 4=CTF
set g_gametype       0

// Player limits
set sv_maxclients    16

// Match rules
set fraglimit        30
set timelimit        15

// Bots (set bot_enable 1 to activate)
set bot_enable       0
set bot_minplayers   4      // Auto-fill to this many players
set g_spSkill        3      // 1=easy, 5=nightmare
```

After editing, restart the server:

```bash
docker compose restart
```

### Map Rotation

The map rotation is defined in `server.cfg` using chained variables:

```
set d1 "map q3dm17; set nextmap vstr d2"
set d2 "map q3dm6;  set nextmap vstr d3"
...
set d7 "map q3dm1;  set nextmap vstr d1"
vstr d1
```

Each `dN` variable loads a map and sets the next one. The last entry loops
back to `d1`. Add or remove entries as desired.

## How the Build Works

The Dockerfile uses a multi-stage build:

**Stage 1 (builder):** Starts from Alpine Linux, installs build tools (gcc,
cmake, etc.), clones the ioquake3 source at a pinned commit, and compiles
the dedicated server binary (`ioq3ded`). This stage is ~250MB.

**Stage 2 (runtime):** Starts from a fresh Alpine image, installs only the
minimal runtime libraries (`libstdc++`, `libgcc`), and copies the compiled
binary from stage 1. The build tools are discarded. Final image is ~15MB.

The source is pinned to a specific commit (`5956299`) rather than tracking
the `main` branch. This prevents supply chain attacks — a compromised
upstream repository cannot silently inject malicious code into builds.

## Security Hardening

This setup applies defense-in-depth for an internet-facing service:

| Layer                  | What it does                                           |
|------------------------|--------------------------------------------------------|
| **Non-root user**      | Server runs as `quake3`, not root                      |
| **cap_drop: ALL**      | All Linux capabilities removed                         |
| **no-new-privileges**  | Cannot gain privileges via setuid binaries              |
| **read_only**          | Container filesystem is immutable                      |
| **Bind mount :ro**     | Game data cannot be modified by the server              |
| **tmpfs for runtime**  | Writes go to RAM-backed tmpfs, capped and ephemeral     |
| **Resource limits**    | CPU and memory capped to prevent DoS/resource starvation|
| **Input validation**   | Environment variables validated before use              |
| **Pinned source**      | ioquake3 built from a specific audited commit           |
| **Multi-stage build**  | No compilers or build tools in the runtime image        |
| **Secrets via .env**   | RCON password never in the image or server.cfg          |

### Writable surfaces

The only writable areas in the container are:

| Path                 | Type  | Size | Purpose           |
|----------------------|-------|------|-------------------|
| `/tmp`               | tmpfs | 10MB | Temp files         |
| `/opt/quake3/.q3a`   | tmpfs | 50MB | Logs, runtime data |

Both are in RAM and disappear when the container stops.

## Operations

### Common Commands

```bash
# Start the server
docker compose up -d --build

# Stop the server
docker compose down

# View logs
docker compose logs -f

# Restart after config change
docker compose restart

# Rebuild after Dockerfile or source changes
docker compose up -d --build

# Shell into the container for debugging
docker compose run --rm quake3 sh

# Check container health
docker compose ps
```

### RCON (Remote Console)

If `Q3_RCON` is set, you can administer the server from a Quake 3 client:

```
\rcon YOUR_PASSWORD status        # Show connected players
\rcon YOUR_PASSWORD map q3dm6     # Change map
\rcon YOUR_PASSWORD kick player   # Kick a player
\rcon YOUR_PASSWORD quit          # Shut down server
```

### Updating ioquake3

To update the engine to a newer commit:

1. Check the [ioquake3 repository](https://github.com/ioquake/ioq3) for recent commits
2. Update the `IOQUAKE3_COMMIT` value in the `Dockerfile`
3. Rebuild: `docker compose up -d --build`

### Monitoring

Server logs are written to stdout (visible via `docker compose logs`) and
to `server.log` in the tmpfs runtime directory. The healthcheck runs every
30 seconds and will mark the container unhealthy if `ioq3ded` stops.

## Network Setup

### Firewall / Firewall

Create a port forwarding rule on your Firewall:

- **Protocol:** UDP
- **External port:** 27960
- **Internal IP:** your VM's IP address
- **Internal port:** 27960

If placing the VM in a DMZ zone, ensure no other services on the VM are
exposed. The VM should be single-purpose.

### LAN Play

For LAN-only use (no internet exposure), change `dedicated` mode in
`entrypoint.sh`:

```
+set dedicated 1    # LAN only — does not register with master servers
```

`dedicated 2` (the default) advertises to public master server lists, making
the server discoverable in the in-game browser.

## Troubleshooting

**"pak0.pk3 not found"** — The `baseq3/` directory is missing or doesn't
contain the game data. Copy your pak files and try again.

**Container starts but no one can connect** — Check that UDP 27960 is
forwarded through your firewall. Use `docker compose logs` to confirm the
server started successfully.

**Container is "unhealthy"** — The `ioq3ded` process crashed or hung.
Check `docker compose logs` for errors. Common cause: insufficient memory
(increase the `memory` limit in docker-compose.yml).

**Build fails at cmake step** — The pinned commit may have build issues on
your architecture. Check the ioquake3 issue tracker or try a newer commit.
