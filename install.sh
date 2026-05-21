#!/bin/bash
#
# Antigravity SSH Server Installation Script (Client-Side Only)
# This script runs entirely on the CLIENT machine and installs the server on a remote macOS host
#
# Usage: ./install.sh [user@hostname]
# Example: ./install.sh michael@mini
#
# Requirements:
# - Client: Antigravity installed
# - Server: Node.js, npm (usually pre-installed on macOS)
# - Both: SSH access configured
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMMIT_ID="2.0.1-bf9a033f33934fb4496d7eebed52486272437c3a"
VSCODE_VERSION="1.107.0"
SERVER_COMMIT_ID="${COMMIT_ID}"
NODE_VERSION="v22.11.0"

# Parse arguments
REMOTE_HOST="$1"
if [ -z "$REMOTE_HOST" ]; then
    echo -e "${RED}Error: Remote host required${NC}"
    echo "Usage: $0 [user@hostname]"
    echo "Example: $0 michael@mini"
    echo ""
    echo "This script installs Antigravity SSH server on a remote macOS machine."
    echo "The server machine does NOT need Antigravity.app installed - only Node.js/npm."
    exit 1
fi

echo -e "${BLUE}=== Antigravity SSH Server Installation ===${NC}"
echo "Remote host: ${GREEN}$REMOTE_HOST${NC}"
echo "Version: ${GREEN}${COMMIT_ID}${NC}"
echo ""

# Temporary directory on client
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# ============================================================================
# Step 1: Check server prerequisites
# ============================================================================
echo -e "${YELLOW}Step 1: Checking server prerequisites...${NC}"

echo "  Checking for Node.js on server... (Skipped, using provided binary)"
# if ! ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "zsh -lic 'command -v node'" > /dev/null 2>&1; then
#     echo -e "${RED}  Error: Node.js not found on server${NC}"
#     echo "  Install on server: brew install node"
#     exit 1
# fi
echo -e "${GREEN}  ✓ Node.js check skipped${NC}"

echo "  Checking for npm on server... (Skipped, using provided modules)"
# if ! ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "zsh -lic 'command -v npm'" > /dev/null 2>&1; then
#     echo -e "${RED}  Error: npm not found on server${NC}"
#     exit 1
# fi
echo -e "${GREEN}  ✓ npm check skipped${NC}"

echo ""

# ============================================================================
# Step 2: Download server files to client
# ============================================================================
echo -e "${YELLOW}Step 2: Downloading server files to client...${NC}"

# Download linux-arm server tarball
echo "  Downloading linux-arm server tarball..."
wget --tries=3 --timeout=30 --continue --quiet --no-check-certificate \
  -O "$TEMP_DIR/antigravity-linux.tar.gz" \
  "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${COMMIT_ID}/linux-arm/Antigravity-reh.tar.gz"

if [ ! -f "$TEMP_DIR/antigravity-linux.tar.gz" ]; then
    echo -e "${RED}  Error: Failed to download server tarball${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Downloaded server tarball$(du -h "$TEMP_DIR/antigravity-linux.tar.gz" | cut -f1)${NC}"

# Download Node.js binary for darwin-arm64
echo "  Downloading Node.js ${NODE_VERSION} for darwin-arm64..."
curl -fsSLk "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-darwin-arm64.tar.gz" -o "$TEMP_DIR/node.tar.gz"

if [ ! -f "$TEMP_DIR/node.tar.gz" ]; then
    echo -e "${RED}  Error: Failed to download Node.js${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Downloaded Node.js$(du -h "$TEMP_DIR/node.tar.gz" | cut -f1)${NC}"

echo ""

# ============================================================================
# Step 3: Prepare server package on client
# ============================================================================
echo -e "${YELLOW}Step 3: Preparing server package on client...${NC}"

# Extract linux-arm server
echo "  Extracting linux-arm server..."
mkdir -p "$TEMP_DIR/server"
tar -xzf "$TEMP_DIR/antigravity-linux.tar.gz" -C "$TEMP_DIR/server" --strip-components 1
echo -e "${GREEN}  ✓ Extracted$(du -sh "$TEMP_DIR/server" | cut -f1)${NC}"

# Extract and replace Node.js binary
echo "  Replacing Node.js binary with darwin-arm64 version..."
mkdir -p "$TEMP_DIR/node-temp"
tar -xzf "$TEMP_DIR/node.tar.gz" -C "$TEMP_DIR/node-temp"
cp "$TEMP_DIR/node-temp/node-${NODE_VERSION}-darwin-arm64/bin/node" "$TEMP_DIR/server/node"
chmod +x "$TEMP_DIR/server/node"
echo -e "${GREEN}  ✓ Node.js binary replaced${NC}"

# SURGICAL REPLACEMENT: Native Modules from local app
echo "  Surgically replacing native modules from local Antigravity app..."
LOCAL_APP_RESOURCES="/Applications/Antigravity IDE.app/Contents/Resources/app"
SERVER_NODE_MODULES="$TEMP_DIR/server/node_modules"

