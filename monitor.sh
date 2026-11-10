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
    log "${STATES[$level]} $label=$value (warnin=$warn critical=$crit)"
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
}
check_memory() {
    local percent
}
check_load() {
    local load
}
check_disk() {
    local percent

    if ! percent=$(remote "LC_ALL=C df -P /" |
        awk 'NR == 2 {gsub (/%/, "", $5); print $5}') ||
        [[ -z "$percent"]]; then
        raise 2
        log "CRITICAL could not read Pi disk usage"
        return
    fi
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