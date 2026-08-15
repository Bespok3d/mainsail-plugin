#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) 2026 unlucio and the Bespok3d contributors
# SPDX-License-Identifier: GPL-3.0-only
# The lane filament dialog offers a weight box, and AFC Lite refuses SET_WEIGHT outright, so on a
# lane with no Spoolman spool that box could only ever answer with an error. This runs against the
# bundle this plugin actually ships and proves the box is drawn only for a lane on a Spoolman spool,
# and that a browser already holding the old code is handed the new one instead of serving its own.
set -uo pipefail

PLUGIN_DIR="${1:?usage: test-weight-box.sh <plugin-dir>}"
SERVICE_WORKER="$PLUGIN_DIR/files/html/sw.js"

# shellcheck disable=SC2016 # $t is a Vue translation method in the bundle, not a shell variable
WEIGHT_ROW='t(H,{attrs:{title:e.$t("Panels.AfcPanel.Weight")'
# shellcheck disable=SC2016 # as above
WEIGHT_ROW_ON_A_SPOOLMAN_SPOOL='e.lane&&e.lane.spool_id!=null?[t(j,{staticClass:"my-3"}),'"$WEIGHT_ROW"

failures=0

fail() {
    echo "  FAIL: $1" >&2
    failures=$((failures + 1))
}

count_in_app_chunk() {
    grep -oF "$1" "$app_chunk" | wc -l | tr -d ' '
}

# The chunk name carries upstream's content hash, so it is found by its stable prefix.
app_chunk="$(echo "$PLUGIN_DIR"/files/html/assets/index-*.js)"
[ -f "$app_chunk" ] || {
    echo "  FAIL: no app chunk in the vendored bundle" >&2
    exit 1
}

weight_rows="$(count_in_app_chunk "$WEIGHT_ROW")"
rows_on_a_spoolman_spool="$(count_in_app_chunk "$WEIGHT_ROW_ON_A_SPOOLMAN_SPOOL")"

[ "$weight_rows" = 1 ] || fail "the dialog draws the weight box $weight_rows times, expected once"
[ "$weight_rows" = "$rows_on_a_spoolman_spool" ] ||
    fail "the weight box is drawn on a lane with no Spoolman spool, where the printer refuses it"

# The service worker only refetches a file whose revision string changed, and upstream lists this
# chunk with a null revision, meaning its contents can never change. A browser that already holds
# this build would go on drawing the box the printer refuses.
chunk_name="$(basename "$app_chunk")"
precache_entry="$(grep -oE "\{url:\"assets/$chunk_name\",revision:[^}]*\}" "$SERVICE_WORKER")"
case "$precache_entry" in
    '') fail "the app chunk is not in the service worker's precache list" ;;
    *'revision:null'*) fail "a browser holding the old app chunk would keep serving it" ;;
esac

[ "$failures" -eq 0 ]
