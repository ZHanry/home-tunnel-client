PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS device (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, hostname TEXT NOT NULL,
 platform TEXT NOT NULL, arch TEXT NOT NULL, version TEXT NOT NULL,
 ip_last TEXT NOT NULL, mac TEXT NOT NULL DEFAULT '', room TEXT NOT NULL DEFAULT '',
 owner TEXT NOT NULL DEFAULT '', online_at INTEGER NOT NULL, created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS session_log (
 seq INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT NOT NULL UNIQUE,
 device_id TEXT NOT NULL REFERENCES device(id), peer_id TEXT NOT NULL, peer_ip TEXT NOT NULL,
 action TEXT NOT NULL CHECK(action IN ('start','end')), at INTEGER NOT NULL,
 duration_s INTEGER, conn_type TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS session_device_at ON session_log(device_id,at);
CREATE INDEX IF NOT EXISTS session_at ON session_log(at);
CREATE TABLE IF NOT EXISTS wol_target (
 device_id TEXT PRIMARY KEY REFERENCES device(id), mac TEXT NOT NULL,
 broadcast_ip TEXT NOT NULL, port INTEGER NOT NULL DEFAULT 9
);
CREATE TABLE IF NOT EXISTS setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);
PRAGMA user_version=1;
