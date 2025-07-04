# SimpleAPINetwork AI 参考文档

## 库概述
SimpleAPINetwork 是一个 Swift 网络请求库，支持 iOS 13.0+ 和 macOS 11.0+，依赖 LoggerProxy 进行日志记录。

## 核心协议和类型

### NetworkClient 协议
```swift
public protocol NetworkClient {
    /// 拦截器数组，按顺序执行请求拦截，逆序执行响应拦截
    var interceptors: [NetworkInterceptor] { get set }

    /// 发起网络请求
    /// - Parameters:
    ///   - request: 请求配置
    ///   - commonType: 公共响应头类型，用于检查 API 返回的通用状态码
    ///   - completion: 回调，返回解码后的模型或错误
    /// - Returns: URLSessionTask，可用于取消请求
    func send<T: Decodable, H: CommonResponseHead>(
        _ request: NetworkRequest,
        commonType: H.Type?,
        completion: @Sendable @escaping (Result<T, any Error>) -> Void
    ) -> URLSessionTask?
}
```

### CommonResponseHead 公共响应头协议
```swift
public protocol CommonResponseHead: Decodable {
    var code: Int { get }        // 状态码，0 表示成功
    var msg: String? { get }     // 错误消息
}
```

### URLSessionNetworkClient 实现类
```swift
public class URLSessionNetworkClient: NetworkClient {
    /// 初始化网络客户端
    /// - Parameters:
    ///   - baseURL: 基础 URL，会与请求路径拼接
    ///   - session: URLSession 实例，默认为 .shared
    public init(baseURL: String, session: URLSession = .shared)
}
```

### NetworkRequest 请求配置
```swift
public struct NetworkRequest: CustomStringConvertible, Identifiable, Sendable {
    /// HTTP 请求方法
    public enum Method: String, Hashable, Equatable, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    /// 请求体类型
    public enum Body: @unchecked Sendable {
        case data(Data)           // 普通数据
        case inputStream(InputStream)  // 流式数据，用于大文件上传
    }

    /// 重置请求的回调类型
    public typealias ResetBlock = @Sendable (NetworkRequest) throws -> NetworkRequest

    public let id: String                    // 唯一标识符
    public let path: String                  // 请求路径（相对或绝对URL）
    public let method: Method                // 请求方法
    public let query: [String: String]?      // URL查询参数
    public let body: Body?                   // 请求体
    public let headers: [String: String]?    // 请求头
    public let resetBlock: ResetBlock?       // 自定义重试逻辑
    public let retryTime: Int               // 当前重试次数

    /// 创建网络请求
    public init(
        path: String,
        method: Method,
        query: [String: String]? = nil,
        body: Body? = nil,
        bodyStream: InputStream? = nil,
        headers: [String: String]? = nil,
        reset: ResetBlock? = nil,
        retryTime: Int = 0
    )

    /// 复制并修改请求参数
    public func copyWithModify(
        path: ((String) -> String)? = nil,
        method: ((Method) -> Method)? = nil,
        query: (([String: String]?) -> [String: String]?)? = nil,
        body: ((Body?) -> Body?)? = nil,
        headers: (([String: String]?) -> [String: String]?)? = nil,
        reset: ResetBlock? = nil,
        retryTime: ((Int) -> Int)? = nil
    ) -> NetworkRequest
}
```

### NetworkError 错误类型
```swift
public enum NetworkError: Error {
    case invalidURL              // 无效的 URL
    case noData                 // 没有返回数据
    case requestFailed(Error)   // 网络请求失败
    case httpError(Int)         // HTTP 状态码错误
    case decodingFailed(Error)  // JSON 解码失败
    case apiError(Int, String)  // API 业务错误（code != 0）
    case unknown                // 未知错误
    case maxRetry              // 超过最大重试次数
}
```

### NetworkInterceptor 拦截器协议
```swift
public protocol NetworkInterceptor {
    /// 请求发起前拦截，可修改请求参数
    func intercept(request: NetworkRequest) -> NetworkRequest

    /// 响应返回后拦截，可处理响应或错误
    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error>
}
```

## 工具类

