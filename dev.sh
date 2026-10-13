#!/bin/bash
# Riftborn dev loop. Mechanical steps run locally (zero tokens); model work goes through jev-route,
# which scores the task with JEV and picks the cheapest capable model tier.
#   ./dev.sh check            build + selftest + snapshot (no LLM)
#   ./dev.sh task "<text>"    JEV-routed implementation task, then auto check + commit + push
#   ./dev.sh route "<text>"   show JEV routing decision only
set -euo pipefail
cd "$(dirname "$0")"

check() {
  ./build.sh 2>&1 | grep -E "error|Built" | head -20
  ./build/Riftborn.app/Contents/MacOS/Riftborn --selftest | grep -E "result|duel|sim fps"
  RIFTBORN_SAVE=/tmp/rb-dev.json ./build/Riftborn.app/Contents/MacOS/Riftborn --mute --snapshot /tmp/riftborn_latest.png 2>&1 | grep snapshot || true
  rm -f /tmp/rb-dev.json
}

case "${1:-check}" in
  check) check ;;
  route) shift; JEV_ROUTE_DRY=1 jev-route "$*" ;;
  task)
    shift
    jev-route --run "Work in $(pwd) (Riftborn, Swift/SpriteKit, build with ./build.sh, test with build/Riftborn.app/Contents/MacOS/Riftborn --selftest). $*" -- -t file,terminal --max-turns 80
    if check | grep -q "result           : PASS"; then
      git add -A && git commit -q -m "$*" && git push -q && echo "committed + pushed"
    else
      echo "selftest FAILED — changes left uncommitted for review"
    fi ;;
  *) echo "usage: $0 {check|route|task} ..." ;;
esac
