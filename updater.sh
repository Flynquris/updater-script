#!/bin/bash

# version 0.3

SELF_UPDATE_URL="https://raw.githubusercontent.com/Flynquris/updater-script/refs/heads/main/updater.sh"
SCRIPT_PATH="$HOME/.local/bin/updater.sh"
LOGFILE="$HOME/.local/share/updater.log"
LOCKFILE="/tmp/updater.lock"

# --- SAFE SELF-UPDATE MECHANISM ---
TMPFILE="${SCRIPT_PATH}.new"

echo "[$(date)] Updater: Checking for self-update..." | tee -a "$LOGFILE"
if curl -fsSL "$SELF_UPDATE_URL" -o "$TMPFILE"; then
    if [ -s "$TMPFILE" ] && grep -q '^#!/bin/bash' "$TMPFILE"; then
        if ! cmp -s "$TMPFILE" "$SCRIPT_PATH"; then
            echo "[$(date)] Updater: New version downloaded, replacing script..." | tee -a "$LOGFILE"
            mv "$TMPFILE" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            exec "$SCRIPT_PATH" "$@"  
            exit 0
        else
            echo "[$(date)] Updater: No update needed." | tee -a "$LOGFILE"
            rm -f "$TMPFILE"
        fi
    else
        echo "[$(date)] Updater: Downloaded file invalid (empty or missing shebang), aborting self-update!" | tee -a "$LOGFILE"
        rm -f "$TMPFILE"
    fi
else
    echo "[$(date)] Updater: Download failed, aborting self-update!" | tee -a "$LOGFILE"
    rm -f "$TMPFILE"
fi
# --- End of safe self-update ---

{
    echo "[$(date)] === System updater started ==="

    echo "-> Updating packages via apt..."
    sudo apt update
    sudo apt upgrade -y

    echo "-> Installing upgradable packages if available..."
    upgradable=$(apt list --upgradable | awk '/^[a-z]/ {print $1}')
    if [ -n "$upgradable" ]; then
        sudo apt install $upgradable -y
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
