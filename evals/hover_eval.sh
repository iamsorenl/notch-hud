#!/bin/bash
# Automated M0 hover eval: launches app, drives cursor into notch + peek-edge, asserts expand fires.
set +e
cd "$(dirname "$0")/.."
swift build >/dev/null 2>&1 || exit 1
rm -f ~/.notch-hud/hover.log
NOTCHHUD_DEBUG=1 swift run NotchHUD > .eval-run.log 2>&1 &
APP=$!
sleep 5
# center of notch, then peek edge (left of cutout)
for pt in "1028 3" "850 3" "1200 3"; do
  for y in 60 30 10 4 3; do ./tools/movemouse ${pt% *} $y >/dev/null 2>&1; sleep 0.2; done
  sleep 0.8
  ./tools/movemouse ${pt% *} 500 >/dev/null 2>&1; sleep 0.8
done
kill $APP 2>/dev/null; pkill -f "debug/NotchHUD" 2>/dev/null
ENTERS=$(grep -c "ENTER delivered" ~/.notch-hud/hover.log 2>/dev/null || echo 0)
echo "expand triggers: $ENTERS (expected >=3)"
[ "$ENTERS" -ge 3 ] && { echo "HOVER EVAL: PASS"; exit 0; } || { echo "HOVER EVAL: FAIL"; exit 1; }
