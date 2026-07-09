#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.local.wisper-clone"

pkill -f WisperClone 2>/dev/null || true
tccutil reset Microphone "$BUNDLE_ID"
tccutil reset ListenEvent "$BUNDLE_ID"
tccutil reset Accessibility "$BUNDLE_ID"

echo "Reset Microphone, Input Monitoring, and Accessibility for $BUNDLE_ID."
echo "Reopen the app and allow the permissions again."
