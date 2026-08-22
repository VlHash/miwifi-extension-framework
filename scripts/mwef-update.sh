#!/bin/sh

set -u

BASE="/data/other_vol/xqext"
DATA_ROOT="/data/other_vol"
UPDATE_LOCK="/tmp/mwef-transaction.lock"
MANIFEST_FILE="/tmp/mwef-framework-update.json"
MAX_ARCHIVE_SIZE=16777216
MAX_MANIFEST_SIZE=65536
ACTIVE_STAGING=""

release_lock() {
    if [ -n "${LOCK_HELD:-}" ]; then
        rm -f "$UPDATE_LOCK/pid"
        rmdir "$UPDATE_LOCK" 2>/dev/null || true
        LOCK_HELD=""
    fi
}

cleanup() {
    if [ -n "$ACTIVE_STAGING" ] && [ -d "$ACTIVE_STAGING" ]; then
        rm -rf "$ACTIVE_STAGING"
    fi
    release_lock
}

fail() {
    cleanup
    printf '%s\n' "MWEF update: $*" >&2
    exit 1
}

valid_token() {
    case "$1" in
        ""|*[!A-Fa-f0-9-]*) return 1 ;;
    esac
    [ "${#1}" -le 80 ]
}

valid_version() {
    case "$1" in
        ""|*[!0-9A-Za-z.-]*|.*|*..*|*.) return 1 ;;
    esac
    [ "${#1}" -le 32 ]
}

file_size() {
    wc -c < "$1" 2>/dev/null | tr -d '[:space:]'
}

file_sha256() {
    sha256sum "$1" 2>/dev/null | sed -n 's/[[:space:]].*$//p' | tr 'A-F' 'a-f'
}

acquire_lock() {
    local owner
    if mkdir "$UPDATE_LOCK" 2>/dev/null; then
        :
    else
        owner="$(cat "$UPDATE_LOCK/pid" 2>/dev/null || true)"
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            rm -f "$UPDATE_LOCK/pid"
            rmdir "$UPDATE_LOCK" 2>/dev/null || true
        fi
        mkdir "$UPDATE_LOCK" 2>/dev/null || fail "another framework or plugin operation is still running"
    fi
    LOCK_HELD=1
    printf '%s\n' "$$" > "$UPDATE_LOCK/pid" || fail "cannot record the update lock"
    trap 'cleanup; exit 1' HUP INT TERM
}

valid_manifest_url() {
    case "$1" in
        https://raw.githubusercontent.com/VlHash/miwifi-extension-framework/plugins/framework.json|\
        https://testingcf.jsdelivr.net/gh/VlHash/miwifi-extension-framework@plugins/framework.json)
            return 0
            ;;
    esac
    return 1
}

valid_archive_url() {
    printf '%s\n' "$1" | grep -Eq '^https://github\.com/VlHash/miwifi-extension-framework/releases/download/v[0-9A-Za-z.-]+/mwef-[0-9A-Za-z.-]+\.tar\.gz$' && return 0
    printf '%s\n' "$1" | grep -Eq '^https://ghfast\.top/https://github\.com/VlHash/miwifi-extension-framework/releases/download/v[0-9A-Za-z.-]+/mwef-[0-9A-Za-z.-]+\.tar\.gz$'
}

download_file() {
    local url destination limit
    url="$1"
    destination="$2"
    limit="$3"
    command -v curl >/dev/null 2>&1 || fail "curl is required for online updates"
    rm -f "$destination"
    curl -kfsSL --connect-timeout 20 --max-time 180 --max-filesize "$limit" -o "$destination" "$url" || {
        rm -f "$destination"
        return 1
    }
    [ -f "$destination" ] || return 1
    [ "$(file_size "$destination")" -le "$limit" ] || {
        rm -f "$destination"
        return 1
    }
}

fetch_manifest() {
    local url temporary
    url="$1"
    valid_manifest_url "$url" || fail "untrusted update manifest URL"
    temporary="$MANIFEST_FILE.$$"
    download_file "$url" "$temporary" "$MAX_MANIFEST_SIZE" || fail "cannot download the update manifest"
    mv "$temporary" "$MANIFEST_FILE" || fail "cannot publish the update manifest"
    chmod 600 "$MANIFEST_FILE"
    printf '%s\n' "MWEF update: manifest downloaded"
}

