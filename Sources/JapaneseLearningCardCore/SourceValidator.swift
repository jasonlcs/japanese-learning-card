import Foundation

public enum SourceValidationError: LocalizedError, Equatable {
    case unsupportedScheme
    case missingHost
    case blockedHost(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            "Only http and https URLs are supported."
        case .missingHost:
            "URL must include a host."
        case .blockedHost(let host):
            "Host is blocked: \(host)"
        }
    }
}

public struct SourceValidator: Sendable {
    public init() {}

    public func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw SourceValidationError.unsupportedScheme
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw SourceValidationError.missingHost
        }
        if let resolved = Self.resolve(host: host), Self.isBlockedAddress(resolved) {
            throw SourceValidationError.blockedHost(host)
        }
    }

    private static func resolve(host: String) -> String? {
        if host == "localhost" {
            return "127.0.0.1"
        }
        if let address = ipv4(from: host) {
            return address
        }
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        defer { if let result { freeaddrinfo(result) } }
        guard status == 0, let first = result else { return nil }
        var nodeBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let lookup = getnameinfo(
            first.pointee.ai_addr,
            first.pointee.ai_addrlen,
            &nodeBuffer,
            socklen_t(nodeBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard lookup == 0 else { return nil }
        if let nullIndex = nodeBuffer.firstIndex(of: 0) {
            nodeBuffer.removeSubrange(nullIndex...)
        }
        return String(cString: nodeBuffer)
    }

    private static func ipv4(from host: String) -> String? {
        var addr = in_addr()
        return inet_pton(AF_INET, host, &addr) == 1
            ? String(cString: inet_ntoa(addr))
            : nil
    }

    private static func isBlockedAddress(_ address: String) -> Bool {
        if address == "::1" || address == "::" { return true }
        if address.hasPrefix("fc") || address.hasPrefix("fd") { return true }
        if address.hasPrefix("fe8") || address.hasPrefix("fe9") || address.hasPrefix("fea") || address.hasPrefix("feb") {
            return true
        }
        let parts = address.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 127 { return true }
        if parts[0] == 0 { return true }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] >= 224 { return true }
        return false
    }
}
