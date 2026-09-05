import Foundation
import Combine
import AppKit

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
    case unavailable
}

class SpaceManager: ObservableObject {
    static let shared = SpaceManager()
    static let desktopRenamerBundleIdentifier = "com.michaelqiu.DesktopRenamer"
    static let desktopRenamerDownloadURL = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest")!

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
    private var pendingRequests: [String: String] = [:]
    private var lastSnapshotRevision: UInt64?

    private init() {
        startListening()
    }

    deinit {
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
        } else {
            requestStructuredAPIInfo()
        }
    }

    var desktopRenamerApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.desktopRenamerBundleIdentifier)
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

    private func requestStructuredAPIInfo() {
        guard !structuredAPIAvailable, !structuredProbeInFlight else { return }

        structuredProbeInFlight = true
        structuredProbeGeneration += 1
        let generation = structuredProbeGeneration
        let requestID = UUID().uuidString
        pendingRequests[requestID] = "getAPIInfo"

        postStructuredRequest(id: requestID, method: "getAPIInfo")

        // A pre-1.0 DesktopRenamer does not know the RPC channel and will
        // never respond. Preserve compatibility without delaying the legacy
        // path indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self,
                  self.structuredProbeGeneration == generation,
                  self.structuredProbeInFlight else { return }

            self.pendingRequests.removeValue(forKey: requestID)
            self.structuredProbeInFlight = false
            self.refreshLegacySpaceList()
        }
    }

    private func requestStructuredSnapshot() {
        let requestID = UUID().uuidString
        pendingRequests[requestID] = "getSpaceSnapshot"
        postStructuredRequest(id: requestID, method: "getSpaceSnapshot")
    }

    private func postStructuredRequest(id: String, method: String) {
        let request: [String: Any] = [
            "jsonrpc": jsonRPCVersion,
            "id": id,
            "method": method
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let payload = String(data: data, encoding: .utf8) else {
            print("OptClicker: Could not encode DesktopRenamer API request: \(method)")
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            rpcRequest,
            object: nil,
            userInfo: [payloadKey: payload],
            deliverImmediately: true
        )
    }

    private func handleRPCResponse(_ notification: Notification) {
        guard let payload = notification.userInfo?[payloadKey] as? String,
              let data = payload.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestID = response["id"] as? String,
              let requestType = pendingRequests.removeValue(forKey: requestID) else {
            return
        }

        if let error = response["error"] as? [String: Any] {
            let code = (error["code"] as? NSNumber)?.intValue
            if code == -32001 {
                setDisconnected(as: .disabled)
            } else if requestType == "getAPIInfo" {
                structuredProbeInFlight = false
                structuredAPIAvailable = false
                refreshLegacySpaceList()
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

        switch requestType {
        case "getAPIInfo":
            let supportsSnapshots = (result["supportedMethods"] as? [String])?.contains("getSpaceSnapshot") == true
            let supportsJSONRPC = result["jsonRPCVersion"] as? String == jsonRPCVersion
            let contractVersion = result["contractVersion"] as? String
            guard supportsSnapshots && supportsJSONRPC,
                  let contractVersion,
                  isSupportedContractVersion(contractVersion) else {
                structuredProbeInFlight = false
                refreshLegacySpaceList()
                return
            }

            structuredProbeInFlight = false
            structuredAPIAvailable = true
            apiAvailability = .available
            isAPIEnabled = true
            requestStructuredSnapshot()

        case "getSpaceSnapshot":
            applyStructuredSnapshot(result, isEvent: false)

        default:
            break
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

    private func handleRPCEvent(_ notification: Notification) {
        guard let payload = notification.userInfo?[payloadKey] as? String,
              let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["jsonrpc"] as? String == jsonRPCVersion,
              event["method"] as? String == "stateChanged",
              let params = event["params"] as? [String: Any],
              let snapshot = params["snapshot"] as? [String: Any] else {
            return
        }

        structuredAPIAvailable = true
        structuredProbeInFlight = false
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
        structuredAPIAvailable = false
        structuredProbeInFlight = false
        pendingRequests.removeAll()
        lastSnapshotRevision = nil
        apiAvailability = availability
        isAPIEnabled = false
        availableSpaces.removeAll()
        currentSpaceName = "Disconnected"
        currentSpaceID = nil
    }
}
