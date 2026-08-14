#!/usr/bin/env bash
# create-env.sh — bring ReLay to a ready-to-test state.
#
# What this sets up:
#   • Release build → /Applications/ReLay.app
#   • Relaunch with Accessibility already granted (if previously authorized)
#   • Log tail pointer + how to verify tiling / Layout Library / eligibility
#
# Usage:
#   ./scripts/create-env.sh
#   ./scripts/create-env.sh --reset-ax   # force Accessibility re-prompt
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ReLay environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

"$REPO/install.sh" "$@"

LOG="${HOME}/Library/Logs/ReLay.log"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " App:     /Applications/ReLay.app"
echo " Bundle:  com.cameroncohen.relay"
echo " Logs:    $LOG"
echo " Padding: Settings → General → Window Padding"
echo ""
echo " Verify window eligibility (menu-bar / popups ignored):"
echo "   1. Open 2 normal apps → they should auto-tile"
echo "   2. Open a menu-bar dropdown / small popup → tiles should NOT change"
echo "   3. Check log for 'auto-layout skip — newcomer not tileable' or no new tile line"
echo ""
echo " Layout Library:"
echo "   Status menu → Open Layout Library → Apply (slots auto-fill)"
echo ""
echo " Linked edge resize:"
echo "   Drag the shared edge between tiled windows"
echo "   Expect log: linked-edge begin …"
echo ""
if [[ -f "$LOG" ]]; then
    echo " Last log lines:"
    tail -8 "$LOG" | sed 's/^/   /'
fi
