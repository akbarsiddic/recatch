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
        // The dashboard opens its own connection while capture is writing: WAL + a busy
        // timeout keep reads from failing with "database is locked".
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA busy_timeout=3000;")
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

    func logLLM(provider: String, model: String, tokensIn: Int, tokensOut: Int, windowSec: Int) throws {        try run("""
            INSERT INTO llm_log(id,t,provider,model,tokens_in,tokens_out,window_sec)
            VALUES(?,?,?,?,?,?,?);
            """, [UUID().uuidString, Int64(Date().timeIntervalSince1970 * 1000),
                  provider, model, tokensIn, tokensOut, windowSec])
    }

    struct LLMLogEntry: Sendable {
        let t: Int64
        let provider: String
        let model: String
        let tokensIn: Int
        let tokensOut: Int
        let windowSec: Int
    }

    /// What left this Mac (timestamp + size only, never content). Newest first.
    func fetchLLMLog(limit: Int = 50) throws -> [LLMLogEntry] {
        let sql = "SELECT t,provider,model,tokens_in,tokens_out,window_sec FROM llm_log ORDER BY t DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw NSError(domain: "Radar", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int64(s, 1, Int64(limit))
        var out: [LLMLogEntry] = []
        while sqlite3_step(s) == SQLITE_ROW {
            func text(_ col: Int32) -> String {
                sqlite3_column_text(s, col).map { String(cString: $0) } ?? ""
            }
            out.append(LLMLogEntry(t: sqlite3_column_int64(s, 0), provider: text(1), model: text(2),
                                   tokensIn: Int(sqlite3_column_int64(s, 3)),
                                   tokensOut: Int(sqlite3_column_int64(s, 4)),
                                   windowSec: Int(sqlite3_column_int64(s, 5))))
        }
        return out
    }

    /// Hourly janitor: delete rows past expires_at + vacuum.
    // MARK: - Dashboard reads

    struct MeetingSummary: Identifiable, Sendable {
        let id: UUID
        let title: String
        let startedAt: Date
        let endedAt: Date?
        let segments: Int
        let preview: String

        var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    }

    /// Newest first — the Meetings pane and Overview "today" counts both use this.
    func listMeetings(limit: Int = 200) throws -> [MeetingSummary] {
        let sql = """
            SELECT m.id, COALESCE(m.title,''), m.started_at, m.ended_at,
                   (SELECT COUNT(*) FROM segments s WHERE s.meeting_id=m.id),
                   COALESCE((SELECT text FROM segments s WHERE s.meeting_id=m.id ORDER BY t_start LIMIT 1),'')
            FROM meetings m ORDER BY m.started_at DESC LIMIT ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw NSError(domain: "Radar", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int64(s, 1, Int64(limit))
        var out: [MeetingSummary] = []
        while sqlite3_step(s) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(s, 0))
            let started = sqlite3_column_int64(s, 2)
            let ended: Int64? = sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 3)
            out.append(MeetingSummary(
                id: UUID(uuidString: id) ?? UUID(),
                title: String(cString: sqlite3_column_text(s, 1)),
                startedAt: Date(timeIntervalSince1970: Double(started) / 1000),
                endedAt: ended.map { Date(timeIntervalSince1970: Double($0) / 1000) },
                segments: Int(sqlite3_column_int64(s, 4)),
                preview: String(cString: sqlite3_column_text(s, 5))))
        }
        return out
    }

    func renameMeeting(id: UUID, title: String) throws {
        try run("UPDATE meetings SET title=? WHERE id=?;", [title, id.uuidString])
    }

    func deleteMeeting(id: UUID) throws {
        try run("DELETE FROM segments WHERE meeting_id=?;", [id.uuidString])
        try run("DELETE FROM meetings WHERE id=?;", [id.uuidString])
    }

    /// Bytes on disk (WAL included) — the Privacy pane shows real numbers, not a guess.
    func storageBytes() -> Int64 {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ["ReCatch.sqlite", "ReCatch.sqlite-wal", "ReCatch.sqlite-shm"].reduce(0) { sum, name in
            let path = dir.appendingPathComponent(name).path
            let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            return sum + (size ?? 0)
        }
    }

    func purgeExpired() throws {
        try exec("DELETE FROM meetings WHERE expires_at < strftime('%s','now')*1000; VACUUM;")
    }

    func deleteEverything() throws {
        // FK on: deleting meetings cascades. Also clear logs + settings per spec.
        try exec("DELETE FROM meetings; DELETE FROM llm_log; DELETE FROM settings; VACUUM;")
    }
}
