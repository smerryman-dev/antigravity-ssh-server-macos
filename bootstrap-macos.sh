#!/bin/bash
#
# Antigravity macOS Remote Server Bootstrap Script
# Runs natively on the macOS target host (e.g. Mac Mini) to prepare the environment.
#
# Usage: ./bootstrap-macos.sh [COMMIT_ID]
# Example: ./bootstrap-macos.sh 1.107.0-bf9a033f33934fb4496d7eebed52486272437c3a
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Antigravity macOS Server NATIVE Bootstrap ===${NC}"

# 1. Identify active version and commit hash
VSCODE_VERSION="1.107.0"
COMMIT_HASH="15487b3041e65228cae24980a3f796c905ef582c"
IDE_VERSION="1.23.2"

# Parse arguments
ARG_IDE_VERSION="$1"
ARG_COMMIT_HASH="$2"
ARG_VSCODE_VERSION="$3"

LOCAL_APP_RESOURCES="/Applications/Antigravity IDE.app/Contents/Resources/app"

# If no arguments are passed, dynamically detect from local app metadata
if [ -z "$ARG_COMMIT_HASH" ] && [ -f "$LOCAL_APP_RESOURCES/product.json" ]; then
    echo -e "${GREEN}Found local Antigravity IDE.app. Extracting metadata...${NC}"
    VSCODE_VERSION=$(node -p "require('$LOCAL_APP_RESOURCES/package.json').version")
    COMMIT_HASH=$(node -p "require('$LOCAL_APP_RESOURCES/product.json').commit")
    if [ "$VSCODE_VERSION" = "1.107.0" ]; then
        if [ "$COMMIT_HASH" = "bd0307c171dbaf4cd6135192515e160af7d9d132" ]; then
            IDE_VERSION="2.0.2"
        else
            IDE_VERSION="2.0.1"
        fi
    fi
else
    if [ -n "$ARG_IDE_VERSION" ]; then
        IDE_VERSION="$ARG_IDE_VERSION"
    fi
    if [ -n "$ARG_COMMIT_HASH" ]; then
        COMMIT_HASH="$ARG_COMMIT_HASH"
    fi
    if [ -n "$ARG_VSCODE_VERSION" ]; then
        VSCODE_VERSION="$ARG_VSCODE_VERSION"
    fi
fi

COMMIT_ID="${IDE_VERSION}-${COMMIT_HASH}"
NODE_VERSION="v22.11.0"

echo "  VS Code version: ${GREEN}${VSCODE_VERSION}${NC}"
echo "  Commit Hash:     ${GREEN}${COMMIT_HASH}${NC}"
echo "  Target ID:       ${GREEN}${COMMIT_ID}${NC}"
echo "  Node Version:    ${GREEN}${NODE_VERSION}${NC}"
echo ""

# Setup directories
SERVER_DATA_DIR_NEW="$HOME/.antigravity-ide-server"
SERVER_DATA_DIR_OLD="$HOME/.antigravity-server"
SERVER_DIR="$SERVER_DATA_DIR_NEW/bin/${COMMIT_ID}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo -e "${YELLOW}Step 1: Preparing directories...${NC}"
mkdir -p "$SERVER_DATA_DIR_NEW/bin"

# Back up existing server build if present
if [ -d "$SERVER_DIR" ]; then
    echo "  Backing up existing server folder..."
    mv "$SERVER_DIR" "${SERVER_DIR}.backup.$(date +%Y%m%d%H%M%S)"
fi
mkdir -p "$SERVER_DIR"
echo -e "${GREEN}  ✓ Directories prepared${NC}"

# ============================================================================
# Step 2: Download server files
# ============================================================================
echo -e "${YELLOW}Step 2: Downloading server files...${NC}"

# Download linux-arm server tarball (CDN uses branded version 2.0.1 for URLs)
CDN_VERSION="${IDE_VERSION}-${COMMIT_HASH}"
echo "  Downloading linux-arm server tarball for version ${CDN_VERSION}..."
curl --connect-timeout 30 --retry 3 --location --fail \
  -o "$TEMP_DIR/antigravity-linux.tar.gz" \
  "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${CDN_VERSION}/linux-arm/Antigravity%20IDE-reh.tar.gz"

echo -e "${GREEN}  ✓ Downloaded server tarball ($(du -h "$TEMP_DIR/antigravity-linux.tar.gz" | cut -f1))${NC}"

