#!/bin/sh

BASE="/data/other_vol/xqext"
RUNTIME="/tmp/xqext"
LUCI_TARGET="/usr/lib/lua/luci"
WWW_TARGET="/www"
CORE_LUCI="$BASE/router-overlay/luci-upper"
CORE_WWW="$BASE/router-overlay/www-upper"
GENERATED="$BASE/runtime-generated"
LUCI_UPPER="$GENERATED/current/luci"
WWW_UPPER="$GENERATED/current/www"
LUCI_MERGED="$RUNTIME/merged/luci"
WWW_MERGED="$RUNTIME/merged/www"
LUCI_WORK="$BASE/runtime-work/luci"
WWW_WORK="$BASE/runtime-work/www"

log() {
    logger -t mwef "$*"
    printf '%s\n' "MWEF: $*"
}

plugin_directory() {
    value="$(sed -n '1p' "$BASE/config/plugin-directory" 2>/dev/null)"
    case "$value" in
        /data/*)
            case "$value" in *".."*|*"//"*|*[!A-Za-z0-9_./-]*) printf '%s\n' "$BASE/plugins" ;; *) printf '%s\n' "$value" ;; esac
            ;;
        *) printf '%s\n' "$BASE/plugins" ;;
    esac
}

build_layers() {
    plugin_dir="$(plugin_directory)"
    staging="$GENERATED/next-$$"
    previous="$GENERATED/previous"
    [ ! -e "$staging" ] || { log "generated staging path already exists"; return 1; }
    mkdir -p "$staging/luci" "$staging/www" "$plugin_dir" || return 1
    cp -a "$CORE_LUCI/." "$staging/luci/" || return 1
    cp -a "$CORE_WWW/." "$staging/www/" || return 1

    for plugin in "$plugin_dir"/*; do
        [ -d "$plugin" ] || continue
        [ -f "$plugin/.enabled" ] || continue
        id="${plugin##*/}"
        case "$id" in ""|*[!a-z0-9_-]*|[!a-z]*) log "ignoring invalid plugin directory: $id"; continue ;; esac
        if [ -d "$plugin/overlay/luci" ]; then
            cp -a "$plugin/overlay/luci/." "$staging/luci/" || return 1
        fi
        if [ -d "$plugin/overlay/www" ]; then
            cp -a "$plugin/overlay/www/." "$staging/www/" || return 1
        fi
        if [ -d "$plugin/i18n" ]; then
            mkdir -p "$staging/www/xqext/plugins/$id/i18n" || return 1
            cp -a "$plugin/i18n/." "$staging/www/xqext/plugins/$id/i18n/" || return 1
        fi
    done

    rm -rf "$previous"
    if [ -d "$GENERATED/current" ]; then mv "$GENERATED/current" "$previous" || return 1; fi
    mv "$staging" "$GENERATED/current" || return 1
    rm -rf "$previous" "$LUCI_WORK" "$WWW_WORK"
    log "generated plugin layers rebuilt"
}

is_mounted() {
    awk -v target="$1" '$2 == target { found = 1 } END { exit !found }' /proc/mounts
}

mount_overlay() {
    target="$1"
    upper="$2"
    work="$3"
    merged="$4"
    label="$5"

    if is_mounted "$target"; then
        if [ -f "$target/.xqext-overlay" ]; then
            log "$label overlay is already active"
            return 0
        fi
        log "$label target already has an unrelated mount; refusing to stack overlays"
        return 1
    fi

    [ -d "$target" ] || { log "$label target is missing: $target"; return 1; }
    [ -d "$upper" ] || { log "$label upper directory is missing: $upper"; return 1; }
    mkdir -p "$work" "$merged"

    if ! is_mounted "$merged"; then
        mount -t overlay overlay -o "lowerdir=$target,upperdir=$upper,workdir=$work" "$merged" || {
            log "failed to mount $label overlay"
            return 1
        }
    fi

    mount --bind "$merged" "$target" || {
        log "failed to bind $label overlay to $target"
        umount "$merged" 2>/dev/null
        return 1
    }
    log "$label overlay mounted"
}

unmount_overlay() {
    target="$1"
    merged="$2"
    label="$3"

    if is_mounted "$target"; then
        if [ -f "$target/.xqext-overlay" ]; then
            if umount "$target" 2>/dev/null; then
                log "$label bind mount removed"
            elif umount -l "$target" 2>/dev/null; then
                log "$label busy bind mount detached lazily"
            else
                log "$label bind mount could not be removed"
                return 1
            fi
        else
            log "$label target is owned by another mount; leaving it untouched"
            return 1
        fi
    fi
    if is_mounted "$merged"; then
        if umount "$merged" 2>/dev/null || umount -l "$merged" 2>/dev/null; then
            log "$label overlay removed"
        fi
    fi
}

start_xqext() {
    if is_mounted "$LUCI_TARGET" && is_mounted "$WWW_TARGET" \
        && [ -f "$LUCI_TARGET/.xqext-overlay" ] && [ -f "$WWW_TARGET/.xqext-overlay" ]; then
        log "MWEF overlays are already active"
        return 0
    fi
    build_layers || return 1
    mkdir -p "$RUNTIME/merged" "$BASE/runtime-work"
    mount_overlay "$LUCI_TARGET" "$LUCI_UPPER" "$LUCI_WORK" "$LUCI_MERGED" "LuCI" || return 1
    if ! mount_overlay "$WWW_TARGET" "$WWW_UPPER" "$WWW_WORK" "$WWW_MERGED" "WWW"; then
        unmount_overlay "$LUCI_TARGET" "$LUCI_MERGED" "LuCI"
        return 1
    fi
    # LuCI regenerates this disposable index on the next request.
    rm -f /tmp/luci-indexcache
    log "MiWiFi-Extension-Framework is ready"
}

stop_xqext() {
    unmount_overlay "$WWW_TARGET" "$WWW_MERGED" "WWW"
    unmount_overlay "$LUCI_TARGET" "$LUCI_MERGED" "LuCI"
    rm -f /tmp/luci-indexcache
    log "stopped"
}

case "${1:-start}" in
    start)
        start_xqext
        ;;
    stop)
        stop_xqext
        ;;
    restart)
        stop_xqext
        start_xqext
        ;;
    status)
        if is_mounted "$LUCI_TARGET" && is_mounted "$WWW_TARGET" \
            && [ -f "$LUCI_TARGET/.xqext-overlay" ] && [ -f "$WWW_TARGET/.xqext-overlay" ]; then
            printf '%s\n' "MWEF is active"
            exit 0
        fi
        printf '%s\n' "MWEF is inactive"
        exit 1
        ;;
    *)
        printf 'Usage: %s {start|stop|restart|status}\n' "$0" >&2
        exit 2
        ;;
esac
