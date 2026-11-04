# Merging a newer archetype-catalog into an existing one

Run:

    ./merge-archetype-catalog.sh archetype-catalog.xml archetype-catalog-YYYYMMDD.xml
    DRY_RUN=1 ./merge-archetype-catalog.sh ...   # writes BASE.xml.merged only

Method
1. Both catalogs are flat: `<archetype>` entries (groupId, artifactId, version,
   optional description) at 4-space indent. Merge key = `groupId:artifactId:version`.
2. `awk` flattens each entry to `key<TAB>block` (newlines encoded as `\001`).
3. A second `awk` pass keeps NEW entries whose key is absent from BASE.
4. `head`/`cat`/`tail` splice those entries before `  </archetypes>` in BASE.
5. Validate with `xmllint --noout`, entry count (old + added), and no duplicate keys.
6. Back up BASE (timestamped, `cmp`-verified), then replace it.

Behavior
- BASE entries are never changed or removed (entries only in BASE are kept).
- Entries present in both with differing content (e.g. description) keep BASE's version.
- New entries are appended at the end, not sorted.

Result of the 2026-10-09 run: 74,524 + 211 = 74,735 entries
(NEW had 55,631; 19,104 keys were only in BASE; 606 shared keys differed in content).
Backup of that run: archetype-catalog.xml.bak-20261009
