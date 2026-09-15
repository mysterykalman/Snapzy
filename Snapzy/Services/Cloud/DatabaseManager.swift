//
//  DatabaseManager.swift
//  Snapzy
//
//  Singleton managing the SQLite database connection and schema migrations via GRDB
//

import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "DatabaseManager")

struct DatabaseRecoveryArchive {
  let archiveDirectoryURL: URL?
  let archivedFileURLs: [URL]

  var isEmpty: Bool {
    archivedFileURLs.isEmpty
  }
}

enum DatabaseInitializationError: LocalizedError {
  case directoryCreationFailed(directoryURL: URL, underlyingError: Error)
  case openOrMigrationFailed(databaseURL: URL, underlyingError: Error)

  var errorDescription: String? {
    switch self {
    case let .directoryCreationFailed(directoryURL, underlyingError):
      return "Could not create database directory at \(directoryURL.path): \(underlyingError.localizedDescription)"
    case let .openOrMigrationFailed(databaseURL, underlyingError):
      return "Could not open or migrate database at \(databaseURL.path): \(underlyingError.localizedDescription)"
    }
  }

  var recoverySuggestion: String? {
    "Try repairing the database, reset it after backing up the existing files, or quit Snapzy."
  }

  var databaseURL: URL {
    switch self {
    case let .directoryCreationFailed(directoryURL, _):
      return directoryURL.appendingPathComponent("snapzy.db")
    case let .openOrMigrationFailed(databaseURL, _):
      return databaseURL
    }
  }
}

/// Manages the SQLite database connection and schema migrations
final class DatabaseManager: @unchecked Sendable {

  private static let stateLock = NSLock()
  private static var sharedInstance: DatabaseManager?
  private static var sharedFailure: DatabaseInitializationError?
  private static let databaseFileNames = ["snapzy.db", "snapzy.db-wal", "snapzy.db-shm"]

  let dbPool: DatabasePool
  let databaseURL: URL

  // The project builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so
  // without this, the compiler synthesizes an isolated deinit that hits a
  // Swift runtime bug in swift_task_deinitOnExecutorMainActorBackDeploy,
  // corrupting the heap when a *non-singleton* instance of this class is
  // deallocated (DatabaseManager.shared() never triggers it because that
  // instance lives for the app's whole lifetime -- but DatabaseManager
  // instances created directly via openDatabase(at:), e.g. in tests, do).
  // Same root cause and fix as BrowserBridgeCoordinator's nonisolated deinit.
  nonisolated deinit {}

  private init(databaseURL: URL = DatabaseManager.defaultDatabaseURL) throws {
    let dir = databaseURL.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      throw DatabaseInitializationError.directoryCreationFailed(
        directoryURL: dir,
        underlyingError: error
      )
    }

