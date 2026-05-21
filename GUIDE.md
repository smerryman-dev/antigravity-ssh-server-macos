# Technical Guide: Antigravity Remote SSH Server for macOS

## Problem Analysis

### Why darwin-arm is Not Available

Antigravity (based on VS Code) does not provide official macOS ARM64 server builds. The download attempts return 404:

```
Download failed from .../darwin-arm/Antigravity-reh.tar.gz
Error downloading server from all URLs
```

### Availability Matrix

| Platform | Status | URL Pattern |
|----------|--------|-------------|
| linux-arm | ✅ Available (HTTP 200) | `stable/{VERSION}-{COMMIT}/linux-arm/Antigravity-reh.tar.gz` |
| linux-x64 | ✅ Available (HTTP 200) | `stable/{VERSION}-{COMMIT}/linux-x64/Antigravity-reh.tar.gz` |
| darwin-arm | ❌ Not Available (HTTP 404) | `stable/{VERSION}-{COMMIT}/darwin-arm/Antigravity-reh.tar.gz` |
| darwin-arm64 | ❌ Not Available (HTTP 404) | `stable/{VERSION}-{COMMIT}/darwin-arm64/Antigravity-reh.tar.gz` |

## Solution Architecture

### Key Insight

The **linux-arm server tarball for the same version IS available**.

This is crucial - we don't need an old version skeleton. We can use the current version's linux-arm build.

### Why This Works

1. **Same Version Availability**: The linux-arm tarball exists for the same version
2. **Server vs Desktop**: The tarball contains the **server version** (`server-main.js`), not the desktop version (`cli.js`)
3. **JavaScript Portability**: `server-main.js` is platform-agnostic JavaScript
4. **Binary Replacement**: Only the Node.js binary needs to be platform-specific
5. **Native Modules**: Can be rebuilt using `npm rebuild`

## Recommended Solution: Native Host Bootstrap (bootstrap-macos.sh)

For hybrid client-host architectures (e.g., an Intel MacBook Pro client connecting to an Apple Silicon M1/M2 Mac Mini host), running the bootstrap script natively on the target host is the most robust and secure approach. This prevents copying incompatible Intel binaries to an ARM host.

The `bootstrap-macos.sh` script automates this process natively on the target macOS host:
1. **Downloads the official `linux-arm` tarball** (using the release version 2.0.1 URL) to the host.
2. **Extracts it** to the correct release directory: `~/.antigravity-ide-server/bin/2.0.1-bf9a033f33934fb4496d7eebed52486272437c3a`.
3. **Replaces the Node.js binary** with a native macOS Darwin arm64 build (`v22.11.0`).
4. **Surgically extracts native modules** (`spdlog.node`, `watcher.node`, `pty.node`) from the local `/Applications/Antigravity IDE.app` bundle on the host. These are already compiled natively for macOS Darwin arm64 and properly signed, eliminating compilation or Gatekeeper blockers.
5. **Updates product configurations and metadata** (`product.json` commit key and tunnel credentials).
6. **Signs all binaries and native modules** and clears quarantine flags using macOS `codesign` and `xattr`.
7. **Establishes backward-compatible symlinks** between the old folder `~/.antigravity-server` and the modern folder `~/.antigravity-ide-server`.

### How to Run Natively on the Host:
```bash
cd antigravity-ssh-server-macos
chmod +x bootstrap-macos.sh
./bootstrap-macos.sh
```

---

## Manual Installation Steps

### Prerequisites

```bash
# Install required tools
brew install wget
```

### Step 1: Extract COMMIT_ID

From the Antigravity client installation script:

```bash
DISTRO_IDE_VERSION="2.0.1"
DISTRO_COMMIT="bf9a033f33934fb4496d7eebed52486272437c3a"
COMMIT_ID="${DISTRO_IDE_VERSION}-${DISTRO_COMMIT}"
# Result: "2.0.1-bf9a033f33934fb4496d7eebed52486272437c3a"
```

### Step 2: Download linux-arm Server

```bash
wget -O /tmp/antigravity.tar.gz \
  "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${COMMIT_ID}/linux-arm/Antigravity-reh.tar.gz"
```

**Alternative mirrors** (if primary fails):
```bash
https://redirector.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${COMMIT_ID}/linux-arm/Antigravity-reh.tar.gz
https://edgedl.me.gvt1.com/edgedl/antigravity/stable/${COMMIT_ID}/linux-arm/Antigravity-reh.tar.gz
```

### Step 3: Extract Server

