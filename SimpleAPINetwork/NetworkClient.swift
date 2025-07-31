import Combine
import ConcurrencyCollection
import Foundation
import LoggerProxy

fileprivate let kLogTag = "bdpan.Net"

struct EmptyResponse: Codable {}

// 公共头检查
public protocol CommonResponseHead: Decodable {
    var code: Int { get }
    var msg: String? { get }
    var isSuccess: Bool { get }
}

/// 网络请求客户端，负责发起请求、处理响应
public protocol NetworkClient {
    /// 添加拦截器
    /// - Parameters:
    ///     - interceptor 拦截器
    func add(interceptor: any NetworkInterceptor)
    /// 移除拦截器
    /// - Parameters:
    ///     - interceptor 拦截器
    func remove(interceptor: any NetworkInterceptor)

    /// 发起网络请求 - async/await版本
    /// - Parameters:
    ///   - request: 请求配置
    ///   - commonType: 公共头检查
    ///   - usingCommon: 是否使用公共头验证
    /// - Returns: 解码后的模型
    /// - Throws: 网络错误
    func send<T: Decodable, H: CommonResponseHead>(
        _ request: NetworkRequest,
        commonType: H.Type,
        usingCommon: Bool
    ) async throws -> T
}

public extension NetworkClient {
    func send<T: Decodable, H: CommonResponseHead>(
        _ request: NetworkRequest,
        commonType: H.Type
    ) async throws -> T {
        try await send(request, commonType: commonType, usingCommon: true)
    }
}

/// URLSession 默认实现
public class URLSessionNetworkClient: NetworkClient {
    private var interceptors: ConcurrentArray<NetworkInterceptor> = ConcurrentArray()
    public func add(interceptor: any NetworkInterceptor) {
        interceptors.append(interceptor)
    }

    public func remove(interceptor: any NetworkInterceptor) {
        interceptors.removeAll(where: { $0 === interceptor })
    }

    private let baseURL: String
    private let session: URLSession

    public init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private struct CommonResponseHeadSuccess: CommonResponseHead {
        var code: Int { 0 }
        var msg: String? { "ok" }
        var isSuccess: Bool { true }
    }

    public func send<T: Decodable, H: CommonResponseHead>(
        _ request: NetworkRequest,
        commonType: H.Type,
        usingCommon: Bool
    ) async throws -> T {
        var currentRequest = request

        // 使用循环代替递归来处理重试逻辑
        repeat {
            // 1. 依次通过拦截器处理请求
            var processedRequest = currentRequest
            for interceptor in interceptors.values {
                try Task.checkCancellation()
                processedRequest = try await interceptor.intercept(request: processedRequest)
            }

            // 2. 日志打印请求
            LoggerProxy.DLog(tag: kLogTag, msg: "send:\(processedRequest.id) of: \(processedRequest)")

            // 3. 构建URLRequest
            guard let urlRequest = buildURLRequest(from: processedRequest) else {
                throw NetworkError.invalidURL
            }

            // 4. 发起请求并处理所有可能的错误
            let requestResult: Result<T, Error>
            var _data: Data?
            var _response: URLResponse?
            do {
                let (data, response) = try await performRequest(urlRequest: urlRequest, requestID: processedRequest.id)
                _data = data
                _response = response
                // 5. 处理响应
                let result: T = try await processResponse(
                    data: data,
                    response: response,
                    request: processedRequest,
                    commonType: commonType,
                    usingCommon: usingCommon
                )
                requestResult = .success(result)
            } catch {
                LoggerProxy.WLog(tag: kLogTag, msg: "send error:\(error)")
                requestResult = .failure(error)
            }

            // 6. 通过拦截器处理结果（包括网络异常）
            let interceptorResult: (success: T?, shouldRetry: Bool, retryRequest: NetworkRequest?) = try await processResultThroughInterceptors(
                result: requestResult,
                data: _data,
                response: _response,
                request: processedRequest,
                commonType: commonType,
                usingCommon: usingCommon
            )

            // 7. 处理拦截器返回的结果
            if let successResult = interceptorResult.success {
                return successResult
            }

            if interceptorResult.shouldRetry, let retryRequest = interceptorResult.retryRequest {
                LoggerProxy.DLog(tag: kLogTag, msg: "Retrying request=\(retryRequest.id), remaining retries=\(retryRequest.retryTime)")
                currentRequest = retryRequest
                continue // 继续循环进行重试
            } else {
                // 无法重试，抛出最后的错误
                if case let .failure(error) = requestResult {
                    LoggerProxy.WLog(tag: kLogTag, msg: "send error:\(error)")
                    throw error
                } else {
                    throw NetworkError.unknown
                }
            }
        } while true
    }

