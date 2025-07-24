//
//  LimitedFileInputStream.swift
//  SimpleAPINetwork
//
//  Created by 陈任伟 on 2025/7/24.
//

import Foundation
import LoggerProxy

public class LimitedFileInputStream: InputStream {
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

    override public func open() {
        guard _streamStatus == .notOpen else { return }
        _streamStatus = .open
    }

    override public func close() {
        if _streamStatus != .closed {
            try? fileHandle.close()
            _streamStatus = .closed
        }
    }

    override public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
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

    override public var hasBytesAvailable: Bool {
        return _streamStatus == .open && bytesRead < maxBytes
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

    override public func property(forKey key: Stream.PropertyKey) -> Any? {
        // 返回流属性，通常返回 nil
        return nil
    }

    override public func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
        // 设置流属性，通常返回 false
        return false
    }
}
