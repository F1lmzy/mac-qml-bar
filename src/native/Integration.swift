// Native integration boundary. Donor provenance: third_party/omacosy/SOURCE.md.
import Foundation

struct IntegrationFailure: Error {
    let code: String
    let message: String
    init(_ code: String = "nativeFailure", _ message: String) { self.code = code; self.message = message }
}

final class IntegrationCancellation {
    private let lock = NSLock()
    private var canceled = false
    private var handler: (() -> Void)?
    var isCanceled: Bool { lock.lock(); defer { lock.unlock() }; return canceled }
    func install(_ handler: @escaping () -> Void) {
        lock.lock(); self.handler = handler; let now = canceled; lock.unlock()
        if now { handler() }
    }
    func cancel() {
        lock.lock(); canceled = true; let h = handler; handler = nil; lock.unlock(); h?()
    }
    func clear() { lock.lock(); handler = nil; lock.unlock() }
}

// All lifecycle, snapshot, callback and permission work is main-thread-only.
// Worker closures must capture drivers/values, NOT a service or weak service.
class PillIntegration: NSObject {
    static var liveInstanceCount = 0
    override init() { precondition(Thread.isMainThread); super.init(); PillIntegration.liveInstanceCount += 1 }
    let worker = DispatchQueue(label: "local.pill.integration.\(UUID().uuidString)", qos: .utility)
    var state: [String: Any] = ["available": false, "lastErrorCode": "", "lastError": ""]
    private var callback: (([String: Any]) -> Void)?
    private var generation = 0
    private var operations: [UUID: IntegrationCancellation] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timers: [Timer] = []
    var running: Bool { callback != nil }

    func start(_ callback: @escaping ([String: Any]) -> Void) {
        precondition(Thread.isMainThread); stop(); self.callback = callback; refresh()
    }
    func refresh() {}
    func invoke(_ action: String, _ argument: Any) { fail(action, "unsupported", "This action is unavailable.") }
    func publish(_ fields: [String: Any]) {
        precondition(Thread.isMainThread)
        state = ["available": false, "lastErrorCode": "", "lastError": ""].merging(fields) { _, new in new }
        if running { callback?(state) }
    }
    func fail(_ operation: String, _ code: String, _ message: String) {
        var next = state; next["lastErrorCode"] = code; next["lastError"] = message
        next["errorOperation"] = operation; publish(next)
    }
    func observe(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main, using: body)
        observers.append((center, token))
    }
    func every(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in body() }
        RunLoop.main.add(timer, forMode: .common); timers.append(timer)
    }
    func perform(_ operation: String, work: @escaping (IntegrationCancellation) throws -> [String: Any],
                 receive: (([String: Any]) -> Void)? = nil, failure: ((IntegrationFailure) -> Void)? = nil) {
        precondition(Thread.isMainThread)
        guard running else { return }
        let id = UUID(), cancellation = IntegrationCancellation(), token = generation
        operations[id] = cancellation
        // Create the weak closure on main, never resolve a service on worker.
        let deliver: (Result<[String: Any], Error>) -> Void = { [weak self] result in
            guard let self = self, self.running, self.generation == token else { return }
            self.operations.removeValue(forKey: id)
            switch result {
            case .success(let next):
                if let receive = receive { receive(next) } else { self.publish(next) }
            case .failure(let error):
                let e = (error as? IntegrationFailure) ?? IntegrationFailure("nativeFailure", String(describing: error))
                if let failure = failure { failure(e) } else { self.fail(operation, e.code, e.message) }
            }
        }
        worker.async {
            guard !cancellation.isCanceled else { return }
            let result = Result { try work(cancellation) }
            cancellation.clear()
            DispatchQueue.main.async { deliver(result) }
        }
    }
    func stop() {
        precondition(Thread.isMainThread)
        generation += 1; callback = nil
        operations.values.forEach { $0.cancel() }; operations.removeAll()
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        timers.forEach { $0.invalidate() }; timers.removeAll()
    }
    deinit { precondition(Thread.isMainThread); PillIntegration.liveInstanceCount -= 1 }
}

func finiteUnit(_ argument: Any) throws -> Double {
    guard let value = argument as? NSNumber, value.doubleValue.isFinite else {
        throw IntegrationFailure("invalidInput", "Expected a finite normalized number.")
    }
    return min(1, max(0, value.doubleValue))
}
