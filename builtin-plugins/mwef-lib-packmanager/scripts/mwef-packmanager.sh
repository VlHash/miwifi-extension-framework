#!/bin/sh

set -u

INDEX_LIMIT=1048576
ARCHIVE_LIMIT=8388608

fail() {
    printf '%s\n' "MWEF package manager: $*" >&2
    exit 1
}

valid_token() {
    case "$1" in
        ""|*[!A-Fa-f0-9-]*) return 1 ;;
    esac
    [ "${#1}" -le 80 ]
}

valid_https_url() {
    case "$1" in
        https://*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!A-Za-z0-9:/?\&=._~%+@#,-]*) return 1 ;;
    esac
    [ "${#1}" -le 512 ]
}

file_size() {
    wc -c < "$1" 2>/dev/null | tr -d '[:space:]'
}

file_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | sed -n 's/[[:space:]].*$//p' | tr 'A-F' 'a-f'
        return
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" 2>/dev/null | sed -n 's/^.*= *//p' | tr 'A-F' 'a-f'
        return
    fi
    fail "sha256sum or openssl is required"
}

download_file() {
    local url destination limit temporary size
    url="$1"
    destination="$2"
    limit="$3"
    temporary="$destination.$$"
    valid_https_url "$url" || fail "only safe HTTPS source URLs are accepted"
    command -v curl >/dev/null 2>&1 || fail "curl is required for online packages"
    rm -f "$temporary"
    curl -kfsSL --globoff --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 180 --max-filesize "$limit" \
        -o "$temporary" -- "$url" || {
            rm -f "$temporary"
            fail "download failed"
        }
    [ -f "$temporary" ] || fail "download did not create a file"
    size="$(file_size "$temporary")"
    case "$size" in ""|*[!0-9]*) rm -f "$temporary"; fail "cannot determine download size" ;; esac
    [ "$size" -gt 0 ] && [ "$size" -le "$limit" ] || {
        rm -f "$temporary"
        fail "download is empty or exceeds the size limit"
    }
    mv "$temporary" "$destination" || {
        rm -f "$temporary"
        fail "cannot publish downloaded file"
    }
    chmod 600 "$destination"
}

fetch_index() {
    local url token destination
    url="$1"
    token="$2"
    valid_token "$token" || fail "invalid request token"
    destination="/tmp/mwef-packmanager-index-$token.json"
    rm -f "$destination"
    download_file "$url" "$destination" "$INDEX_LIMIT"
    printf '%s\n' "MWEF package manager: index downloaded"
}

download_archive() {
    local url sha expected_size token destination actual_size actual_sha
    url="$1"
    sha="$2"
    expected_size="$3"
    token="$4"
    valid_token "$token" || fail "invalid pending token"
    case "$sha" in ""|*[!a-f0-9]*) fail "invalid expected SHA-256" ;; esac
    [ "${#sha}" -eq 64 ] || fail "invalid expected SHA-256"
    case "$expected_size" in ""|*[!0-9]*) fail "invalid expected package size" ;; esac
    [ "$expected_size" -gt 0 ] && [ "$expected_size" -le "$ARCHIVE_LIMIT" ] || fail "package exceeds 8 MiB"
    destination="/tmp/mwef-upload-$token.tar.gz"
    rm -f "$destination"
    download_file "$url" "$destination" "$ARCHIVE_LIMIT"
    actual_size="$(file_size "$destination")"
    [ "$actual_size" -eq "$expected_size" ] || {
        rm -f "$destination"
        fail "package size does not match the plugin index"
    }
    actual_sha="$(file_sha256 "$destination")"
    [ "$actual_sha" = "$sha" ] || {
        rm -f "$destination"
        fail "package SHA-256 does not match the plugin index"
    }
    printf '%s\n' "MWEF package manager: package downloaded and verified"
}

case "${1:-}" in
    fetch-index)
        [ "$#" -eq 3 ] || fail "fetch-index requires URL and token"
        fetch_index "$2" "$3"
        ;;
    download)
        [ "$#" -eq 5 ] || fail "download requires URL, SHA-256, size and token"
        download_archive "$2" "$3" "$4" "$5"
        ;;
    *)
        fail "usage: $0 {fetch-index|download}"
        ;;
esac
