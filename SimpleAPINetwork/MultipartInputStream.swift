import Foundation
import LoggerProxy

// MARK: - 流式 Multipart InputStream

extension String {
    func rfc5987Encoded() -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

public class MultipartInputStream: InputStream {
    public enum PartBody {
        case data(data: Data)
        case streamFactory(openAction: () throws -> InputStream, contentLength: Int64)
        var contentLength: Int64 {
            switch self {
                case let .data(data):
                    return Int64(data.count)
                case let .streamFactory(_, int64):
                    return int64
            }
        }
    }
    
    public struct ContentDisposition {
        let type = "form-data"
        var name: String
        var filename: String?
        
        public var description: String {
            let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
            if let filename = filename?.rfc5987Encoded() {
                return "Content-Disposition: \(type); name=\"\(escapedName)\"; filename*=UTF-8''\(filename)"
            } else {
                return "Content-Disposition: \(type); name=\"\(escapedName)\""
            }
        }
    }
    
    public struct Part {
        let contentDisposition: ContentDisposition
        let contentType: String?
        let body: PartBody
        
        public var header: Data {
            var lines: [String] = []
            lines.append(contentDisposition.description)
            if let contentType = contentType {
                lines.append("Content-Type: \(contentType)")
            }
            lines.append("") // 空行：分隔 header 与 body
            let headerString = lines.joined(separator: "\r\n") + "\r\n"
            return Data(headerString.utf8)
        }
    }
    
    fileprivate enum InternalPartContent {
        case data(Data)
        case stream(stream: InputStream)
        func close() {
            switch self {
                case .data:
                    break
                case let .stream(stream):
                    stream.close()
            }
        }
    }
    
    fileprivate class InternalPart {
        let content: InternalPartContent
        let contentLength: Int64
        var offset: Int64 = 0
        
        convenience init(part: PartBody) throws {
            switch part {
                case let .data(data):
                    self.init(content: .data(data), contentLength: Int64(data.count), offset: 0)
                case let .streamFactory(openAction, contentLength):
                    let stream = try openAction()
                    self.init(content: .stream(stream: stream), contentLength: contentLength, offset: 0)
            }
        }
        
        init(content: InternalPartContent, contentLength: Int64, offset: Int64 = 0) {
            self.content = content
            self.contentLength = contentLength
            self.offset = offset
        }
    }
    
    private var _streamError: Error?
    private var _delegate: StreamDelegate?
    private let contentLength: Int64
    private let partsBody: [PartBody]
    private var openParts: [InternalPart]?
    private var currentPartIndex: Int = 0
    private var _streamStatus: Stream.Status = .notOpen
    private static let emptyData = Data()
    private static let newLine = Data("\r\n".utf8)
    
    public init(parts: [Part], boundary: String) throws {
        // 修复：boundary 格式应该是 --boundary，并且开头不需要 \r\n
        let boundaryPrefix = Data("--\(boundary)\r\n".utf8)
        let boundarySuffix = Data("\r\n--\(boundary)--\r\n".utf8)
        
        var partsBody: [PartBody] = []
        
        // 添加第一个边界
        partsBody.append(.data(data: boundaryPrefix))
        
        for (index, part) in parts.enumerated() {
            // 添加 header
            partsBody.append(.data(data: part.header))
            
            // 添加 body（如果有内容）
            if part.body.contentLength > 0 {
                partsBody.append(part.body)
            }
            
            // 添加分隔符（除了最后一个）
            if index < parts.count - 1 {
                partsBody.append(.data(data: Data("\r\n--\(boundary)\r\n".utf8)))
            }
        }
        
        // 添加结束边界
        partsBody.append(.data(data: boundarySuffix))
        
        self.partsBody = partsBody
        contentLength = partsBody.reduce(0, { $0 + $1.contentLength })
        super.init(data: Data())
    }
    
    // MARK: - InputStream Override Methods
    
    override public func open() {
        guard _streamStatus == .notOpen else { return }
        _streamStatus = .opening
        
        do {
            openParts = try partsBody.map({ try InternalPart(part: $0) })
            
            // 打开所有的流
            for part in openParts! {
                if case let .stream(stream) = part.content {
                    stream.open()
                }
            }
            
            currentPartIndex = 0
            _streamStatus = .open
        } catch {
            _streamError = error
            _streamStatus = .error
        }
    }
    