# Download Node.js binary for darwin-arm64
echo "  Downloading Node.js ${NODE_VERSION} for darwin-arm64..."
curl --retry 3 --location --fail \
  -o "$TEMP_DIR/node.tar.gz" \
  "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-darwin-arm64.tar.gz"

echo -e "${GREEN}  ✓ Downloaded Node.js ($(du -h "$TEMP_DIR/node.tar.gz" | cut -f1))${NC}"
echo ""

# ============================================================================
# Step 3: Extract and assemble package
# ============================================================================
echo -e "${YELLOW}Step 3: Extracting and assembling server package...${NC}"

echo "  Extracting linux-arm server..."
tar -xzf "$TEMP_DIR/antigravity-linux.tar.gz" -C "$SERVER_DIR" --strip-components 1
echo -e "${GREEN}  ✓ Extracted server skeleton${NC}"

echo "  Replacing Node.js binary with darwin-arm64 version..."
mkdir -p "$TEMP_DIR/node-temp"
tar -xzf "$TEMP_DIR/node.tar.gz" -C "$TEMP_DIR/node-temp"
cp "$TEMP_DIR/node-temp/node-${NODE_VERSION}-darwin-arm64/bin/node" "$SERVER_DIR/node"
chmod +x "$SERVER_DIR/node"
echo -e "${GREEN}  ✓ Node.js binary replaced with native macOS executable${NC}"
echo ""

# ============================================================================
# Step 4: Surgical Module Replacement (Darwin compatible)
# ============================================================================
echo -e "${YELLOW}Step 4: Swapping native modules for macOS...${NC}"
SERVER_NODE_MODULES="$SERVER_DIR/node_modules"

if [ -d "$LOCAL_APP_RESOURCES" ]; then
    echo "  Copying pre-compiled native modules from local Antigravity IDE app..."
    
    # 1. spdlog
    cp "$LOCAL_APP_RESOURCES/node_modules/@vscode/spdlog/build/Release/spdlog.node" "$SERVER_NODE_MODULES/@vscode/spdlog/build/Release/spdlog.node"
    
    # 2. watcher
    cp "$LOCAL_APP_RESOURCES/node_modules/@parcel/watcher/build/Release/watcher.node" "$SERVER_NODE_MODULES/@parcel/watcher/build/Release/watcher.node"
    
    # 3. node-pty
    cp "$LOCAL_APP_RESOURCES/node_modules/node-pty/build/Release/pty.node" "$SERVER_NODE_MODULES/node-pty/build/Release/pty.node" 2>/dev/null || \
    cp "$LOCAL_APP_RESOURCES/node_modules/node-pty/prebuilds/darwin-arm64/pty.node" "$SERVER_NODE_MODULES/node-pty/build/Release/pty.node"
    
    cp "$LOCAL_APP_RESOURCES/node_modules/node-pty/build/Release/spawn-helper" "$SERVER_NODE_MODULES/node-pty/build/Release/spawn-helper" 2>/dev/null || true

    echo -e "${GREEN}  ✓ Natively compiled .node extensions replaced successfully${NC}"
    
    # 4. Language Server
    echo "  Copying and symlinking Language Server..."
    LOCAL_EXT_BIN="$LOCAL_APP_RESOURCES/extensions/antigravity/bin"
    SERVER_EXT_BIN="$SERVER_DIR/extensions/antigravity/bin"
    
    mkdir -p "$SERVER_EXT_BIN"
    if [ -f "$LOCAL_EXT_BIN/language_server_macos_arm" ]; then
        cp "$LOCAL_EXT_BIN/language_server_macos_arm" "$SERVER_EXT_BIN/language_server_macos_arm"
        ln -sf "language_server_macos_arm" "$SERVER_EXT_BIN/language_server_macos_x64"
        ln -sf "language_server_macos_arm" "$SERVER_EXT_BIN/language_server_linux_arm"
        echo -e "${GREEN}  ✓ Language server binary (arm64) aligned${NC}"
    elif [ -f "$LOCAL_EXT_BIN/language_server_macos_x64" ]; then
        cp "$LOCAL_EXT_BIN/language_server_macos_x64" "$SERVER_EXT_BIN/language_server_macos_x64"
        ln -sf "language_server_macos_x64" "$SERVER_EXT_BIN/language_server_macos_arm"
        ln -sf "language_server_macos_x64" "$SERVER_EXT_BIN/language_server_linux_arm"
        echo -e "${GREEN}  ✓ Language server binary (x64) aligned${NC}"
    else
        echo -e "${RED}  ⚠ Language server binary not found in local app!${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Local Antigravity IDE.app not found. Running npm rebuild as fallback...${NC}"
    cd "$SERVER_DIR"
    npm rebuild @vscode/spdlog @parcel/watcher node-pty > /dev/null 2>&1 || true
    echo -e "${GREEN}  ✓ npm rebuild finished${NC}"