    do {
      dbPool = try DatabasePool(path: databaseURL.path)
      try Self.migrator.migrate(dbPool)
      self.databaseURL = databaseURL
      logger.info("Database initialized at \(databaseURL.path)")
    } catch {
      throw DatabaseInitializationError.openOrMigrationFailed(
        databaseURL: databaseURL,
        underlyingError: error
      )
    }
  }

  @discardableResult
  static func prepare() -> Result<DatabaseManager, DatabaseInitializationError> {
    stateLock.lock()
    defer { stateLock.unlock() }

    if let sharedInstance {
      return .success(sharedInstance)
    }
    if let sharedFailure {
      return .failure(sharedFailure)
    }

    do {
      let manager = try DatabaseManager()
      sharedInstance = manager
      return .success(manager)
    } catch let error as DatabaseInitializationError {
      sharedFailure = error
      logger.error("Database initialization failed: \(error.localizedDescription)")
      return .failure(error)
    } catch {
      let wrappedError = DatabaseInitializationError.openOrMigrationFailed(
        databaseURL: defaultDatabaseURL,
        underlyingError: error
      )
      sharedFailure = wrappedError
      logger.error("Database initialization failed: \(wrappedError.localizedDescription)")
      return .failure(wrappedError)
    }
  }

  static func shared() throws -> DatabaseManager {
    switch prepare() {
    case let .success(manager):
      return manager
    case let .failure(error):
      throw error
    }
  }

  static func openDatabase(at databaseURL: URL) throws -> DatabaseManager {
    try DatabaseManager(databaseURL: databaseURL)
  }

  static func retryInitialization() -> Result<DatabaseManager, DatabaseInitializationError> {
    clearCachedFailure()
    return prepare()
  }

  static func attemptRepair() throws {
    switch retryInitialization() {
    case .success:
      return
    case let .failure(error):
      throw error
    }
  }

  static func resetDatabaseFiles() throws -> DatabaseRecoveryArchive {
    clearCachedState()
    return try archiveDatabaseFiles(named: databaseFileNames)
  }

  static var defaultDatabaseURL: URL {
    databaseDirectory().appendingPathComponent("snapzy.db")
  }

  private static func databaseDirectory() -> URL {
    #if DEBUG
      if isRunningUnderXCTest {
        let processID = ProcessInfo.processInfo.processIdentifier
        return FileManager.default.temporaryDirectory
          .appendingPathComponent("SnapzyTests", isDirectory: true)
          .appendingPathComponent("Databases", isDirectory: true)
          .appendingPathComponent("runner-\(processID)", isDirectory: true)
      }
    #endif

    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport.appendingPathComponent("Snapzy", isDirectory: true)
  }

  static var isRunningUnderXCTest: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  // MARK: - Migrations

  private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    #if DEBUG
      // Speed up development by nuking the database when migrations change
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1_createCloudUploadRecords") { db in
      try db.create(table: "cloudUploadRecord") { t in
        t.column("id", .text).primaryKey()
        t.column("fileName", .text).notNull()
        t.column("publicURL", .text).notNull()
        t.column("key", .text).notNull()
        t.column("fileSize", .integer).notNull()
        t.column("uploadedAt", .datetime).notNull()
        t.column("providerType", .text).notNull()
        t.column("expireTime", .text).notNull()
        t.column("contentType", .text)
      }
      try db.create(
        index: "idx_cloudUploadRecord_uploadedAt",
        on: "cloudUploadRecord",
        columns: ["uploadedAt"]
      )
      try db.create(
        index: "idx_cloudUploadRecord_key",
        on: "cloudUploadRecord",
        columns: ["key"]
      )
    }

    migrator.registerMigration("v2_createCaptureHistoryRecords") { db in
      try db.create(table: "captureHistoryRecord") { t in
        t.column("id", .text).primaryKey()
        t.column("filePath", .text).notNull()
        t.column("fileName", .text).notNull()
        t.column("captureType", .text).notNull()
        t.column("fileSize", .integer).notNull()
        t.column("capturedAt", .datetime).notNull()
        t.column("width", .integer)
        t.column("height", .integer)
        t.column("duration", .double)
        t.column("thumbnailPath", .text)
        t.column("isDeleted", .boolean).notNull().defaults(to: false)
      }
      try db.create(
        index: "idx_captureHistory_type",
        on: "captureHistoryRecord",
        columns: ["captureType"]
      )
      try db.create(
        index: "idx_captureHistory_capturedAt",
        on: "captureHistoryRecord",
        columns: ["capturedAt"]
      )
      try db.create(
        index: "idx_captureHistory_deleted",
        on: "captureHistoryRecord",
        columns: ["isDeleted"]
      )
    }

    migrator.registerMigration("v3_createBaselines") { db in
      try db.create(table: "baseline") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("createdAt", .datetime).notNull()
        t.column("sourceCaptureID", .text).notNull()
        t.column("viewportWidth", .double)
        t.column("viewportHeight", .double)
      }
      try db.create(
        index: "idx_baseline_sourceCaptureID",
        on: "baseline",
        columns: ["sourceCaptureID"]
      )

      try db.create(table: "baselineComparison") { t in
        t.column("id", .text).primaryKey()
        t.column("baselineID", .text).notNull()
        t.column("comparedCaptureID", .text).notNull()
        t.column("comparedAt", .datetime).notNull()
        t.column("differingRatio", .double).notNull()
        // `threshold` is a Codable enum with an associated value
        // (ChangeThreshold), so GRDB's derived Codable-record support
        // stores it as a JSON blob in this one column rather than
        // needing a separate kind/value column pair.
        t.column("threshold", .blob).notNull()
        t.column("approvalState", .text).notNull()
      }
      try db.create(
        index: "idx_baselineComparison_baselineID",
        on: "baselineComparison",
        columns: ["baselineID"]
      )
      try db.create(
        index: "idx_baselineComparison_comparedAt",
        on: "baselineComparison",
        columns: ["comparedAt"]
      )
    }

    return migrator
  }

  private static func clearCachedFailure() {
    stateLock.lock()
    if sharedInstance == nil {
      sharedFailure = nil
    }
    stateLock.unlock()
  }

  private static func clearCachedState() {
    stateLock.lock()
    sharedInstance = nil
    sharedFailure = nil
    stateLock.unlock()
  }

  private static func archiveDatabaseFiles(named fileNames: [String]) throws -> DatabaseRecoveryArchive {
    try archiveDatabaseFiles(
      in: databaseDirectory(),
      fileNames: fileNames,
      timestamp: recoveryTimestamp()
    )
  }

  private static func archiveDatabaseFiles(
    in directoryURL: URL,
    fileNames: [String],
    timestamp: String
  ) throws -> DatabaseRecoveryArchive {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let existingFileURLs = fileNames
      .map { directoryURL.appendingPathComponent($0) }
      .filter { fileManager.fileExists(atPath: $0.path) }

    guard !existingFileURLs.isEmpty else {
      return DatabaseRecoveryArchive(archiveDirectoryURL: nil, archivedFileURLs: [])
    }

    let archiveDirectoryURL = uniqueArchiveDirectoryURL(
      in: directoryURL,
      timestamp: timestamp,
      fileManager: fileManager
    )
    try fileManager.createDirectory(at: archiveDirectoryURL, withIntermediateDirectories: true)

    var archivedFileURLs: [URL] = []
    for fileURL in existingFileURLs {
      let destinationURL = archiveDirectoryURL.appendingPathComponent(fileURL.lastPathComponent)
      try fileManager.moveItem(at: fileURL, to: destinationURL)
      archivedFileURLs.append(destinationURL)
    }

    logger.warning("Archived database files in \(archiveDirectoryURL.path)")
    return DatabaseRecoveryArchive(
      archiveDirectoryURL: archiveDirectoryURL,
      archivedFileURLs: archivedFileURLs
    )
  }

  private static func recoveryTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }

  private static func uniqueArchiveDirectoryURL(
    in directoryURL: URL,
    timestamp: String,
    fileManager: FileManager
  ) -> URL {
    let baseName = "DatabaseRecovery-\(timestamp)"
    var candidateURL = directoryURL.appendingPathComponent(baseName, isDirectory: true)
    var suffix = 2

    while fileManager.fileExists(atPath: candidateURL.path) {
      candidateURL = directoryURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
      suffix += 1
    }

    return candidateURL
  }

  #if DEBUG
    static func archiveDatabaseFilesForTesting(
      in directoryURL: URL,
      fileNames: [String],
      timestamp: String = "20260605-000000"
    ) throws -> DatabaseRecoveryArchive {
      try archiveDatabaseFiles(in: directoryURL, fileNames: fileNames, timestamp: timestamp)
    }
  #endif
}
