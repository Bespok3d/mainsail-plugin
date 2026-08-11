#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) 2026 unlucio and the Bespok3d contributors
# SPDX-License-Identifier: GPL-3.0-only
# This plugin's own gate: it must pass from this repo's root, with no sibling repo cloned except
# lib_bespok3d. This repo ships config, assets and shell only, so its gate is the shared detectors.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The shared gate helpers and the detectors that enforce a workspace-wide rule live in one place.
# See lib_bespok3d/tooling/README.md. This is the only line that knows where they are.
B3D_TOOLING="${B3D_TOOLING:-$REPO_ROOT/lib_bespok3d/tooling}"
# lib_bespok3d is a submodule. A clone made without it leaves an empty directory here, so say what
# is actually wrong instead of letting every check below fail on a missing file.
if [ ! -f "$B3D_TOOLING/gate-lib.sh" ] || [ ! -f "$B3D_TOOLING/release-trigger-detector.mjs" ]; then
    echo "The shared gate helpers are missing or older than the checks this gate runs:" >&2
    echo "the lib_bespok3d submodule is not checked out, or is pinned to an older commit." >&2
    echo "Run this once from the repo root, then try again:" >&2
    echo "  git submodule sync --recursive && git submodule update --init --recursive" >&2
    echo "See CONTRIBUTING.md for the full environment setup." >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$B3D_TOOLING/gate-lib.sh"

cd "$REPO_ROOT" || exit 1

echo ""
echo "mainsail-plugin gate"

release_trigger_check "$REPO_ROOT"
workflow_pinning_check "$REPO_ROOT"
em_dash_check "$REPO_ROOT"
shellcheck_repo "$REPO_ROOT"
# The vendored bundle is upstream's build plus this plugin's own patches. Re-vendoring wipes the
# tree, so the gate proves every patch is still in it.
run_check "Bespok3d patches in the Mainsail bundle" \
    "$REPO_ROOT/mainsail/scripts/patch-mainsail.sh" --verify

# Mainsail serves its own nginx site, so it must include the directory where every other plugin
# drops its web location. Without the line, a printer running Mainsail on port 80 answers the
# remote screen and every other plugin endpoint with the Mainsail index page instead.
nginx_site_serves_plugin_endpoints() {
    grep -Fq 'include /userdata/bespok3d/etc/nginx/locations/*.conf;' "$1"
}

for plugin_name in mainsail mainsail-bleeding-edge; do
    # The shared shellcheck pass only sees names ending in .sh, and an init script the printer runs
    # has no extension, so it is linted here by name.
    run_check "shellcheck s90mainsail: $plugin_name" \
        shellcheck --shell=sh "$REPO_ROOT/$plugin_name/files/etc/init.d/s90mainsail"
    run_check "plugin endpoints: $plugin_name" \
        nginx_site_serves_plugin_endpoints "$REPO_ROOT/$plugin_name/files/nginx/mainsail.conf"
    # Only one interface can hold port 80. A printer that breaks the rule silently loses Fluidd or
    # Mainsail, so the start script is run against a fake nginx tree in both site shapes.
    run_check "port rule: $plugin_name" \
        bash "$REPO_ROOT/scripts/test-port-rule.sh" "$REPO_ROOT/$plugin_name"
done

gate_summary || exit 1
