# SimpleAPINetwork 使用文档

## 概述

SimpleAPINetwork 是一个用 Swift 编写的轻量级网络请求库，专为 iOS 和 macOS 平台设计。它提供了简洁而强大的 API，支持常见的网络请求操作，包括 RESTful API 调用、文件上传、表单提交等功能。

### 主要特性

- 🚀 **简洁易用**：基于协议设计，API 简洁明了
- 🔧 **灵活配置**：支持自定义请求头、查询参数、请求体等
- 🛡️ **错误处理**：完善的错误类型定义和处理机制
- 🔄 **拦截器支持**：可插拔的请求/响应拦截器
- 📤 **文件上传**：支持流式多部分文件上传
- 🔁 **重试机制**：内置请求重试和重置功能
- 📝 **日志记录**：集成 LoggerProxy 进行请求日志记录

### 系统要求

- iOS 13.0+ / macOS 11.0+
- Swift 5.9+
- Xcode 15.0+

## 安装

### Swift Package Manager

在 Xcode 中添加包依赖：

1. 打开 Xcode 项目
2. 选择 `File` → `Add Package Dependencies...`
3. 输入仓库 URL：`https://github.com/enefry/SimpleAPINetwork.git`
4. 选择版本并添加到项目

或者在 `Package.swift` 文件中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/enefry/SimpleAPINetwork.git", from: "1.0.0")
]
```

## 快速开始

### 基础使用

```swift
import SimpleAPINetwork

// 1. 创建网络客户端
let client = URLSessionNetworkClient(baseURL: "https://api.example.com")

// 2. 创建请求
let request = NetworkRequest(
    path: "/users",
    method: .get
)

// 3. 发送请求
client.send(request, commonType: nil) { (result: Result<[User], Error>) in
    switch result {
    case .success(let users):
        print("获取到 \(users.count) 个用户")
    case .failure(let error):
        print("请求失败: \(error)")
    }
}
```

### 定义响应模型

```swift
struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

// 如果 API 有统一的响应格式
struct APIResponse<T: Codable>: Codable {
    let code: Int
    let message: String?
    let data: T?
}

// 实现 CommonResponseHead 协议
extension APIResponse: CommonResponseHead {
    var msg: String? { message }
}
```

## 核心组件

### NetworkClient

`NetworkClient` 是网络请求的核心协议，提供了发送请求的主要接口。

```swift
// 创建客户端实例
let client = URLSessionNetworkClient(
    baseURL: "https://api.example.com",
    session: URLSession.shared
)

// 添加拦截器
client.interceptors.append(AuthInterceptor())
client.interceptors.append(LoggingInterceptor())
```

### NetworkRequest

`NetworkRequest` 用于配置网络请求的各种参数。

```swift
// GET 请求
let getRequest = NetworkRequest(
    path: "/users",
    method: .get,
    query: ["page": "1", "limit": "10"],
    headers: ["Authorization": "Bearer token"]
)

// POST 请求
let postData = try JSONEncoder().encode(newUser)
let postRequest = NetworkRequest(
    path: "/users",
    method: .post,
    body: .data(postData),
    headers: [
        "Content-Type": "application/json",
        "Authorization": "Bearer token"
    ]
)

// PUT 请求
let putRequest = NetworkRequest(
    path: "/users/123",
    method: .put,
    body: .data(updateData)
)

// DELETE 请求
let deleteRequest = NetworkRequest(
    path: "/users/123",
    method: .delete
)
```

### 错误处理

```swift
client.send(request, commonType: APIResponse<User>.self) { result in
    switch result {
    case .success(let response):
        if let user = response.data {
            print("用户信息: \(user)")
        }
    case .failure(let error):
        switch error {
        case NetworkError.invalidURL:
            print("无效的 URL")
        case NetworkError.noData:
            print("没有返回数据")
        case NetworkError.httpError(let statusCode):
            print("HTTP 错误: \(statusCode)")
        case NetworkError.decodingFailed(let decodingError):
            print("解码失败: \(decodingError)")
        case NetworkError.apiError(let code, let message):
            print("API 错误: \(code) - \(message)")
        case NetworkError.requestFailed(let underlyingError):
            print("请求失败: \(underlyingError)")
        default:
            print("未知错误: \(error)")
        }
    }
}
```

## 拦截器

拦截器允许你在请求发送前和响应返回后进行自定义处理。

### 创建自定义拦截器

```swift
// 认证拦截器
class AuthInterceptor: NetworkInterceptor {
    private let token: String

