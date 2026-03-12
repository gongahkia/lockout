import Foundation
import Network
import Combine

@MainActor
public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    @Published public private(set) var isConnected: Bool = true
    private var _forcedOffline: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self._forcedOffline { self.isConnected = path.status == .satisfied }
            }
        }
        monitor.start(queue: queue)
    }

    /// test-only: override connection state (synchronous, call on main thread)
    public func forceOffline(_ offline: Bool) {
        _forcedOffline = offline
        isConnected = !offline
    }
}
