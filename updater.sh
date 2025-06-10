#!/bin/bash

SELF_UPDATE_URL="https://raw.githubusercontent.com/Flynquris/updater-script/refs/heads/main/updater.sh"
SCRIPT_PATH="$HOME/.local/bin/updater.sh"

# --- LOGGING ---
LOGFILE="$HOME/.local/share/updater.log"
mkdir -p "$(dirname "$LOGFILE")"

# --- Prevent multiple concurrent runs ---
LOCKFILE="/tmp/updater.lock"
exec 9>"$LOCKFILE"
flock -n 9 || { echo "Updater is already running!"; exit 1; }

# --- SELF-UPDATE ---
TMPFILE=$(mktemp)
curl -fsSL "$SELF_UPDATE_URL" -o "$TMPFILE"
if ! cmp -s "$TMPFILE" "$SCRIPT_PATH"; then
    echo "[$(date)] Updater: New version found on GitHub, updating myself..." | tee -a "$LOGFILE"
    cp "$TMPFILE" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    rm -f "$TMPFILE"
    exec "$SCRIPT_PATH" "$@"  # Restart with the new version
    exit 0
fi
rm -f "$TMPFILE"

{
    echo "[$(date)] === System updater started ==="

    echo "-> Updating packages via nala..."
    sudo nala update
    sudo nala upgrade -y

    echo "-> Installing upgradable packages if available..."
    upgradable=$(nala list --upgradable | awk '/^[a-z]/ {print $1}')
    if [ -n "$upgradable" ]; then
        sudo nala install $upgradable -y
    fi

    echo "-> Refreshing snap packages..."
    sudo snap refresh

    echo "-> Updating flatpak packages..."
    sudo flatpak update -y

    echo "-> Updating VSCode extensions..."
    if command -v code >/dev/null; then
        code --update-extensions || true
    fi

    echo "-> Updating Node.js to latest LTS (via nvm)..."
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts

    echo "-> Updating npm to latest version..."
    npm install -g npm@latest

    echo "-> Updating global Node.js packages..."
    npm update -g

    echo "-> Upgrading bun..."
    if command -v bun >/dev/null; then
        bun upgrade
    fi

    echo "-> Fixing world-writable directories (adding sticky bit)..."
    sudo find / -type d \( -perm -0002 -a ! -perm -1000 \) -exec chmod +t {} \; 2>/dev/null

    echo "[$(date)] === System update complete ==="
    echo
} >> "$LOGFILE" 2>&1
