#!/bin/bash

# version 0.4

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

# --- LOG ROTATION: Keep only the last 4 days based on Czech date format ---
if [ -f "$LOGFILE" ]; then
    TMPLOG=$(mktemp)
    cutoff=$(date --date='4 days ago' +%Y-%m-%d)

    last_valid=$(awk -v cutoff="$cutoff" '
        function cz_month_to_num(mesic) {
            m["ledna"]="01"; m["února"]="02"; m["března"]="03"; m["dubna"]="04";
            m["května"]="05"; m["června"]="06"; m["července"]="07"; m["srpna"]="08";
            m["září"]="09"; m["října"]="10"; m["listopadu"]="11"; m["prosince"]="12";
            return (m[mesic] ? m[mesic] : "00");
        }
        /^\[[A-Za-zČŠŽŘĎŤŇÁÉĚÍÓÚŮÝčšžřďťňáéěíóúůýž]+\s+[0-9]{1,2}\.\s+([a-záčďéěíňóřšťúůýž]+)[a-z]*\s+[0-9]{4},/ {
            match($0, /^\[[A-Za-zČŠŽŘĎŤŇÁÉĚÍÓÚŮÝčšžřďťňáéěíóúůýž]+\s+([0-9]{1,2})\.\s+([a-záčďéěíňóřšťúůýž]+)[a-z]*\s+([0-9]{4}),/, arr)
            d = (length(arr[1]) == 1 ? "0" arr[1] : arr[1])
            m = cz_month_to_num(arr[2])
            y = arr[3]
            if (y m d >= gensub("-", "", "g", cutoff)) last = NR
        }
        END { if (last) print last; else print 0 }
    ' "$LOGFILE")

    if [ "$last_valid" -eq 0 ]; then
        # No recent entry – wipe whole log!
        : > "$LOGFILE"
    else
        tail -n +"$last_valid" "$LOGFILE" > "$TMPLOG" && mv "$TMPLOG" "$LOGFILE"
    fi
fi

# --- LOCK: Avoid running multiple updaters at once ---
exec 9>"$LOCKFILE"
flock -n 9 || { echo "[$(date)] Updater: Already running, exiting." | tee -a "$LOGFILE"; exit 1; }

{
    echo "[$(date)] === System updater started ==="

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

    echo "-> Fixing world-writable directories (adding sticky bit)..."
    sudo find / -type d \( -perm -0002 -a ! -perm -1000 \) -exec chmod +t {} \; 2>/dev/null

    echo "[$(date)] === System update complete ==="
    echo
} >> "$LOGFILE" 2>&1

