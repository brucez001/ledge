import Darwin
import Foundation

/// How a terminal tab's shell is started: which program, under what name, in
/// which directory, and with which environment.
///
/// Ledge is started by launchd -- often at login -- so its own environment is
/// the minimal one launchd gives GUI apps, not the user's shell environment.
/// The shell is therefore started as a login shell (`argv[0]` prefixed with
/// `-`) so it reads the user's profile and builds `PATH` itself, the way
/// Terminal does.
struct ShellLaunch: Equatable {
    var executable: String
    /// `argv[0]`. A leading `-` is what makes the shell a login shell.
    var execName: String
    var directory: String
    /// `KEY=value` pairs, sorted so the result is deterministic.
    var environment: [String]

    /// The launch for a new shell, read from this Mac's account and process.
    static func current(directory preferred: URL?) -> ShellLaunch {
        let fileManager = FileManager.default
        let shell = shellPath(
            accountShell: accountShell(),
            environmentShell: ProcessInfo.processInfo.environment["SHELL"],
            isExecutable: fileManager.isExecutableFile(atPath:)
        )
        return ShellLaunch(
            executable: shell,
            execName: loginName(for: shell),
            directory: startingDirectory(
                preferred: preferred,
                home: fileManager.homeDirectoryForCurrentUser,
                isDirectory: isDirectory
            ),
            environment: environment(
                inheriting: ProcessInfo.processInfo.environment,
                shell: shell,
                locale: .current,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                localeExists: { fileManager.fileExists(atPath: "/usr/share/locale/\($0)") }
            )
        )
    }

    /// The account's login shell, falling back to `$SHELL` and then to zsh,
    /// the macOS default. Each candidate must be executable: a stale account
    /// record must not leave the user with a terminal that cannot start.
    static func shellPath(
        accountShell: String?,
        environmentShell: String?,
        isExecutable: (String) -> Bool
    ) -> String {
        for candidate in [accountShell, environmentShell] {
            guard let candidate, candidate.hasPrefix("/"), isExecutable(candidate) else { continue }
            return candidate
        }
        return "/bin/zsh"
    }

    static func loginName(for shell: String) -> String {
        "-" + (shell as NSString).lastPathComponent
    }

    /// The remembered directory when it still exists, else home.
    static func startingDirectory(
        preferred: URL?,
        home: URL,
        isDirectory: (String) -> Bool
    ) -> String {
        if let preferred, preferred.isFileURL, isDirectory(preferred.path) {
            return preferred.path
        }
        return home.path
    }

    /// Keys that describe the process that launched Ledge rather than the new
    /// shell. Passing them on would, for instance, tell programs they are
    /// running inside whichever terminal ran `swift run`.
    static let discardedKeys: Set<String> = [
        "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID",
        "COLORTERM", "SHLVL", "PWD", "OLDPWD", "_",
        "__CFBundleIdentifier", "XPC_SERVICE_NAME", "XPC_FLAGS",
        "ITERM_SESSION_ID", "ITERM_PROFILE", "LC_TERMINAL", "LC_TERMINAL_VERSION"
    ]

    static func environment(
        inheriting inherited: [String: String],
        shell: String,
        locale: Locale,
        appVersion: String?,
        localeExists: (String) -> Bool
    ) -> [String] {
        var environment = inherited.filter { !discardedKeys.contains($0.key) }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Ledge"
        if let appVersion, !appVersion.isEmpty {
            environment["TERM_PROGRAM_VERSION"] = appVersion
        }
        environment["SHELL"] = shell
        if environment["LANG"]?.isEmpty ?? true {
            environment["LANG"] = localeName(for: locale, exists: localeExists)
        }
        return environment.map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// A UTF-8 POSIX locale matching the user's language and region, such as
    /// `en_AU.UTF-8`. Without one, tools fall back to ASCII and mangle
    /// anything outside it.
    static func localeName(for locale: Locale, exists: (String) -> Bool) -> String {
        let fallback = "en_US.UTF-8"
        guard let language = locale.language.languageCode?.identifier,
              let region = locale.region?.identifier else { return fallback }
        let name = "\(language)_\(region).UTF-8"
        return exists(name) ? name : fallback
    }

    private static func accountShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
