import Darwin
import Foundation

/// Read-only questions about a terminal's shell, answered by the kernel.
///
/// Shells on macOS do not report their working directory or running command
/// unless the user's configuration asks them to, so Ledge reads both from
/// the process table instead of waiting for escape sequences.
enum ShellProcess {
    /// The working directory of `pid`, or `nil` once it has exited.
    static func currentDirectory(of pid: pid_t) -> URL? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The short process name of `pid`, such as `vim`.
    static func name(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    /// The foreground process group of `pid`'s terminal. While a shell sits at
    /// its prompt this is the shell itself.
    ///
    /// Read from the process table: on macOS `tcgetpgrp` only answers for the
    /// caller's own controlling terminal, which a shell's terminal is not.
    static func terminalForegroundGroup(of pid: pid_t) -> pid_t? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let group = pid_t(bitPattern: info.e_tpgid)
        return group > 0 ? group : nil
    }

    /// The job the user is running in front of the shell, or `nil` at the
    /// prompt. The shell runs as its own session and process-group leader,
    /// so any other foreground group is a command it started.
    static func foregroundJob(shellPID: pid_t) -> pid_t? {
        guard let group = terminalForegroundGroup(of: shellPID), group != shellPID else { return nil }
        return group
    }
}

/// Collects shells Ledge has hung up on.
///
/// A shell is Ledge's child, so once it exits it stays a zombie until Ledge
/// waits on it. SwiftTerm stops watching a process as soon as it is told to
/// terminate it, so closing a terminal hands the shell to this instead.
@MainActor
enum ShellReaper {
    private static var watchers: [pid_t: DispatchSourceProcess] = [:]

    /// Hangs up on `pid` and waits for it, without blocking.
    static func hangUp(_ pid: pid_t) {
        guard pid > 0 else { return }
        kill(pid, SIGHUP)
        reap(pid)
    }

    static func reap(_ pid: pid_t) {
        guard pid > 0, watchers[pid] == nil, !collect(pid) else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                watchers.removeValue(forKey: pid)?.cancel()
            }
            // The exit event can come just before the shell is waitable, so
            // this wait may block briefly; never on the main thread.
            DispatchQueue.global(qos: .utility).async {
                var status: Int32 = 0
                _ = waitpid(pid, &status, 0)
            }
        }
        watchers[pid] = source
        source.activate()
        // The exit may have landed between the first check and the source
        // starting to watch; a source on an already-gone process never fires.
        if collect(pid) {
            watchers.removeValue(forKey: pid)?.cancel()
        }
    }

    /// `true` once `pid` has been waited on, or is not Ledge's to wait on.
    private static func collect(_ pid: pid_t) -> Bool {
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        return result == pid || (result == -1 && errno == ECHILD)
    }
}