fi
echo ""

# ============================================================================
# Step 5: Updating config and metadata
# ============================================================================
echo -e "${YELLOW}Step 5: Updating server product configuration...${NC}"
echo "$COMMIT_HASH" > "$SERVER_DIR/commit-id"

if [ -f "$SERVER_DIR/product.json" ]; then
    python3 << EOF
import json
try:
    with open('$SERVER_DIR/product.json', 'r') as f:
        data = json.load(f)
    data['commit'] = '${COMMIT_HASH}'
    # Inject tunnel config credentials
    data['tunnelApplicationName'] = 'antigravity-tunnel'
    data['tunnelApplicationConfig'] = {
        'authenticationProviders': {
            'github': {
                'scopes': ['user:email', 'read:org']
            }
        }
    }
    with open('$SERVER_DIR/product.json', 'w') as f:
        json.dump(data, f, indent=2)
    print("  ✓ product.json successfully updated")
except Exception as e:
    print(f"  ⚠ product.json update error: {e}")
EOF
else
    echo -e "${YELLOW}  ⚠ product.json not found, skipping update${NC}"
fi
echo ""

# ============================================================================
# Step 6: Codesigning and Clearing quarantine flags
# ============================================================================
echo -e "${YELLOW}Step 6: Conducting codesigning and clearing quarantine tags...${NC}"

echo "  Ad-hoc signing Node.js binary..."
codesign --force --deep --sign - "$SERVER_DIR/node" 2>/dev/null || true

echo "  Ad-hoc signing native .node modules..."
find "$SERVER_DIR/node_modules" -name "*.node" -exec codesign --force --sign - {} \; 2>/dev/null || true

echo "  Ad-hoc signing spawn-helper..."
find "$SERVER_DIR/node_modules" -name "spawn-helper" -exec codesign --force --sign - {} \; 2>/dev/null || true

echo "  Clearing com.apple.quarantine tags..."
xattr -dr com.apple.quarantine "$SERVER_DIR" 2>/dev/null || true

echo -e "${GREEN}  ✓ Codesigning and quarantine clean complete${NC}"
echo ""

# ============================================================================
# Step 7: Creating compatibility symlinks
# ============================================================================
echo -e "${YELLOW}Step 7: Establishing compatibility links...${NC}"

# Symlink .antigravity-server to .antigravity-ide-server
if [ ! -L "$SERVER_DATA_DIR_OLD" ] && [ ! -d "$SERVER_DATA_DIR_OLD" ]; then
    ln -nsf "$SERVER_DATA_DIR_NEW" "$SERVER_DATA_DIR_OLD"
fi

# Ensure the bin folder structure exists
mkdir -p "$SERVER_DATA_DIR_NEW/bin"

# DO NOT create 1.107.0-* engine or 'latest' symlinks in bin/.
# This avoids triggering the client's destructive clean_up_old_servers loop,
# which uses a BSD-incompatible find command on macOS and deletes active server tokens.
# The 2.0.1 client only looks for and matches the physical "${COMMIT_ID}" directory.

echo -e "${GREEN}  ✓ Symlinks and compatibility configurations set up${NC}"
echo ""

# ============================================================================
# Step 8: Verify Startup
# ============================================================================
echo -e "${YELLOW}Step 8: Verifying server binary execution...${NC}"

VERSION_OUTPUT=$("$SERVER_DIR/node" "$SERVER_DIR/out/server-main.js" --version 2>&1 | head -3)
echo -e "  Server report:\n${GREEN}$VERSION_OUTPUT${NC}"

echo ""
echo -e "${GREEN}=== Bootstrap Complete ===${NC}"
echo "Server is ready at: ${GREEN}~/.antigravity-ide-server/bin/${COMMIT_ID}${NC}"
echo "Start coding via SSH now!"
echo ""
