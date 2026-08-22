#!/bin/sh

set -u

BASE="/data/other_vol/xqext"
INIT="$BASE/scripts/xqext-init.sh"
DEFAULT_PLUGIN_DIR="$BASE/plugins"
LOCK_DIR="/tmp/mwef-transaction.lock"
ACTIVE_STAGING=""
ACTIVE_LISTING=""

release_lock() {
    if [ -n "${LOCK_HELD:-}" ]; then
        rm -f "$LOCK_DIR/pid"
        rmdir "$LOCK_DIR" 2>/dev/null || true
        LOCK_HELD=""
    fi
}

cleanup() {
    if [ -n "$ACTIVE_STAGING" ] && [ -d "$ACTIVE_STAGING" ]; then
        rm -rf "$ACTIVE_STAGING"
    fi
    if [ -n "$ACTIVE_LISTING" ]; then
        rm -f "$ACTIVE_LISTING"
    fi
    release_lock
}

fail() {
    cleanup
    printf '%s\n' "MWEF: $*" >&2
    exit 1
}

acquire_lock() {
    local attempts owner
    attempts=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            rm -f "$LOCK_DIR/pid"
            rmdir "$LOCK_DIR" 2>/dev/null || true
            continue
        fi
        if [ -z "$owner" ] && [ "$attempts" -gt 0 ]; then
            if rmdir "$LOCK_DIR" 2>/dev/null; then
                continue
            fi
        fi
        attempts=$((attempts + 1))
        [ "$attempts" -lt 50 ] || fail "another framework or plugin operation is still running"
        sleep 1
    done
    LOCK_HELD=1
    printf '%s\n' "$$" > "$LOCK_DIR/pid" || fail "cannot record transaction lock"
    trap 'cleanup; exit 1' HUP INT TERM
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

validate_luci_conflicts_locked() {
    local pending plugin_dir id listing relative plugin_path other_id
    pending="$1"
    plugin_dir="$2"
    id="$3"
    [ -d "$pending/overlay/luci" ] || return 0
    listing="/tmp/mwef-conflicts-$$"
    ACTIVE_LISTING="$listing"
    find "$pending/overlay/luci" -type f | sed "s|^$pending/overlay/luci/||" > "$listing" \
        || fail "cannot enumerate plugin LuCI files"
    while IFS= read -r relative; do
        [ ! -f "$BASE/router-overlay/luci-upper/$relative" ] \
            || fail "plugin LuCI path conflicts with framework core: overlay/luci/$relative"
        for plugin_path in "$plugin_dir"/*; do
            [ -d "$plugin_path" ] || continue
            other_id="${plugin_path##*/}"
            [ "$other_id" = "$id" ] && continue
            valid_id "$other_id" || continue
            [ ! -f "$plugin_path/overlay/luci/$relative" ] \
                || fail "plugin LuCI path conflicts with $other_id: overlay/luci/$relative"
        done
    done < "$listing"
    rm -f "$listing"
    ACTIVE_LISTING=""
}