    init(token: String) {
        self.token = token
    }

    func intercept(request: NetworkRequest) -> NetworkRequest {
        return request.copyWithModify { headers in
            var newHeaders = headers ?? [:]
            newHeaders["Authorization"] = "Bearer \(token)"
            return newHeaders
        }
    }

    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error> {
        // 可以在这里处理响应，比如刷新 token
        return response
    }
}

// 日志拦截器
class LoggingInterceptor: NetworkInterceptor {
    func intercept(request: NetworkRequest) -> NetworkRequest {
        print("🚀 发送请求: \(request.method.rawValue) \(request.path)")
        return request
    }

    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error> {
        switch response {
        case .success:
            print("✅ 请求成功: \(request.path)")
        case .failure(let error):
            print("❌ 请求失败: \(request.path) - \(error)")
        }
        return response
    }
}
```

### 使用拦截器

```swift
let client = URLSessionNetworkClient(baseURL: "https://api.example.com")

// 添加拦截器（按顺序执行）
client.interceptors = [
    AuthInterceptor(token: "your-token"),
    LoggingInterceptor()
]
```

## 表单参数编码

使用 `URLEncodedFormParameterEncoder` 处理表单数据：

```swift
// 创建表单编码器
let encoder = URLEncodedFormParameterEncoder()

// 编码 Codable 对象
struct LoginForm: Codable {
    let username: String
    let password: String
}

let form = LoginForm(username: "user", password: "pass")
let formData = try encoder.encode(form)

// 或者直接编码字典
let parameters = ["username": "user", "password": "pass"]
let formData = try encoder.encode(parameters)

// 创建请求
let request = NetworkRequest(
    path: "/login",
    method: .post,
    body: .data(formData),
    headers: ["Content-Type": "application/x-www-form-urlencoded"]
)
```

## 文件上传

### 流式多部分上传

对于大文件上传，可以使用 `StreamingMultipartInputStream`：

```swift
// 创建流式多部分输入流
let fileURL = URL(fileURLWithPath: "/path/to/large/file.zip")
let boundary = "Boundary-\(UUID().uuidString)"

let inputStream = try StreamingMultipartInputStream(
    boundary: boundary,
    preuploadID: "upload-123",
    sliceNo: 1,
    sliceMD5: "file-md5-hash",
    fileURL: fileURL,
    sliceOffset: 0,
    sliceSize: 1024 * 1024 // 1MB 分片
)

// 创建上传请求
let uploadRequest = NetworkRequest(
    path: "/upload/slice",
    method: .post,
    body: .inputStream(inputStream),
    headers: [
        "Content-Type": "multipart/form-data; boundary=\(boundary)",
        "Content-Length": "\(inputStream.contentLength)"
    ]
)

// 发送上传请求
client.send(uploadRequest, commonType: nil) { (result: Result<UploadResponse, Error>) in
    switch result {
    case .success(let response):
        print("上传成功: \(response)")
    case .failure(let error):
        print("上传失败: \(error)")
    }
}
```

### 简单文件上传

```swift
// 读取文件数据
let fileData = try Data(contentsOf: fileURL)

// 构建 multipart 数据
let boundary = "Boundary-\(UUID().uuidString)"
var body = Data()

body.append("--\(boundary)\r\n".data(using: .utf8)!)
body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
body.append(fileData)
body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

