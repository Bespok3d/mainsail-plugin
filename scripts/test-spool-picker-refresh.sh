#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) 2026 unlucio and the Bespok3d contributors
# SPDX-License-Identifier: GPL-3.0-only
# A spool added in Spoolman while the page is open has to show in the lane's spool picker without
# reloading the page. Mainsail's own spool chooser reads Spoolman again each time it opens, so the
# Bespok3d patch that did the same from the lane's spool button only sent a second request. This
# runs against the bundle this plugin actually ships and proves the chooser still reads Spoolman as
# it opens, and that the lane's spool button does not read it a second time.
#
# The chooser only sees itself open because the lane keeps it drawn while it is closed and flips its
# dialog flag, so that is checked too. The app dispatches server/spoolman/refreshSpools only from
# inside the chooser, so one more dispatch of it is a second read. The anchors carry upstream's
# minified names, which change with every Mainsail build: a new Mainsail fails here until someone has
# checked this wiring again.
set -uo pipefail

PLUGIN_DIR="${1:?usage: test-spool-picker-refresh.sh <plugin-dir>}"

# shellcheck disable=SC2016 # the backticks and $store are JavaScript in the bundle, not shell
CHOOSER_READS_SPOOLMAN='refresh(){this.$store.dispatch(`server/spoolman/refreshSpools`)}close(){this.showDialog=!1}refreshSpools(){this.$store.dispatch(`server/spoolman/refreshSpools`)}customFilter(e,t,n){var r;if(t.trim().startsWith(`web+spoolman:s-`))'
# shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
CHOOSER_READS_SPOOLMAN_AS_IT_OPENS='onShowDialogChanged(e){e&&(this.refresh(),this.search=``)}};U([rt({type:Boolean})],eh.prototype,`showDialog`,void 0),U([R({required:!1,default:null})],eh.prototype,`tool`,void 0),U([R({required:!1,default:null})],eh.prototype,`afcLane`,void 0),U([R({required:!1,default:!0})],eh.prototype,`setActiveSpool`,void 0),U([B(`showDialog`)],eh.prototype,`onShowDialogChanged`,null)'
SPOOL_LIST_READ='server/spoolman/refreshSpools'
LANE_PICKER_IS_THE_CHOOSER='var th=window.b3dSpoolChooser=W(eh,'
LANE_KEEPS_THE_CHOOSER_DRAWN='e._v(e._s(e.spoolWeightsOutput))])])]),e.afcExistsSpoolman?t(th,{attrs:{"afc-lane":e.name},model:{value:e.showSpoolmanDialog,callback:function(t){e.showSpoolmanDialog=t}'
LANE_SPOOL_BUTTON_ONLY_OPENS_PICKER='onFilamentClick(){if(this.afcExistsSpoolman){this.showSpoolmanDialog=!0;return}'

# The chunk name carries upstream's content hash, so it is found by its stable prefix.
app_chunk="$(echo "$PLUGIN_DIR"/files/html/assets/index-*.js)"
[ -f "$app_chunk" ] || {
    echo "  FAIL: no app chunk in the vendored bundle" >&2
    exit 1
}

failures=0
spool_list_reads_in_the_chooser="$(grep -oF "$SPOOL_LIST_READ" <<<"$CHOOSER_READS_SPOOLMAN" | wc -l | tr -d ' ')"

fail() {
    echo "  FAIL: $1" >&2
    failures=$((failures + 1))
}

expect_in_app_chunk() {
    local expected_count="$1" bundle_text="$2" failure="$3"
    [ "$(grep -oF "$bundle_text" "$app_chunk" | wc -l | tr -d ' ')" = "$expected_count" ] || fail "$failure"
}

expect_in_app_chunk 1 "$CHOOSER_READS_SPOOLMAN" \
    "Mainsail's spool chooser no longer has its read of Spoolman; check this upstream code again"
expect_in_app_chunk 1 "$CHOOSER_READS_SPOOLMAN_AS_IT_OPENS" \
    "Mainsail's spool chooser no longer reads Spoolman as it opens; check this upstream code again"
expect_in_app_chunk 1 "$LANE_PICKER_IS_THE_CHOOSER" \
    "the lane's spool picker is no longer Mainsail's spool chooser, or the Bespok3d patch that shares it with the lane toolbar changed"
expect_in_app_chunk 1 "$LANE_KEEPS_THE_CHOOSER_DRAWN" \
    "the lane no longer keeps the spool chooser drawn while it is closed, so the chooser may not see itself open"
expect_in_app_chunk 1 "$LANE_SPOOL_BUTTON_ONLY_OPENS_PICKER" \
    "the lane's spool button does more than open the picker: a second read of Spoolman, or new upstream code to check again"
expect_in_app_chunk "$spool_list_reads_in_the_chooser" "$SPOOL_LIST_READ" \
    "the app's reads of Spoolman's spool list changed: a second read when the picker opens, or new upstream code to check again"

[ "$failures" -eq 0 ]
