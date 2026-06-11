import Foundation

enum RepositoryError: LocalizedError {
    case notFound
    case unauthorized
    case forbidden(String)
    case conflict(String)
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .notFound: return "The requested resource was not found."
        case .unauthorized: return "You are not authorized to perform this action."
        case .forbidden(let msg): return msg
        case .conflict(let msg): return msg
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .decodingError(let err): return "Decoding error: \(err is DecodingError ? String(describing: err) : err.localizedDescription)"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .unknown: return "An unknown error occurred."
        }
    }
}

extension RepositoryError: Equatable {
    public static func == (lhs: RepositoryError, rhs: RepositoryError) -> Bool {
        switch (lhs, rhs) {
        case (.notFound, .notFound): return true
        case (.unauthorized, .unauthorized): return true
        case (.unknown, .unknown): return true
        case (.forbidden(let a), .forbidden(let b)): return a == b
        case (.conflict(let a), .conflict(let b)): return a == b
        case (.serverError(let a, let b), .serverError(let c, let d)): return a == c && b == d
        default: return false
        }
    }
}
