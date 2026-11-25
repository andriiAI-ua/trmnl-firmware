#!/usr/bin/env bash
# Put a build from dist/ into wwwroot/firmware of the trmnl-server checkout next to this one.
# Run it in the repository root (Git Bash on Windows, bash on the NAS), after a build.
#
#   ./publish.sh               copy the last build (dist/.last_build)
#   ./publish.sh <name>        copy dist/<name>.bin and dist/<name>.json
#
# The builds go to the servers through git: commit and push wwwroot/firmware of trmnl-server,
# then deploy trmnl-server on each server. If a proxy sends the device to the first trmnl-server
# that answers, all servers must have the same release.
#
# TRMNL_FW_TARGETS is the list of target folders, separated by spaces.
# A target is a local folder or "user@host:/path" for scp.
# Default: ../trmnl-server/wwwroot/firmware (the trmnl-server checkout next to this one).
# TRMNL_FW_KEEP is the number of builds of the model to keep in each target folder (default 3).
#
# The script copies the .bin to all targets first and the .json last.
# The server uses a build only when the manifest (.json) exists and the SHA-256 is correct.
# If a target fails, the script continues with the other targets and then stops with an error.
set -euo pipefail

cd "$(dirname "$0")"

SERVER_CHECKOUT=../trmnl-server
if [[ -n "${TRMNL_FW_TARGETS:-}" ]]; then
    TARGETS=$TRMNL_FW_TARGETS
elif [[ -e "$SERVER_CHECKOUT/.git" ]]; then
    TARGETS="$SERVER_CHECKOUT/wwwroot/firmware"
else
    echo "No trmnl-server checkout in $SERVER_CHECKOUT. Clone it there or set TRMNL_FW_TARGETS." >&2
    exit 1
fi
KEEP=${TRMNL_FW_KEEP:-3}
DIST=dist

if [[ $# -ge 1 ]]; then
    NAME="$1"
elif [[ -f "$DIST/.last_build" ]]; then
    NAME=$(tr -d '\r\n' < "$DIST/.last_build")
else
    echo "No build. Run ./build.sh first." >&2
    exit 1
fi

BIN="$DIST/$NAME.bin"
JSON="$DIST/$NAME.json"

for f in "$BIN" "$JSON"; do
    if [[ ! -f "$f" ]]; then
        echo "File not found: $f" >&2
        exit 1
    fi
done

# Check the image again: it must agree with its manifest.
SHA256=$(sha256sum "$BIN" | cut -d ' ' -f 1)
if ! grep -q "\"sha256\": \"$SHA256\"" "$JSON"; then
    echo "The SHA-256 of $BIN does not agree with $JSON" >&2
    exit 1
fi

MODEL=$(sed -n 's/.*"model": "\([^"]*\)".*/\1/p' "$JSON")

# Split a target into HOST and DIR.
# A remote target is "[user@]host:/path". A drive letter ("D:/...") has one letter only.
split_target() {
    if [[ "$1" =~ ^([^/@:]+@)?([^/@:]{2,}):(.*)$ ]]; then
        HOST="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        DIR="${BASH_REMATCH[3]}"
    else
        HOST=""
        DIR="$1"
    fi
}

# Copy one file to one target.
copy_file() {
    split_target "$1"
    if [[ -n "$HOST" ]]; then
        scp -q "$2" "$HOST:$DIR/"
    else
        mkdir -p "$DIR" && cp -f "$2" "$DIR/"
    fi
}

# A local target must not have a different build with the same version.
# Devices with this version do not take a second build of it.
for t in $TARGETS; do
    split_target "$t"
    if [[ -z "$HOST" && -f "$DIR/$NAME.bin" ]] && ! cmp -s "$BIN" "$DIR/$NAME.bin"; then
        echo "$DIR already has a different build $NAME." >&2
        echo "Increase FW_OWN_BUILD (./build.sh --bump-only on Windows), commit, push and build again." >&2
        exit 1
    fi
done

# Remove the old builds of this model. Keep the newest $KEEP builds (version order).
# Remove the manifest first: then the server does not see a build without its image.
CLEANUP_TEMPLATE="ls -1 trmnl-$MODEL-*.json 2>/dev/null | sed 's/\\.json\$//' | sort -V | head -n -$KEEP \
    | while read -r n; do rm -f -- \"\$n.json\" \"\$n.bin\"; echo \"Removed \$n\"; done; ls -l"

clean_target() {
    split_target "$1"
    local cmd="cd '$DIR' && $CLEANUP_TEMPLATE"
    if [[ -n "$HOST" ]]; then
        ssh "$HOST" "$cmd"
    else
        bash -c "$cmd"
    fi
}

read -r -a LIST <<< "$TARGETS"
OK=()
FAILED=()

echo "==> Publish $NAME to ${#LIST[@]} target(s)"

# Step 1: the image to all targets.
for t in "${LIST[@]}"; do
    echo "--> $t: $NAME.bin"
    if copy_file "$t" "$BIN"; then
        OK+=("$t")
    else
        echo "    FAILED" >&2
        FAILED+=("$t")
    fi
done

# Step 2: the manifest, only to the targets that have the image.
for t in "${OK[@]}"; do
    echo "--> $t: $NAME.json"
    if ! copy_file "$t" "$JSON"; then
        echo "    FAILED" >&2
        FAILED+=("$t")
    fi
done

# Step 3: remove old builds, show the folder.
for t in "${OK[@]}"; do
    case " ${FAILED[*]} " in *" $t "*) continue ;; esac
    echo "--> $t: folder"
    clean_target "$t" || echo "    Cleanup FAILED (the new build is in place)" >&2
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "==> NOT published to: ${FAILED[*]}" >&2
    echo "    The instances have different builds now. Repeat for these targets:" >&2
    echo "    TRMNL_FW_TARGETS=\"${FAILED[*]}\" ./publish.sh $NAME" >&2
    exit 1
fi

echo "==> Published to all targets."
if [[ -z "${TRMNL_FW_TARGETS:-}" ]]; then
    SERVER_ABS=$(cd "$SERVER_CHECKOUT" && pwd)
    cat <<EOF
Next steps:
  1. Commit only wwwroot/firmware in trmnl-server and push:
     cd $SERVER_ABS && git add -A wwwroot/firmware && git commit -m "Add firmware $NAME" && git push
  2. Deploy trmnl-server on each server, in its trmnl-server checkout:
     git pull && ./build.sh && sudo ./deploy.sh
  Flash or update a device only after the deploy on all servers.
EOF
fi
