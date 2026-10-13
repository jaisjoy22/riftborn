#!/bin/bash
# Executes docs/PLAN_v3.md phase-by-phase with claude-opus-5.5 (fresh cached session per phase).
# Each phase must build + pass --selftest before it is committed; a failing phase is rolled back
# and stops the run (no token spend on later phases built on a broken base).
set -uo pipefail
cd "$(dirname "$0")"
LOG=docs/exec_log.txt; : > "$LOG"
PHASES=("1. Baseline and deterministic harness"
        "2. Procedural silhouette and environment readability"
        "3. Traversal with explicit authority over physics"
        "4. Directional, committed combat"
        "5. Spawn staging and bounded HUD"
        "6. Small environmental gameplay set"
        "7. Audio refinement without a synthesis rewrite")
for p in "${PHASES[@]}"; do
  n=${p%%.*}
  echo "=== PHASE $p ===" | tee -a "$LOG"
  hermes chat --provider astra -m claude-opus-5.5 -t file,terminal --max-turns 70 --run-budget 1500 --oneshot -q \
"EXECUTOR for Riftborn (Swift/SpriteKit, $(pwd)). Implement ONLY section '## $p' of docs/PLAN_v3.md, plus the
selftest assertions from section 8 and acceptance items from section 9 that belong to this phase.
Context: read docs/PLAN_v3.md sections 0 and $n, and docs/CODE_DIGEST.txt; open a Sources/*.swift file only
when you edit it, and read only the regions you need (use offsets). Prefer targeted patch edits over rewrites.
Constraints: no new dependencies; keep 60 fps; keep all existing CLI flags and the existing selftest passing.
Verify before finishing: ./build.sh must print Built, and build/Riftborn.app/Contents/MacOS/Riftborn --selftest
must print 'result           : PASS'. Fix any failure you introduce. Do not git commit.
Finish with one line: PHASE_${n}_DONE, or PHASE_${n}_BLOCKED: <reason>." 2>&1 | tail -6 | tee -a "$LOG"
  ./build.sh > /tmp/rb_build.txt 2>&1
  if grep -q Built /tmp/rb_build.txt && ./build/Riftborn.app/Contents/MacOS/Riftborn --selftest > /tmp/rb_test.txt 2>&1 && grep -q "result           : PASS" /tmp/rb_test.txt; then
    git add -A && git commit -q -m "v3 phase $p" && git push -q
    echo "PHASE $n VERIFIED + PUSHED ($(git rev-parse --short HEAD))" | tee -a "$LOG"
  else
    echo "PHASE $n FAILED VERIFICATION; rolling back" | tee -a "$LOG"
    grep -E "error|result" /tmp/rb_build.txt /tmp/rb_test.txt | head -20 | tee -a "$LOG"
    git checkout -- . && git clean -fdq Sources
    exit 1
  fi
done
echo "ALL PHASES COMPLETE" | tee -a "$LOG"
