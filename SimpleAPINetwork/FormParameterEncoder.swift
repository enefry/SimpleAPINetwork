import Foundation

public protocol ParameterEncoder {
    func encode<T: Encodable>(_ parameters: T) throws -> Data
    func encode(_ parameters: [String: Any]) throws -> Data
}

/***
 * url encode 方式参数的encoder，form表单提交信息使用
 **/
public class URLEncodedFormParameterEncoder: ParameterEncoder {
    public init() {
    }

    public func encode<T: Encodable>(_ parameters: T) throws -> Data {
        let data = try JSONEncoder().encode(parameters)
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return try encode(dictionary)
    }

    public func encode(_ parameters: [String: Any]) throws -> Data {
        guard !parameters.isEmpty else {
            return Data()
        }

        var components: [String] = []

        for (key, value) in parameters {
            let encodedKey = percentEncoded(key)
            let encodedValue = percentEncoded(stringValue(for: value))
            components.append("\(encodedKey)=\(encodedValue)")
        }

        let encodedString = components.joined(separator: "&")
        return encodedString.data(using: .utf8) ?? Data()
    }

    private func stringValue(for value: Any) -> String {
        if let array = value as? [Any] {
            // 对于数组，转换为JSON字符串
            if let jsonData = try? JSONSerialization.data(withJSONObject: array),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "[]"
        } else if let dict = value as? [String: Any] {
            // 对于字典，转换为JSON字符串
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "{}"
        } else {
            return String(describing: value)
        }
    }

    private func percentEncoded(_ string: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics
            .union(.init(charactersIn: "-._~"))

        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }
}
