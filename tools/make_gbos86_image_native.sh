#!/bin/sh
# make_gbos86_image_native.sh: assemble the standard (live/installer) gbOS86 image with host tools, without docker.
#
# Why this exists: tools/make_gbos86_image.sh runs the FAT assembly inside `alpine` with $OUT bind-mounted. On a
# Windows host (WSL + Docker Desktop, repo under /mnt/c) that bind mount can deliver an EMPTY view of the directory:
# the container's `ls /o` shows only the files it created itself, and mcopy dies with
#   gbOS86-YYYYMMDD.stage/efi/EFI: No such file or directory
# while the host plainly has that directory. The same class of bug bites the other way in tools/fetch_busybox.sh
# (a container writing into a /mnt/c bind mount exits 0 with the host directory empty), which is why busybox is now
# streamed out on stdout. No mount is involved here at all.
#
# Needs: dosfstools (mkfs.fat), mtools (mcopy, mdir), sfdisk (util-linux), coreutils. On Debian/Ubuntu:
#   apt-get install -y dosfstools mtools
#
# Usage: tools/make_gbos86_image_native.sh [--check] [DIST_DIR]
#   DIST_DIR defaults to <repo>/dist; the script uses the single *.stage directory it finds there and names the
#   image after it (gbOS86-YYYYMMDD.stage -> gbOS86-YYYYMMDD.img).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=0
[ "$1" = "--check" ] && { CHECK=1; shift; }
OUT=${1:-$ROOT/dist}
EFI_MB=256
GBOS_MB=6144

for t in truncate mkfs.fat mcopy mdir sfdisk dd sha256sum; do
  command -v "$t" >/dev/null 2>&1 || { echo "missing '$t' (apt-get install -y dosfstools mtools)" >&2; exit 1; }
done

[ -d "$OUT" ] || { echo "no such directory: $OUT" >&2; exit 1; }
set -- "$OUT"/*.stage
[ -d "$1" ] || { echo "no *.stage directory in $OUT (run build.sh up to the assembly step first)" >&2; exit 1; }
[ $# -eq 1 ] || { echo "more than one .stage directory in $OUT: remove the stale one" >&2; exit 1; }
S=$1
NAME=$(basename "$S" .stage)

echo "stage:  $NAME.stage ($(du -sh "$S" | cut -f1))"
echo "image:  $NAME.img  (ESP ${EFI_MB}M + GBOS ${GBOS_MB}M)"
[ -f "$S/efi/EFI/BOOT/BOOTX64.EFI" ] || { echo "the stage has no efi/EFI/BOOT/BOOTX64.EFI: the kernel was not staged" >&2; exit 1; }
[ $CHECK = 1 ] && { echo "(check only: nothing written)"; exit 0; }

cd "$OUT"
rm -f p1.fat p2.fat
echo "== p1 (EFI ${EFI_MB}M)"
truncate -s ${EFI_MB}M p1.fat
mkfs.fat -F 32 -n EFI p1.fat >/dev/null
mcopy -s -i p1.fat "$S"/efi/EFI ::/

echo "== p2 (GBOS ${GBOS_MB}M)"
truncate -s ${GBOS_MB}M p2.fat
mkfs.fat -F 32 -n GBOS p2.fat >/dev/null
mcopy -s -i p2.fat "$S"/gbos/* ::/

echo "== $NAME.img"
rm -f "$NAME.img"
truncate -s $(( (EFI_MB + GBOS_MB + 2) * 1048576 )) "$NAME.img"
printf 'label: gpt\nstart=2048, size=%s, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="gbOS86 EFI"\nsize=%s, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="gbOS86"\n' \
  $((EFI_MB * 2048)) $((GBOS_MB * 2048)) | sfdisk -q "$NAME.img" >/dev/null
dd if=p1.fat of="$NAME.img" bs=1M seek=1 conv=notrunc,sparse status=none
dd if=p2.fat of="$NAME.img" bs=1M seek=$(( 1 + EFI_MB )) conv=notrunc,sparse status=none
rm -f p1.fat p2.fat

echo "== verify"
sfdisk -l "$NAME.img" | tail -4
echo "-- ESP: EFI/BOOT"
mdir -i "$NAME.img@@1048576" ::/EFI/BOOT | grep -i bootx64 || { echo "BOOTX64.EFI is NOT in the ESP" >&2; exit 1; }
echo "-- GBOS: ::/gbos"
mdir -i "$NAME.img@@$(( 1048576 * (1 + EFI_MB) ))" ::/gbos | grep -Ei 'super|gbos.cfg|hook.sh' || true

sha256sum "$NAME.img" > "$NAME.img.sha256"
cat "$NAME.img.sha256"
ls -lh "$NAME.img"
