import Foundation
import CryptoKit

/// 小米账号云客户端：passport 登录主链路（密码登录 → serviceToken）
/// 协议端点来自反编译 com.xiaomi.wearable（XMPassport.java）
final class MiCloud {
    static let shared = MiCloud()

    private(set) var userId: String = UserDefaults.standard.string(forKey: "mi_userId") ?? ""
    private(set) var ssecurity: String = UserDefaults.standard.string(forKey: "mi_ssecurity") ?? ""
    private(set) var serviceToken: String = UserDefaults.standard.string(forKey: "mi_serviceToken") ?? ""

    var isLoggedIn: Bool { !serviceToken.isEmpty }

    /// 密码登录（serviceLoginAuth2 公开稳定协议）
    func login(user: String, password: String, completion: @escaping (String) -> Void) {
        let sid = "xiaomiio"
        let step1 = URL(string: "https://account.xiaomi.com/pass/serviceLogin?sid=\(sid)&_locale=zh_CN")!
        URLSession.shared.dataTask(with: step1) { [weak self] data1, _, err1 in
            if let err = err1 { completion("网络错误: \(err.localizedDescription)"); return }
            // step2: serviceLoginAuth2
            let pwdHash = Self.md5Hex(password).uppercased()
            var params: [String: String] = [
                "sid": sid,
                "qs": "%3Fsid%3D" + sid,
                "_json": "true",
                "user": user,
                "hash": pwdHash,
            ]
            // 若 step1 返回 nonce，则补 _sign（部分账号策略要求）
            if let d1 = data1, let j1 = Self.parseJson(d1), let nonce = j1["nonce"] as? String {
                let qs = "%3Fsid%3D" + sid
                let signStr = "nonce=\(nonce)&\(qs)"
                params["_sign"] = Self.md5Hex(signStr).uppercased()
            }
            guard let url2 = URL(string: "https://account.xiaomi.com/pass/serviceLoginAuth2") else { return }
            var req2 = URLRequest(url: url2)
            req2.httpMethod = "POST"
            req2.httpBody = Self.formBody(params)
            req2.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            URLSession.shared.dataTask(with: req2) { [weak self] data2, _, err2 in
                if let err = err2 { completion("网络错误: \(err.localizedDescription)"); return }
                guard let d2 = data2, let j2 = Self.parseJson(d2) else {
                    completion("响应解析失败"); return
                }
                let code = j2["code"] as? Int ?? -1
                let desc = j2["description"] as? String ?? ""
                guard code == 0 else {
                    completion("登录失败[\(code)]: \(desc)")
                    return
                }
                self?.userId = j2["userId"] as? String ?? ""
                self?.ssecurity = j2["ssecurity"] as? String ?? ""
                // step3: 跟随 location 换取 serviceToken cookie
                if let loc = j2["location"] as? String, let url3 = URL(string: loc) {
                    URLSession.shared.dataTask(with: url3) { [weak self] _, _, _ in
                        let cookies = HTTPCookieStorage.shared.cookies?
                            .filter { $0.name == "serviceToken" }
                            .compactMap { $0.value } ?? []
                        self?.serviceToken = cookies.first ?? ""
                        self?.persist()
                        DispatchQueue.main.async {
                            completion(self?.serviceToken.isEmpty == false
                                       ? "登录成功"
                                       : "token 获取失败（location 跟随后无 cookie）")
                        }
                    }.resume()
                } else {
                    self?.persist()
                    DispatchQueue.main.async {
                        completion("登录返回无 location（账号可能需要二次验证）")
                    }
                }
            }.resume()
        }.resume()
    }

    func logout() {
        userId = ""; ssecurity = ""; serviceToken = ""
        persist()
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(userId, forKey: "mi_userId")
        d.set(ssecurity, forKey: "mi_ssecurity")
        d.set(serviceToken, forKey: "mi_serviceToken")
    }

    // MARK: - utils

    static func md5Hex(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 解析小米 passport 特有的 "&&&START&&&{json}" 响应
    static func parseJson(_ data: Data) -> [String: Any]? {
        var text = String(data: data, encoding: .utf8) ?? ""
        if text.hasPrefix("&&&START&&&") { text.removeFirst(11) }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    static func formBody(_ params: [String: String]) -> Data {
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data(comps.percentEncodedQuery?.utf8 ?? Data().utf8)
    }
}
