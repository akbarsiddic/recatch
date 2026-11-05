import Foundation
import SQLite3

/// SQLite store: meetings/segments/notes/nudges/settings/llm_log. No audio persisted.
///
/// Threading: use from one thread/actor only (AudioCaptureManager hops writes to MainActor).
/// All values are bound via sqlite3_bind — transcript text is UNTRUSTED DATA, never interpolated.
final class MeetingStore {
    private var db: OpaquePointer?

    init(path: String) throws {
        var tmp: OpaquePointer?
        let rc = path.withCString { sqlite3_open($0, &tmp) }
        guard rc == SQLITE_OK, let opened = tmp else { throw NSError(domain: "Radar", code: 2) }
        db = opened
        try exec("PRAGMA foreign_keys=ON;")
        try exec(schema)
        // v2 migration: persist lang_prob (older DBs lack the column).
        try? exec("ALTER TABLE segments ADD COLUMN lang_prob REAL DEFAULT 0.8;")
    }

    deinit { sqlite3_close(db) }

    private let schema = """
    CREATE TABLE IF NOT EXISTS meetings(id TEXT PRIMARY KEY, started_at INTEGER, ended_at INTEGER, title TEXT, output_language TEXT, expires_at INTEGER);
    CREATE TABLE IF NOT EXISTS segments(id TEXT PRIMARY KEY, meeting_id TEXT REFERENCES meetings(id) ON DELETE CASCADE, t_start INTEGER, t_end INTEGER, stream TEXT, lang TEXT, lang_prob REAL DEFAULT 0.8, text TEXT, confidence REAL);
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

    /// Bound-parameter runner. Params: String, Int/Int64, Double. nil → NULL.
    private func run(_ sql: String, _ params: [Any?] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw NSError(domain: "Radar", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(s) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case nil:
                sqlite3_bind_null(s, idx)
            case let v as String:
                v.withCString { sqlite3_bind_text(s, idx, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            case let v as Int64:
                sqlite3_bind_int64(s, idx, v)
            case let v as Int:
                sqlite3_bind_int64(s, idx, Int64(v))
            case let v as Double:
                sqlite3_bind_double(s, idx, v)
            default:
                throw NSError(domain: "Radar", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "unsupported bind type \(type(of: p))"])
            }
        }
        guard sqlite3_step(s) == SQLITE_DONE else {
            throw NSError(domain: "Radar", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    // MARK: - Meetings

    /// Parent row — must exist before insertSegment (FK). Called once per Start listening.
    func createMeeting(id: UUID, title: String, outputLanguage: String,
                       startedAt: Int64, expiresAt: Int64) throws {
        try run("""
            INSERT INTO meetings(id,started_at,ended_at,title,output_language,expires_at)
            VALUES(?,?,?,?,?,?);
            """, [id.uuidString, startedAt, nil as Int?, title, outputLanguage, expiresAt])
    }

    func endMeeting(id: UUID, endedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws {
        try run("UPDATE meetings SET ended_at=? WHERE id=?;", [endedAt, id.uuidString])
    }

    // MARK: - Segments

    func insertSegment(_ s: TranscriptSegment) throws {
        try run("""
            INSERT INTO segments(id,meeting_id,t_start,t_end,stream,lang,lang_prob,text,confidence)
            VALUES(?,?,?,?,?,?,?,?,?);
            """, [s.id.uuidString, s.meetingId.uuidString, s.tStartMs, s.tEndMs,
                  s.stream.rawValue, s.lang, s.langProb, s.text, s.confidence])
    }

    /// Segments for one meeting, ordered — feeds Right now / Missed / Ask prompts.
    func fetchSegments(meetingId: UUID, sinceMs: Int64 = 0) throws -> [TranscriptSegment] {
        let sql = """
            SELECT id,meeting_id,t_start,t_end,stream,lang,COALESCE(lang_prob,0.8),text,confidence
            FROM segments WHERE meeting_id=? AND t_start>=? ORDER BY t_start;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw NSError(domain: "Radar", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(s) }
        meetingId.uuidString.withCString { sqlite3_bind_text(s, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        sqlite3_bind_int64(s, 2, sinceMs)
        var out: [TranscriptSegment] = []
        while sqlite3_step(s) == SQLITE_ROW {
            func text(_ col: Int32) -> String {
                sqlite3_column_text(s, col).map { String(cString: $0) } ?? ""
            }
            guard let id = UUID(uuidString: text(0)),
                  let mid = UUID(uuidString: text(1)) else { continue }
            let stream = AudioStream(rawValue: text(4)) ?? .system
            out.append(TranscriptSegment(
                id: id, meetingId: mid,
                tStartMs: sqlite3_column_int64(s, 2), tEndMs: sqlite3_column_int64(s, 3),
                stream: stream, lang: text(5), langProb: sqlite3_column_double(s, 6),
                text: text(7), confidence: sqlite3_column_double(s, 8)))
        }
        return out
    }

    /// "mm:ss text" lines for prompt windows.
    func transcriptText(meetingId: UUID, sinceMs: Int64 = 0) throws -> String {
        try fetchSegments(meetingId: meetingId, sinceMs: sinceMs).map { seg in
            let total = max(0, seg.tStartMs) / 1000
            return "[\(String(format: "%02d:%02d", total / 60, total % 60))] \(seg.text)"
        }.joined(separator: "\n")
    }

    func logLLM(provider: String, model: String, tokensIn: Int, tokensOut: Int, windowSec: Int) throws {
        try run("""
            INSERT INTO llm_log(id,t,provider,model,tokens_in,tokens_out,window_sec)
            VALUES(?,?,?,?,?,?,?);
            """, [UUID().uuidString, Int64(Date().timeIntervalSince1970 * 1000),
                  provider, model, tokensIn, tokensOut, windowSec])
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
