#!/usr/bin/env bash
# Builds the no-delete indexer CLI jar from the maven-indexer-4.1.2 tag plus patches/.
set -euo pipefail

TAG=maven-indexer-4.1.2
here=$(cd "$(dirname "$0")" && pwd)
out=${OUT:-$here/out}
m2=${M2:-$here/.m2-cache}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$out" "$m2"
git clone -q --depth 1 --branch "$TAG" https://github.com/sonatype/maven-indexer.git "$work/src"
git -C "$work/src" apply "$here"/patches/*.patch

docker run --rm -v "$work/src":/work -v "$m2":/root/.m2 -w /work \
  maven:3.8.8-eclipse-temurin-8 mvn -B -q -DskipTests package

cp "$work/src/indexer-core/target/indexer-core-4.1.2-cli.jar" "$out/indexer-4.1.2-nodelete-cli.jar"
echo "built $out/indexer-4.1.2-nodelete-cli.jar"
