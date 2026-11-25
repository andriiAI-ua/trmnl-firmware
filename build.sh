#!/usr/bin/env bash
# Build a release of our firmware for one PlatformIO environment.
# Run it in the repository root: Git Bash on Windows, or bash on Linux.
#
#   ./build.sh                 increase FW_OWN_BUILD, then build the env "trmnl" (TRMNL OG)
#   ./build.sh -e <env>        build a different env
#   ./build.sh --no-bump       build again with the current version
#   ./build.sh --bump-only     only increase FW_OWN_BUILD (then commit, push, docker-build.sh on the NAS)
#
# The result is in dist/ ("<name>" is "trmnl-<model>-<version>", for example trmnl-og-1.8.19-own.1):
#   <name>.bin          OTA image (app partition). trmnl-server sends this file to the devices.
#   <name>.json         manifest for trmnl-server: version, SHA-256, size, model.
#   <name>-factory.bin  full image for address 0x0. It also erases the settings (Wi-Fi, API key).
#   <name>.elf          symbols to decode a crash of this build.
# dist/.last_build contains the last "<name>". publish.sh reads it.
set -euo pipefail

cd "$(dirname "$0")"

ENV_NAME=trmnl
BUMP=1
BUMP_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--env)     ENV_NAME="$2"; shift 2 ;;
        --no-bump)    BUMP=0; shift ;;
        --bump-only)  BUMP=1; BUMP_ONLY=1; shift ;;
        -h|--help)    sed -n '2,16p' "$0"; exit 0 ;;
        *)          echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

OWN_HEADER=include/own_version.h
CONFIG_HEADER=include/config.h
DIST=dist

# Read the number of "#define <name> <number>" from a header.
read_define() {
    sed -n "s/^#define[[:space:]]\{1,\}$1[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p" "$2" | head -n 1
}

# Increase FW_OWN_BUILD in the header and set OWN to the new number.
bump_own() {
    OWN=$((OWN + 1))
    # Change only the number. "-b" keeps CRLF: without it, sed in Git Bash writes LF.
    sed -b -i "s/^\(#define[[:space:]]\{1,\}FW_OWN_BUILD[[:space:]]\{1,\}\)[0-9]\{1,\}/\1$OWN/" "$OWN_HEADER"
}

# ---------- Version ----------

OWN=$(read_define FW_OWN_BUILD "$OWN_HEADER")
if [[ -z "$OWN" ]]; then
    echo "FW_OWN_BUILD not found in $OWN_HEADER" >&2
    exit 1
fi

if [[ "$BUMP_ONLY" == 1 ]]; then
    bump_own
    echo "==> FW_OWN_BUILD is $OWN now. Commit $OWN_HEADER and push, then build on the NAS:"
    echo "    git commit -am \"Release own.$OWN\" && git push origin master"
    exit 0
fi

# ---------- Tools ----------

find_pio() {
    if command -v pio >/dev/null 2>&1; then
        echo pio
        return
    fi
    local p
    for p in "$HOME/.platformio/penv/Scripts/pio.exe" "$HOME/.platformio/penv/bin/pio"; do
        if [[ -x "$p" ]]; then
            echo "$p"
            return
        fi
    done
    echo "PlatformIO (pio) not found. Install PlatformIO Core or the VS Code extension." >&2
    exit 1
}

PIO=$(find_pio)

if [[ "$BUMP" == 1 ]]; then
    bump_own
fi

MAJOR=$(read_define FW_MAJOR_VERSION "$CONFIG_HEADER")
MINOR=$(read_define FW_MINOR_VERSION "$CONFIG_HEADER")
PATCH=$(read_define FW_PATCH_VERSION "$CONFIG_HEADER")
VERSION="$MAJOR.$MINOR.$PATCH-own.$OWN"