    private func performRequest(urlRequest: URLRequest, requestID: String) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: urlRequest)
            return (data, response)
        } catch {
            LoggerProxy.ELog(tag: kLogTag, msg: "request=\(requestID),error:\(error)")
            throw NetworkError.requestFailed(error)
        }
    }

    private func processResponse<T: Decodable, H: CommonResponseHead>(
        data: Data,
        response: URLResponse,
        request: NetworkRequest,
        commonType: H.Type,
        usingCommon: Bool
    ) async throws -> T {
        // 检查HTTP状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id), unknown error")
            throw NetworkError.unknown
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id), resp=\(httpResponse)")
            throw NetworkError.httpError(httpResponse.statusCode)
        }

        // 解码响应数据
        let decodedResult: T = try await decodeResponse(
            data: data,
            request: request,
            commonType: commonType,
            usingCommon: usingCommon
        )

        return decodedResult
    }

    private func decodeResponse<T: Decodable, H: CommonResponseHead>(
        data: Data,
        request: NetworkRequest,
        commonType: H.Type,
        usingCommon: Bool
    ) async throws -> T {
        do {
            let head: any CommonResponseHead
            if usingCommon {
                head = try JSONDecoder().decode(commonType, from: data)
            } else {
                head = CommonResponseHeadSuccess()
            }

            if head.isSuccess {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                return decodedData
            } else {
                // 尝试返回空响应或Unit类型
                if let emptyResponse = EmptyResponse() as? T {
                    return emptyResponse
                } else if let unitResponse = () as? T {
                    return unitResponse
                } else {
                    LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id),api->\(head.code),\(head.msg ?? "-")")
                    throw NetworkError.apiError(head.code, head.msg ?? "unknown error")
                }
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id),process:\(error)")
            throw NetworkError.decodingFailed(error)
        }
    }

    private func processResultThroughInterceptors<T: Decodable, H: CommonResponseHead>(
        result: Result<T, Error>,
        data: Data?,
        response: URLResponse?,
        request: NetworkRequest,
        commonType: H.Type,
        usingCommon: Bool
    ) async throws -> (success: T?, shouldRetry: Bool, retryRequest: NetworkRequest?) {
        var interceptorResponse = NetworkInterceptorResponse<T>(
            httpResponse: response,
            data: data,
            request: request,
            result: result
        )

        // 逆序处理拦截器
        for interceptor in interceptors.values.reversed() {
            interceptorResponse = try await interceptor.intercept(response: interceptorResponse)
        }

        // 检查是否需要重试
        if case let .failure(error) = interceptorResponse.result,
           let netError = error as? NetworkError,
           netError.canRetry(),
           let retryRequest = try? await interceptorResponse.request.reset(),
           retryRequest.retryTime > 0 {
            // 返回重试信息
            return (success: nil, shouldRetry: true, retryRequest: retryRequest)
        } else if case let .success(value) = interceptorResponse.result {
            // 返回成功结果
            return (success: value, shouldRetry: false, retryRequest: nil)
        } else {
            // 不需要重试，返回失败
            return (success: nil, shouldRetry: false, retryRequest: nil)
        }
    }

    public func buildURLRequest(from request: NetworkRequest) -> URLRequest? {
        var urlString = request.path

        // 如果path不是绝对URL，则拼接baseURL
        if !request.path.hasPrefix("http://") && !request.path.hasPrefix("https://") {
            urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard var urlComponents = URLComponents(string: urlString) else {
            return nil
        }

        // 添加查询参数
        if let query = request.query, !query.isEmpty {
            urlComponents.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            return nil
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        if let body = request.body {
            switch body {
            case let .data(data):
                urlRequest.httpBody = data
            case let .inputStream(inputStream):
                urlRequest.httpBodyStream = inputStream
            }
        }

        // 设置请求头
        request.headers?.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        return urlRequest
    }
}

// MARK: - 为了向后兼容，提供基于回调的接口

public extension URLSessionNetworkClient {
    /// 向后兼容的回调版本
    @discardableResult
    func send<T: Decodable, H: CommonResponseHead>(
        _ request: NetworkRequest,
        commonType: H.Type,
        usingCommon: Bool,
        completion: @Sendable @escaping (Result<T, any Error>) -> Void
    ) -> (any Cancellable)? {
        let task = Task {
            do {
                let result: T = try await send(request, commonType: commonType, usingCommon: usingCommon)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }

        return AnyCancellable {
            task.cancel()
        }
    }

    @discardableResult
    func send<T: Decodable, H: CommonResponseHead>(
        _ request: NetworkRequest,
        commonType: H.Type,
        completion: @Sendable @escaping (Result<T, any Error>) -> Void
    ) -> (any Cancellable)? {
        send(request, commonType: commonType, usingCommon: true, completion: completion)
    }
}
