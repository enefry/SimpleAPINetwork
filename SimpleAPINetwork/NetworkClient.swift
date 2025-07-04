import Foundation
import LoggerProxy

fileprivate let kLogTag = "bdpan.Net"

struct EmptyResponse: Codable {}

// 公共头检查
public protocol CommonResponseHead: Decodable {
    var code: Int { get }
    var msg: String? { get }
}

/// 网络请求客户端，负责发起请求、处理响应
public protocol NetworkClient {
    /// 拦截器数组
    var interceptors: [NetworkInterceptor] { get set }

    /// 发起网络请求
    /// - Parameters:
    ///   - request: 请求配置
    ///   - commonType: 公共头检查
    ///   - completion: 回调，返回解码后的模型或错误
    func send<T: Decodable, H: CommonResponseHead>(_ request: NetworkRequest, commonType: H.Type?, completion: @Sendable @escaping (Result<T, any Error>) -> Void) -> URLSessionTask?
}

/// URLSession 默认实现（接口定义，具体实现后续补充）
public class URLSessionNetworkClient: NetworkClient {
    public var interceptors: [NetworkInterceptor] = []
    private let baseURL: String
    private let session: URLSession

    public init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private struct CommonResponseHeadSuccess: CommonResponseHead {
        var code: Int { 0 }
        var msg: String? { "ok" }
    }

    @discardableResult
    public func send<T: Decodable, H: CommonResponseHead>(_ request: NetworkRequest, commonType: H.Type?, completion: @Sendable @escaping (Result<T, any Error>) -> Void) -> URLSessionTask? {
        let reqID = request.id
        // 1. 依次通过拦截器处理请求
        var processedRequest = request
        for interceptor in interceptors {
            processedRequest = interceptor.intercept(request: processedRequest)
        }

        // 2. 日志打印请求
        LoggerProxy.DLog(tag: kLogTag, msg: "send:\(reqID) of: \(processedRequest)")

        // 3. 发起请求
        guard let urlRequest = buildURLRequest(from: processedRequest) else {
            let error = NetworkError.invalidURL
            let result: Result<T, any Error> = .failure(error)
            handleResponse(result, for: processedRequest, completion: completion)
            return nil
        }

        let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self = self else {
                return
            }
            let result: Result<T, any Error>
            if let error = error {
                LoggerProxy.ELog(tag: kLogTag, msg: "request=\(reqID),error:\(error)")
                result = .failure(NetworkError.requestFailed(error))
            } else if let httpResponse = response as? HTTPURLResponse {
                if 200 ... 299 ~= httpResponse.statusCode {
                    if let data = data {
                        do {
                            let head: any CommonResponseHead
                            if let type = commonType {
                                head = try JSONDecoder().decode(type, from: data)
                            } else {
                                head = CommonResponseHeadSuccess()
                            }
                            if head.code == 0 {
                                let data = try JSONDecoder().decode(T.self, from: data)
                                result = .success(data)
                            } else if let ret = EmptyResponse() as? T {
                                result = .success(ret)
                            } else if let noneReuslt = () as? T {
                                result = .success(noneReuslt)
                            } else {
                                LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id),api->\(head.code),\(head.msg ?? "-")")
                                throw NetworkError.apiError(head.code, head.msg ?? "unknown error")
                            }
                        } catch let error as NetworkError {
                            result = .failure(error)
                        } catch {
                            LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id),process:\(error)")
                            result = .failure(NetworkError.decodingFailed(error))
                        }
                    } else {
                        LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id), noData")
                        result = .failure(NetworkError.noData)
                    }
                } else {
                    LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id), resp=\(httpResponse)")
                    result = .failure(NetworkError.httpError(httpResponse.statusCode))
                }
            } else {
                LoggerProxy.ELog(tag: kLogTag, msg: "request=\(request.id), unknown error")
                result = .failure(NetworkError.unknown)
            }
            self.handleResponse(result, for: processedRequest, completion: completion)
        }

        task.resume()
        return task
    }

    private func buildURLRequest(from request: NetworkRequest) -> URLRequest? {
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

    private func handleResponse<T: Decodable>(_ result: Result<T, any Error>, for request: NetworkRequest, completion: @escaping (Result<T, any Error>) -> Void) {
        // 4. 日志打印响应
        LoggerProxy.DLog(tag: kLogTag, msg: "\(result) for \(request.id)")

        // 5. 依次通过拦截器处理响应（逆序）
        var processedResult = result
        for interceptor in interceptors.reversed() {
            processedResult = interceptor.intercept(response: processedResult, for: request)
        }

        // 6. 回调
        DispatchQueue.main.async {
            completion(processedResult.mapError { $0 as any Error })
        }
    }
}
