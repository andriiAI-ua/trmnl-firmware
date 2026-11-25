#!/usr/bin/env bash
# Build the firmware in Docker, for example on the NAS. Run it in the repository root.
# The build uses the committed version: it does not increase FW_OWN_BUILD.
# Increase the number on Windows (./build.sh --bump-only), then commit and push.
#
#   ./docker-build.sh              build the env "trmnl" (TRMNL OG) into dist/
#   ./docker-build.sh --publish    also put the build into ../trmnl-server/wwwroot/firmware
#   ./docker-build.sh -e <env>     build a different env
#   ./docker-build.sh --dirty      allow local changes in the checkout (test builds only)
#
# Install on the build host (once): clone this repository next to the trmnl-server checkout.
# Each build: cd <this checkout> && git pull && ./docker-build.sh --publish
#
# The image is trmnl-firmware-build (docker/Dockerfile). The PlatformIO packages are in the
# volume trmnl-firmware-pio. The first build downloads them (about 1.5 GB) and takes longer.
# If the user cannot use Docker, the script uses "sudo docker".
set -euo pipefail

cd "$(dirname "$0")"

ENV_NAME=trmnl
PUBLISH=0
DIRTY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--env)   ENV_NAME="$2"; shift 2 ;;
        --publish)  PUBLISH=1; shift ;;
        --dirty)    DIRTY=1; shift ;;
        -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
        *)          echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

IMAGE=trmnl-firmware-build:pio-6.1.19
VOLUME=trmnl-firmware-pio
CONTAINER="trmnl-firmware-build-$$"

# The build must agree with git: then the version and the commit in the manifest are correct.
if [[ "$DIRTY" == 0 && -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "The checkout has local changes. Commit them on Windows and run git pull, or use --dirty." >&2
    git status --short --untracked-files=no >&2
    exit 1
fi

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
fi

echo "==> Image $IMAGE"
"${DOCKER[@]}" build -q -t "$IMAGE" docker >/dev/null

# When this script stops (Ctrl+C, closed SSH session), remove the container.
trap '"${DOCKER[@]}" rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT

echo "==> Build $(git log -1 --format='%h %s')"
"${DOCKER[@]}" run --rm --init --name "$CONTAINER" \
    -v "$PWD:/src" -v "$VOLUME:/root/.platformio" \
    "$IMAGE" bash ./build.sh --no-bump -e "$ENV_NAME"

if [[ "$PUBLISH" == 1 ]]; then
    bash ./publish.sh
fi
