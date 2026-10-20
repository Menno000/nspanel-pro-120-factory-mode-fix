#!/usr/bin/env bash
#
# Catch the short ADB window that opens while a SONOFF NSPanel Pro / Pro 120 boots.
#
# On units that boot into the Chinese factory-test screen (工厂模式), adbd is only
# reachable for roughly 15-20 seconds during boot. This script polls `adb devices`
# every 300 ms and acts the moment the panel appears.
#
# Usage:
#   ./find-adb-window.sh                 # watch and print diagnostics
#   ./find-adb-window.sh --fix           # also disable the factory test app
#   ./find-adb-window.sh --serial XYZ    # only match this USB serial
#   ./find-adb-window.sh --minutes 15
#
set -u

SERIAL=""
FIX=0
MINUTES=10

while [ $# -gt 0 ]; do
  case "$1" in
    --fix)     FIX=1 ;;
    --serial)  SERIAL="$2"; shift ;;
    --minutes) MINUTES="$2"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

command -v adb >/dev/null 2>&1 || { echo "adb not found in PATH" >&2; exit 1; }

log() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
log "watching for the NSPanel Pro boot window (${MINUTES} min)..."

deadline=$(( $(date +%s) + MINUTES * 60 ))

while [ "$(date +%s)" -lt "$deadline" ]; do
  while read -r id state _; do
    case "$state" in
      device|recovery|sideload|unauthorized) ;;
      *) continue ;;
    esac
    case "$id" in *:*) continue ;; esac          # skip TCP transports
    if [ -n "$SERIAL" ] && [ "$id" != "$SERIAL" ]; then continue; fi

    log "found $id [$state]"
    if [ "$state" != "device" ]; then
      log "not authorised - accept the RSA prompt on the panel if it is visible"
      exit 0
    fi

    adb -s "$id" root >/dev/null 2>&1
    sleep 2
    adb -s "$id" wait-for-device >/dev/null 2>&1

    log "id            : $(adb -s "$id" shell id | tr -d '\r')"
    log "build         : $(adb -s "$id" shell getprop ro.build.display.id | tr -d '\r')"
    log "packages      : $(adb -s "$id" shell 'pm list packages | grep -i -e ewelink -e smatek' | tr '\n' ' ')"
    log "home activity : $(adb -s "$id" shell 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME' | tr '\n' ' ')"

    if [ "$FIX" -eq 1 ]; then
      log "disabling factory app..."
      adb -s "$id" shell pm disable-user --user 0 com.eWeLinkNSPro.dev
      adb -s "$id" shell am force-stop com.eWeLinkNSPro.dev
      adb -s "$id" shell pm disable-user --user 0 com.smatek.test
      log "disabled now  : $(adb -s "$id" shell 'pm list packages -d' | tr '\n' ' ')"
      adb -s "$id" shell input keyevent 3 >/dev/null 2>&1
      sleep 3
      log "foreground    : $(adb -s "$id" shell 'dumpsys activity activities | grep mResumedActivity' | tr -d '\r')"
      log 'Pick "eWeLinkControlPanel" and choose "Always" on the panel if a Home chooser appears.'
    fi
    exit 0
  done < <(adb devices | tail -n +2)
  sleep 0.3
done

log "no device appeared. Power-cycle the panel (normal reboot, no 5x reset) and run again."
