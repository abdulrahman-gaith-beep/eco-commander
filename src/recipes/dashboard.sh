#!/usr/bin/env bash
# DESC: Open the current Eco dashboard
# INPUTS: none
# OUTPUT: opens ~/.eco/current/dashboard.html in default browser
# USES: the generated dashboard.html as source
# HUMAN: you read, take action based on what you see
set -eu

DASHBOARD="$HOME/.eco/current/dashboard.html"
[ -f "$DASHBOARD" ] || { echo "Dashboard not found: $DASHBOARD" >&2; exit 1; }
open "$DASHBOARD"
