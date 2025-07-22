import Foundation

/// 网络请求配置
public struct NetworkRequest: CustomStringConvertible, Identifiable, Sendable {
    // MARK: - 类型定义

    /// 请求方法
    public enum Method: String, Hashable, Equatable, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    public enum Body: @unchecked Sendable {
        case data(Data)
        case inputStream(InputStream)
    }

    /// 重置请求
    public typealias ResetBlock = @Sendable (NetworkRequest) async throws -> NetworkRequest

    /// request变量
    public let id: String
    /// 请求路径（相对或绝对URL）
    public let path: String
    /// 请求方法
    public let method: Method
    /// URL查询参数
    public let query: [String: String]?
    /// 请求体（一般为JSON）
    public let body: Body?
    /// 请求头
    public let headers: [String: String]?

    /// 重置请求的block
    public let resetBlock: ResetBlock?
    /// 重试，最大 512，避免无限重试
    public let retryTime: Int

    public init(
        path: String,
        method: Method,
        query: [String: String]? = nil,
        body: Body? = nil,
        headers: [String: String]? = nil,
        reset: ResetBlock? = nil,
        retryTime: Int = 3 /// 最大512次
    ) {
        id = UUID().uuidString
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.headers = headers
        resetBlock = reset
        self.retryTime = min(retryTime,512)
    }
    
    public func reset() async throws -> NetworkRequest {
        if let reset = resetBlock {
            return try await reset(self)
        } else {
            if retryTime == 0 {
                throw NetworkError.maxRetry
            }
            return copyWithModify(retryTime: { $0 - 1 })
        }
    }
    
    
    public var description: String {
        let nullText:(Any?)->String = {
            if let obj = $0{
                return "\(obj)"
            }else{
                return "null"
            }
        }
        return "req[\(id)] ,method=\(method) ,path=\(path) ,q=[\(nullText(query))] ,h=[\(nullText(headers))]"
    }

    public func copyWithModify(
        path: ((String) -> String)? = nil,
        method: ((Method) -> Method)? = nil,
        query: (([String: String]?) -> [String: String]?)? = nil,
        body: ((Body?) -> Body?)? = nil,
        headers: (([String: String]?) -> [String: String]?)? = nil,
        reset: ResetBlock? = nil,
        retryTime: ((Int) -> Int)? = nil
    ) -> NetworkRequest {
        return NetworkRequest(
            path: path?(self.path) ?? self.path,
            method: method?(self.method) ?? self.method,
            query: query?(self.query) ?? self.query,
            body: body?(self.body) ?? self.body,
            headers: headers?(self.headers) ?? self.headers,
            reset: reset ?? resetBlock,
            retryTime: retryTime?(self.retryTime) ?? self.retryTime
        )
    }
}

