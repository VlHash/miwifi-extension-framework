#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
OUTPUT_DIRECTORY=${1:-dist}

command -v tar >/dev/null 2>&1 || {
    printf '%s\n' "MWEF build: tar is required." >&2
    exit 1
}
command -v gzip >/dev/null 2>&1 || {
    printf '%s\n' "MWEF build: gzip is required." >&2
    exit 1
}

VERSION=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/manifest.json" | sed -n '1p')
case "$VERSION" in
    ''|*[!0-9A-Za-z.-]*)
        printf '%s\n' "MWEF build: manifest.json contains an invalid version." >&2
        exit 1
        ;;
esac

case "$OUTPUT_DIRECTORY" in
    /*) OUTPUT_PATH=$OUTPUT_DIRECTORY ;;
    *) OUTPUT_PATH=$SCRIPT_DIR/$OUTPUT_DIRECTORY ;;
esac

mkdir -p "$OUTPUT_PATH"
ARCHIVE=$OUTPUT_PATH/mwef-$VERSION.tar.gz
TEMP_ARCHIVE=$OUTPUT_PATH/.mwef-$VERSION.tar.gz.tmp.$$

cleanup() {
    [ ! -f "$TEMP_ARCHIVE" ] || rm -f "$TEMP_ARCHIVE"
}
trap cleanup 0 1 2 3 15

cd "$SCRIPT_DIR"
tar -cf - \
    router-overlay \
    builtin-plugins \
    scripts \
    docs \
    schema \
    examples \
    tools \
    manifest.json \
    README.md \
    README_CN.md \
    build.sh \
    LICENSE | gzip -n > "$TEMP_ARCHIVE"

mv "$TEMP_ARCHIVE" "$ARCHIVE"
trap - 0 1 2 3 15
printf '%s\n' "$ARCHIVE"
