import Foundation
import LoggerProxy

// MARK: - 流式 Multipart InputStream

public class StreamingMultipartInputStream: InputStream {
    private let boundary: String
    private let preuploadID: String
    private let sliceNo: Int
    private let sliceMD5: String
    private let fileURL: URL
    private let sliceOffset: Int64
    private let sliceSize: Int64

    private var fileInputStream: InputStream?
    private var headerData: Data
    private var footerData: Data
    private var headerIndex = 0
    private var footerIndex = 0

    private enum ReadState {
        case header
        case file
        case footer
        case finished
    }

    private var readState: ReadState = .header
    private var _streamStatus: Stream.Status = .notOpen
    private var _streamError: Error?
    private var _delegate: StreamDelegate?

    public let contentLength: Int64

    public init(boundary: String,
                preuploadID: String,
                sliceNo: Int,
                sliceMD5: String,
                fileURL: URL,
                sliceOffset: Int64,
                sliceSize: Int64) throws {
        self.boundary = boundary
        self.preuploadID = preuploadID
        self.sliceNo = sliceNo
        self.sliceMD5 = sliceMD5
        self.fileURL = fileURL
        self.sliceOffset = sliceOffset
        self.sliceSize = sliceSize

        // 构建头部数据
        headerData = Self.buildHeaderData(
            boundary: boundary,
            preuploadID: preuploadID,
            sliceNo: sliceNo,
            sliceMD5: sliceMD5
        )

        // 构建尾部数据
        footerData = Self.buildFooterData(boundary: boundary)

        // 计算总内容长度
        contentLength = Int64(headerData.count) + sliceSize + Int64(footerData.count)

        super.init(data: Data()) // 传入空数据，实际读取由 read 方法处理
    }

    // MARK: - InputStream Override Methods

    override public func open() {
        guard _streamStatus == .notOpen else { return }
        _streamStatus = .opening

        // 创建文件输入流但不立即打开
        do {
            fileInputStream = try createFileInputStream()
            _streamStatus = .open
        } catch {
            _streamError = error
            _streamStatus = .error
        }
    }

    override public func close() {
        fileInputStream?.close()
        fileInputStream = nil
        _streamStatus = .closed
    }

    override public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard _streamStatus == .open else {
            return -1
        }

        var totalBytesRead = 0
        var remainingLength = len

        while remainingLength > 0 && readState != .finished {
            let bytesRead: Int

            switch readState {
            case .header:
                bytesRead = readFromHeader(buffer: buffer.advanced(by: totalBytesRead), maxLength: remainingLength)
                if headerIndex >= headerData.count {
                    readState = .file
                    // 打开文件流
                    fileInputStream?.open()
                }

            case .file:
                bytesRead = readFromFile(buffer: buffer.advanced(by: totalBytesRead), maxLength: remainingLength)
                if let fileStream = fileInputStream, !fileStream.hasBytesAvailable {
                    readState = .footer
                    fileStream.close()
                }

            case .footer:
                bytesRead = readFromFooter(buffer: buffer.advanced(by: totalBytesRead), maxLength: remainingLength)
                if footerIndex >= footerData.count {
                    readState = .finished
                }

            case .finished:
                bytesRead = -1
                break
            }

            if bytesRead <= 0 {
                break
            }

            totalBytesRead += bytesRead
            remainingLength -= bytesRead
        }

        if readState == .finished && totalBytesRead == 0 {
            _streamStatus = .atEnd
        }