if [ -d "$LOCAL_APP_RESOURCES" ]; then
    # spdlog
    cp "$LOCAL_APP_RESOURCES/node_modules/@vscode/spdlog/build/Release/spdlog.node" "$SERVER_NODE_MODULES/@vscode/spdlog/build/Release/spdlog.node"
    # watcher
    cp "$LOCAL_APP_RESOURCES/node_modules/@parcel/watcher/build/Release/watcher.node" "$SERVER_NODE_MODULES/@parcel/watcher/build/Release/watcher.node"
    # pty
    cp "$LOCAL_APP_RESOURCES/node_modules/node-pty/build/Release/pty.node" "$SERVER_NODE_MODULES/node-pty/build/Release/pty.node" 2>/dev/null || \
    cp "$LOCAL_APP_RESOURCES/node_modules/node-pty/prebuilds/darwin-arm64/pty.node" "$SERVER_NODE_MODULES/node-pty/build/Release/pty.node"
    
    cp "$LOCAL_APP_RESOURCES/node_modules/node-pty/build/Release/spawn-helper" "$SERVER_NODE_MODULES/node-pty/build/Release/spawn-helper" 2>/dev/null || true

    echo -e "${GREEN}  ✓ Native modules replaced from local app${NC}"
    
    # Language Server
    echo "  Extracting Language Server from local app..."
    LOCAL_EXT_BIN="$LOCAL_APP_RESOURCES/extensions/antigravity/bin"
    SERVER_EXT_BIN="$TEMP_DIR/server/extensions/antigravity/bin"
    
    mkdir -p "$SERVER_EXT_BIN"
    if [ -f "$LOCAL_EXT_BIN/language_server_macos_arm" ]; then
        cp "$LOCAL_EXT_BIN/language_server_macos_arm" "$SERVER_EXT_BIN/language_server_macos_arm"
        ln -sf "language_server_macos_arm" "$SERVER_EXT_BIN/language_server_macos_x64"
        ln -sf "language_server_macos_arm" "$SERVER_EXT_BIN/language_server_linux_arm"
        echo -e "${GREEN}  ✓ Language server replaced and aliased (arm64)${NC}"
    elif [ -f "$LOCAL_EXT_BIN/language_server_macos_x64" ]; then
        cp "$LOCAL_EXT_BIN/language_server_macos_x64" "$SERVER_EXT_BIN/language_server_macos_x64"
        ln -sf "language_server_macos_x64" "$SERVER_EXT_BIN/language_server_macos_arm"
        ln -sf "language_server_macos_x64" "$SERVER_EXT_BIN/language_server_linux_arm"
        echo -e "${GREEN}  ✓ Language server replaced and aliased (x64)${NC}"
    else
        echo -e "${RED}  ⚠ Language server not found in local app!${NC}"
    fi
else
    echo -e "${RED}  Error: Local Antigravity IDE.app not found. Cannot perform surgical extraction.${NC}"
    exit 1
fi

# Update product.json with correct commit ID and tunnel config
echo "  Updating product.json..."
COMMIT_HASH="${COMMIT_ID#*-}"
echo "$COMMIT_HASH" > "$TEMP_DIR/server/commit-id"

if [ -f "$TEMP_DIR/server/product.json" ]; then
    if command -v python3 &> /dev/null; then
        python3 << EOF
import json
try:
    with open('$TEMP_DIR/server/product.json', 'r') as f:
        data = json.load(f)
    data['commit'] = '${COMMIT_HASH}'
    # Add missing tunnel configs to satisfy 1.20+ requirements
    data['tunnelApplicationName'] = 'antigravity-tunnel'
    data['tunnelApplicationConfig'] = {
        'authenticationProviders': {
            'github': {
                'scopes': ['user:email', 'read:org']
            }
        }
    }
    with open('$TEMP_DIR/server/product.json', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f"  ⚠ product.json update error: {e}")
EOF
    else
        sed -i.bak "s/\"commit\": \".*\"/\"commit\": \"${COMMIT_HASH}\"/" "$TEMP_DIR/server/product.json" 2>/dev/null || true
        rm -f "$TEMP_DIR/server/product.json.bak" 2>/dev/null || true
    fi
    echo -e "${GREEN}  ✓ product.json updated${NC}"
else
    echo -e "${YELLOW}  ⚠ product.json not found, skipping update${NC}"
fi

echo ""

# ============================================================================
# Step 4: Create remote installation script
# ============================================================================
echo -e "${YELLOW}Step 4: Creating installation script for remote...${NC}"

cat > "$TEMP_DIR/remote-install.sh" << 'REMOTESCRIPT'
#!/bin/bash
set -e

COMMIT_ID="SERVER_COMMIT_ID_PLACEHOLDER"
COMMIT_HASH="SERVER_COMMIT_HASH_PLACEHOLDER"
SERVER_DATA_DIR_NEW="$HOME/.antigravity-ide-server"
SERVER_DATA_DIR_OLD="$HOME/.antigravity-server"
SERVER_DIR="$SERVER_DATA_DIR_NEW/bin/${COMMIT_ID}"
TEMP_DIR="/tmp/antigravity-server-install"

echo "  Installing to $SERVER_DIR"

