import Foundation
import Combine
import AppKit
import Darwin

struct SpaceInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let number: Int

    static func == (lhs: SpaceInfo, rhs: SpaceInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SpaceAPIAvailability: Equatable {
    case available
    case disabled
    case permissionRequired
    case permissionDenied
    case unavailable
}

class SpaceManager: ObservableObject {
    static let shared = SpaceManager()
    // DesktopRenamer changed its application bundle identifier. Keep the
    // legacy identifier for users who still have the older release installed.
    static let desktopRenamerBundleIdentifiers = [
        "dev.mqiu.DesktopRenamer",
        "com.michaelqiu.DesktopRenamer"
    ]
    static let desktopRenamerDownloadURL = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest")!
    private static var desktopRenamerSocketPath: String {
        "/tmp/dev.mqiu.DesktopRenamer-\(getuid()).sock"
    }

    private enum APITransport: Equatable {
        case distributedNotifications
        case socket
    }

    private struct PendingRequest {
        let method: String
        let transport: APITransport
        var allowsSocketAccessRequest = false
    }

    private let apiPrefix = "com.michaelqiu.DesktopRenamer"
    private let jsonRPCVersion = "2.0"
    private let payloadKey = "payload"

    // Structured SpaceAPI channels.
    private lazy var rpcRequest = Notification.Name("\(apiPrefix).RPCRequest")
    private lazy var rpcResponse = Notification.Name("\(apiPrefix).RPCResponse")
    private lazy var rpcEvent = Notification.Name("\(apiPrefix).RPCEvent")

    // Legacy state notification is retained so older DesktopRenamer versions
    // can still signal API availability while the structured probe is pending.
    private lazy var legacyAPIState = Notification.Name("\(apiPrefix).ReturnAPIState")
    private lazy var legacyGetActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    private lazy var legacyGetSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    private lazy var legacyReturnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    private lazy var legacyReturnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")

    @Published var currentSpaceID: String?
    @Published var currentSpaceName: String = "Unknown"
    @Published var availableSpaces: [SpaceInfo] = []
    @Published var isAPIEnabled: Bool = false
    @Published private(set) var apiAvailability: SpaceAPIAvailability = .unavailable

    private var notificationObservers: [NSObjectProtocol] = []
    private var structuredAPIAvailable = false
    private var structuredProbeInFlight = false
    private var structuredProbeGeneration = 0
    private var pendingRequests: [String: PendingRequest] = [:]
    private var activeTransport: APITransport?
    private var socketConnection: SpaceAPISocketConnection?
    private var socketConnectionGeneration = 0
    private var socketConnectionInFlight = false
    private var hasUserRequestedSpaceAPIAccess = false
    private var lastSnapshotRevision: UInt64?

    private init() {
        startListening()
    }

    deinit {
        socketConnection?.close()
        let center = DistributedNotificationCenter.default()
        notificationObservers.forEach(center.removeObserver)
    }

    private func startListening() {
        let center = DistributedNotificationCenter.default()

        notificationObservers.append(center.addObserver(
            forName: rpcResponse,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRPCResponse(notification)
        })

        notificationObservers.append(center.addObserver(
            forName: rpcEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRPCEvent(notification)
        })

        // Keep the availability signal for compatibility with older API
        // versions. Structured snapshots remain the primary data source.
        notificationObservers.append(center.addObserver(
            forName: legacyAPIState,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLegacyAPIState(notification)
        })

        notificationObservers.append(center.addObserver(
            forName: legacyReturnActiveSpace,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLegacyActiveSpace(notification)
        })

        notificationObservers.append(center.addObserver(
            forName: legacyReturnSpaceList,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLegacySpaceList(notification)
        })

        // Negotiate the structured contract before falling back to legacy.
        requestStructuredAPIInfo()
    }

    func refreshSpaceList() {
        if structuredAPIAvailable {
            requestStructuredSnapshot()
        } else if socketConnection != nil {
            guard !structuredProbeInFlight else { return }
            structuredProbeInFlight = true
            structuredProbeGeneration += 1
            requestStructuredAPIInfo(over: .socket)
        } else {
            requestStructuredAPIInfo()
        }
    }

    func requestSpaceAPIAccess() {
        switch apiAvailability {
        case .available:
            refreshSpaceList()
            return
        case .disabled, .permissionRequired, .permissionDenied, .unavailable:
            break
        }

        hasUserRequestedSpaceAPIAccess = true
        guard !socketConnectionInFlight else { return }
        if structuredProbeInFlight {
            guard let requestID = pendingRequests.first(where: {
                $0.value.method == "getAPIInfo" && $0.value.transport == .distributedNotifications
            })?.key,
            var pendingRequest = pendingRequests[requestID] else { return }

            pendingRequest.allowsSocketAccessRequest = true
            pendingRequests[requestID] = pendingRequest
            return
        }

        if socketConnection != nil {
            structuredProbeInFlight = true
            structuredProbeGeneration += 1
            _ = requestStructuredAPIInfo(over: .socket, allowsSocketAccessRequest: true)
        } else {
            requestStructuredAPIInfo(allowsSocketAccessRequest: true)
        }
    }

    var desktopRenamerApplicationURL: URL? {
        Self.desktopRenamerBundleIdentifiers
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    func openDesktopRenamer() {
        guard let applicationURL = desktopRenamerApplicationURL else { return }
        NSWorkspace.shared.open(applicationURL)

        // DesktopRenamer starts its API listener after the application launch
        // callback, so retry while it finishes initializing instead of leaving
        // the status page stuck at unavailable after the first probe races it.
        for delay in [0.5, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshSpaceList()
            }
        }
    }

    func openDesktopRenamerDownloadPage() {
        NSWorkspace.shared.open(Self.desktopRenamerDownloadURL)
    }

    private func requestStructuredAPIInfo(allowsSocketAccessRequest: Bool? = nil) {
        guard !structuredAPIAvailable, !structuredProbeInFlight else { return }

        structuredProbeInFlight = true
        structuredProbeGeneration += 1
        let generation = structuredProbeGeneration
        let requestID = requestStructuredAPIInfo(
            over: .distributedNotifications,
            allowsSocketAccessRequest: allowsSocketAccessRequest ?? shouldRequestSocketAccess
        )

        // A pre-1.0 DesktopRenamer does not know the RPC channel and will
        // never respond. Keep this background probe nonprompting; a socket
        // access request is issued only after the user enables space matching
        // or explicitly requests access.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self,
                  self.structuredProbeGeneration == generation,
                  self.structuredProbeInFlight,
                  let pendingRequest = self.pendingRequests[requestID] else { return }

            self.pendingRequests.removeValue(forKey: requestID)
            self.structuredProbeInFlight = false
            if pendingRequest.allowsSocketAccessRequest {
                self.connectSocket(to: Self.desktopRenamerSocketPath, fallbackToNotifications: false)
            } else {
                self.refreshLegacySpaceList()
                if self.isDesktopRenamerRunning {
                    self.apiAvailability = .permissionRequired
                }
            }
        }
    }

    private func requestStructuredSnapshot() {
        guard let transport = activeTransport else { return }
        let requestID = UUID().uuidString
        pendingRequests[requestID] = PendingRequest(method: "getSpaceSnapshot", transport: transport)
        postStructuredRequest(id: requestID, method: "getSpaceSnapshot", over: transport)
    }

    @discardableResult
    private func requestStructuredAPIInfo(
        over transport: APITransport,
        allowsSocketAccessRequest: Bool = false
    ) -> String {
        let requestID = UUID().uuidString
        pendingRequests[requestID] = PendingRequest(
            method: "getAPIInfo",
            transport: transport,
            allowsSocketAccessRequest: allowsSocketAccessRequest
        )
        postStructuredRequest(id: requestID, method: "getAPIInfo", over: transport)
        return requestID
    }

    private func postStructuredRequest(id: String, method: String, over transport: APITransport) {
        let request: [String: Any] = [
            "jsonrpc": jsonRPCVersion,
            "id": id,
            "method": method,
            "requestedAccess": "read"
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let payload = String(data: data, encoding: .utf8) else {
            print("OptClicker: Could not encode DesktopRenamer API request: \(method)")
            return
        }

        switch transport {
        case .distributedNotifications:
            DistributedNotificationCenter.default().postNotificationName(
                rpcRequest,
                object: nil,
                userInfo: [payloadKey: payload],
                deliverImmediately: true
            )
        case .socket:
            guard socketConnection?.send(payload) == true else {
                pendingRequests.removeValue(forKey: id)
                socketConnection?.close()
                return
            }
        }
    }

    private func handleRPCResponse(_ notification: Notification) {
        guard let payload = notification.userInfo?[payloadKey] as? String,
              let data = payload.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        handleStructuredResponse(response, over: .distributedNotifications)
    }

    private func handleStructuredResponse(_ response: [String: Any], over transport: APITransport) {
        guard
              let requestID = response["id"] as? String,
              let pendingRequest = pendingRequests.removeValue(forKey: requestID),
              pendingRequest.transport == transport else {
            return
        }

        if let error = response["error"] as? [String: Any] {
            let code = (error["code"] as? NSNumber)?.intValue
            if code == -32001 {
                setDisconnected(as: .disabled)
            } else if code == -32003 {
                setDisconnected(as: .permissionDenied)
            } else if pendingRequest.method == "getAPIInfo" {
                structuredProbeInFlight = false
                if transport == .socket {
                    setDisconnected()
                } else {
                    structuredAPIAvailable = false
                    refreshLegacySpaceList()
                }
            } else {
                structuredProbeInFlight = false
                isAPIEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.structuredAPIAvailable else { return }
                    self.requestStructuredSnapshot()
                }
            }
            return
        }

        guard let result = response["result"] as? [String: Any] else { return }

        switch pendingRequest.method {
        case "getAPIInfo":
            guard isCompatibleAPIInfo(result) else {
                structuredProbeInFlight = false
                if transport == .socket {
                    setDisconnected()
                } else {
                    refreshLegacySpaceList()
                }
                return
            }

            if transport == .distributedNotifications,
               (result["transports"] as? [String])?.contains("unixDomainSocket") == true,
               let endpointPath = result["socketEndpoint"] as? String {
                let notificationsAvailable = result["legacyNotifications"] as? Bool ?? true
                connectSocket(to: endpointPath, fallbackToNotifications: notificationsAvailable)
            } else if transport == .distributedNotifications,
                      result["legacyNotifications"] as? Bool == false {
                setDisconnected()
            } else {
                activateStructuredAPI(over: transport)
            }

        case "getSpaceSnapshot":
            applyStructuredSnapshot(result, isEvent: false)

        default:
            break
        }
    }

    private func isCompatibleAPIInfo(_ info: [String: Any]) -> Bool {
        let supportsSnapshots = (info["supportedMethods"] as? [String])?.contains("getSpaceSnapshot") == true
        let supportsJSONRPC = info["jsonRPCVersion"] as? String == jsonRPCVersion
        guard let contractVersion = info["contractVersion"] as? String else { return false }
        return supportsSnapshots && supportsJSONRPC && isSupportedContractVersion(contractVersion)
    }

    private func activateStructuredAPI(over transport: APITransport) {
        structuredProbeGeneration += 1
        structuredProbeInFlight = false
        structuredAPIAvailable = true
        activeTransport = transport
        apiAvailability = .available
        isAPIEnabled = true
        requestStructuredSnapshot()
    }

    private func connectSocket(to endpointPath: String, fallbackToNotifications: Bool) {
        guard endpointPath == Self.desktopRenamerSocketPath else {
            if fallbackToNotifications {
                activateStructuredAPI(over: .distributedNotifications)
            } else {
                setDisconnected()
            }
            return
        }

        guard socketConnection == nil, !socketConnectionInFlight else { return }
        socketConnectionGeneration += 1
        let generation = socketConnectionGeneration
        socketConnectionInFlight = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let connection = try? SpaceAPISocketConnection(
                endpointPath: endpointPath,
                onMessage: { [weak self] message in
                    DispatchQueue.main.async {
                        self?.handleSocketMessage(message)
                    }
                },
                onClose: { [weak self] in
                    DispatchQueue.main.async {
                        self?.handleSocketClosed(generation: generation)
                    }
                }
            )

            DispatchQueue.main.async {
                guard generation == self.socketConnectionGeneration else {
                    connection?.close()
                    return
                }
                self.socketConnectionInFlight = false

                guard let connection else {
                    if fallbackToNotifications {
                        self.activateStructuredAPI(over: .distributedNotifications)
                    } else {
                        self.setDisconnected()
                        self.refreshLegacySpaceList()
                    }
                    return
                }

                self.socketConnection = connection
                self.structuredProbeInFlight = true
                self.structuredProbeGeneration += 1
                _ = self.requestStructuredAPIInfo(over: .socket)
            }
        }
    }

    private func handleSocketMessage(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if message["id"] as? String != nil {
            handleStructuredResponse(message, over: .socket)
        } else if let error = message["error"] as? [String: Any],
                  let code = (error["code"] as? NSNumber)?.intValue {
            if code == -32001 {
                setDisconnected(as: .disabled)
            } else if code == -32003 {
                setDisconnected(as: .permissionDenied)
            }
        } else {
            handleRPCEventPayload(payload, over: .socket)
        }
    }

    private func handleSocketClosed(generation: Int) {
        guard generation == socketConnectionGeneration else { return }

        socketConnection = nil
        socketConnectionInFlight = false
        pendingRequests = pendingRequests.filter { $0.value.transport != .socket }

        guard activeTransport == .socket || structuredProbeInFlight else { return }
        setDisconnected()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.requestStructuredAPIInfo()
        }
    }

    private func isSupportedContractVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".")
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return false
        }

        return major > 1 || (major == 1 && (minor > 0 || (minor == 0 && patch >= 0)))
    }

    private var isDesktopRenamerRunning: Bool {
        Self.desktopRenamerBundleIdentifiers.contains { bundleIdentifier in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
    }

    private var shouldRequestSocketAccess: Bool {
        hasUserRequestedSpaceAPIAccess
            || UserDefaults.standard.bool(forKey: InputManager.isBasedOnSpacesKey)
    }

    private func handleRPCEvent(_ notification: Notification) {
        guard let payload = notification.userInfo?[payloadKey] as? String else { return }
        handleRPCEventPayload(payload, over: .distributedNotifications)
    }

    private func handleRPCEventPayload(_ payload: String, over transport: APITransport) {
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["jsonrpc"] as? String == jsonRPCVersion,
              event["method"] as? String == "stateChanged",
              let params = event["params"] as? [String: Any],
              let snapshot = params["snapshot"] as? [String: Any] else {
            return
        }

        structuredAPIAvailable = true
        structuredProbeInFlight = false
        activeTransport = activeTransport ?? transport
        apiAvailability = .available
        applyStructuredSnapshot(snapshot, isEvent: true)
    }

    private func applyStructuredSnapshot(_ snapshot: [String: Any], isEvent: Bool) {
        guard let rawSpaces = snapshot["spaces"] as? [[String: Any]] else { return }

        let revision = (snapshot["revision"] as? NSNumber)?.uint64Value
        if isEvent, let revision, let lastRevision = lastSnapshotRevision {
            if revision <= lastRevision { return }
            if revision != lastRevision + 1 {
                requestStructuredSnapshot()
                return
            }
        }

        let spaces = rawSpaces.compactMap { rawSpace -> SpaceInfo? in
            // Persist and compare the public SpaceAPI identity. managedSpaceID
            // is the current macOS ID and can change independently.
            guard let id = rawSpace["id"] as? String,
                  let name = rawSpace["name"] as? String,
                  let number = (rawSpace["number"] as? NSNumber)?.intValue else {
                return nil
            }
            return SpaceInfo(id: id, name: name, number: number)
        }.sorted { $0.number < $1.number }

        let currentSpaceIDs = snapshot["currentSpaceIDs"] as? [String] ?? []
        currentSpaceID = currentSpaceIDs.first
        currentSpaceName = snapshot["currentSpaceName"] as? String ?? "Unknown"
        availableSpaces = spaces
        isAPIEnabled = true
        apiAvailability = .available

        if let revision {
            lastSnapshotRevision = revision
        }
    }

    private func handleLegacyAPIState(_ notification: Notification) {
        guard let isEnabled = notification.userInfo?["isEnabled"] as? Bool else { return }

        if isEnabled {
            if !structuredAPIAvailable {
                requestStructuredAPIInfo()
            } else {
                requestStructuredSnapshot()
            }
        } else {
            setDisconnected(as: .disabled)
        }
    }

    private func refreshLegacySpaceList() {
        guard !structuredAPIAvailable else { return }

        let center = DistributedNotificationCenter.default()
        center.postNotificationName(
            legacyGetSpaceList,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        center.postNotificationName(
            legacyGetActiveSpace,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func handleLegacyActiveSpace(_ notification: Notification) {
        guard !structuredAPIAvailable,
              let info = notification.userInfo else { return }

        currentSpaceID = info["spaceUUID"] as? String
        currentSpaceName = info["spaceName"] as? String ?? "Unknown"
        isAPIEnabled = true
        apiAvailability = .available
    }

    private func handleLegacySpaceList(_ notification: Notification) {
        guard !structuredAPIAvailable,
              let info = notification.userInfo,
              let rawSpaces = info["spaces"] as? [[String: Any]] else { return }

        availableSpaces = rawSpaces.compactMap { rawSpace -> SpaceInfo? in
            guard let id = rawSpace["spaceUUID"] as? String,
                  let name = rawSpace["spaceName"] as? String,
                  let number = (rawSpace["spaceNumber"] as? NSNumber)?.intValue else {
                return nil
            }
            return SpaceInfo(id: id, name: name, number: number)
        }.sorted { $0.number < $1.number }
        isAPIEnabled = true
        apiAvailability = .available
    }

    private func setDisconnected(as availability: SpaceAPIAvailability = .unavailable) {
        socketConnectionGeneration += 1
        socketConnectionInFlight = false
        let connection = socketConnection
        socketConnection = nil
        structuredAPIAvailable = false
        structuredProbeInFlight = false
        structuredProbeGeneration += 1
        pendingRequests.removeAll()
        activeTransport = nil
        lastSnapshotRevision = nil
        apiAvailability = availability
        isAPIEnabled = false
        availableSpaces.removeAll()
        currentSpaceName = "Disconnected"
        currentSpaceID = nil
        connection?.close()
    }
}
