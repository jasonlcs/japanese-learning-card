import Foundation

public enum SourceValidationError: LocalizedError, Equatable {
    case unsupportedScheme
    case missingHost

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            "Only http and https URLs are supported."
        case .missingHost:
            "URL must include a host."
        }
    }
}

public struct SourceValidator: Sendable {
    public init() {}

    public func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw SourceValidationError.unsupportedScheme
        }
        guard url.host?.isEmpty == false else {
            throw SourceValidationError.missingHost
        }
    }
}
