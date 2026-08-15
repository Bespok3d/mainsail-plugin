#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) 2026 unlucio and the Bespok3d contributors
# SPDX-License-Identifier: GPL-3.0-only
# The spool picker listed what the browser fetched from Spoolman when the page loaded, so a spool
# added in Spoolman after that was missing from it until the page was reloaded. This runs against
# the bundle this plugin actually ships and proves the lane's own spool button reads Spoolman again
# as it opens the picker, the same as the Fluidd plugin does.
set -uo pipefail

PLUGIN_DIR="${1:?usage: test-spool-picker-refresh.sh <plugin-dir>}"

# shellcheck disable=SC2016 # $store is a Vue property in the bundle, not a shell variable
PICKER_READS_SPOOLMAN='onFilamentClick(){if(this.afcExistsSpoolman){this.$store.dispatch("server/spoolman/refreshSpools"),this.showSpoolmanDialog=!0'

failures=0

fail() {
    echo "  FAIL: $1" >&2
    failures=$((failures + 1))
}

# The chunk name carries upstream's content hash, so it is found by its stable prefix.
app_chunk="$(echo "$PLUGIN_DIR"/files/html/assets/index-*.js)"
[ -f "$app_chunk" ] || {
    echo "  FAIL: no app chunk in the vendored bundle" >&2
    exit 1
}

reads_before_opening="$(grep -oF "$PICKER_READS_SPOOLMAN" "$app_chunk" | wc -l | tr -d ' ')"
[ "$reads_before_opening" = 1 ] ||
    fail "the lane's own spool button opens the picker without reading Spoolman again"

[ "$failures" -eq 0 ]
