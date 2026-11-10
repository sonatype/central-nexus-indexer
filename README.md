# central-nexus-indexer

A no-delete build of the Maven Indexer CLI, used to update the Central search index incrementally.

## Why

The current index build re-reads all of Central (about 125 hours) to find about two weeks of new artifacts. The stock indexer also deletes any entry whose file it did not scan, so it cannot be pointed at only the new files. This build adds new artifacts and deletes nothing.

## Base

Maven Indexer tag `maven-indexer-4.1.2` (Lucene 3.0.3), the version Central runs today, with the two patches below. The built jar has the same 17 bundled libraries, at the same versions, as the jar Central runs.

Do not build from a Lucene 3.6 source (`maven-indexer-4.x`, or the 5.1.2 jar). The working `index/` folder it writes cannot be opened by the 4.1.2 jar (`CorruptIndexException: Unknown format version: -11`).

## Change

The repo holds two patches, not a copy of the source.

`patches/0001-no-delete-and-from-path.patch` touches four files and changes nothing unless the new options are used:

| Option | Meaning |
|---|---|
| (default) | No delete. Adds new or changed artifacts only |
| `-m`, `--delete-missing` | Old behaviour: delete entries for files not found |
| `-p`, `--from-path` | Scan only one sub-path of the repository |

`patches/0002-plexus-utils-3.1.0.patch` adds a direct dependency on `plexus-utils` 3.1.0, the version in Central's jar. The 4.1.2 build otherwise bundles 2.0.5, whose XML parser throws `ArrayIndexOutOfBoundsException` on a processing instruction (such as `<?m2e ignore?>`) after character 8192 of a pom, and that stops the whole run.

`patches/0003-skip-unreadable-pom.patch` handles a pom the XML parser throws an error on. The artifact is still indexed, without name and description (as for a pom with broken XML). It is logged as `[ERROR] Unreadable pom, indexed without pom data: <path>` and counted in `Scanning errors`. The run stops with `Too many unreadable poms` when more than 0.1% of the files are like that, after at least 1000 files.

## Build

Needs `git` and `docker`.

    ./build.sh        # writes out/indexer-4.1.2-nodelete-cli.jar
    EXCLUDE="0002" ./build.sh   # leaves a patch out, only for the skip test below

## Run

    java -Xms8g -Xmx26g -jar out/indexer-4.1.2-nodelete-cli.jar \
      -r <repo-dir> -i <index-dir> -d <publish-dir> \
      -t min,osgi-metadatas,maven-archetype -n central -c -s -e [-p <sub-path>]

The repository name defaults to the index folder name and must match the name stored in the existing index (`central`). Always pass `-n`; otherwise a differently named folder fails with a `NullPointerException` in `removeIndexingContext`.

Always start from the existing index. A fresh index changes the chain ID, and every client then re-downloads the full 3.3 GB.

## Memory and disk

The indexer loads all existing entries (about 115 million) before it scans, and a heap of 16 GB ran out of memory there. Use `-Xms8g -Xmx26g` or more. Each update run also copies the whole existing index (about 51 GB) into a temporary folder next to it, so allow room for the index three times over, plus the files being indexed.

## Limits

- It never removes entries, so artifacts that are later deleted from the repository stay in the index until a full rebuild.
- The list of files to scan is up to the caller. A file that no longer exists cannot be indexed.
- The run window should start at the previous run's start, not its end, because files can appear in folders a long scan has already passed. Files that are already indexed are skipped.

## Verify

    tests/verify-incremental.sh JAR BEFORE_INDEX AFTER_INDEX BEFORE_PUBLISH AFTER_PUBLISH [EXPECTED_ADDED]

Checks that artifacts were added, none deleted, the chain ID is unchanged and a new incremental chunk was written. Needs a JDK (`javac`).

    tests/verify-skip-unreadable-pom.sh SKIP_JAR [CONTROL_JAR [FINAL_JAR]]

The second test runs the real pom that crashed the first sizing run (`tests/fixtures/verbatime-0.8.2.pom`, a `<?m2e ignore?>` after character 8192). SKIP_JAR is built with `EXCLUDE="0002"`: it must index the pom without pom data, log and count it, stop at 3 bad poms in 1100 files and go on at 1 in 1100. CONTROL_JAR is built with `EXCLUDE="0002 0003"` and must crash. FINAL_JAR is the normal build and must read the pom with no error.

## Archetype catalog

After the index update, run the catalog tool on the published `.index`, then merge into the current catalog:

    DRY_RUN=1 scripts/merge-archetype-catalog.sh CURRENT.xml NEW.xml

The new catalog alone misses older archetypes, so always merge into the current one. See `scripts/MERGE-METHOD.md`. `tools/Merge.java` is a sorted alternative: it reproduces the live catalog order, where the script appends at the end.

## Results so far

Tested on a copy of the production index (115,697,725 artifacts), adding files published after the last full build. Three runs in a row, each on top of the one before:

| Run | New files | Artifacts added | Deleted | Indexer time |
|---|---|---|---|---|
| 1 | 25,995 | 23,580 | 0 | 61 min |
| 2 | 99,984 | 40,889 | 0 | 65 min |
| 3 | 71,907 | 46,596 | 0 | 64 min |

- The index ended at 115,808,790 artifacts: the starting count plus everything added.
- The chain ID did not change, and the chunk number went up by one each run.
- No artifact from the starting index was missing afterwards.
- Running 2,000 of the same files again added nothing and deleted nothing.
- The jar that Central runs today read the final published index in full: 115,808,790 artifacts, the same count.
- A run takes about an hour whatever its size. Copying the index, loading it and writing it back is most of that, so fewer, larger runs are cheaper.