### URLEncodedFormParameterEncoder 表单编码器
```swift
public protocol ParameterEncoder {
    /// 编码 Codable 对象为 Data
    func encode<T: Encodable>(_ parameters: T) throws -> Data
    /// 编码字典为 Data
    func encode(_ parameters: [String: Any]) throws -> Data
}

public class URLEncodedFormParameterEncoder: ParameterEncoder {
    /// 将参数编码为 application/x-www-form-urlencoded 格式
    /// 支持嵌套对象和数组，会转换为 JSON 字符串
}
```

### StreamingMultipartInputStream 流式多部分上传
```swift
public class StreamingMultipartInputStream: InputStream {
    public let contentLength: Int64  // 总内容长度

    /// 创建流式多部分输入流，用于大文件分片上传
    /// - Parameters:
    ///   - boundary: multipart 边界字符串
    ///   - preuploadID: 预上传 ID
    ///   - sliceNo: 分片序号
    ///   - sliceMD5: 分片 MD5 值
    ///   - fileURL: 文件 URL
    ///   - sliceOffset: 分片在文件中的偏移量
    ///   - sliceSize: 分片大小
    public init(
        boundary: String,
        preuploadID: String,
        sliceNo: Int,
        sliceMD5: String,
        fileURL: URL,
        sliceOffset: Int64,
        sliceSize: Int64
    ) throws
}
```

## 使用模式

### 基本请求流程
1. 创建 `URLSessionNetworkClient` 实例
2. 配置拦截器（可选）
3. 创建 `NetworkRequest` 配置请求参数
4. 调用 `client.send()` 发起请求
5. 在回调中处理 `Result<T, Error>`

### 拦截器执行顺序
- 请求拦截：按 `interceptors` 数组顺序执行
- 响应拦截：按 `interceptors` 数组逆序执行

### 重试机制
- 默认最多重试 3 次（retryTime > 3 时抛出 maxRetry 错误）
- 可通过 `resetBlock` 自定义重试逻辑
- 每次重试会调用 `reset()` 方法增加 `retryTime`

### 响应处理逻辑
1. 检查 HTTP 状态码（200-299 为成功）
2. 如果指定了 `commonType`，先解码公共响应头
3. 检查 `code` 字段（0 为成功）
4. 解码目标类型 `T`
5. 如果解码失败且目标类型是 `EmptyResponse` 或 `Void`，返回成功

### 日志记录
- 使用 LoggerProxy 记录请求和响应日志
- 日志标签为 "bdpan.Net"
- 包含请求 ID、方法、路径等信息

## 典型使用场景

### GET 请求
```swift
let request = NetworkRequest(
    path: "/api/users",
    method: .get,
    query: ["page": "1", "limit": "10"]
)
```

### POST JSON 请求
```swift
let jsonData = try JSONEncoder().encode(requestModel)
let request = NetworkRequest(
    path: "/api/users",
    method: .post,
    body: .data(jsonData),
    headers: ["Content-Type": "application/json"]
)
```

### 表单提交
```swift
let encoder = URLEncodedFormParameterEncoder()
let formData = try encoder.encode(["username": "user", "password": "pass"])
let request = NetworkRequest(
    path: "/login",
    method: .post,
    body: .data(formData),
    headers: ["Content-Type": "application/x-www-form-urlencoded"]
)
```

### 大文件分片上传
```swift
let inputStream = try StreamingMultipartInputStream(
    boundary: boundary,
    preuploadID: uploadID,
    sliceNo: 1,
    sliceMD5: md5Hash,
    fileURL: fileURL,
    sliceOffset: 0,
    sliceSize: chunkSize
)
let request = NetworkRequest(
    path: "/upload/slice",
    method: .post,
    body: .inputStream(inputStream)
)
```

### 认证拦截器示例
```swift
class AuthInterceptor: NetworkInterceptor {
    func intercept(request: NetworkRequest) -> NetworkRequest {
        return request.copyWithModify { headers in
            var newHeaders = headers ?? [:]
            newHeaders["Authorization"] = "Bearer \(token)"
            return newHeaders
        }
    }

    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error> {
        // 处理 401 错误，刷新 token 等
        return response
    }
}