validate_archive_entry() {
    local entry
    entry="$1"
    case "$entry" in
        ""|/*|./*|*\\*|*"//"*) fail "unsafe archive entry: $entry" ;;
    esac
    printf '/%s/' "$entry" | grep -Eq '/\.\.?/' && fail "path traversal is not allowed: $entry"
    case "$entry" in
        router-overlay|router-overlay/*|\
        builtin-plugins|builtin-plugins/*|\
        scripts|scripts/*|\
        docs|docs/*|\
        schema|schema/*|\
        examples|examples/*|\
        tools|tools/*|\
        manifest.json|README.md|README_CN.md|build.sh|LICENSE)
            ;;
        *) fail "unexpected framework archive entry: $entry" ;;
    esac
}

inspect_archive() {
    local archive token expected_sha expected_size pending listing entry actual_size actual_sha version
    archive="$1"
    token="$2"
    expected_sha="$3"
    expected_size="$4"
    valid_token "$token" || fail "invalid pending token"
    case "$archive" in
        /tmp/mwef-framework-upload-*.tar.gz|/tmp/mwef-framework-online-*.tar.gz) ;;
        *) fail "unexpected framework archive path" ;;
    esac
    [ -f "$archive" ] || fail "framework archive is missing"
    actual_size="$(file_size "$archive")"
    case "$actual_size" in ""|*[!0-9]*) fail "cannot determine archive size" ;; esac
    [ "$actual_size" -gt 0 ] && [ "$actual_size" -le "$MAX_ARCHIVE_SIZE" ] || fail "framework archive is empty or exceeds 16 MiB"
    if [ -n "$expected_size" ]; then
        case "$expected_size" in *[!0-9]*|"") fail "invalid expected archive size" ;; esac
        [ "$actual_size" -eq "$expected_size" ] || fail "framework archive size does not match the update manifest"
    fi
    actual_sha="$(file_sha256 "$archive")"
    [ "${#actual_sha}" -eq 64 ] || fail "cannot calculate archive SHA-256"
    if [ -n "$expected_sha" ]; then
        expected_sha="$(printf '%s' "$expected_sha" | tr 'A-F' 'a-f')"
        case "$expected_sha" in *[!a-f0-9]*|"") fail "invalid expected SHA-256" ;; esac
        [ "${#expected_sha}" -eq 64 ] || fail "invalid expected SHA-256"
        [ "$actual_sha" = "$expected_sha" ] || fail "framework archive SHA-256 mismatch"
    fi

    pending="$DATA_ROOT/.mwef-framework-pending-$token"
    listing="/tmp/mwef-framework-list-$token"
    [ ! -e "$pending" ] || fail "pending token already exists"
    mkdir -m 700 "$pending" || fail "cannot create framework staging directory"
    ACTIVE_STAGING="$pending"
    tar -tzf "$archive" > "$listing" 2>/dev/null || fail "the file is not a readable tar.gz archive"
    [ -s "$listing" ] || fail "the framework archive is empty"
    if tar -tvzf "$archive" 2>/dev/null | grep -Eq '^[lh]'; then
        fail "symbolic and hard links are not allowed in a framework archive"
    fi
    while IFS= read -r entry; do
        validate_archive_entry "$entry"
    done < "$listing"
    tar -xzf "$archive" -C "$pending" 2>/dev/null || fail "framework archive extraction failed"
    rm -f "$listing" "$archive"
    if find "$pending" \( -type l -o -type b -o -type c -o -type p -o -type s \) | grep -q .; then
        fail "links and special files are not allowed in a framework archive"
    fi
    [ -f "$pending/manifest.json" ] || fail "manifest.json must be at the framework archive root"
    [ -f "$pending/router-overlay/luci-upper/controller/api/mwef.lua" ] || fail "framework API is missing"
    [ -f "$pending/router-overlay/www-upper/xqext/framework.js" ] || fail "framework UI is missing"
    [ -f "$pending/scripts/install.sh" ] || fail "framework installer is missing"
    [ -f "$pending/scripts/xqext-init.sh" ] || fail "framework overlay helper is missing"
    [ -f "$pending/scripts/mwef-update.sh" ] || fail "framework update helper is missing"
    grep -Eq '"id"[[:space:]]*:[[:space:]]*"mwef"' "$pending/manifest.json" || fail "archive is not an MWEF framework release"
    grep -Eq '"author"[[:space:]]*:[[:space:]]*"VlHash"' "$pending/manifest.json" || fail "framework author is invalid"
    version="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pending/manifest.json" | sed -n '1p')"
    valid_version "$version" || fail "framework version is invalid"
    printf '%s\n%s\n%s\n' "$version" "$actual_sha" "$actual_size" > "$pending/.mwef-package-info"
    chmod -R go-w "$pending"
    chmod 755 "$pending/scripts/install.sh" "$pending/scripts/xqext-init.sh" "$pending/scripts/mwef-pluginctl.sh" "$pending/scripts/mwef-update.sh"
    ACTIVE_STAGING=""
    printf '%s\n' "MWEF update: framework package staged"
}

download_archive() {
    local url sha size token archive
    url="$1"
    sha="$2"
    size="$3"
    token="$4"
    valid_archive_url "$url" || fail "untrusted framework archive URL"
    valid_token "$token" || fail "invalid pending token"
    case "$size" in ""|*[!0-9]*) fail "invalid framework archive size" ;; esac
    [ "$size" -gt 0 ] && [ "$size" -le "$MAX_ARCHIVE_SIZE" ] || fail "framework archive exceeds 16 MiB"
    archive="/tmp/mwef-framework-online-$token.tar.gz"
    download_file "$url" "$archive" "$MAX_ARCHIVE_SIZE" || fail "cannot download the framework archive"
    inspect_archive "$archive" "$token" "$sha" "$size"
}

discard_pending() {
    local token pending
    token="$1"
    valid_token "$token" || fail "invalid pending token"
    pending="$DATA_ROOT/.mwef-framework-pending-$token"
    [ ! -d "$pending" ] || rm -rf "$pending"
    rm -f "/tmp/mwef-framework-upload-$token.tar.gz" "/tmp/mwef-framework-online-$token.tar.gz" "/tmp/mwef-framework-list-$token"
}

restore_persistent_data() {
    local source destination item
    source="$1"
    destination="$2"
    for item in config plugins migration-backup; do
        if [ -e "$source/$item" ]; then
            [ ! -e "$destination/$item" ] || rm -rf "$destination/$item"
            mv "$source/$item" "$destination/$item" || return 1
        fi
    done
}

apply_pending() {
    local token pending info version old_version stamp backup failed recovery_root
    token="$1"
    valid_token "$token" || fail "invalid pending token"
    pending="$DATA_ROOT/.mwef-framework-pending-$token"
    info="$pending/.mwef-package-info"
    [ -f "$info" ] || fail "pending framework package has expired"
    version="$(sed -n '1p' "$info")"
    valid_version "$version" || fail "pending framework version is invalid"
    acquire_lock
    [ -d "$BASE" ] || fail "installed framework directory is missing"
    old_version="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BASE/manifest.json" 2>/dev/null | sed -n '1p')"
    valid_version "$old_version" || old_version="unknown"
    stamp="$(date +%Y%m%d-%H%M%S)-$$"
    recovery_root="$DATA_ROOT/xqext-framework-recovery"
    backup="$recovery_root/$stamp-v$old_version"
    failed="$recovery_root/$stamp-failed-v$version"
    mkdir -p "$recovery_root" || fail "cannot prepare framework recovery directory"

    "$BASE/scripts/xqext-init.sh" stop >/dev/null 2>&1 || fail "cannot stop the current framework overlay"
    mv "$BASE" "$backup" || {
        "$BASE/scripts/xqext-init.sh" start >/dev/null 2>&1 || true
        fail "cannot preserve the current framework"
    }
    if ! mv "$pending" "$BASE"; then
        mv "$backup" "$BASE" 2>/dev/null || true
        "$BASE/scripts/xqext-init.sh" start >/dev/null 2>&1 || true
        fail "cannot activate the staged framework"
    fi
    ACTIVE_STAGING=""
    rm -f "$BASE/.mwef-package-info"
    if ! restore_persistent_data "$backup" "$BASE" || ! /bin/sh "$BASE/scripts/install.sh"; then
        "$BASE/scripts/xqext-init.sh" stop >/dev/null 2>&1 || true
        restore_persistent_data "$BASE" "$backup" >/dev/null 2>&1 || true
        mv "$BASE" "$failed" 2>/dev/null || true
        if mv "$backup" "$BASE" 2>/dev/null; then
            /bin/sh "$BASE/scripts/install.sh" >/dev/null 2>&1 || "$BASE/scripts/xqext-init.sh" start >/dev/null 2>&1 || true
        fi
        fail "installation failed; the previous framework was restored"
    fi
    release_lock
    printf '%s\n' "MWEF update: framework v$version installed; recovery copy: $backup"
}

case "${1:-}" in
    fetch-manifest)
        [ "$#" -eq 2 ] || fail "fetch-manifest requires a URL"
        fetch_manifest "$2"
        ;;
    inspect)
        [ "$#" -eq 5 ] || fail "inspect requires archive, token, SHA-256 and size"
        inspect_archive "$2" "$3" "$4" "$5"
        ;;
    download)
        [ "$#" -eq 5 ] || fail "download requires URL, SHA-256, size and token"
        download_archive "$2" "$3" "$4" "$5"
        ;;
    apply)
        [ "$#" -eq 2 ] || fail "apply requires a pending token"
        apply_pending "$2"
        ;;
    discard)
        [ "$#" -eq 2 ] || fail "discard requires a pending token"
        discard_pending "$2"
        ;;
    *)
        fail "usage: $0 {fetch-manifest|inspect|download|apply|discard}"
        ;;
esac