let request = NetworkRequest(
    path: "/upload",
    method: .post,
    body: .data(body),
    headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
)
```

## 重试机制

### 自动重试

```swift
// 创建带重试的请求
let request = NetworkRequest(
    path: "/api/data",
    method: .get,
    retryTime: 3 // 最多重试 3 次
)
```

### 自定义重试逻辑

```swift
let request = NetworkRequest(
    path: "/api/data",
    method: .get,
    reset: { originalRequest in
        // 自定义重试逻辑
        print("重试请求: \(originalRequest.id)")
        return originalRequest.copyWithModify { headers in
            var newHeaders = headers ?? [:]
            newHeaders["X-Retry-Count"] = "\((originalRequest.retryTime) + 1)"
            return newHeaders
        }
    }
)
```

## 实际使用示例

### 用户管理 API

```swift
class UserService {
    private let client: NetworkClient

    init(baseURL: String) {
        self.client = URLSessionNetworkClient(baseURL: baseURL)
        self.client.interceptors = [
            AuthInterceptor(token: UserDefaults.standard.string(forKey: "auth_token") ?? ""),
            LoggingInterceptor()
        ]
    }

    // 获取用户列表
    func getUsers(page: Int = 1, completion: @escaping (Result<[User], Error>) -> Void) {
        let request = NetworkRequest(
            path: "/users",
            method: .get,
            query: ["page": "\(page)", "limit": "20"]
        )

        client.send(request, commonType: APIResponse<[User]>.self) { result in
            switch result {
            case .success(let response):
                completion(.success(response.data ?? []))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // 创建用户
    func createUser(_ user: CreateUserRequest, completion: @escaping (Result<User, Error>) -> Void) {
        do {
            let userData = try JSONEncoder().encode(user)
            let request = NetworkRequest(
                path: "/users",
                method: .post,
                body: .data(userData),
                headers: ["Content-Type": "application/json"]
            )

            client.send(request, commonType: APIResponse<User>.self) { result in
                switch result {
                case .success(let response):
                    if let user = response.data {
                        completion(.success(user))
                    } else {
                        completion(.failure(NetworkError.noData))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    // 更新用户
    func updateUser(id: Int, user: UpdateUserRequest, completion: @escaping (Result<User, Error>) -> Void) {
        do {
            let userData = try JSONEncoder().encode(user)
            let request = NetworkRequest(
                path: "/users/\(id)",
                method: .put,
                body: .data(userData),
                headers: ["Content-Type": "application/json"]
            )

            client.send(request, commonType: APIResponse<User>.self, completion: { result in
                switch result {
                case .success(let response):
                    if let user = response.data {
                        completion(.success(user))
                    } else {
                        completion(.failure(NetworkError.noData))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            })
        } catch {
            completion(.failure(error))
        }
    }

    // 删除用户
    func deleteUser(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        let request = NetworkRequest(
            path: "/users/\(id)",
            method: .delete
        )

        client.send(request, commonType: APIResponse<EmptyResponse>.self) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
```

### 使用示例

```swift
let userService = UserService(baseURL: "https://api.example.com")

// 获取用户列表
userService.getUsers(page: 1) { result in
    switch result {
    case .success(let users):
        print("获取到 \(users.count) 个用户")
    case .failure(let error):
        print("获取用户失败: \(error)")
    }
}

// 创建新用户
let newUser = CreateUserRequest(name: "张三", email: "zhangsan@example.com")
userService.createUser(newUser) { result in
    switch result {
    case .success(let user):
        print("创建用户成功: \(user.name)")
    case .failure(let error):
        print("创建用户失败: \(error)")
    }
}
```

## 最佳实践

### 1. 统一错误处理

```swift
extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .noData:
            return "服务器没有返回数据"
        case .requestFailed(let error):
            return "网络请求失败: \(error.localizedDescription)"
        case .httpError(let statusCode):
            return "HTTP 错误 \(statusCode)"
        case .decodingFailed:
            return "数据解析失败"
        case .apiError(let code, let message):
            return "API 错误 \(code): \(message)"
        case .unknown:
            return "未知错误"
        case .maxRetry:
            return "超过最大重试次数"
        }
    }
}
```

### 2. 配置管理

```swift
struct APIConfig {
    static let baseURL = "https://api.example.com"
    static let timeout: TimeInterval = 30

    static var defaultHeaders: [String: String] {
        return [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "MyApp/1.0"
        ]
    }
}

// 创建配置好的客户端
extension URLSessionNetworkClient {
    static func configured() -> URLSessionNetworkClient {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeout
        config.timeoutIntervalForResource = APIConfig.timeout

        let session = URLSession(configuration: config)
        let client = URLSessionNetworkClient(baseURL: APIConfig.baseURL, session: session)

        // 添加默认拦截器
        client.interceptors = [
            DefaultHeadersInterceptor(),
            AuthInterceptor(),
            LoggingInterceptor()
        ]

        return client
    }
}
```

### 3. 响应缓存

```swift
class CachingInterceptor: NetworkInterceptor {
    private let cache = NSCache<NSString, AnyObject>()

    func intercept(request: NetworkRequest) -> NetworkRequest {
        return request
    }

    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error> {
        if case .success(let data) = response, request.method == .get {
            cache.setObject(data as AnyObject, forKey: request.path as NSString)
        }
        return response
    }

    func getCachedResponse<T: Decodable>(for path: String, type: T.Type) -> T? {
        return cache.object(forKey: path as NSString) as? T
    }
}
```

### 4. 网络状态监控

```swift
import Network

class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    var isConnected = false
    var connectionType: NWInterface.InterfaceType?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            self?.connectionType = path.availableInterfaces.first?.type
        }
        monitor.start(queue: queue)
    }
}

// 在拦截器中使用
class NetworkStatusInterceptor: NetworkInterceptor {
    func intercept(request: NetworkRequest) -> NetworkRequest {
        guard NetworkMonitor.shared.isConnected else {
            // 可以抛出自定义错误或者缓存请求
            return request
        }
        return request
    }

    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error> {
        return response
    }
}
```

## API 参考

### NetworkClient

```swift
public protocol NetworkClient {
    var interceptors: [NetworkInterceptor] { get set }

    func send<T: Decodable, H: CommonResponseHead>(
        _ request: NetworkRequest,
        commonType: H.Type?,
        completion: @Sendable @escaping (Result<T, any Error>) -> Void
    ) -> URLSessionTask?
}
```

### NetworkRequest

```swift
public struct NetworkRequest {
    public enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    public enum Body {
        case data(Data)
        case inputStream(InputStream)
    }

    public let id: String
    public let path: String
    public let method: Method
    public let query: [String: String]?
    public let body: Body?
    public let headers: [String: String]?
    public let resetBlock: ResetBlock?
    public let retryTime: Int
}
```

### NetworkError

```swift
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
```

### NetworkInterceptor

```swift
public protocol NetworkInterceptor {
    func intercept(request: NetworkRequest) -> NetworkRequest
    func intercept<T: Decodable>(response: Result<T, any Error>, for request: NetworkRequest) -> Result<T, any Error>
}
```

## 常见问题

### Q: 如何处理 HTTPS 证书验证？

A: 可以通过自定义 URLSessionConfiguration 来配置证书验证：

```swift
let config = URLSessionConfiguration.default
// 配置证书验证逻辑
let session = URLSession(configuration: config, delegate: customDelegate, delegateQueue: nil)
let client = URLSessionNetworkClient(baseURL: baseURL, session: session)
```

### Q: 如何实现请求取消？

A: `send` 方法返回 `URLSessionTask`，可以调用 `cancel()` 方法：

```swift
let task = client.send(request, commonType: nil) { result in
    // 处理结果
}

// 取消请求
task?.cancel()
```

### Q: 如何处理大文件下载？

A: 建议使用 URLSession 的下载任务，或者实现自定义的下载拦截器。

### Q: 如何实现请求队列和并发控制？

A: 可以通过自定义 URLSessionConfiguration 的 `httpMaximumConnectionsPerHost` 属性来控制并发数。

## 许可证

本项目基于 MIT 许可证开源。详情请查看 LICENSE 文件。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个库。

## 更新日志

### v1.0.0
- 初始版本发布
- 支持基本的网络请求功能
- 实现拦截器机制
- 支持流式文件上传
- 完善的错误处理
