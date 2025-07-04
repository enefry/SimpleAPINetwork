import Foundation
/// 网络请求错误
public enum NetworkError: Error {
    case invalidURL
    case noData
    case requestFailed(Error)
    case httpError(Int)
    case decodingFailed(Error)
    case apiError(Int, String)
    case unknown
    case maxRetry
}
