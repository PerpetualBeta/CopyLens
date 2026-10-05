import Foundation

// Diagnostic logging, off by default. Turn it on with:
//   defaults write cc.jorviksoftware.CopyLens CopyLens.debugLogging -bool YES
//   defaults delete cc.jorviksoftware.CopyLens CopyLens.debugLogging   # turn off
// When on, timestamped lines are appended to
//   ~/Library/Logs/CopyLens/copylens.log
// and the lines before the last rotation are kept in copylens.log.1. The flag is
// read on every call, so turning it on or off needs no relaunch.
//
// Until 2026-10-05 the log was /tmp/copylens.log, emptied at each launch. /tmp is
// shared by every process, so a predictable name there invites a symlink attack;
// this is the Jorvik convention instead: a symlink-safe append to a 0700 directory.
private let logDirectory: URL = FileManager.default
    .urls(for: .libraryDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Logs", isDirectory: true)
    .appendingPathComponent("CopyLens", isDirectory: true)
private let logPath = logDirectory.appendingPathComponent("copylens.log").path
private let previousLogPath = logDirectory.appendingPathComponent("copylens.log.1").path

private let logQueue = DispatchQueue(label: "cc.jorviksoftware.CopyLens.log")

private let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

/// Rotate once the live log passes this many bytes, keeping one previous
/// generation, so the logs can never occupy more than twice this figure.
/// 4 MB by default, as in the other Jorvik apps; a knob for a long session:
///
///     defaults write cc.jorviksoftware.CopyLens debugLogMaxBytes -int 20971520
private var logMaxBytes: Int {
    let stored = UserDefaults.standard.integer(forKey: "debugLogMaxBytes")
    return stored > 0 ? stored : 4 * 1024 * 1024
}

func clog(_ msg: String) {
    guard UserDefaults.standard.bool(forKey: "CopyLens.debugLogging") else { return }
    let stamp = timestampFormatter.string(from: Date())
    let limit = logMaxBytes
    logQueue.async {
        append("\(stamp)  \(msg)\n")
        // One process and one serial queue write this file, so the size read here
        // is the file just written to, and nothing can rotate it in between.
        var info = stat()
        guard stat(logPath, &info) == 0, info.st_size >= limit else { return }
        unlink(previousLogPath)
        guard rename(logPath, previousLogPath) == 0 else { return }
        append("\(stamp)  log rotated at \(info.st_size) bytes; the lines before this are in copylens.log.1\n")
    }
}

/// Appends one line. Runs on `logQueue` only.
private func append(_ line: String) {
    guard let data = line.data(using: .utf8) else { return }
    try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    // O_NOFOLLOW + the 0700 parent directory close the symlink-attack vector.
    let fd = open(logPath, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return }
    defer { close(fd) }
    data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
}
