import Foundation

public struct NetworkInterceptorResponse<T: Decodable> {
    public let httpResponse: URLResponse?
    public let data: Data?
    public var request: NetworkRequest
    public var result: Result<T, any Error>
    public init(httpResponse: URLResponse?, data: Data?, request: NetworkRequest, result: Result<T, any Error>) {
        self.httpResponse = httpResponse
        self.data = data
        self.request = request
        self.result = result
    }
}

/// 网络请求拦截器协议
public protocol NetworkInterceptor: AnyObject {
    /// 请求发起前拦截，可修改请求
    func intercept(request: NetworkRequest) async throws -> NetworkRequest
    /// 响应返回后拦截，可处理响应或错误
    func intercept<T: Decodable>(response: NetworkInterceptorResponse<T>) async throws -> NetworkInterceptorResponse<T>
}
