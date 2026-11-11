#!/usr/bin/env bash
set -uo pipefail
TARGET_USER="hank"
TARGET_HOST="192.168.1.10"
URL="http://$TARGET_HOST/wordpress/"
LOG_FILE="$HOME/monitor.log"

MEM_WARN=70; MEM_CRIT=90 #memory
LOAD_WARN=2; LOAD_CRIT=4
DISK_WARN=70; DISK_CRIT=90
HTTP_WARN_MS=1000; HTTP_CRIT_MS=3000

STATUS=0
STATES=(NORMAL WARNING CRITICAL)

#helpers
log() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" |
        tee -a "$LOG_FILE" || exit 2
}

remote() {
    timeout 20s ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$TARGET_USER@$TARGET_HOST" "$@"
} #prevents password prompts during cron runs and limits how long a bad connect can hang

raise() {
    if (( $1 > STATUS)); then
        STATUS=$1
    fi
} #once a check reports CRITICAL, later NORMAL checks can't reset it

classify() {
    local label=$1 value=$2 warn=$3 crit=$4 level

    level=$(awk -v value="$value" -v warn="$warn" -v crit="$crit" '
        BEGIN {
            if (value >= crit) print 2
            else if (value >= warn) print 1
            else print 0
            }')
    
    raise "$level"
    log "${STATES[$level]} $label=$value (warning=$warn critical=$crit)"
}

#checks
check_services() {
    if remote "systemctl is-active apache2 && systemctl is-active mariadb" >/dev/null 2>&1; then
        log "NORMAL Apache and MariaDB active"
    else
        raise 2
        log "CRITICAL Apache/MariaDB inactive or SSH failed"
    fi
} #both apache and mariadb must be active ... ssh failures also make this check critical

check_http() {
    local result code seconds milliseconds

    if ! result=$(curl -sS --connect-timeout 5 --max-time 10 \
        -H 'Host: localhost:9000' -o /dev/null \
        -w '%{http_code} %{time_total}' "$URL"); then
        raise 2
        log "CRITICAL WP request failed"
        return
    fi

    read -r code seconds <<< "$result"

    if [[ "$code" != 200 ]]; then
        raise 2
        log "CRITICAL WP returned HTTP $code"
        return
    fi

    milliseconds=$(awk -v seconds="$seconds" \
        'BEGIN {printf "%.0f", seconds * 1000}')

    classify "HTTP_ms" "$milliseconds" "$HTTP_WARN_MS" "$HTTP_CRIT_MS"
}

check_memory() {
    local percent

    if ! percent=$(remote "LC_ALL=C free -m" |
        awk '$1 == "Mem:" {printf "%.1f", 100 * ($2 - $7) / $2}') ||
        [[ -z "$percent" ]]; then
        raise 2
        log "CRITICAL could not read Pi memory"
        return
    fi
 
    classify "memory_percent" "$percent" "$MEM_WARN" "$MEM_CRIT"
}

check_load() {
    local load

    if ! load=$(remote "cat /proc/loadavg" | awk '{print $1}') ||
        [[ -z "$load" ]]; then
        raise 2
        log "CRITICAL could not read Pi load"
        return
    fi

    classify "load_1min" "$load" "$LOAD_WARN" "$LOAD_CRIT"
}

check_disk() {
    local percent

    if ! percent=$(remote "LC_ALL=C df -P /" |
        awk 'NR == 2 {gsub (/%/, "", $5); print $5}') ||
        [[ -z "$percent" ]]; then
        raise 2
        log "CRITICAL could not read Pi disk usage"
        return
    fi

    classify "disk_percent" "$percent" "$DISK_WARN" "$DISK_CRIT"
} #checks root filesystem and awk reads its usage percentage and removes the % so it can be compared numerically

#MAIN
main() {
    log "check started for $TARGET_HOST"
    check_services
    check_http
    check_memory
    check_load
    check_disk
    log "overall status: ${STATES[$STATUS]} ($STATUS)"
    exit "$STATUS"
}
main