import Foundation
import CryptoKit

/// 小米健康云客户端（hlth.io.mi.com/healthapp/*）
/// 签名算法：HMAC-SHA1(ssecurity) over 排序参数串 → base64，nonce 为 8 字节随机 base64
final class MiHealth {
    static let shared = MiHealth()

    private let host = "https://api.hlth.io.mi.com/healthapp/"
    private(set) var lastError = ""

    struct Record: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let value: String
    }

    // MARK: - 签名调用

    private func signedGet(path: String, params: [String: String],
                           completion: @escaping ([String: Any]?) -> Void) {
        guard !MiCloud.shared.serviceToken.isEmpty else {
            lastError = "未登录"; completion(nil); return
        }
        var all = params
        all["user_id"] = MiCloud.shared.userId
        all["app_name"] = "com.xiaomi.wearable"
        let nonce = Self.randomNonce()
        let data = "GET&/healthapp/\(path)&" + all.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let sig = Self.sign(base64Nonce: nonce, data: data, ssecurity: MiCloud.shared.ssecurity)
        all["signature"] = sig
        all["nonce"] = nonce

        var comps = URLComponents(string: host + path)!
        comps.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!, timeoutInterval: 12)
        req.httpMethod = "GET"
        req.setValue("mi-fitness", forHTTPHeaderField: "appName")
        req.setValue(MiCloud.shared.serviceToken, forHTTPHeaderField: "serviceToken")
        req.setValue(MiCloud.shared.userId, forHTTPHeaderField: "userId")
        URLSession.shared.dataTask(with: req) { [weak self] d, _, e in
            guard let d = d,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                self?.lastError = e?.localizedDescription ?? "解析失败"
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let code = j["code"] as? Int ?? -1
            if code != 0 && code != 200 {
                self?.lastError = "code \(code): \(j["message"] as? String ?? "")"
            }
            DispatchQueue.main.async { completion(j) }
        }.resume()
    }

    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &bytes)
        return Data(bytes).base64EncodedString()
    }

    static func sign(base64Nonce: String, data: String, ssecurity: String) -> String {
        guard let key = Data(base64Encoded: ssecurity) else { return "" }
        let msg = Data((base64Nonce + "&" + data).utf8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: msg, using: SymmetricKey(data: key))
        return Data(mac).base64EncodedString()
    }

    // MARK: - 绑定设备（取市场型号用于表盘过滤）

    func fetchBoundDevices(completion: @escaping ([(model: String, name: String)]) -> Void) {
        signedGet(path: "user/get_bound_devices", params: [:]) { j in
            guard let j = j else { completion([]); return }
            let arr = (j["data"] as? [String: Any])?["devices"] as? [[String: Any]]
                ?? j["data"] as? [[String: Any]] ?? []
            let list = arr.compactMap { d -> (String, String)? in
                let m = d["model"] as? String ?? d["device_model"] as? String ?? ""
                let n = d["name"] as? String ?? d["device_name"] as? String ?? m
                return m.isEmpty ? nil : (m, n)
            }
            if let first = list.first {
                UserDefaults.standard.set(first.0, forKey: "mi_device_model")
                UserDefaults.standard.set(first.1, forKey: "mi_device_name")
            }
            completion(list)
        }
    }

    // MARK: - 运动记录

    func fetchSportRecords(days: Int = 7, completion: @escaping ([Record]) -> Void) {
        let end = Int(Date().timeIntervalSince1970)
        let start = end - days * 86400
        let params: [String: String] = [
            "start_time": "\(start)",
            "end_time": "\(end)",
            "limit": "30",
        ]
        signedGet(path: "fitness/get_sport_history", params: params) { [weak self] j in
            guard let j = j, let list = (j["data"] as? [String: Any])?["items"] as? [[String: Any]]
                    ?? (j["data"] as? [[String: Any]]) else {
                completion([]); return
            }
            let recs = list.enumerated().compactMap { i, it -> Record? in
                let name = it["sport_name"] as? String
                    ?? it["name"] as? String
                    ?? "运动"
                let dur = (it["duration"] as? Int ?? 0) / 60
                let dist = it["distance"] as? Double ?? 0
                let ts = it["start_time"] as? Int ?? 0
                let df = DateFormatter()
                df.dateFormat = "MM-dd HH:mm"
                let when = ts > 0 ? df.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) : ""
                return Record(id: "\(i)-\(ts)", title: name,
                              subtitle: when + (dur > 0 ? "  \(dur) 分钟" : ""),
                              value: dist > 0 ? String(format: "%.2f km", dist / 1000) : "")
            }
            _ = self
            completion(recs)
        }
    }
}
