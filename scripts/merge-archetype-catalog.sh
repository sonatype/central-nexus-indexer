#!/usr/bin/env bash
# merge-archetype-catalog.sh BASE.xml NEW.xml
#
# Appends <archetype> entries from NEW.xml that are absent from BASE.xml
# (key = groupId:artifactId:version) into BASE.xml. Existing BASE entries are
# never modified or removed; new entries go just before </archetypes>.
#
# Requires: bash, awk, sort, comm, cut, tr, head, tail, grep, cp, cmp, xmllint.
# Assumes the flat layout both catalogs use: each entry opens with
# "    <archetype>" and closes with "    </archetype>" (4-space indent).
#
# Set DRY_RUN=1 to write BASE.xml.merged and leave BASE.xml untouched.
set -euo pipefail

base=${1:?usage: $0 BASE.xml NEW.xml}
new=${2:?usage: $0 BASE.xml NEW.xml}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Flatten each entry to one line: "g:a:v<TAB>block" with newlines encoded as \001
cat > "$tmp/keys.awk" <<'EOF'
/^    <archetype>$/ {blk=$0; g=a=v=""; inb=1; next}
inb { blk=blk "\001" $0
  if ($0 ~ /<groupId>/)      {g=$0; gsub(/.*<groupId>|<\/groupId>.*/,"",g)}
  if ($0 ~ /<artifactId>/)   {a=$0; gsub(/.*<artifactId>|<\/artifactId>.*/,"",a)}
  if ($0 ~ /^      <version>/){v=$0; gsub(/.*<version>|<\/version>.*/,"",v)}
  if ($0 ~ /^    <\/archetype>$/) {print g ":" a ":" v "\t" blk; inb=0} }
EOF

xmllint --noout "$base" "$new"
awk -f "$tmp/keys.awk" "$base" > "$tmp/old.tsv"
awk -f "$tmp/keys.awk" "$new"  > "$tmp/new.tsv"

# Entries in NEW whose key is not in BASE
awk -F'\t' 'NR==FNR{old[$1]=1;next} !($1 in old)' "$tmp/old.tsv" "$tmp/new.tsv" \
  | cut -f2- | tr '\001' '\n' > "$tmp/new-blocks.xml"
added=$(grep -c '^    <archetype>$' "$tmp/new-blocks.xml" || true)

# Splice before </archetypes>
n=$(grep -n '^  </archetypes>$' "$base" | cut -d: -f1)
[ -n "$n" ] || { echo "no '  </archetypes>' line found in $base" >&2; exit 1; }
{ head -n $((n-1)) "$base"; cat "$tmp/new-blocks.xml"; tail -n +$n "$base"; } > "$tmp/merged.xml"

# Validate: well-formed, count matches, no duplicate keys
xmllint --noout "$tmp/merged.xml"
before=$(wc -l < "$tmp/old.tsv")
after=$(awk -f "$tmp/keys.awk" "$tmp/merged.xml" | wc -l)
dups=$(awk -f "$tmp/keys.awk" "$tmp/merged.xml" | cut -f1 | sort | uniq -d | wc -l)
[ "$after" -eq $((before + added)) ] && [ "$dups" -eq 0 ] \
  || { echo "validation failed: before=$before added=$added after=$after dups=$dups" >&2; exit 1; }

if [ "${DRY_RUN:-0}" = 1 ]; then
  cp "$tmp/merged.xml" "$base.merged"
  echo "dry run: $before + $added = $after entries -> $base.merged"
else
  bak="$base.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$base" "$bak"; cmp "$base" "$bak"
  cp "$tmp/merged.xml" "$base"
  echo "merged: $before + $added = $after entries; backup at $bak"
fi
