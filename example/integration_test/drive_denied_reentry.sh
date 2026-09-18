#!/bin/bash
#
# Answers finding 2: when the server refuses a re-entry after a reconnect,
# does the room recover, or does it report 3027 forever?
#
# Two processes against one meeting:
#   device (Android) — joins, loses the radio, is removed, tries to come back
#   host   (macOS)   — stays online and removes the device's participant
#
#   ./drive_denied_reentry.sh deactivate   # disable the room via the API
#   ./drive_denied_reentry.sh remove       # moderator removes the participant
#
# deactivate is the one that can actually produce a refusal: with an
# allow_join token a removed participant is simply re-admitted, because the
# token still authorises entry. Disabling the room takes that away.
#
# Reads AUTH_TOKEN and VIDEOSDK_API_ENDPOINT from example/.env.
set -u

MODE="${1:-deactivate}"

cd "$(dirname "$0")/.." || exit 1

ADB="$(command -v adb || echo "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb")"
[ -x "$ADB" ] || { echo "adb not found — set ANDROID_HOME"; exit 2; }
SERIAL="${SERIAL:-$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
[ -n "$SERIAL" ] || { echo "no Android device attached"; exit 2; }

TOKEN=$(grep '^AUTH_TOKEN=' .env | cut -d= -f2-)
ENDPOINT=$(grep '^VIDEOSDK_API_ENDPOINT=' .env | cut -d= -f2-)
[ -n "$TOKEN" ] || { echo "no AUTH_TOKEN in example/.env"; exit 2; }
ENDPOINT="${ENDPOINT:-https://api.videosdk.live/v2}"

MEETING=$(curl -s -X POST "$ENDPOINT/meetings" -H "Authorization: $TOKEN" \
  | sed -n 's/.*"meetingId":"\([^"]*\)".*/\1/p')
[ -n "$MEETING" ] || { echo "could not create a meeting — token expired?"; exit 2; }

SIGNAL="$(mktemp -u -t denied-signal)"
DEV_LOG="$(mktemp -t denied-device)"
MOD_LOG="$(mktemp -t denied-moderator)"

echo "[driver] meeting $MEETING"
echo "[driver] device log $DEV_LOG"
echo "[driver] moderator log $MOD_LOG"

radio() { "$ADB" -s "$SERIAL" shell cmd connectivity airplane-mode "$1" >/dev/null 2>&1; }
cleanup() { radio disable; rm -f "$SIGNAL"; }
trap cleanup EXIT INT TERM

radio disable
rm -f "$SIGNAL"

DEFINES="--dart-define=MEETING_ID=$MEETING --dart-define=MEETING_TOKEN=$TOKEN"

# Device first — it has the slower build.
flutter test integration_test/denied_reentry_test.dart -d "$SERIAL" \
  $DEFINES > "$DEV_LOG" 2>&1 &
DEV_PID=$!

# Moderator on the host, joining the same meeting — only needed in remove mode.
MOD_PID=""
if [ "$MODE" = "remove" ]; then
  flutter test integration_test/moderator_remove_test.dart -d macos \
    $DEFINES --dart-define=SIGNAL_FILE="$SIGNAL" > "$MOD_LOG" 2>&1 &
  MOD_PID=$!
fi

echo "[driver] waiting for the device to join and settle"
for _ in $(seq 1 400); do
  if grep -q "READY_FOR_DROP" "$DEV_LOG" 2>/dev/null; then break; fi
  if ! kill -0 $DEV_PID 2>/dev/null; then
    echo "[driver] device test exited early"; break
  fi
  sleep 1
done

if grep -q "READY_FOR_DROP" "$DEV_LOG" 2>/dev/null; then
  echo "[driver] radio off ($(date +%T))"
  radio enable
  sleep 4

  if [ "$MODE" = "remove" ]; then
    echo "[driver] signalling the moderator to remove the device"
    touch "$SIGNAL"
  else
    echo "[driver] disabling room $MEETING via the API"
    curl -s -X POST "https://api.videosdk.live/v2/rooms/deactivate" \
      -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
      -d "{\"roomId\":\"$MEETING\"}" \
      | sed -n 's/.*"disabled":\([a-z]*\).*/[driver] room disabled=\1/p'
  fi

  # Long enough for the removal to land and the re-entry to be attempted,
  # short enough that socket.io's 5 attempts are not exhausted.
  sleep 16
  radio disable
  echo "[driver] radio on  ($(date +%T))"
else
  echo "[driver] never saw READY_FOR_DROP — no drop performed"
fi

wait $DEV_PID; DEV_STATUS=$?
MOD_STATUS=0
if [ -n "$MOD_PID" ]; then wait $MOD_PID; MOD_STATUS=$?; fi

echo
if [ "$MODE" = "remove" ]; then
  echo "===== moderator ====="
  grep "MODERATOR |" "$MOD_LOG"
fi
echo "===== device ====="
grep "DEVICE |" "$DEV_LOG"
echo "=================="
echo "[driver] device exit $DEV_STATUS · moderator exit $MOD_STATUS"
echo "[driver] look for the VERDICT line above"
