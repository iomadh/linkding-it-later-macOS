//
//  NetworkMonitor.swift
//  LinkdingosApp
//

import Foundation
import Network
import Combine

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: NWInterface.InterfaceType?

    let networkBecameAvailable = PassthroughSubject<Void, Never>()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dellah.linkdingos.networkmonitor")
    private var wasConnected: Bool = true

    private init() {
        monitor = NWPathMonitor()
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    private func handlePathUpdate(_ path: NWPath) {
        let newConnected = path.status == .satisfied
        let previouslyConnected = wasConnected

        isConnected = newConnected
        wasConnected = newConnected

        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = nil
        }

        // Notify when network becomes available (was offline, now online)
        if newConnected && !previouslyConnected {
            networkBecameAvailable.send()
        }
    }
}
