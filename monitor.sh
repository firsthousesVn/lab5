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

STATUS=0 #worst state seen: 0 NORMAL, 1 WARNING, 2 CRIT
STATES=(NORMAL WARNING CRITICAL)

#helpers
log() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" |
        tee -a "$LOG_FILE" || exit 2
}

remote() {}
raise() {}
classify() {}

#checks
check_services() {}
check_http() {}
check_memory() {}
check_load() {}
check_disk() {}

#MAIN
main() {
    log "check started for $TARGET_HOST"
    check_services
    check_http
    check_memory
    check_load
    check_disk
    log "overall status: $STATUS"
    exit "$STATUS"
}
main