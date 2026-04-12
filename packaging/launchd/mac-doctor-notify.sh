#!/bin/bash
# mac-doctor-notify.sh — Run Mac Doctor silently and send a macOS notification
# Called by the LaunchAgent on a schedule. No terminal needed.

set -e

# Find mac-doctor — check common install locations
if [ -x "/usr/local/bin/mac-doctor" ]; then
    DOCTOR="/usr/local/bin/mac-doctor"
elif [ -x "/opt/homebrew/bin/mac-doctor" ]; then
    DOCTOR="/opt/homebrew/bin/mac-doctor"
else
    DOCTOR=$(command -v mac-doctor 2>/dev/null || echo "")
    if [ -z "$DOCTOR" ]; then
        osascript -e 'display notification "mac-doctor not found. Reinstall with: brew install mac-doctor" with title "Mac Doctor" sound name "Basso"'
        exit 1
    fi
fi
LOG_DIR="$HOME/.mac-doctor/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
LOG_FILE="$LOG_DIR/scan-${TIMESTAMP}.log"

# Run the scan (no-fix, snapshot enabled, capture output)
"$DOCTOR" --no-snap > "$LOG_FILE" 2>&1 || true

# Parse results from output
ISSUES=$(grep -c '\[CRITICAL\]' "$LOG_FILE" 2>/dev/null || echo "0")
WARNINGS=$(grep -c '\[WARNING\]' "$LOG_FILE" 2>/dev/null || echo "0")
SCORE=$(grep -oE 'Health Score: [0-9]+' "$LOG_FILE" 2>/dev/null | grep -oE '[0-9]+' || echo "?")

# Build notification
if (( ISSUES > 0 )); then
    TITLE="Mac Doctor: ${ISSUES} issue(s) found"
    SUBTITLE="Health Score: ${SCORE}/100"
    MSG="${ISSUES} critical, ${WARNINGS} warnings. Run 'mac-doctor --fix' to resolve."
    SOUND="Basso"
elif (( WARNINGS > 3 )); then
    TITLE="Mac Doctor: ${WARNINGS} warnings"
    SUBTITLE="Health Score: ${SCORE}/100"
    MSG="No critical issues, but ${WARNINGS} warnings worth checking."
    SOUND="Purr"
else
    TITLE="Mac Doctor: All clear"
    SUBTITLE="Health Score: ${SCORE}/100"
    MSG="Your Mac is healthy. ${WARNINGS} minor warning(s)."
    SOUND="Glass"
fi

# Send macOS notification
osascript -e "display notification \"${MSG}\" with title \"${TITLE}\" subtitle \"${SUBTITLE}\" sound name \"${SOUND}\""

# Clean up old logs (keep last 10)
ls -t "$LOG_DIR"/scan-*.log 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
