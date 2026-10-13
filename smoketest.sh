#!/bin/bash
# Boots the real windowed app (muted, throwaway save) for N seconds, logs real rendered FPS, reports health.
cd "$(dirname "$0")"
export RIFTBORN_SAVE=/tmp/rb-gui.json
rm -f "$RIFTBORN_SAVE"
./build/Riftborn.app/Contents/MacOS/Riftborn --mute --fpslog > /tmp/rb.log 2>&1 &
PID=$!
sleep "${1:-8}"
if kill -0 $PID 2>/dev/null; then
  echo "GUI alive after ${1:-8}s (pid $PID)"
  ps -o rss=,%cpu= -p $PID | awk '{printf "RSS %.0f MB, CPU %s%%\n",$1/1024,$2}'
  echo "rendered fps per second: $(grep '^fps' /tmp/rb.log | awk '{print $2}' | tr '\n' ' ')"
  kill $PID
else
  echo "GUI exited early:"; cat /tmp/rb.log
fi
[ -f "$RIFTBORN_SAVE" ] && echo "chronicle written: $(wc -c < $RIFTBORN_SAVE) bytes"
rm -f "$RIFTBORN_SAVE"
