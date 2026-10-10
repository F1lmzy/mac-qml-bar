import Foundation

// Boundary proof only. No donor Model, hardware access, permissions or observers.
// All facade state and callback delivery are owned by the macOS main thread.
@objc(PillNativeBackend)
public final class NativeBackend: NSObject {
    @objc public private(set) static var liveInstanceCount = 0
    private var callback: (() -> Void)?
    private var generation: UInt64 = 0

    public override init() {
        precondition(Thread.isMainThread)
        super.init()
        Self.liveInstanceCount += 1
    }

    @objc(startWithCallback:)
    public func start(callback: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        generation &+= 1
        let current = generation
        self.callback = callback
        // Exercise an asynchronous worker -> native main -> Qt queued delivery.
        let deliver = { [weak self] in
            guard let self, self.generation == current else { return }
            self.callback?()
        }
        // Create the weak capture on main. Creating another weak capture on
        // the worker can temporarily retain self there and deinit off-thread.
        DispatchQueue.global().async {
            DispatchQueue.main.async(execute: deliver)
        }
    }

    // Serialized with delivery on main. Once this returns, old deliveries
    // fail their generation check even if the backend is still alive.
    @objc public func stop() {
        precondition(Thread.isMainThread)
        generation &+= 1
        callback = nil
    }

    deinit {
        precondition(Thread.isMainThread)
        Self.liveInstanceCount -= 1
    }
}
