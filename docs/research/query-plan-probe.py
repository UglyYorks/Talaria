#!/usr/bin/env python3
"""Inspect candidate indexes on a synthetic subset of schema 11.

Uses an in-memory database only. This is query-plan evidence, not an app benchmark.
Schema sources: Source/DatabaseMigrator.m:154,285 and additive message columns.
Query sources: Source/Database.m:328,365,958.
"""
import sqlite3

database = sqlite3.connect(":memory:")
database.executescript("""
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id INTEGER NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('system','user','assistant')),
  content TEXT NOT NULL, thinking TEXT,
  attachments TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE browser_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url TEXT NOT NULL, title TEXT NOT NULL,
  visited_at TEXT NOT NULL DEFAULT (datetime('now')), favicon BLOB
);
CREATE INDEX browser_history_recent
  ON browser_history(visited_at DESC, id DESC);
""")
queries = {
    "transcript": ("SELECT id, role, content, thinking, attachments, created_at "
                   "FROM messages WHERE chat_id = ? ORDER BY id", (42,)),
    "prior favicon": ("SELECT favicon FROM browser_history WHERE url = ? "
                      "AND favicon IS NOT NULL ORDER BY id DESC LIMIT 1", ("https://example.test/",)),
    "full history": ("SELECT id, url, title, visited_at, favicon FROM browser_history "
                     "ORDER BY visited_at DESC, id DESC", ()),
}

def print_plans(label):
    print(label)
    for name, (sql, parameters) in queries.items():
        details = [row[3] for row in database.execute("EXPLAIN QUERY PLAN " + sql, parameters)]
        print(" ", name + ":", "; ".join(details))

print("Python SQLite version:", sqlite3.sqlite_version)
print_plans("Existing indexes")
database.executescript("""
CREATE INDEX proposed_messages_chat_id ON messages(chat_id, id);
CREATE INDEX proposed_browser_favicon
  ON browser_history(url, id DESC) WHERE favicon IS NOT NULL;
""")
print_plans("Candidate indexes")
database.close()
