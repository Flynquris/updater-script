#!/bin/bash

# version 0.5

SELF_UPDATE_URL="https://raw.githubusercontent.com/Flynquris/updater-script/refs/heads/main/updater.sh"
SCRIPT_PATH="$HOME/.local/bin/updater.sh"
LOGFILE="$HOME/.local/share/updater.log"
LOCKFILE="/tmp/updater.lock"

# --- SAFE SELF-UPDATE MECHANISM ---
TMPFILE="${SCRIPT_PATH}.new"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

echo "[$(timestamp)] Updater: Checking for self-update..." | tee -a "$LOGFILE"
if curl -fsSL "$SELF_UPDATE_URL" -o "$TMPFILE"; then
    if [ -s "$TMPFILE" ] && grep -q '^#!/bin/bash' "$TMPFILE"; then
        if ! cmp -s "$TMPFILE" "$SCRIPT_PATH"; then
            echo "[$(timestamp)] Updater: New version downloaded, replacing script..." | tee -a "$LOGFILE"
            mv "$TMPFILE" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            exec "$SCRIPT_PATH" "$@"
            exit 0
        else
            echo "[$(timestamp)] Updater: No update needed." | tee -a "$LOGFILE"
            rm -f "$TMPFILE"
        fi
    else
        echo "[$(timestamp)] Updater: Downloaded file invalid (empty or missing shebang), aborting self-update!" | tee -a "$LOGFILE"
        rm -f "$TMPFILE"
    fi
else
    echo "[$(timestamp)] Updater: Download failed, aborting self-update!" | tee -a "$LOGFILE"
    rm -f "$TMPFILE"
fi
# --- End of safe self-update ---

# --- LOG ROTATION: keep only last 4 days, for any language/locale ---
if [ -f "$LOGFILE" ]; then
    TMPLOG=$(mktemp)
    cutoff=$(date --date='4 days ago' +%Y-%m-%d)
    firstline=0
    lineno=0
    while IFS= read -r line; do
        lineno=$((lineno+1))
        if [[ $line =~ \[([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
            logdate="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
            if [[ "$logdate" > "$cutoff" ]] || [[ "$logdate" == "$cutoff" ]]; then
                firstline=$lineno
                break
            fi
        fi
    done < "$LOGFILE"
    if [[ $firstline -gt 0 ]]; then
        tail -n +"$firstline" "$LOGFILE" > "$TMPLOG" && mv "$TMPLOG" "$LOGFILE"
    else
        : > "$LOGFILE"
    fi
fi

# --- LOCK: Avoid running multiple updaters at once ---
exec 9>"$LOCKFILE"
flock -n 9 || { echo "[$(timestamp)] Updater: Already running, exiting." | tee -a "$LOGFILE"; exit 1; }

{
    echo "[$(timestamp)] === System updater started ==="

    echo "-> Updating packages via apt..."
    sudo apt update
    sudo apt upgrade -y

    echo "-> Installing upgradable packages if available..."
    upgradable=$(apt list --upgradeable 2>/dev/null | awk -F/ '/upgradable from/ {print $1}')
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

    echo "Running postfix updates..."
    sudo dpkg --configure -a

    echo "-> Fixing world-writable directories (adding sticky bit)..."
    sudo find / -type d \( -perm -0002 -a ! -perm -1000 \) -exec chmod +t {} \; 2>/dev/null

    echo "Cleaning unused packages..."
    sudo apt autoremove -y

    echo "[$(timestamp)] === System update complete ==="
    echo
} >> "$LOGFILE" 2>&1

