import Foundation
import SQLite3

class StyleDB {
    static let shared = StyleDB()
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.ghostwriter.styledb")
    
    private init() {
        dbQueue.sync {
            openDatabase()
            createTable()
        }
    }
    
    deinit {
        dbQueue.sync {
            if db != nil {
                sqlite3_close(db)
            }
        }
    }
    
    private func openDatabase() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ StyleDB error: Could not find Application Support directory")
            return
        }
        
        let dbFolderURL = appSupportURL.appendingPathComponent("GhostWriter")
        do {
            try fileManager.createDirectory(at: dbFolderURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ StyleDB error: Could not create folder: \(error)")
            return
        }
        
        let dbPath = dbFolderURL.appendingPathComponent("style.db").path
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ StyleDB error: Could not open database at \(dbPath)")
        }
    }
    
    private func createTable() {
        let createTableQuery = """
        CREATE TABLE IF NOT EXISTS completions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_name TEXT,
            prefix TEXT,
            accepted_text TEXT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        
        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, createTableQuery, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.flatMap { String(cString: $0) } ?? "Unknown error"
            print("❌ StyleDB error: Creating table failed: \(error)")
            if let errorMsg = errorMsg {
                sqlite3_free(errorMsg)
            }
        }
    }
    
    func saveCompletion(appName: String, prefix: String, acceptedText: String) {
        dbQueue.sync {
            let insertQuery = "INSERT INTO completions (app_name, prefix, accepted_text) VALUES (?, ?, ?);"
            var statement: OpaquePointer?
            
            guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
                print("❌ StyleDB error: Failed to prepare insert statement")
                return
            }
            
            sqlite3_bind_text(statement, 1, (appName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (prefix as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (acceptedText as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                print("❌ StyleDB error: Insert failed: \(errmsg)")
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    func fetchRecentExamples(appName: String, limit: Int = 3) -> [String] {
        return dbQueue.sync {
            let selectQuery = "SELECT accepted_text FROM completions WHERE app_name = ? ORDER BY timestamp DESC LIMIT ?;"
            var statement: OpaquePointer?
            var examples: [String] = []
            
            guard sqlite3_prepare_v2(db, selectQuery, -1, &statement, nil) == SQLITE_OK else {
                print("❌ StyleDB error: Failed to prepare select statement")
                return []
            }
            
            sqlite3_bind_text(statement, 1, (appName as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let cString = sqlite3_column_text(statement, 0) {
                    examples.append(String(cString: cString))
                }
            }
            
            sqlite3_finalize(statement)
            return examples
        }
    }
    
    func getCompletionsCount() -> Int {
        return dbQueue.sync {
            let query = "SELECT COUNT(*) FROM completions;"
            var statement: OpaquePointer?
            var count = 0
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(statement, 0))
                }
            }
            sqlite3_finalize(statement)
            return count
        }
    }
}
