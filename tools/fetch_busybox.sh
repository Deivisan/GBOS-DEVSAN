#!/bin/sh
# kernel/out/busybox: the static x86-64 busybox stage0 and the stick use (Debian's busybox-static, 1.37).
# Needs docker; safe to re-run.   tools/fetch_busybox.sh [OUT_FILE]
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/kernel/out/busybox}
mkdir -p "$(dirname "$OUT")"
# The binary is streamed out of the container on stdout, with no path in the transfer. Neither of the two obvious
# ways survives a Windows host: the `docker` on PATH inside WSL is docker.exe, which rewrites Linux paths
# ("docker cp ... /tmp/x" -> "invalid output path: directory C:\tmp\x"), and a container writing into a directory
# bind-mounted from a Windows checkout (/mnt/c through Docker Desktop) can exit 0 with the host directory still
# empty (build/busybox.XXXXXX was empty while the container had just run /out/busybox).
docker run --rm --platform linux/amd64 debian:trixie-slim sh -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends busybox-static >/dev/null &&
  /bin/busybox | head -1 >&2 && cat /bin/busybox' > "$OUT"
[ -s "$OUT" ] || { rm -f "$OUT"; echo "fetch_busybox: the container produced no binary" >&2; exit 1; }
chmod 755 "$OUT"
echo "busybox -> $OUT"
