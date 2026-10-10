import Foundation

@objc(PillAudioService)
public final class AudioService: NSObject {
    // Main-thread lifetime diagnostic used by the teardown tests.
    @objc public private(set) static var liveInstanceCount = 0
    private let queue = DispatchQueue(label: "local.pill.audio", qos: .utility)
    private var controller: AudioController!
    private var callback: ((NSDictionary) -> Void)?
    private var generation = 0
    private var pendingVolume: DispatchWorkItem?

    @objc public init(fake: Bool) {
        super.init()
        precondition(Thread.isMainThread)
        Self.liveInstanceCount += 1
        let hardware: AudioHardware = fake ? FakeAudioHardware() : CoreAudioHardware(queue: queue)
        let worker = queue
        controller = AudioController(hardware: hardware, retry: { work in
            worker.asyncAfter(deadline: .now() + .seconds(1), execute: work)
        })
    }

    @objc public func start(callback: @escaping (NSDictionary) -> Void) {
        precondition(Thread.isMainThread)
        stop()
        self.callback = callback
        let token = generation
        // Resolve the weak facade only on main, never on the hardware worker.
        let deliver: (NSDictionary) -> Void = { [weak self] snapshot in
            guard let self = self, self.generation == token else { return }
            self.callback?(snapshot)
        }
        let controller = self.controller!
        queue.async {
            controller.start { state in
                let snapshot = state as NSDictionary
                DispatchQueue.main.async { deliver(snapshot) }
            }
        }
    }

    @objc public func setVolume(_ value: Double, device: UInt32) {
        precondition(Thread.isMainThread)
        guard callback != nil else { return }
        if !value.isFinite {
            let controller = self.controller!
            queue.async { controller.setVolume(value, device: device) }
            return // Invalid actions report errors even amid coalesced dragging.
        }
        pendingVolume?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.callback != nil else { return }
            let controller = self.controller!
            self.queue.async { controller.setVolume(value, device: device) }
        }
        pendingVolume = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20), execute: work)
    }

    @objc public func setMuted(_ value: Bool, device: UInt32) {
        precondition(Thread.isMainThread)
        guard callback != nil else { return }
        let controller = self.controller!
        queue.async { controller.setMuted(value, device: device) }
    }

    @objc public func stop() {
        precondition(Thread.isMainThread)
        generation += 1
        callback = nil
        pendingVolume?.cancel()
        pendingVolume = nil
        let controller = self.controller!
        queue.async { controller.stop() }
    }

    deinit {
        precondition(Thread.isMainThread)
        Self.liveInstanceCount -= 1
        // Explicit stop is the adapter's contract; also protect direct users.
        let controller = self.controller!
        queue.async { controller.stop() }
    }
}
