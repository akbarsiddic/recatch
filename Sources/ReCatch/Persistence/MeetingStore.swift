import Foundation
import SQLite3

/// SQLite store: meetings/segments/notes/nudges/settings/llm_log. No audio persisted.
final class MeetingStore {
    private var db: OpaquePointer?

    init(path: String) throws {
        var tmp: OpaquePointer?
        let rc = path.withCString { sqlite3_open($0, &tmp) }
        guard rc == SQLITE_OK, let opened = tmp else { throw NSError(domain: "Radar", code: 2) }
        db = opened
        try exec("PRAGMA foreign_keys=ON;")
        try exec(schema)
    }

    deinit { sqlite3_close(db) }

    private let schema = """
    CREATE TABLE IF NOT EXISTS meetings(id TEXT PRIMARY KEY, started_at INTEGER, ended_at INTEGER, title TEXT, output_language TEXT, expires_at INTEGER);
    CREATE TABLE IF NOT EXISTS segments(id TEXT PRIMARY KEY, meeting_id TEXT REFERENCES meetings(id) ON DELETE CASCADE, t_start INTEGER, t_end INTEGER, stream TEXT, lang TEXT, text TEXT, confidence REAL);
    CREATE TABLE IF NOT EXISTS notes(id TEXT PRIMARY KEY, meeting_id TEXT REFERENCES meetings(id) ON DELETE CASCADE, t_start INTEGER, t_end INTEGER, kind TEXT, text TEXT);
    CREATE TABLE IF NOT EXISTS nudges(id TEXT PRIMARY KEY, meeting_id TEXT REFERENCES meetings(id) ON DELETE CASCADE, t INTEGER, kind TEXT, segment_ids TEXT, dismissed INTEGER DEFAULT 0, marked_irrelevant INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE IF NOT EXISTS llm_log(id TEXT PRIMARY KEY, t INTEGER, provider TEXT, model TEXT, tokens_in INTEGER, tokens_out INTEGER, window_sec INTEGER);
    """

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sql.withCString { sqlite3_exec(db, $0, nil, nil, &err) }
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "sql error"
            throw NSError(domain: "Radar", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    func insertSegment(_ s: TranscriptSegment) throws {
        let sql = "INSERT INTO segments(id,meeting_id,t_start,t_end,stream,lang,text,confidence) VALUES('\(s.id.uuidString)','\(s.meetingId.uuidString)',\(s.tStartMs),\(s.tEndMs),'\(s.stream.rawValue)','\(s.lang)','\(s.text.replacingOccurrences(of: "'", with: "''"))',\(s.confidence));"
        try exec(sql)
    }

    func logLLM(provider: String, model: String, tokensIn: Int, tokensOut: Int, windowSec: Int) throws {
        try exec("INSERT INTO llm_log(id,t,provider,model,tokens_in,tokens_out,window_sec) VALUES('\(UUID().uuidString)',\(Int(Date().timeIntervalSince1970*1000)),'\(provider)','\(model)',\(tokensIn),\(tokensOut),\(windowSec));")
    }

    /// Hourly janitor: delete rows past expires_at + vacuum.
    func purgeExpired() throws {
        try exec("DELETE FROM meetings WHERE expires_at < strftime('%s','now')*1000; VACUUM;")
    }

    func deleteEverything() throws {
        // FK on: deleting meetings cascades. Also clear logs + settings per spec.
        try exec("DELETE FROM meetings; DELETE FROM llm_log; DELETE FROM settings; VACUUM;")
    }
}
