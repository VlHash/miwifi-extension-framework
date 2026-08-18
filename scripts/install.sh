#!/bin/sh

BASE="/data/other_vol/xqext"
INIT="$BASE/scripts/xqext-init.sh"

if [ ! -f "$BASE/manifest.json" ] || [ ! -x "$INIT" ]; then
    printf '%s\n' "MWEF package is incomplete at $BASE" >&2
    exit 1
fi

mkdir -p "$BASE/config" "$BASE/plugins"
[ -f "$BASE/config/language" ] || printf '%s\n' "zh-CN" > "$BASE/config/language"
[ -f "$BASE/config/plugin-directory" ] || printf '%s\n' "$BASE/plugins" > "$BASE/config/plugin-directory"

plugin_dir="$(sed -n '1p' "$BASE/config/plugin-directory" 2>/dev/null)"
case "$plugin_dir" in
    /data/*) case "$plugin_dir" in *".."*|*"//"*|*[!A-Za-z0-9_./-]*) plugin_dir="$BASE/plugins" ;; esac ;;
    *) plugin_dir="$BASE/plugins" ;;
esac
mkdir -p "$plugin_dir/system"
cp -a "$BASE/builtin-plugins/system/." "$plugin_dir/system/"
touch "$plugin_dir/system/.builtin" "$plugin_dir/system/.enabled"
[ -f "$plugin_dir/system/.grants" ] || printf '%s\n' "system.read" > "$plugin_dir/system/.grants"

# Preserve legacy XQExt 0.1 files so they cannot register duplicate routes.
legacy="$BASE/migration-backup/xqext-0.1"
mkdir -p "$legacy"
for relative in \
    router-overlay/luci-upper/controller/api/xqext.lua \
    router-overlay/luci-upper/controller/web/xqext_status.lua \
    router-overlay/luci-upper/view/web/xqext/index.htm \
    router-overlay/www-upper/xqext/system.css \
    router-overlay/www-upper/xqext/system.js; do
    source="$BASE/$relative"
    if [ -f "$source" ]; then
        destination="$legacy/${relative##*/}"
        [ -e "$destination" ] || mv "$source" "$destination"
    fi
done

find "$BASE/router-overlay" "$BASE/builtin-plugins" -type d -exec chmod 755 {} \;
find "$BASE/router-overlay" "$BASE/builtin-plugins" -type f -exec chmod 644 {} \;
chmod 755 "$BASE/scripts/xqext-init.sh" "$BASE/scripts/mwef-pluginctl.sh" "$BASE/scripts/install.sh" "$BASE/scripts/uninstall.sh"

"$INIT" restart || exit 1

uci set firewall.xqext='include'
uci set firewall.xqext.type='script'
uci set firewall.xqext.path="$INIT"
uci set firewall.xqext.reload='1'
uci commit firewall

printf '%s\n' "MWEF installed. The XQExt compatibility path and firewall boot hook remain active without reloading the firewall."