        return totalBytesRead
    }

    override public var hasBytesAvailable: Bool {
        return _streamStatus == .open && readState != .finished
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
    private var propertyLock: NSLock = NSLock()
    override public func property(forKey key: Stream.PropertyKey) -> Any? {
        // 返回流属性，通常返回 nil
        propertyLock.lock()
        defer {
            propertyLock.unlock()
        }
        return propertyStorage[key]
    }

    override public func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
        // 设置流属性，通常返回 false
        propertyLock.lock()
        defer {
            propertyLock.unlock()
        }
        propertyStorage[key] = property
        return true
    }

    // MARK: - Private Methods

    private func createFileInputStream() throws -> InputStream {
        // 创建文件句柄并定位到指定偏移量
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        fileHandle.seek(toFileOffset: UInt64(sliceOffset))

        // 创建有限制大小的文件输入流
        return LimitedFileInputStream(fileHandle: fileHandle, maxBytes: sliceSize)
    }

    private func readFromHeader(buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        let remainingHeaderBytes = headerData.count - headerIndex
        let bytesToRead = min(maxLength, remainingHeaderBytes)

        guard bytesToRead > 0 else { return 0 }

        headerData.withUnsafeBytes { bytes in
            let sourcePtr = bytes.bindMemory(to: UInt8.self).baseAddress!.advanced(by: headerIndex)
            buffer.initialize(from: sourcePtr, count: bytesToRead)
        }

        headerIndex += bytesToRead
        return bytesToRead
    }

    private func readFromFile(buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        guard let fileStream = fileInputStream else { return 0 }
        return fileStream.read(buffer, maxLength: maxLength)
    }

    private func readFromFooter(buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        let remainingFooterBytes = footerData.count - footerIndex
        let bytesToRead = min(maxLength, remainingFooterBytes)

        guard bytesToRead > 0 else { return 0 }

        footerData.withUnsafeBytes { bytes in
            let sourcePtr = bytes.bindMemory(to: UInt8.self).baseAddress!.advanced(by: footerIndex)
            buffer.initialize(from: sourcePtr, count: bytesToRead)
        }

        footerIndex += bytesToRead
        return bytesToRead
    }

    // MARK: - Static Helper Methods

    private static func buildHeaderData(boundary: String,
                                        preuploadID: String,
                                        sliceNo: Int,
                                        sliceMD5: String) -> Data {
        var header = Data()

        func appendFormField(_ name: String, value: String) {
            header.append("--\(boundary)\r\n".data(using: .utf8)!)
            header.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            header.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendFormField("preuploadID", value: preuploadID)
        appendFormField("sliceNo", value: String(sliceNo))
        appendFormField("sliceMD5", value: sliceMD5)

        // 文件部分的头部
        header.append("--\(boundary)\r\n".data(using: .utf8)!)
        header.append("Content-Disposition: form-data; name=\"slice\"; filename=\"slice\"\r\n".data(using: .utf8)!)
        header.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)

        return header
    }

    private static func buildFooterData(boundary: String) -> Data {
        var footer = Data()
        footer.append("\r\n".data(using: .utf8)!)
        footer.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return footer
    }
}

// MARK: - 有限制的文件输入流

private class LimitedFileInputStream: InputStream {
    private let fileHandle: FileHandle
    private let maxBytes: Int64
    private var bytesRead: Int64 = 0

    private var _streamStatus: Stream.Status = .notOpen
    private var _streamError: Error?
    private var _delegate: StreamDelegate?

    init(fileHandle: FileHandle, maxBytes: Int64) {
        self.fileHandle = fileHandle
        self.maxBytes = maxBytes
        super.init(data: Data())
    }

    deinit {
        close()
    }

    override func open() {
        guard _streamStatus == .notOpen else { return }
        _streamStatus = .open
    }

    override func close() {
        if _streamStatus != .closed {
            try? fileHandle.close()
            _streamStatus = .closed
        }
    }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard _streamStatus == .open else { return -1 }
        guard bytesRead < maxBytes else {
            _streamStatus = .atEnd
            return 0
        }

        let remainingBytes = maxBytes - bytesRead
        let bytesToRead = min(Int64(len), remainingBytes)

        let data = fileHandle.readData(ofLength: Int(bytesToRead))
        guard !data.isEmpty else {
            _streamStatus = .atEnd
            return 0
        }

        data.withUnsafeBytes { bytes in
            buffer.initialize(from: bytes.bindMemory(to: UInt8.self).baseAddress!, count: data.count)
        }

        bytesRead += Int64(data.count)

        if bytesRead >= maxBytes {
            _streamStatus = .atEnd
        }

        return data.count
    }

    override var hasBytesAvailable: Bool {
        return _streamStatus == .open && bytesRead < maxBytes
    }

    override var streamStatus: Stream.Status {
        return _streamStatus
    }

    override var streamError: Error? {
        return _streamError
    }

    // MARK: - StreamDelegate Support

    override var delegate: StreamDelegate? {
        get { return _delegate }
        set { _delegate = newValue }
    }

    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        // 实现 RunLoop 调度，通常为空实现
    }

    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        // 实现 RunLoop 移除，通常为空实现
    }

    override func property(forKey key: Stream.PropertyKey) -> Any? {
        // 返回流属性，通常返回 nil
        return nil
    }

    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
        // 设置流属性，通常返回 false
        return false
    }
}
