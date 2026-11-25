# Build environment for trmnl-firmware: PlatformIO Core on Debian.
# docker-build.sh builds this image and runs build.sh in it.
# The PlatformIO packages (toolchain, frameworks) are not in the image.
# They are in the volume trmnl-firmware-pio (/root/.platformio), so the image stays small.
FROM python:3.11.11-slim-bookworm

# git: build.sh and PlatformIO use it (version text, libraries from git).
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Use the same PlatformIO version as on Windows.
RUN pip install --no-cache-dir platformio==6.1.19

# The checkout in /src belongs to a different user. Let git read it.
RUN git config --system --add safe.directory '*'

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

WORKDIR /src
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
