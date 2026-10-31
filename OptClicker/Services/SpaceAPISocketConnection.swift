import Darwin
import Foundation

final class SpaceAPISocketConnection: @unchecked Sendable {
    private static let headerLength = 4
    private static let maximumPayloadBytes = 1_048_576

    private let descriptor: Int32
    private let readQueue = DispatchQueue(label: "dev.mqiu.OptClicker.SpaceAPI.socket.read")
    private let stateLock = NSLock()
    private let onMessage: (String) -> Void
    private let onClose: () -> Void
    private var isClosed = false
    private var didFinish = false

    private var connectionIsClosed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isClosed
    }

    deinit {
        stateLock.lock()
        let shouldClose = !didFinish
        didFinish = true
        isClosed = true
        stateLock.unlock()

        if shouldClose {
            _ = shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
    }

    init(
        endpointPath: String,
        onMessage: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) throws {
        var address = sockaddr_un()
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        let pathCString = endpointPath.utf8CString
        guard pathCString.count <= pathCapacity else {
            throw SpaceAPISocketConnectionError.invalidEndpoint
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw SpaceAPISocketConnectionError.socket(errno)
        }

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            pathPointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                pathCString.withUnsafeBufferPointer { buffer in
                    destination.update(from: buffer.baseAddress!, count: buffer.count)
                }
            }
        }

        var noSignal: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )

        let connectStatus = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectStatus == 0 else {
            let errorCode = errno
            Darwin.close(descriptor)
            throw SpaceAPISocketConnectionError.socket(errorCode)
        }

        self.descriptor = descriptor
        self.onMessage = onMessage
        self.onClose = onClose
        readQueue.async { [weak self] in
            self?.readMessages()
        }
    }

    @discardableResult
    func send(_ payload: String) -> Bool {
        let payloadData = Data(payload.utf8)
        guard !payloadData.isEmpty, payloadData.count <= Self.maximumPayloadBytes else {
            return false
        }

        let length = UInt32(payloadData.count)
        var frame = Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ])
        frame.append(payloadData)

        stateLock.lock()
        guard !isClosed else {
            stateLock.unlock()
            return false
        }

        let succeeded = frame.withUnsafeBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress else { return false }
            var offset = 0
            while offset < frame.count {
                let result = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    frame.count - offset,
                    0
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if result == 0 { return false }
                offset += result
            }
            return true
        }
        stateLock.unlock()

        if !succeeded {
            close()
        }
        return succeeded
    }

    func close() {
        stateLock.lock()
        let shouldShutdown = !isClosed
        isClosed = true
        stateLock.unlock()

        if shouldShutdown {
            _ = shutdown(descriptor, SHUT_RDWR)
        }
    }

    private func readMessages() {
        defer { finish() }

        while !connectionIsClosed {
            guard let header = readExactly(Self.headerLength) else { return }
            let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= Self.maximumPayloadBytes,
                  let payload = readExactly(Int(length)),
                  let message = String(data: payload, encoding: .utf8) else {
                return
            }
            onMessage(message)
        }
    }

    private func readExactly(_ count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0

        while offset < count {
            let result = data.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return recv(descriptor, baseAddress.advanced(by: offset), count - offset, 0)
            }
            if result == 0 { return nil }
            if result < 0 {
                if errno == EINTR { continue }
                return nil
            }
            offset += result
        }

        return data
    }

    private func finish() {
        stateLock.lock()
        guard !didFinish else {
            stateLock.unlock()
            return
        }
        didFinish = true
        isClosed = true
        stateLock.unlock()

        _ = shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
        DispatchQueue.main.async(execute: onClose)
    }
}

private enum SpaceAPISocketConnectionError: Error {
    case invalidEndpoint
    case socket(Int32)
}
