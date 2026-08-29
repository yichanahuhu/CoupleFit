import Foundation

// MARK: - LeanCloud 配置

/// 占位配置：拿到 leancloud.app 控制台的应用 Key 后，只改这里三行即可。
/// - apiBase：应用「设置 / 应用 Key」里的 REST API 地址，形如 https://xxxx.api.lncldglobal.com（不含 /1.1）
enum LeanCloudConfig {
    static let appId = "YOUR_LEANCLOUD_APP_ID"
    static let appKey = "YOUR_LEANCLOUD_APP_KEY"
    static let apiBase = "https://your-app.api.lncldglobal.com"
}

// MARK: - LeanCloud 错误

struct LeanCloudError: LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

/// 把 LeanCloud 错误码映射为面向用户的中文提示
func mapLeanCloudError(code: Int, message: String) -> Error {
    switch code {
    case 202:
        return AppError.unknown("该邮箱已注册，请直接登录")
    case 210:
        return AppError.unknown("密码错误，请重试")
    case 211:
        return AppError.unknown("该邮箱尚未注册")
    case 219:
        return AppError.unknown("操作过于频繁，请稍后再试")
    case 401, 403:
        return AppError.notSignedIn
    default:
        return LeanCloudError(code: code, message: message)
    }
}

// MARK: - LeanCloud REST 客户端

/// 所有与 LeanCloud 的 HTTP 交互集中在此。
/// 认证用国际版 `X-LC-Id` + `X-LC-Key`（无需 HMAC 签名）；
/// 登录后通过 `sessionToken` 设置 `X-LC-Session` 以操作用户私有数据。
final class LeanCloudClient {

    static let shared = LeanCloudClient()

    /// 登录后由 AuthService 写入，用于后续请求的 X-LC-Session
    var sessionToken: String?

    private let base: String
    private let decoder = JSONDecoder()

    private init() {
        let trimmed = LeanCloudConfig.apiBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        base = trimmed + "/1.1"
    }

    // MARK: - 请求构造

    private func makeRequest(path: String, method: String, query: [URLQueryItem]?, body: Data?) -> URLRequest {
        var urlString = base + path
        if let query, !query.isEmpty,
           var comp = URLComponents(string: urlString) {
            comp.queryItems = query
            urlString = comp.string ?? urlString
        }
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = method
        req.setValue(LeanCloudConfig.appId, forHTTPHeaderField: "X-LC-Id")
        req.setValue(LeanCloudConfig.appKey, forHTTPHeaderField: "X-LC-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let s = sessionToken {
            req.setValue(s, forHTTPHeaderField: "X-LC-Session")
        }
        req.httpBody = body
        req.timeoutInterval = 20
        return req
    }

    // MARK: - 通用请求

    /// 发送请求，返回解析后的 JSON（字典或数组）。非 2xx 时抛出映射后的错误。
    func requestJSON(path: String, method: String = "GET", query: [URLQueryItem]? = nil, body: [String: Any]? = nil) async throws -> Any {
        var bodyData: Data? = nil
        if let body {
            bodyData = try? JSONSerialization.data(withJSONObject: body)
        }
        let req = makeRequest(path: path, method: method, query: query, body: bodyData)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AppError.unknown("网络响应异常，请重试") }
        if !(200..<300).contains(http.statusCode) {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = dict["code"] as? Int,
               let msg = dict["error"] as? String {
                throw mapLeanCloudError(code: code, message: msg)
            }
            throw AppError.unknown("请求失败（HTTP \(http.statusCode)）")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - 数据对象（classes）

    /// 查询 class，返回 results 数组（每个元素是字典）
    func getResults(className: String, query: [URLQueryItem]? = nil) async throws -> [[String: Any]] {
        let json = try await requestJSON(path: "/classes/\(className)", method: "GET", query: query)
        if let dict = json as? [String: Any], let results = dict["results"] as? [[String: Any]] {
            return results
        }
        return []
    }

    /// 创建对象，返回新 objectId。业务对象自动加公开读写 ACL（本地自用，安全不敏感）。
    func createObject(className: String, fields: [String: Any]) async throws -> String {
        var f = fields
        f["ACL"] = ["*": ["read": true, "write": true]]
        let json = try await requestJSON(path: "/classes/\(className)", method: "POST", body: f)
        guard let dict = json as? [String: Any], let oid = dict["objectId"] as? String else {
            throw AppError.unknown("创建数据失败，请重试")
        }
        return oid
    }

    func updateObject(className: String, objectId: String, fields: [String: Any]) async throws {
        _ = try await requestJSON(path: "/classes/\(className)/\(objectId)", method: "PUT", body: fields)
    }

    func deleteObject(className: String, objectId: String) async throws {
        _ = try await requestJSON(path: "/classes/\(className)/\(objectId)", method: "DELETE")
    }

    // MARK: - 字典 → 模型

    func decode<T: Decodable>(_ dict: [String: Any], as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - 查询构造辅助

    /// 生成 `where={"key":"value"}` 形式的 URLQueryItem
    static func whereItem(_ dict: [String: Any]) -> URLQueryItem {
        let json = (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return URLQueryItem(name: "where", value: json)
    }
}
