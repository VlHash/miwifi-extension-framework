#!/bin/sh

set -eu
umask 077

MWEF_VERSION=${MWEF_VERSION:-0.3.0}
MWEF_TAG=${MWEF_TAG:-v0.3.0-pre.1}
MWEF_ASSET=${MWEF_ASSET:-mwef-$MWEF_VERSION.tar.gz}
MWEF_SHA256=${MWEF_SHA256:-6E4695A69F461F1A93C6D0E28EB493B25204EDA4ECC7D5380040B4CB9F579FEB}
MWEF_BASE=/data/other_vol/xqext
MWEF_RELEASE_BASE=${MWEF_RELEASE_BASE:-https://github.com/VlHash/miwifi-extension-framework/releases/download}
MWEF_DOWNLOAD_URL=${MWEF_DOWNLOAD_URL:-$MWEF_RELEASE_BASE/$MWEF_TAG/$MWEF_ASSET}
MWEF_GITHUB_MIRROR=${MWEF_GITHUB_MIRROR:-}

ARCHIVE=/tmp/mwef-install-$$.tar.gz
LIST=/tmp/mwef-install-$$.list
STAGING=/data/other_vol/.mwef-install-$$

say() { printf '%s\n' "$*"; }
fail() {
    printf '%s\n' "MWEF: $*" >&2
    exit 1
}
cleanup() {
    rm -f "$ARCHIVE" "$LIST"
    case "$STAGING" in
        /data/other_vol/.mwef-install-[0-9]*)
            [ ! -e "$STAGING" ] || rm -rf "$STAGING"
            ;;
    esac
}
trap cleanup 0 1 2 3 15

download() {
    source_url=$1
    destination=$2

    if command -v curl >/dev/null 2>&1; then
        if [ "${MWEF_INSECURE:-0}" = "1" ]; then
            curl -kfsSL --connect-timeout 20 --retry 2 -o "$destination" "$source_url"
        else
            curl -fsSL --connect-timeout 20 --retry 2 -o "$destination" "$source_url"
        fi
        return
    fi

    if command -v uclient-fetch >/dev/null 2>&1; then
        if [ "${MWEF_INSECURE:-0}" = "1" ]; then
            uclient-fetch -q --no-check-certificate -O "$destination" "$source_url"
        else
            uclient-fetch -q -O "$destination" "$source_url"
        fi
        return
    fi

    if command -v wget >/dev/null 2>&1; then
        if [ "${MWEF_INSECURE:-0}" = "1" ]; then
            wget -q --no-check-certificate -O "$destination" "$source_url"
        else
            wget -q -O "$destination" "$source_url"
        fi
        return
    fi

    fail "curl, uclient-fetch, or wget is required"
}

archive_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
        return
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
        return
    fi
    fail "sha256sum or openssl is required to verify the package"
}

validate_archive() {
    tar -tzf "$ARCHIVE" > "$LIST" || fail "the downloaded package is not a valid tar.gz archive"
    while IFS= read -r member; do
        case "$member" in
            ''|/*|..|../*|*/../*|*/..|*\\*)
                fail "unsafe archive path: $member"
                ;;
        esac
    done < "$LIST"
}

validate_staging() {
    [ -f "$STAGING/manifest.json" ] || fail "manifest.json is missing from the package root"
    [ -f "$STAGING/scripts/install.sh" ] || fail "the package installer is missing"
    [ -f "$STAGING/scripts/xqext-init.sh" ] || fail "the runtime initializer is missing"

    for file_type in l b c p s; do
        if find "$STAGING" -type "$file_type" -print 2>/dev/null | grep -q .; then
            fail "the package contains links or special files"
        fi
    done
}

[ "$(id -u 2>/dev/null || printf '1')" = "0" ] || fail "run this installer as root"
[ -d /data ] && [ -w /data ] || fail "/data is not available as writable persistent storage"
[ -d /data/other_vol ] || mkdir -p /data/other_vol
[ -w /data/other_vol ] || fail "/data/other_vol is not writable"
command -v tar >/dev/null 2>&1 || fail "tar is required"
command -v awk >/dev/null 2>&1 || fail "awk is required"
command -v find >/dev/null 2>&1 || fail "find is required"
command -v wc >/dev/null 2>&1 || fail "wc is required"

case "$MWEF_GITHUB_MIRROR" in
    '') ;;
    http://*|https://*) MWEF_DOWNLOAD_URL=${MWEF_GITHUB_MIRROR%/}/$MWEF_DOWNLOAD_URL ;;
    *) fail "MWEF_GITHUB_MIRROR must be an HTTP or HTTPS URL prefix" ;;
esac

case "$MWEF_SHA256" in
    ''|*[!0-9A-Fa-f]*) fail "the installer does not contain a valid package checksum" ;;
esac
[ "${#MWEF_SHA256}" -eq 64 ] || fail "the installer checksum must contain 64 hexadecimal characters"

say "MWEF $MWEF_VERSION one-click installer"
say "Downloading $MWEF_DOWNLOAD_URL"
download "$MWEF_DOWNLOAD_URL" "$ARCHIVE" || fail "download failed"
[ "$(wc -c < "$ARCHIVE" | tr -d '[:space:]')" -le 16777216 ] || fail "the downloaded package exceeds 16 MiB"

ACTUAL_SHA256=$(archive_sha256 "$ARCHIVE" | tr 'A-F' 'a-f')
EXPECTED_SHA256=$(printf '%s' "$MWEF_SHA256" | tr 'A-F' 'a-f')
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "package checksum mismatch"
say "Package checksum verified."

validate_archive
mkdir "$STAGING"
tar -xzf "$ARCHIVE" -C "$STAGING" || fail "package extraction failed"
validate_staging

mkdir -p "$MWEF_BASE"
cp -a "$STAGING/." "$MWEF_BASE/" || fail "cannot copy MWEF into persistent storage"
chmod 755 \
    "$MWEF_BASE/scripts/install.sh" \
    "$MWEF_BASE/scripts/xqext-init.sh" \
    "$MWEF_BASE/scripts/mwef-pluginctl.sh" \
    "$MWEF_BASE/scripts/mwef-update.sh" \
    "$MWEF_BASE/scripts/uninstall.sh"

say "Installing MWEF into $MWEF_BASE"
"$MWEF_BASE/scripts/install.sh" || fail "framework installation failed"
say "MWEF $MWEF_VERSION installation completed."
