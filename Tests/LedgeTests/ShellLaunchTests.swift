import XCTest
@testable import Ledge

/// Covers how a terminal's shell is chosen, named, placed, and given an
/// environment, without starting one.
final class ShellLaunchTests: XCTestCase {
    // MARK: - Shell

    func testTheAccountShellWinsWhenItCanRun() {
        let shell = ShellLaunch.shellPath(
            accountShell: "/opt/homebrew/bin/fish",
            environmentShell: "/bin/bash",
            isExecutable: { _ in true }
        )
        XCTAssertEqual(shell, "/opt/homebrew/bin/fish")
    }

    func testAShellThatCannotRunFallsBackToShellThenZsh() {
        XCTAssertEqual(
            ShellLaunch.shellPath(
                accountShell: "/gone/fish",
                environmentShell: "/bin/bash",
                isExecutable: { $0 == "/bin/bash" }
            ),
            "/bin/bash"
        )
        XCTAssertEqual(
            ShellLaunch.shellPath(accountShell: nil, environmentShell: nil, isExecutable: { _ in false }),
            "/bin/zsh"
        )
    }

    func testARelativeShellIsNeverRun() {
        XCTAssertEqual(
            ShellLaunch.shellPath(accountShell: "zsh", environmentShell: "bash", isExecutable: { _ in true }),
            "/bin/zsh"
        )
    }

    func testTheShellStartsAsALoginShell() {
        XCTAssertEqual(ShellLaunch.loginName(for: "/bin/zsh"), "-zsh")
        XCTAssertEqual(ShellLaunch.loginName(for: "/opt/homebrew/bin/fish"), "-fish")
    }

    // MARK: - Directory

    func testARememberedDirectoryIsUsedWhileItExists() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let project = URL(fileURLWithPath: "/Users/someone/project", isDirectory: true)

        XCTAssertEqual(
            ShellLaunch.startingDirectory(preferred: project, home: home, isDirectory: { _ in true }),
            "/Users/someone/project"
        )
        XCTAssertEqual(
            ShellLaunch.startingDirectory(preferred: project, home: home, isDirectory: { _ in false }),
            "/Users/someone"
        )
        XCTAssertEqual(
            ShellLaunch.startingDirectory(preferred: nil, home: home, isDirectory: { _ in true }),
            "/Users/someone"
        )
    }

    // MARK: - Environment

    private func environment(
        _ inherited: [String: String],
        locale: Locale = Locale(identifier: "en_AU"),
        localeExists: (String) -> Bool = { _ in true }
    ) -> [String: String] {
        let pairs = ShellLaunch.environment(
            inheriting: inherited,
            shell: "/bin/zsh",
            locale: locale,
            appVersion: "1.2.3",
            localeExists: localeExists
        )
        return Dictionary(uniqueKeysWithValues: pairs.map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? parts[1] : "")
        })
    }

    func testTheShellIsToldItRunsInLedge() {
        let env = environment(["TERM": "dumb", "TERM_PROGRAM": "Apple_Terminal", "HOME": "/Users/someone"])

        XCTAssertEqual(env["TERM"], "xterm-256color")
        XCTAssertEqual(env["COLORTERM"], "truecolor")
        XCTAssertEqual(env["TERM_PROGRAM"], "Ledge")
        XCTAssertEqual(env["TERM_PROGRAM_VERSION"], "1.2.3")
        XCTAssertEqual(env["SHELL"], "/bin/zsh")
        XCTAssertEqual(env["HOME"], "/Users/someone")
    }

    func testWhateverLaunchedLedgeIsNotPassedOn() {
        let env = environment([
            "SHLVL": "3",
            "PWD": "/somewhere",
            "TERM_SESSION_ID": "abc",
            "__CFBundleIdentifier": "com.apple.Terminal",
            "XPC_SERVICE_NAME": "application.io.github.brucez001.ledge"
        ])

        for key in ["SHLVL", "PWD", "TERM_SESSION_ID", "__CFBundleIdentifier", "XPC_SERVICE_NAME"] {
            XCTAssertNil(env[key], key)
        }
    }

    func testAnExistingLanguageIsKept() {
        XCTAssertEqual(environment(["LANG": "fr_FR.UTF-8"])["LANG"], "fr_FR.UTF-8")
    }

    func testAMissingLanguageFollowsTheUsersLocale() {
        XCTAssertEqual(environment([:])["LANG"], "en_AU.UTF-8")
    }

    func testAnUnknownLocaleFallsBackToUSEnglish() {
        XCTAssertEqual(environment([:], localeExists: { _ in false })["LANG"], "en_US.UTF-8")
        XCTAssertEqual(
            ShellLaunch.localeName(for: Locale(identifier: "en"), exists: { _ in true }),
            "en_US.UTF-8"
        )
    }

    func testTheEnvironmentIsDeterministic() {
        let pairs = ShellLaunch.environment(
            inheriting: ["B": "2", "A": "1"],
            shell: "/bin/zsh",
            locale: Locale(identifier: "en_AU"),
            appVersion: nil,
            localeExists: { _ in true }
        )
        XCTAssertEqual(pairs, pairs.sorted())
        XCTAssertFalse(pairs.contains { $0.hasPrefix("TERM_PROGRAM_VERSION=") })
    }
}
