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

find "$BASE/router-overlay" "$BASE/builtin-plugins" -type d -exec chmod 755 {} \;
find "$BASE/router-overlay" "$BASE/builtin-plugins" -type f -exec chmod 644 {} \;

plugin_dir="$(sed -n '1p' "$BASE/config/plugin-directory" 2>/dev/null)"
case "$plugin_dir" in
    /data/*) case "$plugin_dir" in *".."*|*"//"*|*[!A-Za-z0-9_./-]*) plugin_dir="$BASE/plugins" ;; esac ;;
    *) plugin_dir="$BASE/plugins" ;;
esac
mkdir -p "$plugin_dir" || exit 1
install_builtin_plugin() {
    id="$1"
    shift
    source="$BASE/builtin-plugins/$id"
    target="$plugin_dir/$id"
    staging="$plugin_dir/.mwef-builtin-$id-$$"
    backup=""
    [ -d "$source" ] || return 1
    [ ! -e "$staging" ] || return 1
    mkdir -m 700 "$staging" || return 1
    cp -a "$source/." "$staging/" || { rm -rf "$staging"; return 1; }
    touch "$staging/.builtin" "$staging/.enabled" || { rm -rf "$staging"; return 1; }
    if [ -f "$target/.grants" ]; then
        cp "$target/.grants" "$staging/.grants" || { rm -rf "$staging"; return 1; }
    else
        : > "$staging/.grants" || { rm -rf "$staging"; return 1; }
        for grant in "$@"; do
            printf '%s\n' "$grant" >> "$staging/.grants" || { rm -rf "$staging"; return 1; }
        done
    fi
    find "$staging" -type d -exec chmod 755 {} \; || { rm -rf "$staging"; return 1; }
    find "$staging" -type f -exec chmod 644 {} \; || { rm -rf "$staging"; return 1; }
    chmod 644 "$staging/.builtin" "$staging/.enabled" "$staging/.grants" || { rm -rf "$staging"; return 1; }
    if [ -e "$target" ]; then
        mkdir -p "$plugin_dir/.recovery" || { rm -rf "$staging"; return 1; }
        backup="$plugin_dir/.recovery/$id-builtin-$(date +%Y%m%d-%H%M%S)-$$"
        mv "$target" "$backup" || { rm -rf "$staging"; return 1; }
    fi
    if ! mv "$staging" "$target"; then
        if [ -n "$backup" ] && ! mv "$backup" "$target" 2>/dev/null; then
            printf '%s\n' "MWEF: cannot activate $id or restore previous built-in; recovery copy: $backup" >&2
            rm -rf "$staging"
            return 1
        fi
        rm -rf "$staging"
        return 1
    fi
}

install_builtin_plugin system system.read || exit 1
install_builtin_plugin mwef-lib-packmanager \
    filesystem.read filesystem.write network.client shell.execute || exit 1

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

chmod 755 "$BASE/scripts/xqext-init.sh" "$BASE/scripts/mwef-pluginctl.sh" "$BASE/scripts/mwef-update.sh" "$BASE/scripts/install.sh" "$BASE/scripts/uninstall.sh"

"$INIT" restart || exit 1

uci set firewall.xqext='include'
uci set firewall.xqext.type='script'
uci set firewall.xqext.path="$INIT"
uci set firewall.xqext.reload='1'
uci commit firewall

printf '%s\n' "MWEF installed. The XQExt compatibility path and firewall boot hook remain active without reloading the firewall."
