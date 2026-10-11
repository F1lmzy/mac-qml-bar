import Foundation
import Darwin

struct CommandOutput { let stdout: Data; let stderr: Data }
private final class CommandBuffer {
    private let lock = NSLock()
    private var bytes = Data()
    private(set) var overflow = false
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if bytes.count + data.count > 1_048_576 { overflow = true } else { bytes.append(data) }
    }
    func result() -> Data { lock.lock(); defer { lock.unlock() }; return bytes }
}

enum CommandRunner {
    // Called only on a worker. No shell interpolation, bounded output/time,
    // concurrent pipe draining, and stop only kills this service's own child.
    static func run(_ path: String, _ args: [String], timeout: Double = 5,
                    cancellation: IntegrationCancellation = IntegrationCancellation()) throws -> CommandOutput {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw IntegrationFailure("unavailable", "Executable is unavailable: \(path)")
        }
        guard !cancellation.isCanceled else { throw IntegrationFailure("canceled", "Operation canceled.") }
        let process = Process(), out = Pipe(), err = Pipe(), ended = DispatchSemaphore(value: 0)
        let output = CommandBuffer(), errors = CommandBuffer(), readers = DispatchGroup()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        process.standardOutput = out; process.standardError = err
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        cancellation.install { if process.isRunning { process.terminate() } }
        for (pipe, buffer) in [(out, output), (err, errors)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                while let data = try? pipe.fileHandleForReading.read(upToCount: 16384), !data.isEmpty {
                    buffer.append(data)
                    if buffer.overflow, process.isRunning { process.terminate() }
                }
                try? pipe.fileHandleForReading.close(); readers.leave()
            }
        }
        let timedOut = ended.wait(timeout: .now() + max(0.1, timeout)) == .timedOut
        if timedOut || cancellation.isCanceled {
            if process.isRunning { process.terminate() }
            if ended.wait(timeout: .now() + 0.3) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = ended.wait(timeout: .now() + 1)
            }
        }
        cancellation.clear()
        // A descendant retaining a pipe must not hold the worker forever.
        guard readers.wait(timeout: .now() + 1) == .success else {
            try? out.fileHandleForReading.close(); try? err.fileHandleForReading.close()
            throw IntegrationFailure("timeout", "Child output did not close.")
        }
        if cancellation.isCanceled { throw IntegrationFailure("canceled", "Operation canceled.") }
        if timedOut { throw IntegrationFailure("timeout", "Command timed out.") }
        guard !output.overflow, !errors.overflow else { throw IntegrationFailure("invalidResponse", "Command output exceeded limit.") }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let diagnostic = String(data: errors.result(), encoding: .utf8) ?? ""
            let code = diagnostic.contains("-1743") || diagnostic.localizedCaseInsensitiveContains("not authorized") ? "permissionDenied" : "nativeFailure"
            throw IntegrationFailure(code, diagnostic.isEmpty ? "Command failed (\(process.terminationStatus))." : String(diagnostic.prefix(1000)))
        }
        return CommandOutput(stdout: output.result(), stderr: errors.result())
    }
}
