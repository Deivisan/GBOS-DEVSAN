#!/system/bin/sh
# Run by init right after apexd has activated all APEXes (and before zygote): bind the SHA-NI-free libcrypto
# over every APEX copy that is byte-identical to the Conscrypt one. Mounts go into init's (default) namespace.
# The "apex" lines of patched/MANIFEST (tools/port_build.py) give the path inside an APEX, the sha256 of the original
# and the patched file; a copy with any other hash is left alone and logged, so a new Google build shows up here.
M=/postinstall/gbos/patched/MANIFEST
[ -f $M ] || { log -t gbos "apex_patch: $M missing"; exit 0; }
# Native SHA-NI (AMD Zen, Intel Ice Lake+): the patch forces scalar SHA-256, which is slower there. Same rule as
# hook.sh/early_patch.sh; GBOS_NATIVE_SHA=0|1 overrides the probe.
gbos_sha=${GBOS_NATIVE_SHA:-auto}
if [ "$gbos_sha" = auto ]; then
  grep -qw sha_ni ${CPUINFO:-/proc/cpuinfo} 2>/dev/null && gbos_sha=1 || gbos_sha=0
fi
while read -r kind rel want file rest; do
  [ "$kind" = apex ] || continue
  if [ "$gbos_sha" = 1 ]; then
    log -t gbos "apex_patch: skipped $rel (CPU has native SHA-NI)"
    continue
  fi
  P=/postinstall/gbos/$file
  [ -f $P ] || { log -t gbos "apex_patch: $P missing"; continue; }
  for d in /apex/*; do
    case $d in *@*) continue;; esac
    f=$d/$rel
    [ -f $f ] || continue
    have=$(sha256sum $f | cut -d' ' -f1)
    if [ "$have" = "$want" ]; then
      mount -o bind $P $f && log -t gbos "apex_patch: patched $f" || log -t gbos "apex_patch: bind FAILED $f"
    else
      log -t gbos "apex_patch: $f left alone (sha256 $have, patch is for $want)"
    fi
  done
done < $M
