import Foundation

/// 网络请求拦截器协议
public protocol NetworkInterceptor {
    /// 请求发起前拦截，可修改请求
    func intercept(request: NetworkRequest) -> NetworkRequest
    /// 响应返回后拦截，可处理响应或错误
    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error>
}