# The model is DEVICE_MODEL of the env. The device sends it in the "Model" header.
MODEL=$(sed -n "/^\[env:$ENV_NAME\]/,/^\[/p" platformio.ini \
    | grep -o 'DEVICE_MODEL=\\"[^\\]*' | head -n 1 | sed 's/.*\\"//' || true)
MODEL=${MODEL:-$ENV_NAME}

NAME="trmnl-$MODEL-$VERSION"

echo "==> Env: $ENV_NAME, model: $MODEL, version: $VERSION"

# ---------- sdkconfig ----------

# PlatformIO makes sdkconfigs/sdkconfig.<env> from sdkconfigs/sdkconfig.defaults* only once.
# ESP-IDF does not apply a changed default to an existing sdkconfig (for example -Os after -Og).
# Remove a generated sdkconfig that is older than a defaults file. The build then makes it again.
# Do not remove a committed sdkconfig: it is not generated.
for generated in "sdkconfigs/sdkconfig.$ENV_NAME" "sdkconfig.$ENV_NAME"; do
    [[ -f "$generated" ]] || continue
    git ls-files --error-unmatch "$generated" >/dev/null 2>&1 && continue
    for defaults in sdkconfigs/sdkconfig.defaults*; do
        if [[ "$defaults" -nt "$generated" ]]; then
            echo "==> $defaults is newer than $generated: remove it, the build makes it again"
            rm -f "$generated"
            break
        fi
    done
done

# ---------- Build ----------

"$PIO" run -e "$ENV_NAME"

BUILD_DIR=".pio/build/$ENV_NAME"
APP="$BUILD_DIR/firmware.bin"
ELF="$BUILD_DIR/firmware.elf"
MERGED="$BUILD_DIR/merged_firmware.bin"

if [[ ! -s "$APP" ]]; then
    echo "Build output not found: $APP" >&2
    exit 1
fi

# ---------- Checks ----------

# The device sends FW_VERSION_STRING in the "FW-Version" header.
# If the image does not contain this text, the server and the device see different versions.
# Find the whole C string: "1.8.19-own.1" must not match in "1.8.19-own.12".
if ! LC_ALL=C grep -q -a -P "(?<![0-9.])\Q$VERSION\E\x00" "$APP"; then
    echo "The image does not contain the version text \"$VERSION\"" >&2
    exit 1
fi

# An app image has the app description (magic word 0xABCD5432) at offset 0x20.
# A merged image starts with the bootloader and does not have it.
MAGIC=$(od -An -tx1 -j32 -N4 "$APP" | tr -d ' \n')
if [[ "$MAGIC" != "3254cdab" ]]; then
    echo "The file is not an ESP-IDF app image: $APP" >&2
    exit 1
fi

# ---------- Dist ----------

mkdir -p "$DIST"

cp -f "$APP" "$DIST/$NAME.bin"
[[ -f "$ELF" ]] && cp -f "$ELF" "$DIST/$NAME.elf"
[[ -f "$MERGED" ]] && cp -f "$MERGED" "$DIST/$NAME-factory.bin"

SHA256=$(sha256sum "$DIST/$NAME.bin" | cut -d ' ' -f 1)
SIZE=$(wc -c < "$DIST/$NAME.bin" | tr -d ' ')
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
UPSTREAM=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-own*' 2>/dev/null || echo "")
BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "$DIST/$NAME.json" <<EOF
{
  "version": "$VERSION",
  "file": "$NAME.bin",
  "sha256": "$SHA256",
  "size": $SIZE,
  "model": "$MODEL",
  "env": "$ENV_NAME",
  "commit": "$COMMIT",
  "upstream": "$UPSTREAM",
  "built": "$BUILT"
}
EOF

echo "$NAME" > "$DIST/.last_build"

echo "==> Build OK: $DIST/$NAME.bin ($SIZE bytes)"
echo "    SHA-256: $SHA256"
[[ -f "$DIST/$NAME-factory.bin" ]] && echo "    Factory image: $DIST/$NAME-factory.bin"
echo "    Next: ./publish.sh"