    override public func close() {
        openParts?.forEach({ $0.content.close() })
        _streamStatus = .closed
        currentPartIndex = -1
    }
    
    override public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard _streamStatus == .open,
              let openParts = openParts,
              len > 0 else {
            return -1
        }
        
        var totalBytesRead = 0
        var remainingLength = len
        
        while remainingLength > 0 && currentPartIndex < openParts.count {
            let currentPart = openParts[currentPartIndex]
            let remainingInCurrentPart = currentPart.contentLength - currentPart.offset
            
            // 如果当前 part 已经读完，移动到下一个
            if remainingInCurrentPart <= 0 {
                currentPartIndex += 1
                continue
            }
            
            let bytesToRead = min(remainingLength, Int(remainingInCurrentPart))
            var bytesRead = 0
            
            switch currentPart.content {
                case let .data(data):
                    // 从 Data 中读取
                    let startIndex = Int(currentPart.offset)
                    let endIndex = min(startIndex + bytesToRead, data.count)
                    let bytesToCopy = endIndex - startIndex
                    
                    if bytesToCopy > 0 {
                        data.withUnsafeBytes { dataBytes in
                            let sourcePtr = dataBytes.bindMemory(to: UInt8.self).baseAddress! + startIndex
                            let destPtr = buffer.advanced(by: totalBytesRead)
                            destPtr.initialize(from: sourcePtr, count: bytesToCopy)
                        }
                        bytesRead = bytesToCopy
                    }
                    
                case let .stream(stream):
                    // 从 InputStream 中读取
                    let destPtr = buffer.advanced(by: totalBytesRead)
                    let result = stream.read(destPtr, maxLength: bytesToRead)
                    
                    if result < 0 {
                        // 流读取出错
                        _streamError = stream.streamError
                        _streamStatus = .error
                        return -1
                    } else if result == 0 {
                        // 流已结束，但可能还有剩余长度未读完
                        // 这种情况下应该移动到下一个 part
                        currentPartIndex += 1
                        continue
                    } else {
                        bytesRead = result
                    }
            }
            
            // 更新偏移量和计数器
            currentPart.offset += Int64(bytesRead)
            totalBytesRead += bytesRead
            remainingLength -= bytesRead
            
            // 如果当前 part 读完了，移动到下一个
            if currentPart.offset >= currentPart.contentLength {
                currentPartIndex += 1
            }
        }
        
        // 如果所有 parts 都读完了，标记为结束
        if currentPartIndex >= openParts.count {
            _streamStatus = .atEnd
        }
        
        return totalBytesRead
    }
    
    override public var hasBytesAvailable: Bool {
        guard _streamStatus == .open,
              let openParts = openParts,
              currentPartIndex >= 0 else {
            return false
        }
        
        // 检查是否还有未读完的 parts
        if currentPartIndex < openParts.count {
            let currentPart = openParts[currentPartIndex]
            // 如果当前 part 还有数据，或者还有后续 parts
            return currentPart.offset < currentPart.contentLength || currentPartIndex < openParts.count - 1
        }
        
        return false
    }
    
    override public var streamStatus: Stream.Status {
        return _streamStatus
    }
    
    override public var streamError: Error? {
        return _streamError
    }
    
    // MARK: - StreamDelegate Support
    
    override public var delegate: StreamDelegate? {
        get { return _delegate }
        set { _delegate = newValue }
    }
    
    override public func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        // 实现 RunLoop 调度，通常为空实现
    }
    
    override public func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        // 实现 RunLoop 移除，通常为空实现
    }
    
    private var propertyStorage: [Stream.PropertyKey: Any] = [:]
    private var propertyLock = NSLock()
    
    override public func property(forKey key: Stream.PropertyKey) -> Any? {
        propertyLock.lock()
        defer {
            propertyLock.unlock()
        }
        return propertyStorage[key]
    }
    
    override public func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
        propertyLock.lock()
        defer {
            propertyLock.unlock()
        }
        propertyStorage[key] = property
        return true
    }
}
