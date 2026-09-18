#!/bin/bash
#
# Drives the reconnect integration tests by taking the network away.
#
# The tests cannot drop their own connection, so they print READY_FOR_DROP and
# wait; this script watches for that marker and toggles airplane mode over adb.
# It also passes --dart-define=RECONNECT_DRIVER=true, without which the tests
# skip rather than pass trivially.
#
#   ./drive_reconnect.sh validation   # reconnect_validation_test.dart  (1 drop)
#   ./drive_reconnect.sh scenarios    # reconnect_scenarios_test.dart   (3 drops)
#
# Requires: an Android device with USB debugging, and adb on PATH or at
# ANDROID_HOME/platform-tools/adb.
set -u

SUITE="${1:-validation}"
case "$SUITE" in
  validation) TEST_FILE=integration_test/reconnect_validation_test.dart; DROPS=1 ;;
  scenarios)  TEST_FILE=integration_test/reconnect_scenarios_test.dart;  DROPS=3 ;;
  *) echo "usage: $0 [validation|scenarios]"; exit 2 ;;
esac

ADB="$(command -v adb || echo "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb")"
[ -x "$ADB" ] || { echo "adb not found — set ANDROID_HOME"; exit 2; }

SERIAL="${SERIAL:-$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
[ -n "$SERIAL" ] || { echo "no Android device attached"; exit 2; }

# Seconds the radio stays off. Long enough for the SDK to notice and report
# 3027, short enough not to exhaust socket.io's 5 reconnect attempts — past
# that the room closes for real, which is a different scenario.
DROP_SECONDS="${DROP_SECONDS:-12}"

cd "$(dirname "$0")/.." || exit 1
LOG="$(mktemp -t reconnect-drive)"
PKG=live.videosdk.rtc.flutter

echo "[driver] device $SERIAL · suite $SUITE · $DROPS drop(s) of ${DROP_SECONDS}s"
echo "[driver] log $LOG"

radio() { "$ADB" -s "$SERIAL" shell cmd connectivity airplane-mode "$1" >/dev/null 2>&1; }
cleanup() { radio disable; }
trap cleanup EXIT INT TERM

radio disable

flutter test "$TEST_FILE" -d "$SERIAL" \
  --dart-define=RECONNECT_DRIVER=true > "$LOG" 2>&1 &
TEST_PID=$!

# Grant mic/camera once the app lands, so a runtime permission dialog cannot
# stall a test that needs the microphone.
(
  for _ in $(seq 1 120); do
    if "$ADB" -s "$SERIAL" shell pm list packages 2>/dev/null | grep -q "$PKG"; then
      "$ADB" -s "$SERIAL" shell pm grant $PKG android.permission.RECORD_AUDIO 2>/dev/null
      "$ADB" -s "$SERIAL" shell pm grant $PKG android.permission.CAMERA 2>/dev/null
      break
    fi
    sleep 2
  done
) &

seen=0
for drop in $(seq 1 "$DROPS"); do
  echo "[driver] waiting for READY_FOR_DROP #$drop"
  for _ in $(seq 1 400); do
    count=$(grep -c "READY_FOR_DROP" "$LOG" 2>/dev/null)
    count=${count:-0}
    [ "$count" -gt "$seen" ] && { seen=$count; break; }
    if ! kill -0 $TEST_PID 2>/dev/null; then
      echo "[driver] test exited before drop #$drop"
      wait $TEST_PID; exit $?
    fi
    sleep 1
  done
  [ "$seen" -ge "$drop" ] || { echo "[driver] marker #$drop never arrived"; break; }

  echo "[driver] drop #$drop: radio off ($(date +%T))"
  radio enable
  sleep "$DROP_SECONDS"
  radio disable
  echo "[driver] drop #$drop: radio on  ($(date +%T))"
done

wait $TEST_PID
STATUS=$?

echo
echo "===== test output ====="
grep -E "RECONNECT_TEST \||SCENARIO_TEST \||^[0-9]{2}:[0-9]{2} \+" "$LOG"
echo "======================="
echo "[driver] exit status $STATUS · full log at $LOG"
exit $STATUS
