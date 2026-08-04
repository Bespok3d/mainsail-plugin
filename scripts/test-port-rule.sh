#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) 2026 unlucio and the Bespok3d contributors
# SPDX-License-Identifier: GPL-3.0-only
# The port rule: whichever web interface is set to 80 holds it, and the other one moves to 81. nginx
# drops a second server block on a port that already has a default server, so a printer that breaks
# this rule loses one of its two interfaces with no error the user ever sees. This test runs the
# plugin's own start script against a fake nginx tree, in both shapes the stock Fluidd site comes in.
set -uo pipefail

PLUGIN_DIR="${1:?usage: test-port-rule.sh <plugin-dir>}"
START_SCRIPT="$PLUGIN_DIR/files/etc/init.d/s90mainsail"
NGINX_TEMPLATE="$PLUGIN_DIR/files/nginx/mainsail.conf"

failures=0

fail() {
    echo "  FAIL: $1" >&2
    failures=$((failures + 1))
}

stock_fluidd_site() {
    cat <<'SITE'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    root /home/lava/fluidd;
}
SITE
}

# The tree a printer has: a fake nginx on PATH so the script's reload is a no-op, the conf.d the
# Mainsail block is written into, and the Fluidd site in the shape this case is testing.
build_nginx_tree() {
    tree_root="$1"
    enabled_shape="$2"
    mkdir -p "$tree_root/bin" "$tree_root/conf.d" "$tree_root/sites-available" "$tree_root/sites-enabled"
    printf '#!/bin/sh\nexit 0\n' > "$tree_root/bin/nginx"
    chmod +x "$tree_root/bin/nginx"
    stock_fluidd_site > "$tree_root/sites-available/fluidd"
    echo "$enabled_shape" > "$tree_root/shape"
    if [ "$enabled_shape" = symlink ]; then
        ln -sf ../sites-available/fluidd "$tree_root/sites-enabled/fluidd"
        return 0
    fi
    stock_fluidd_site > "$tree_root/sites-enabled/fluidd"
}

run_start_script() {
    tree_root="$1"
    shift
    NGINX_TMPL="$NGINX_TEMPLATE" \
    NGINX_CONF="$tree_root/conf.d/mainsail.conf" \
    FLUIDD_SITE="$tree_root/sites-enabled/fluidd" \
    PATH="$tree_root/bin:$PATH" \
        sh "$START_SCRIPT" "$@" > /dev/null
}

expect_fluidd_port() {
    tree_root="$1"
    expected_port="$2"
    what_ran="$3"
    served_site="$(readlink -f "$tree_root/sites-enabled/fluidd")"
    grep -q "^    listen ${expected_port};$" "$served_site" || fail "$what_ran: Fluidd ipv4 is not on $expected_port"
    grep -q "^    listen \[::\]:${expected_port};$" "$served_site" || fail "$what_ran: Fluidd ipv6 is not on $expected_port"
    # A printer whose site is the stock symlink must still have the symlink afterwards: turning it
    # into a plain file is how the two copies drift apart and the one nginx serves stops being the
    # one the port was written into.
    if [ "$(cat "$tree_root/shape")" = symlink ] && [ ! -L "$tree_root/sites-enabled/fluidd" ]; then
        fail "$what_ran: the stock symlink was replaced by a plain file"
    fi
}

expect_mainsail_port() {
    grep -q "^    listen ${2};$" "$1/conf.d/mainsail.conf" || fail "$3: Mainsail is not on $2"
}

# Mainsail takes 80, so Fluidd moves to 81 and both interfaces answer.
test_mainsail_primary() {
    tree_root="$1"
    run_start_script "$tree_root" start 80
    expect_mainsail_port "$tree_root" 80 "Mainsail primary"
    expect_fluidd_port "$tree_root" 81 "Mainsail primary"
}

# Mainsail leaves 80 while it stays installed. Port 80 goes back to Fluidd; before this fix nothing
# gave it back, both blocks sat on 81 and the printer served nothing on 80 at all.
test_mainsail_leaves_primary() {
    tree_root="$1"
    run_start_script "$tree_root" start 80
    run_start_script "$tree_root" start 81
    expect_mainsail_port "$tree_root" 81 "Mainsail off 80"
    expect_fluidd_port "$tree_root" 80 "Mainsail off 80"
}

test_uninstall_restores_fluidd() {
    tree_root="$1"
    run_start_script "$tree_root" start 80
    run_start_script "$tree_root" stop
    expect_fluidd_port "$tree_root" 80 "Mainsail removed"
    [ ! -f "$tree_root/conf.d/mainsail.conf" ] || fail "Mainsail removed: its nginx config is still there"
}

for enabled_shape in symlink plain-file; do
    echo "  Fluidd site as a $enabled_shape"
    for one_test in test_mainsail_primary test_mainsail_leaves_primary test_uninstall_restores_fluidd; do
        case_root="$(mktemp -d)"
        build_nginx_tree "$case_root" "$enabled_shape"
        "$one_test" "$case_root"
        rm -rf "$case_root"
    done
done

[ "$failures" -eq 0 ]