```bash
SERVER_DIR="$HOME/.antigravity-ide-server/bin/2.0.1-${DISTRO_COMMIT}"
mkdir -p "$SERVER_DIR"
tar -xzf /tmp/antigravity.tar.gz -C "$SERVER_DIR" --strip-components 1
```

### Step 4: Update Configuration

```bash
cd "$SERVER_DIR"

# Update product.json with correct commit hash
COMMIT_HASH="${COMMIT_ID##*-}"  # Extract hash
OLD_COMMIT=$(grep '"commit"' product.json | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
sed -i.bak "s/$OLD_COMMIT/$COMMIT_HASH/g" product.json
rm -f product.json.bak

# Create commit-id marker
echo "$COMMIT_HASH" > commit-id
```

### Step 5: Replace Node.js Binary

```bash
# Download darwin-arm64 Node.js
NODE_VERSION="v22.11.0"
curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-darwin-arm64.tar.gz" -o /tmp/node.tar.gz
tar -xzf /tmp/node.tar.gz -C /tmp

# Replace node binary
cp "/tmp/node-${NODE_VERSION}-darwin-arm64/bin/node" "$SERVER_DIR/node"
chmod +x "$SERVER_DIR/node"

# Sign the binary
codesign --force --deep --sign - "$SERVER_DIR/node"
```

### Step 6: Rebuild Native Modules

```bash
cd "$SERVER_DIR"

# Rebuild macOS-specific modules
npm rebuild @vscode/spdlog @parcel/watcher

# Sign rebuilt modules
find node_modules/@vscode/spdlog -name "*.node" -exec codesign --force --sign - {} \;
find node_modules/@parcel/watcher -name "*.node" -exec codesign --force --sign - {} \;
```

### Step 7: Clear Quarantine Flags

```bash
xattr -dr com.apple.quarantine "$SERVER_DIR"
```

### Step 8: Verify Installation

```bash
cd "$SERVER_DIR"

# Test server version
./node out/server-main.js --version
# Expected output:
# 1.107.0
# 4603c2a412f8c7cca552ff00db91c3ee787016ff
# arm64

# Verify server can start
TOKEN_FILE="/tmp/test-token.txt"
echo "test-token" > "$TOKEN_FILE"
./bin/antigravity-server --start-server --host 127.0.0.1 --port 0 \
  --connection-token-file "$TOKEN_FILE" --telemetry-level off \
  --accept-server-license-terms > /tmp/server.log 2>&1 &
SERVER_PID=$!

sleep 2
cat /tmp/server.log
# Should contain: "Server bound to 127.0.0.1:PORT" and "Extension host agent listening on PORT"

# Cleanup
kill $SERVER_PID 2>/dev/null
```

## Server Directory Structure

```
~/.antigravity-server/bin/{COMMIT_ID}/
├── bin/
│   └── antigravity-server          # Entry point script
├── out/
│   ├── server-main.js             # ← Main entry point (CRITICAL!)
│   ├── server-cli.js              # Server CLI
│   └── vs/                        # VS Code modules
├── node                            # Darwin-arm64 Node.js binary
├── node_modules/                   # Node modules
│   └── @vscode/spdlog/            # ← Rebuilt for macOS
├── extensions/                     # Server extensions (43 total)
├── product.json                    # Contains commit ID
└── commit-id                       # Commit marker file
```

## Critical Differences

### ❌ Wrong Approach

1. **Copy files from `/Applications/Antigravity.app`**
   - The app contains the desktop version
   - Uses `cli.js` which doesn't support `--start-server`

2. **Use `out/cli.js` as entry point**
   - Desktop version, not server version
   - Doesn't recognize `--start-server` option

3. **Copy app's `node_modules` and `out`**
   - Wrong version for server use
   - Missing server-specific files

### ✅ Correct Approach

1. **Use complete linux-arm tarball (same version)**
   - Contains the server version
   - All server-specific files included

2. **Use `out/server-main.js` as entry point**
   - Server version, supports `--start-server`
   - Platform-agnostic JavaScript

3. **Only replace Node.js binary**
   - Keep all other files from linux-arm
   - Rebuild only necessary native modules

## Server Startup Process

### Client's Installation Script

The Antigravity client sends this bash script to the server:

```bash
# Key variables from client script
DISTRO_IDE_VERSION="2.0.1"
DISTRO_COMMIT="bf9a033f33934fb4496d7eebed52486272437c3a"
DISTRO_ID="$DISTRO_COMMIT"
SERVER_DIR="$HOME/.antigravity-ide-server/bin/2.0.1-$DISTRO_ID"
SERVER_SCRIPT="$SERVER_DIR/bin/antigravity-ide-server"

# Server startup command
$SERVER_SCRIPT --start-server \
  --host=127.0.0.1 \
  --port=0 \
  --connection-token-file=$TOKEN_FILE \
  --telemetry-level=off \
  --enable-remote-auto-shutdown \
  --accept-server-license-terms
```