# Backup existing installation
if [ -d "$SERVER_DIR" ]; then
    mv "$SERVER_DIR" "${SERVER_DIR}.backup.$(date +%Y%m%d%H%M%S)"
fi

# Create directory
mkdir -p "$SERVER_DIR"

# Extract server package
tar -xzf "$TEMP_DIR/server-package.tar.gz" -C "$SERVER_DIR"

# Rebuild native modules
echo "  Rebuilding native modules..."
cd "$SERVER_DIR"
npm rebuild @vscode/spdlog @parcel/watcher node-pty > /dev/null 2>&1 || true

# Sign binaries
echo "  Signing binaries..."
codesign --force --deep --sign - "$SERVER_DIR/node" 2>/dev/null || true
find "$SERVER_DIR/node_modules" -name "*.node" -exec codesign --force --sign - {} \; 2>/dev/null || true
find "$SERVER_DIR/node_modules" -name "spawn-helper" -exec codesign --force --sign - {} \; 2>/dev/null || true

# Clear quarantine
xattr -dr com.apple.quarantine "$SERVER_DIR" 2>/dev/null || true

# Create symlinks for compatibility
if [ ! -L "$SERVER_DATA_DIR_OLD" ] && [ ! -d "$SERVER_DATA_DIR_OLD" ]; then
    ln -nsf "$SERVER_DATA_DIR_NEW" "$SERVER_DATA_DIR_OLD"
fi
mkdir -p "$SERVER_DATA_DIR_NEW/bin"

# DO NOT create 1.107.0-* engine or 'latest' symlinks in bin/.
# This avoids triggering the client's destructive clean_up_old_servers loop,
# which uses a BSD-incompatible find command on macOS and deletes active server tokens.
# The 2.0.1 client only looks for and matches the physical "${COMMIT_ID}" directory.

echo "  ✓ Server installed successfully"

# Verify
VERSION_OUTPUT=$("$SERVER_DIR/node" "$SERVER_DIR/out/server-main.js" --version 2>&1 | head -3)
echo "  Server version: $VERSION_OUTPUT"
REMOTESCRIPT

# Replace placeholders
sed -i.bak "s/SERVER_COMMIT_ID_PLACEHOLDER/${SERVER_COMMIT_ID}/" "$TEMP_DIR/remote-install.sh"
sed -i.bak "s/SERVER_COMMIT_HASH_PLACEHOLDER/${COMMIT_HASH}/" "$TEMP_DIR/remote-install.sh"
rm -f "$TEMP_DIR/remote-install.sh.bak"
chmod +x "$TEMP_DIR/remote-install.sh"

echo -e "${GREEN}  ✓ Installation script created${NC}"

echo ""

# ============================================================================
# Step 5: Upload and install on remote server
# ============================================================================
echo -e "${YELLOW}Step 5: Uploading and installing on remote server...${NC}"

# Create tarball of server package
echo "  Packaging server files..."
tar -czf "$TEMP_DIR/server-package.tar.gz" -C "$TEMP_DIR/server" .
PACKAGE_SIZE=$(du -h "$TEMP_DIR/server-package.tar.gz" | cut -f1)
echo -e "${GREEN}  ✓ Package created: ${PACKAGE_SIZE}${NC}"

# Upload files to remote server
echo "  Uploading files to $REMOTE_HOST..."
ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "mkdir -p /tmp/antigravity-server-install"
scp -o StrictHostKeyChecking=no -q "$TEMP_DIR/server-package.tar.gz" "$REMOTE_HOST:/tmp/antigravity-server-install/server-package.tar.gz"
scp -o StrictHostKeyChecking=no -q "$TEMP_DIR/remote-install.sh" "$REMOTE_HOST:/tmp/antigravity-server-install/remote-install.sh"
echo -e "${GREEN}  ✓ Upload complete${NC}"

# Execute installation on remote
echo "  Running installation on $REMOTE_HOST..."
ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "zsh -lic 'bash /tmp/antigravity-server-install/remote-install.sh'"
echo -e "${GREEN}  ✓ Server installed${NC}"

echo ""

# ============================================================================
# Step 6: Restart server on remote
# ============================================================================
echo -e "${YELLOW}Step 6: Restarting server on remote...${NC}"

# Kill existing server processes
ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "pkill -f antigravity-server || true"

sleep 2

echo -e "${GREEN}  ✓ Server restarted${NC}"

# Cleanup remote temp files
ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "rm -f /tmp/antigravity-*.sh /tmp/antigravity-*.tar.gz 2>/dev/null; rm -rf /tmp/antigravity-server-install 2>/dev/null" 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "Server installed on: ${GREEN}$REMOTE_HOST${NC}"
echo "Version: ${GREEN}${COMMIT_ID}${NC}"
echo "Location: ~/.antigravity-ide-server/bin/${SERVER_COMMIT_ID}"
echo ""
echo "Next steps:"
echo "  1. Open Antigravity on this client machine"
echo "  2. Connect to $REMOTE_HOST via Remote SSH"
echo "  3. Start coding!"
echo ""
echo -e "${YELLOW}Note: If you see 'Authentication Required' in the agent panel, please use the recommended OrbStack Linux VM approach.${NC}"
echo ""
