import Foundation

// Owns one child and its pipe handlers. All methods except process callbacks are
// called on main. Process output is only parsed on main via the callback made
// by WindowManagerIntegration.start; stop terminates and reaps this child only.
final class CommandStream {
    private let path: String
    private let arguments: [String]
    private let queue = DispatchQueue(label: "local.pill.command-stream", qos: .utility)
    private let lock = NSLock()
    private var process: Process?
    private var pipe: Pipe?
    private var stopped = true
    private var token = 0

    init(path: String, arguments: [String]) { self.path = path; self.arguments = arguments }

    func start(onData: @escaping (Data) -> Void, onTermination: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        stop()
        lock.lock(); stopped = false; token += 1; let current = token; lock.unlock()
        let path = self.path, arguments = self.arguments
        queue.async { [weak self] in
            guard let self = self, !self.isStopped(current) else { return }
            let child = Process(), output = Pipe()
            child.executableURL = URL(fileURLWithPath: path); child.arguments = arguments
            child.standardOutput = output; child.standardError = FileHandle.nullDevice
            output.fileHandleForReading.readabilityHandler = { handle in
                guard let data = try? handle.read(upToCount: 16384) else { return }
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isStopped(current) else { return }
                    onData(data)
                }
            }
            child.terminationHandler = { [weak self] _ in
                child.terminationHandler = nil
                output.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isStopped(current) else { return }
                    self.clear(current)
                    onTermination()
                }
            }
            do {
                try child.run()
                guard self.install(child, output, current) else {
                    Self.reap(child)
                    return
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isStopped(current) else { return }
                    self.clear(current); onTermination()
                }
            }
        }
    }

    func stop() {
        precondition(Thread.isMainThread)
        lock.lock(); stopped = true; token += 1; let currentPipe = pipe; pipe = nil
        let child = process; process = nil; lock.unlock()
        currentPipe?.fileHandleForReading.readabilityHandler = nil
        try? currentPipe?.fileHandleForReading.close()
        guard let child = child else { return }
        child.terminationHandler = nil
        if child.isRunning { child.terminate() }
        queue.async { Self.reap(child) }
    }

    private static func reap(_ child: Process) {
        if child.isRunning { child.terminate() }
        let deadline = Date().addingTimeInterval(0.5)
        while child.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
    }
    private func isStopped(_ expected: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped || token != expected
    }
    private func install(_ child: Process, _ output: Pipe, _ expected: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, token == expected else { return false }
        process = child; pipe = output
        return true
    }
    private func clear(_ expected: Int) {
        lock.lock(); defer { lock.unlock() }
        guard token == expected else { return }
        process = nil; pipe = nil
    }
}
