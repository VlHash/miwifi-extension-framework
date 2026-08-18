#!/bin/sh

BASE="/data/other_vol/xqext"
INIT="$BASE/scripts/xqext-init.sh"

if [ -x "$INIT" ]; then
    "$INIT" stop
fi

uci -q delete firewall.xqext
uci commit firewall

timestamp="$(date +%Y%m%d-%H%M%S)"
disabled="/data/other_vol/xqext.disabled-$timestamp"
if [ -d "$BASE" ]; then
    mv "$BASE" "$disabled"
    printf '%s\n' "MWEF disabled and preserved at $disabled"
else
    printf '%s\n' "MWEF boot hook removed; package directory was already absent"
fi
