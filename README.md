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

## Build

Needs `git` and `docker`.

    ./build.sh        # writes out/indexer-4.1.2-nodelete-cli.jar

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

## Archetype catalog

After the index update, run the catalog tool on the published `.index`, then merge into the current catalog:

    DRY_RUN=1 scripts/merge-archetype-catalog.sh CURRENT.xml NEW.xml

The new catalog alone misses older archetypes, so always merge into the current one. See `scripts/MERGE-METHOD.md`. `tools/Merge.java` is a sorted alternative: it reproduces the live catalog order, where the script appends at the end.

## Results so far

Tested on a copy of the production index: 585 added, 0 deleted, 58 minutes. Central's 4.1.2 jar read the result in full (115,009,998 artifacts).