inspect_package() {
    local archive token pending listing entry expanded_size entry_count
    archive="$1"
    token="$2"
    case "$archive" in /tmp/mwef-upload-*.tar.gz) ;; *) fail "unexpected upload path" ;; esac
    case "$token" in *[!A-Fa-f0-9-]*|"") fail "invalid pending token" ;; esac
    pending="/tmp/mwef-pending-$token"
    listing="/tmp/mwef-list-$token"
    [ ! -e "$pending" ] || fail "pending token already exists"
    mkdir -m 700 "$pending" || fail "cannot create pending directory"
    ACTIVE_STAGING="$pending"
    command -v gzip >/dev/null 2>&1 || fail "gzip is required to inspect plugin packages"
    command -v head >/dev/null 2>&1 || fail "head is required to inspect plugin packages"
    expanded_size="$(gzip -dc "$archive" 2>/dev/null | head -c 67108865 | wc -c | tr -d '[:space:]')"
    case "$expanded_size" in ""|*[!0-9]*) fail "cannot determine expanded package size" ;; esac
    [ "$expanded_size" -le 67108864 ] || fail "expanded plugin package exceeds 64 MiB"
    ACTIVE_LISTING="$listing"
    tar -tzf "$archive" > "$listing" 2>/dev/null || fail "the file is not a readable tar.gz package"
    [ -s "$listing" ] || fail "the package is empty"
    entry_count="$(wc -l < "$listing" 2>/dev/null | tr -d '[:space:]')"
    case "$entry_count" in ""|*[!0-9]*) fail "cannot determine package entry count" ;; esac
    [ "$entry_count" -le 2048 ] || fail "plugin package contains too many entries"
    if tar -tvzf "$archive" 2>/dev/null | grep -Eq '^[^d-]'; then
        fail "only regular files and directories are allowed in a plugin package"
    fi
    while IFS= read -r entry; do
        case "$entry" in
            ""|/*|./*|*\\*|*"//"*|*[!A-Za-z0-9_./-]*) fail "unsafe archive entry: $entry" ;;
        esac
        printf '/%s/' "$entry" | grep -Eq '/\.\.?/' && fail "path traversal is not allowed: $entry"
        case "$entry" in
            .builtin|.builtin/*|.enabled|.enabled/*|.grants|.grants/*|.grants.*|.recovery|.recovery/*|.mwef-*)
                fail "plugin package contains a reserved framework state file: $entry"
                ;;
        esac
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
    ACTIVE_LISTING=""
    if find "$pending" \( -type l -o -type b -o -type c -o -type p -o -type s \) | grep -q .; then
        fail "links and special files are not allowed in a plugin package"
    fi
    [ -f "$pending/mwef-plugin.json" ] || fail "mwef-plugin.json must be at the package root"
    chmod -R go-w "$pending"
    ACTIVE_STAGING=""
    printf '%s\n' "MWEF: package staged"
}

discard_pending() {
    local token pending archive
    token="$1"
    case "$token" in *[!A-Fa-f0-9-]*|"") fail "invalid pending token" ;; esac
    pending="/tmp/mwef-pending-$token"
    archive="/tmp/mwef-upload-$token.tar.gz"
    [ ! -d "$pending" ] || rm -rf "$pending"
    rm -f "$archive" "/tmp/mwef-list-$token"
}

write_grants() {
    local grants_target grants_value grants_temp old_ifs permission
    grants_target="$1"
    grants_value="$2"
    grants_temp="$grants_target/.grants.$$"
    : > "$grants_temp" || return 1
    old_ifs="$IFS"
    IFS=','
    for permission in $grants_value; do
        case "$permission" in
            system.read|filesystem.read|filesystem.write|network.client|service.control|shell.execute)
                printf '%s\n' "$permission" >> "$grants_temp" || { rm -f "$grants_temp"; IFS="$old_ifs"; return 1; }
                ;;
            "") ;;
            *) rm -f "$grants_temp"; IFS="$old_ifs"; return 1 ;;
        esac
    done
    IFS="$old_ifs"
    mv "$grants_temp" "$grants_target/.grants" || { rm -f "$grants_temp"; return 1; }
}

install_pending() {
    local token plugin_dir id grants pending staging target backup failed
    token="$1"
    plugin_dir="$2"
    id="$3"
    grants="$4"
    valid_data_path "$plugin_dir" || fail "unsafe plugin directory"
    valid_id "$id" || fail "invalid plugin id"
    pending="/tmp/mwef-pending-$token"
    [ -f "$pending/mwef-plugin.json" ] || fail "pending package has expired"
    acquire_lock
    mkdir -p "$plugin_dir/.recovery" || fail "cannot prepare plugin directory"
    validate_luci_conflicts_locked "$pending" "$plugin_dir" "$id"
    staging="$plugin_dir/.mwef-install-$id-$$"
    ACTIVE_STAGING="$staging"
    target="$plugin_dir/$id"
    [ ! -e "$staging" ] || fail "staging path already exists"
    mkdir -m 700 "$staging" || fail "cannot create install staging directory"
    cp -a "$pending/." "$staging/" || fail "cannot copy staged plugin"
    rm -rf "$staging/.builtin" "$staging/.enabled" "$staging/.grants" "$staging/.recovery"
    for reserved in "$staging"/.grants.* "$staging"/.mwef-*; do
        [ ! -e "$reserved" ] || rm -rf "$reserved"
    done
    write_grants "$staging" "$grants" || fail "invalid permission grant"
    touch "$staging/.enabled"
    chmod -R go-w "$staging"
    backup=""
    if [ -d "$target" ]; then
        backup="$plugin_dir/.recovery/$id-$(date +%Y%m%d-%H%M%S)-$$"
        [ ! -e "$backup" ] || fail "recovery path already exists: $backup"
        mv "$target" "$backup" || fail "cannot preserve previous plugin version"
    fi
    if ! mv "$staging" "$target"; then
        if [ -n "$backup" ] && ! mv "$backup" "$target"; then
            fail "cannot activate plugin or restore previous version; recovery copy: $backup"
        fi
        fail "cannot activate plugin; the previous version was restored"
    fi
    ACTIVE_STAGING=""
    rm -rf "$pending"
    if ! repatch; then
        failed="$plugin_dir/.recovery/$id-failed-$(date +%Y%m%d-%H%M%S)-$$"
        [ ! -e "$failed" ] || fail "failed-plugin recovery path already exists: $failed"
        if ! mv "$target" "$failed" 2>/dev/null; then
            fail "repatch failed and the failed plugin could not be preserved"
        fi
        if [ -n "$backup" ]; then
            if ! mv "$backup" "$target" 2>/dev/null; then
                fail "repatch failed and the previous version remains at $backup"
            fi
            repatch >/dev/null 2>&1 || fail "the previous plugin was restored but repatch still failed"
            fail "repatch failed; the previous version was restored"
        fi
        repatch >/dev/null 2>&1 || true
        fail "repatch failed; the new plugin was moved to $failed"
    fi
    release_lock
}

plugin_action() {
    local action plugin_dir id argument target removed
    action="$1"
    plugin_dir="$2"
    id="$3"
    argument="${4:-}"
    valid_data_path "$plugin_dir" || fail "unsafe plugin directory"
    valid_id "$id" || fail "invalid plugin id"
    target="$plugin_dir/$id"
    [ -d "$target" ] || fail "plugin not found"
    acquire_lock
    case "$action" in
        enable)
            touch "$target/.enabled" || fail "cannot enable plugin"
            repatch
            ;;
        disable)
            [ ! -f "$target/.builtin" ] || fail "built-in plugins cannot be disabled"
            rm -f "$target/.enabled"
            repatch
            ;;
        remove)
            [ ! -f "$target/.builtin" ] || fail "built-in plugins cannot be removed"
            mkdir -p "$plugin_dir/.recovery" || fail "cannot prepare recovery directory"
            removed="$plugin_dir/.recovery/$id-removed-$(date +%Y%m%d-%H%M%S)-$$"
            [ ! -e "$removed" ] || fail "removed-plugin recovery path already exists: $removed"
            mv "$target" "$removed" || fail "cannot preserve removed plugin"
            repatch
            ;;
        permissions)
            write_grants "$target" "$argument" || fail "invalid permission grant"
            ;;
        *) fail "unknown plugin action" ;;
    esac
    release_lock
}

copy_directory() {
    local source destination
    source="$1"
    destination="$2"
    valid_data_path "$source" || fail "unsafe source directory"
    valid_data_path "$destination" || fail "unsafe destination directory"
    acquire_lock
    mkdir -p "$destination" || fail "cannot create destination directory"
    if [ -d "$source" ]; then
        cp -a "$source/." "$destination/" || fail "cannot copy installed plugins"
    fi
    release_lock
}

run_hook() {
    local plugin_dir id hook target
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
