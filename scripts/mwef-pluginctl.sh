#!/bin/sh

set -u

BASE="/data/other_vol/xqext"
INIT="$BASE/scripts/xqext-init.sh"
DEFAULT_PLUGIN_DIR="$BASE/plugins"

fail() {
    printf '%s\n' "MWEF: $*" >&2
    exit 1
}

valid_id() {
    case "$1" in
        ""|*[!a-z0-9_-]*|[!a-z]*) return 1 ;;
    esac
    [ "${#1}" -le 48 ]
}

valid_data_path() {
    case "$1" in
        /data/*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *".."*|*"//"*|*[!A-Za-z0-9_./-]*) return 1 ;;
    esac
}

repatch() {
    "$INIT" restart
}

inspect_package() {
    archive="$1"
    token="$2"
    case "$archive" in /tmp/mwef-upload-*.tar.gz) ;; *) fail "unexpected upload path" ;; esac
    case "$token" in *[!A-Fa-f0-9-]*|"") fail "invalid pending token" ;; esac
    pending="/tmp/mwef-pending-$token"
    listing="/tmp/mwef-list-$token"
    [ ! -e "$pending" ] || fail "pending token already exists"
    mkdir -m 700 "$pending" || fail "cannot create pending directory"
    tar -tzf "$archive" > "$listing" 2>/dev/null || fail "the file is not a readable tar.gz package"
    [ -s "$listing" ] || fail "the package is empty"
    if tar -tvzf "$archive" 2>/dev/null | grep -Eq '^[lh]'; then
        fail "symbolic and hard links are not allowed in a plugin package"
    fi
    while IFS= read -r entry; do
        case "$entry" in
            ""|/*|./*|*\\*|*"//"*) fail "unsafe archive entry: $entry" ;;
        esac
        printf '/%s/' "$entry" | grep -Eq '/\.\.?/' && fail "path traversal is not allowed: $entry"
        case "$entry" in
            overlay/luci/view/web/inc/header.htm|\
            overlay/luci/controller/api/mwef.lua|\
            overlay/luci/controller/web/xqext.lua|\
            overlay/luci/controller/web/mwef_manage.lua|\
            overlay/luci/view/web/xqext/nav.htm|\
            overlay/luci/view/web/xqext/framework.htm|\
            overlay/www/xqext/core.css|\
            overlay/www/xqext/framework.js|\
            overlay/www/xqext/i18n/*)
                fail "plugin package attempts to overwrite an MWEF core file: $entry"
                ;;
        esac
        case "$entry" in
            overlay/luci/|overlay/luci/controller/|overlay/luci/controller/api/|overlay/luci/controller/web/|overlay/luci/view/|overlay/luci/view/web/|overlay/luci/view/web/xqext/|\
            overlay/luci/controller/api/mwef_*.lua|overlay/luci/controller/web/mwef_*.lua|overlay/luci/view/web/xqext/*|\
            overlay/www/|overlay/www/xqext/|overlay/www/xqext/plugins/|overlay/www/xqext/plugins/*)
                ;;
            overlay/luci/*|overlay/www/*)
                fail "plugin files must stay inside MWEF controller, view and static namespaces: $entry"
                ;;
        esac
    done < "$listing"
    tar -xzf "$archive" -C "$pending" 2>/dev/null || fail "package extraction failed"
    rm -f "$listing" "$archive"
    if find "$pending" \( -type l -o -type b -o -type c -o -type p -o -type s \) | grep -q .; then
        fail "links and special files are not allowed in a plugin package"
    fi
    [ -f "$pending/mwef-plugin.json" ] || fail "mwef-plugin.json must be at the package root"
    chmod -R go-w "$pending"
    printf '%s\n' "MWEF: package staged"
}

discard_pending() {
    token="$1"
    case "$token" in *[!A-Fa-f0-9-]*|"") fail "invalid pending token" ;; esac
    pending="/tmp/mwef-pending-$token"
    archive="/tmp/mwef-upload-$token.tar.gz"
    [ ! -d "$pending" ] || rm -rf "$pending"
    rm -f "$archive" "/tmp/mwef-list-$token"
}

write_grants() {
    target="$1"
    grants="$2"
    : > "$target/.grants" || return 1
    old_ifs="$IFS"
    IFS=','
    for permission in $grants; do
        case "$permission" in
            system.read|filesystem.read|filesystem.write|network.client|service.control|shell.execute)
                printf '%s\n' "$permission" >> "$target/.grants" || return 1
                ;;
            "") ;;
            *) return 1 ;;
        esac
    done
    IFS="$old_ifs"
}

install_pending() {
    token="$1"
    plugin_dir="$2"
    id="$3"
    grants="$4"
    valid_data_path "$plugin_dir" || fail "unsafe plugin directory"
    valid_id "$id" || fail "invalid plugin id"
    pending="/tmp/mwef-pending-$token"
    [ -f "$pending/mwef-plugin.json" ] || fail "pending package has expired"
    mkdir -p "$plugin_dir/.recovery" || fail "cannot prepare plugin directory"
    staging="$plugin_dir/.mwef-install-$id-$$"
    target="$plugin_dir/$id"
    [ ! -e "$staging" ] || fail "staging path already exists"
    mkdir -m 700 "$staging" || fail "cannot create install staging directory"
    cp -a "$pending/." "$staging/" || fail "cannot copy staged plugin"
    write_grants "$staging" "$grants" || fail "invalid permission grant"
    touch "$staging/.enabled"
    chmod -R go-w "$staging"
    backup=""
    if [ -d "$target" ]; then
        backup="$plugin_dir/.recovery/$id-$(date +%Y%m%d-%H%M%S)"
        mv "$target" "$backup" || fail "cannot preserve previous plugin version"
    fi
    mv "$staging" "$target" || fail "cannot activate plugin"
    rm -rf "$pending"
    if ! repatch; then
        failed="$plugin_dir/.recovery/$id-failed-$(date +%Y%m%d-%H%M%S)"
        mv "$target" "$failed" 2>/dev/null
        [ -z "$backup" ] || mv "$backup" "$target" 2>/dev/null
        repatch >/dev/null 2>&1 || true
        fail "repatch failed; the previous version was restored"
    fi
}

plugin_action() {
    action="$1"
    plugin_dir="$2"
    id="$3"
    argument="${4:-}"
    valid_data_path "$plugin_dir" || fail "unsafe plugin directory"
    valid_id "$id" || fail "invalid plugin id"
    target="$plugin_dir/$id"
    [ -d "$target" ] || fail "plugin not found"
    case "$action" in
        enable)
            touch "$target/.enabled" || fail "cannot enable plugin"
            repatch
            ;;
        disable)
            [ "$id" != "system" ] || fail "the system plugin is protected"
            rm -f "$target/.enabled"
            repatch
            ;;
        remove)
            [ "$id" != "system" ] || fail "the system plugin is protected"
            mkdir -p "$plugin_dir/.recovery" || fail "cannot prepare recovery directory"
            mv "$target" "$plugin_dir/.recovery/$id-removed-$(date +%Y%m%d-%H%M%S)" || fail "cannot preserve removed plugin"
            repatch
            ;;
        permissions)
            write_grants "$target" "$argument" || fail "invalid permission grant"
            ;;
        *) fail "unknown plugin action" ;;
    esac
}

copy_directory() {
    source="$1"
    destination="$2"
    valid_data_path "$source" || fail "unsafe source directory"
    valid_data_path "$destination" || fail "unsafe destination directory"
    mkdir -p "$destination" || fail "cannot create destination directory"
    if [ -d "$source" ]; then
        cp -a "$source/." "$destination/" || fail "cannot copy installed plugins"
    fi
}

run_hook() {
    plugin_dir="$1"
    id="$2"
    hook="$3"
    valid_data_path "$plugin_dir" || fail "unsafe plugin directory"
    valid_id "$id" || fail "invalid plugin id"
    case "$hook" in scripts/[A-Za-z0-9_.-]*.sh) ;; *) fail "invalid hook path" ;; esac
    target="$plugin_dir/$id"
    grep -Fxq 'shell.execute' "$target/.grants" 2>/dev/null || fail "shell.execute permission has not been granted"
    [ -f "$target/$hook" ] || fail "hook not found"
    chmod 700 "$target/$hook"
    MWEF_PLUGIN_ID="$id" MWEF_PLUGIN_ROOT="$target" /bin/sh "$target/$hook"
}

case "${1:-}" in
    inspect) [ "$#" -eq 3 ] || fail "inspect requires archive and token"; inspect_package "$2" "$3" ;;
    discard) [ "$#" -eq 2 ] || fail "discard requires token"; discard_pending "$2" ;;
    install) [ "$#" -eq 5 ] || fail "install requires token, directory, id and grants"; install_pending "$2" "$3" "$4" "$5" ;;
    enable|disable|remove|permissions) [ "$#" -ge 4 ] || fail "$1 requires directory and id"; plugin_action "$1" "$2" "$3" "${4:-}" ;;
    copy-directory) [ "$#" -eq 3 ] || fail "copy-directory requires two paths"; copy_directory "$2" "$3" ;;
    repatch) repatch ;;
    run-hook) [ "$#" -eq 4 ] || fail "run-hook requires directory, id and hook"; run_hook "$2" "$3" "$4" ;;
    *) fail "usage: $0 {inspect|discard|install|enable|disable|remove|permissions|copy-directory|repatch|run-hook}" ;;
esac
