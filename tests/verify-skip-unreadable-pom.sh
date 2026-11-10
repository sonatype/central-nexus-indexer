#!/usr/bin/env bash
# verify-skip-unreadable-pom.sh SKIP_JAR [CONTROL_JAR [FINAL_JAR]]
# SKIP_JAR must index a pom the parser cannot read without its pom data, log it, count it and carry on, and must stop when more than 0.1% of 1000+ files are like that. Build it with EXCLUDE=0002 so the old XML parser is present.
# CONTROL_JAR (EXCLUDE="0002 0003") is optional and must stop on that pom, which shows the test really reaches the crash.
# FINAL_JAR (all patches) is optional and must read that pom without any error. Needs a JDK (javac).
set -uo pipefail

skip=${1:?skip jar} control=${2:-} final=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
bad=$here/fixtures/verbatime-0.8.2.pom
mkdir -p "$work/cls"; javac -cp "$skip" -d "$work/cls" "$here/../tools/CountIndex.java" || exit 1

pom() { mkdir -p "$1/$2/$3/1.0"; printf '<project><modelVersion>4.0.0</modelVersion><groupId>%s</groupId><artifactId>%s</artifactId><version>1.0</version><packaging>pom</packaging></project>\n' "$2" "$3" > "$1/$2/$3/1.0/$3-1.0.pom"; }
badpom() { mkdir -p "$1/bad/$2/1.0"; cp "$bad" "$1/bad/$2/1.0/$2-1.0.pom"; }
run() { java -Xmx1g -jar "$1" -r "$2" -i "$2.idx" -d "$2.pub" -t min -n central -c -s -e 2>&1; }
fail=0; check() { if ! eval "$2"; then echo "FAIL $1"; fail=1; fi; }

# small repo: a good pom, the pom that crashed the first sizing run, another good pom
small=$work/small; pom "$small" a good1; badpom "$small" b; pom "$small" z good2
echo "bad/b/1.0/b-1.0.pom" > "$work/bad-path.txt"
out=$(run "$skip" "$small"); rc=$?
echo "$out" | grep -E 'Unreadable pom|Scanning errors|Artifacts added' || true
check "skip jar exit code $rc" '[ "$rc" -eq 0 ]'
check "bad pom not logged with its path" 'grep -q "Unreadable pom, indexed without pom data: .*/bad/b/1.0/b-1.0.pom" <<<"$out"'
check "error not counted as 1" 'grep -q "Scanning errors: *1$" <<<"$out"'
check "three poms were not all indexed" 'grep -q "Artifacts added: *3$" <<<"$out"'
check "bad pom is not in the index" 'java -cp "$skip:$work/cls" CountIndex --has "$small.idx" "$work/bad-path.txt" | grep -q "present=1 "'

# a bad pom with a jar next to it: both go into the index
jarpom() { mkdir -p "$1/$2/1.0"; cp "$bad" "$1/$2/1.0/$3-1.0.pom"; (cd "$1/$2/1.0" && echo x > x.txt && jar cf "$3-1.0.jar" x.txt && rm x.txt); }
withjar=$work/withjar; pom "$withjar" a good1; jarpom "$withjar" bad/j j; pom "$withjar" z good2
printf 'bad/j/1.0/j-1.0.pom\nbad/j/1.0/j-1.0.jar\n' > "$work/jar-paths.txt"
out=$(run "$skip" "$withjar"); rc=$?
check "bad pom with a jar: exit $rc or counts wrong" '[ "$rc" -eq 0 ] && grep -q "Scanning errors: *1$" <<<"$out" && grep -q "Artifacts added: *3$" <<<"$out"'
check "bad pom with a jar: jar or pom missing from the index" 'java -cp "$skip:$work/cls" CountIndex --has "$withjar.idx" "$work/jar-paths.txt" | grep -q "present=2 "'

# a run stopped by the guard must leave an existing index as it was
upd=$work/upd; pom "$upd" a good1; pom "$upd" z good2; run "$skip" "$upd" >/dev/null
before=$(java -cp "$skip:$work/cls" CountIndex "$upd.idx")
for i in $(seq 1 1100); do pom "$upd" x "n$i"; done; for i in 1 2 3; do badpom "$upd" "u$i"; done
out=$(run "$skip" "$upd"); rc=$?
after=$(java -cp "$skip:$work/cls" CountIndex "$upd.idx")
check "guard abort on an existing index did not stop the run" '[ "$rc" -ne 0 ] && grep -q "Too many unreadable poms" <<<"$out"'
check "guard abort changed the existing index" '[ "$before" = "$after" ]'

# 3 bad poms in 1100 files: more than 0.1%, the run must stop
many=$work/many; for i in $(seq 1 1097); do pom "$many" x "n$i"; done; for i in 1 2 3; do badpom "$many" "b$i"; done
out=$(run "$skip" "$many"); rc=$?
check "run did not stop at 3 bad poms in 1100 files" '[ "$rc" -ne 0 ] && grep -q "Too many unreadable poms" <<<"$out"'

# 1 bad pom in 1100 files: 0.09%, the run must go on
few=$work/few; for i in $(seq 1 1099); do pom "$few" x "n$i"; done; badpom "$few" b1
out=$(run "$skip" "$few"); rc=$?
check "run stopped at 1 bad pom in 1100 files (rc $rc)" '[ "$rc" -eq 0 ] && grep -q "Scanning errors: *1$" <<<"$out"'

if [ -n "$control" ]; then
  mkdir -p "$work/csmall"; cp -R "$small/." "$work/csmall/"
  cout=$(run "$control" "$work/csmall"); crc=$?
  check "control jar did not crash on the pom" '[ "$crc" -ne 0 ] && grep -q "ArrayIndexOutOfBoundsException" <<<"$cout"'
fi
if [ -n "$final" ]; then
  mkdir -p "$work/fsmall"; cp -R "$small/." "$work/fsmall/"
  fout=$(run "$final" "$work/fsmall"); frc=$?
  check "final jar did not index all three poms cleanly" '[ "$frc" -eq 0 ] && grep -q "Artifacts added: *3$" <<<"$fout" && ! grep -q "Scanning errors" <<<"$fout"'
fi

[ "$fail" -eq 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
