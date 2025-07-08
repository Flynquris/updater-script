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

    # Projde log a zapamatuje číslo řádku posledního timestampu, který je v cutoffu nebo novější
    lastline=0
    lineno=0

    # Funkce převodu měsíce
    cz_month_to_num() {
        case "$1" in
            ledna) echo 01;;
            února) echo 02;;
            března) echo 03;;
            dubna) echo 04;;
            května) echo 05;;
            června) echo 06;;
            července) echo 07;;
            srpna) echo 08;;
            září) echo 09;;
            října) echo 10;;
            listopadu) echo 11;;
            prosince) echo 12;;
            *) echo 00;;
        esac
    }

    while IFS= read -r line; do
        lineno=$((lineno+1))
        if [[ $line =~ \[([A-Za-zČŠŽŘĎŤŇÁÉĚÍÓÚŮÝčšžřďťňáéěíóúůýž]+)\ ([0-9]{1,2})\.\ ([a-záčďéěíňóřšťúůýž]+)\ ([0-9]{4}), ]]; then
            day="${BASH_REMATCH[2]}"
            [[ ${#day} -eq 1 ]] && day="0$day"
            month=$(cz_month_to_num "${BASH_REMATCH[3]}")
            year="${BASH_REMATCH[4]}"
            logdate="${year}-${month}-${day}"
            if [[ "$logdate" > "$cutoff" ]] || [[ "$logdate" == "$cutoff" ]]; then
                lastline=$lineno
            fi
        fi
    done < "$LOGFILE"

    if [[ $lastline -gt 0 ]]; then
        # Zachovej od posledního mladého timestampu včetně
        tail -n +"$lastline" "$LOGFILE" > "$TMPLOG" && mv "$TMPLOG" "$LOGFILE"
    else
        # Nenašel se žádný timestamp v limitu, smaž vše
        : > "$LOGFILE"
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

