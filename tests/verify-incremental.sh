#!/usr/bin/env bash
# verify-incremental.sh JAR BEFORE_INDEX_DIR AFTER_INDEX_DIR BEFORE_PUBLISH_DIR AFTER_PUBLISH_DIR [EXPECTED_ADDED]
# Checks an incremental run: artifacts added, every earlier artifact still present, chain ID unchanged, a new chunk written.
set -euo pipefail

jar=${1:?jar} bi=${2:?before index dir} ai=${3:?after index dir} bp=${4:?before publish dir} ap=${5:?after publish dir}
expected=${6:-}
here=$(cd "$(dirname "$0")/.." && pwd)
cls=$(mktemp -d); trap 'rm -rf "$cls"' EXIT
javac -cp "$jar" -d "$cls" "$here/tools/CountIndex.java"

count() { java -cp "$jar:$cls" CountIndex "$1"; }
field() { sed -n "s/^$2=//p" "$1/nexus-maven-repository-index.properties"; }
num() { sed -n "s/.*$2=\([0-9]*\).*/\1/p" <<<"$1"; }

b=$(count "$bi"); a=$(count "$ai")
echo "before: $b"; echo "after:  $a"
ba=$(num "$b" 'artifacts(u)'); aa=$(num "$a" 'artifacts(u)')
bd=$(num "$b" 'deleteMarkers(del)'); ad=$(num "$a" 'deleteMarkers(del)')
fail=0
[ "$aa" -ge "$ba" ] || { echo "FAIL artifacts went down"; fail=1; }
[ "$ad" -eq "$bd" ] || { echo "FAIL delete markers changed: $bd -> $ad"; fail=1; }
missing=$(java -cp "$jar:$cls" CountIndex --subset "$bi" "$ai" | sed -n 's/^missingFromAfter=//p')
[ "$missing" = "0" ] || { echo "FAIL $missing artifacts from the before index are missing after"; fail=1; }
[ -z "$expected" ] || [ "$((aa - ba))" -eq "$expected" ] || { echo "FAIL added $((aa - ba)), expected $expected"; fail=1; }

bc=$(field "$bp" nexus.index.chain-id); ac=$(field "$ap" nexus.index.chain-id)
[ -n "$bc" ] && [ "$bc" = "$ac" ] || { echo "FAIL chain ID '$bc' -> '$ac'"; fail=1; }
bl=$(field "$bp" nexus.index.last-incremental); al=$(field "$ap" nexus.index.last-incremental)
[ -n "$bl" ] && [ "$al" -gt "$bl" ] || { echo "FAIL last-incremental '$bl' -> '$al'"; fail=1; }

[ "$fail" -eq 0 ] && echo "OK: added $((aa - ba)), deleted 0, chain $ac, chunk $bl -> $al"
exit "$fail"
