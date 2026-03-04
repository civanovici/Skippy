import Foundation
import Network
import Observation

@MainActor
@Observable
final class ConnectivityStore {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "skippy.connectivity.monitor")

    private(set) var isNetworkReachable = true
    private(set) var isServerReachable = true

    var isOfflineEffective: Bool {
        !isNetworkReachable || !isServerReachable
    }

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isNetworkReachable = path.status == .satisfied
                self.isServerReachable = self.isNetworkReachable
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    func markServerReachable() {
        isServerReachable = true
    }

    func markServerUnreachable() {
        if isNetworkReachable {
            isServerReachable = false
        }
    }

    func reportResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            markServerReachable()
        case let .failure(error):
            if shouldTreatAsOffline(error) {
                markServerUnreachable()
            }
        }
    }

    private func shouldTreatAsOffline(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .networkUnreachable:
                return true
            default:
                return false
            }
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorTimedOut,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive,
             NSURLErrorDataNotAllowed,
             NSURLErrorSecureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
