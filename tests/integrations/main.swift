import Foundation

func runIntegrationFixtures() throws {
        try runDisplayTests()
        try runPrivacyTests()
        try runWindowManagerTests()
        try runLifecycleTests()
        runEmptyWorkspaceTests()
        runWorkspaceEventTests()
        try runThemeTests()
        // Shared-service mode has no local theme watcher, catalog or helper.
        let sharedTheme = ServiceOwnedThemeIntegration()
        var sharedSnapshot: [String: Any] = [:]
        sharedTheme.start { sharedSnapshot = $0 }
        precondition(sharedSnapshot["available"] as? Bool == false)
        precondition(sharedSnapshot["canNext"] as? Bool == false)
        precondition(sharedSnapshot["canSelect"] as? Bool == false)
        precondition((sharedSnapshot["themes"] as? [[String: String]])?.isEmpty == true)
        sharedTheme.invoke("next", ["confirmed": true])
        precondition(sharedSnapshot["lastErrorCode"] as? String == "serviceOwned")
        sharedTheme.refresh()
        precondition(sharedSnapshot["lastErrorCode"] as? String == "")
        sharedTheme.stop()
        try runThumbnailTests()
        let duplicateMonitor = Data(#"[{"monitor-id":1,"monitor-name":"A"},{"monitor-id":1,"monitor-name":"B"}]"#.utf8)
        do {
            _ = try WindowManagerModels.snapshot(workspaces: Data(#"[{"workspace":"empty","monitor-id":1,"workspace-is-visible":true}]"#.utf8),
                monitors: duplicateMonitor, windows: Data("[]".utf8), focusedWorkspace: Data("empty".utf8), focusedWindow: Data("[]".utf8))
            preconditionFailure("duplicate monitor accepted")
        } catch is WMParseError { }
        let gamma = try GammaTable(red: [0, 0.5, 1], green: [0, 0.4, 1], blue: [0, 0.3, 1])
        let shaded = try gamma.shaded(1)
        let unshaded = try gamma.shaded(0)
        precondition(abs(shaded.red[2] - 0.15) < 0.001 && gamma.matches(unshaded))
        do { _ = try GammaTable(red: [.nan], green: [0], blue: [0]); preconditionFailure("invalid gamma accepted") } catch {}
        let metadata = SpotifyMetadata.parse(["Player State": "Paused", "Name": "Track", "Artist": "Artist"])
        precondition(metadata["known"] as? Bool == true && metadata["playing"] as? Bool == false)
        precondition(SpotifyMetadata.parse([:])["known"] as? Bool == false)
        let weather = try WeatherSnapshot.parse(Data(#"{"current_condition":[{"temp_C":"20","weatherDesc":[{"value":"Clear"}]}]}"#.utf8))
        precondition(weather["temperatureC"] as? String == "20")
        do { _ = try WeatherSnapshot.parse(Data("{}".utf8)); preconditionFailure("invalid weather accepted") } catch {}
        // Test transport off-main, with only owned harmless fixture commands.
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            do {
                let echo = try CommandRunner.run("/bin/echo", ["fixture"])
                precondition(String(data: echo.stdout, encoding: .utf8) == "fixture\n")
                do { _ = try CommandRunner.run("/bin/sleep", ["1"], timeout: 0.1); preconditionFailure("timeout ignored") }
                catch let error as IntegrationFailure { precondition(error.code == "timeout") }
                let cancellation = IntegrationCancellation(); cancellation.cancel()
                do { _ = try CommandRunner.run("/bin/echo", ["must-not-run"], cancellation: cancellation); preconditionFailure("cancel ignored") }
                catch let error as IntegrationFailure { precondition(error.code == "canceled") }
                print("PASS: native integration, permission, WM, gamma, metadata and transport fixtures")
            } catch { fatalError(String(describing: error)) }
            done.signal()
        }
        precondition(done.wait(timeout: .now() + 5) == .success)
}
try runIntegrationFixtures()