### Entry Point Script

`bin/antigravity-ide-server`:
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
exec "$SERVER_DIR/node" "$SERVER_DIR/out/server-main.js" "$@"
```

This runs:
```bash
$SERVER_DIR/node $SERVER_DIR/out/server-main.js --start-server ...
```

## Troubleshooting

### "posix_spawnp failed" Error

**Cause**: Binaries not signed for Gatekeeper

**Fix**:
```bash
cd ~/.antigravity-server/bin/{COMMIT_ID}
codesign --force --deep --sign - node
find node_modules/@vscode/spdlog -name "*.node" -exec codesign --force --sign - {} \;
find node_modules/@parcel/watcher -name "*.node" -exec codesign --force --sign - {} \;
xattr -dr com.apple.quarantine .
```

### spdlog Warnings (Harmless)

**Symptom**:
```
Error: dlopen(.../spdlog.node, 0x0001): slice is not valid mach-o file
```

**Explanation**:
- `spdlog.node` may remain in Linux ELF format
- This is a logging library, not critical
- Server will function normally

**Verification**:
```bash
# Check server log
cat ~/.antigravity-server/.$COMMIT_HASH.log
# Should contain: "Extension host agent listening on PORT"

# If present, server is working despite warnings
```

### "Server did not start successfully"

**Check server log**:
```bash
cat ~/.antigravity-server/.$COMMIT_HASH.log
```

**Common issues**:
1. **Wrong entry point** → Verify `out/server-main.js` exists
2. **Node binary issue** → Verify `file node` shows `Mach-O 64-bit executable arm64`
3. **Missing modules** → Run `npm rebuild @vscode/spdlog @parcel/watcher`

## Download URLs Reference

### URL Pattern

```
https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/{COMMIT_ID}/{PLATFORM}-{ARCH}/Antigravity-reh.tar.gz
```

### Components

- `{COMMIT_ID}`: `{VERSION}-{COMMIT_HASH}`
  - Example: `1.23.2-15487b3041e65228cae24980a3f796c905ef582c`
- `{PLATFORM}`: `linux`, `darwin`
- `{ARCH}`: `arm`, `arm64`, `x64`

### Available Combinations

| COMMIT_ID | PLATFORM | ARCH | Status |
|-----------|----------|------|--------|
| 2.0.1-* | linux | arm | ✅ 200 |
| 2.0.1-* | linux | arm64 | ✅ 200 |
| 2.0.1-* | linux | x64 | ✅ 200 |
| 2.0.1-* | darwin | arm | ❌ 404 |
| 2.0.1-* | darwin | arm64 | ❌ 404 |

## Version Compatibility

### Tested Versions

- **Antigravity**: 2.0.1
- **VS Code Engine**: 1.107.0
- **Commit**: bf9a033f33934fb4496d7eebed52486272437c3a
- **Node.js**: v22.11.0
- **macOS**: darwin-arm64 (M1/M2/M3)

### Upgrade Path

Each Antigravity version:

1. Extract new COMMIT_ID from client
2. Run installer with new COMMIT_ID
3. Previous version is backed up automatically
4. Can rollback if needed

## Advanced Topics

### Why Not Use VS Code Server?

Antigravity has custom modifications and branding:
- Product name: "antigravity-server"
- Custom extensions
- Different telemetry endpoints
- Modified UI/UX

### Why server-main.js Instead of cli.js?

- **cli.js**: Desktop app entry point
  - Requires Electron
  - Doesn't support `--start-server`
  - Designed for GUI use

- **server-main.js**: Server entry point
  - Pure Node.js
  - Supports `--start-server`
  - Designed for headless operation

### Native Module Rebuild

**Why rebuild**:
- Linux ELF binaries don't work on macOS
- Need Mach-O format for darwin

**What gets rebuilt**:
- `@vscode/spdlog`: Logging library
- `@parcel/watcher`: File watcher

**What doesn't need rebuilding**:
- Pure JavaScript modules
- Most npm packages

## Contributing

### Testing Changes

1. Create test environment: `mkdir -p /tmp/test-server`
2. Modify installer script
3. Test with: `./install.sh "TEST-COMMIT-ID"`
4. Verify server starts correctly

### Pull Requests

Welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - See LICENSE file

## Disclaimer

This is an unofficial workaround. The Antigravity darwin-arm server build may become officially available in the future.
