import Foundation
/// 网络请求错误
public enum NetworkError: Error {
    case invalidURL
    case noData
    case cancel
    case noAuthProvider
    case requestFailed(Error)
    case httpError(Int)
    case decodingFailed(Error)
    case apiError(Int, String)
    case unknown
    case maxRetry
    case inRetry
    case custom(String)
    func canRetry() -> Bool {
        switch self {
        case .requestFailed, .httpError, .inRetry:
            return true
        default:
            return false
        }
    }
}
