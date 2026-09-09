# Browser import dependencies

Runtime sources only, with macOS configuration headers. No network fetch is needed at build time.

- Google LevelDB 1.23: https://github.com/google/leveldb/tree/1.23 (BSD-3-Clause, see leveldb-1.23/LICENSE).
- Google Snappy 1.1.9: https://github.com/google/snappy/tree/1.1.9 (BSD-3-Clause, see snappy-1.1.9/COPYING).

LevelDB handles manifests, WAL replay, tombstones and checksums on a private snapshot, avoiding recovery of deleted browser data. Snappy decodes compressed database blocks and Firefox values.
