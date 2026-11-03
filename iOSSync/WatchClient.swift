import Foundation

/// 手表端 HTTP 客户端（与手表 iOSSync App 的 /sync 端点对接）
final class WatchClient {
    static let shared = WatchClient()
    /// 不写死 IP（路由器天天换）——默认空，靠 Bonjour 自动发现填充。
    /// 只有发现失败时才会回退到 UserDefaults 里上次成功的地址。
    static let defaultBase = ""

    var baseURL: String {
        get {
            let s = UserDefaults.standard.string(forKey: "watch_base") ?? Self.defaultBase
            return s.hasSuffix("/") ? String(s.dropLast()) : s
        }
        set {
            var v = newValue
            if v.hasSuffix("/") { v = String(v.dropLast()) }
            UserDefaults.standard.set(v, forKey: "watch_base")
        }
    }

    /// 用户手动填过地址→不再被自动发现覆盖
    var manualOverride: Bool {
        get { UserDefaults.standard.bool(forKey: "watch_manual") }
        set { UserDefaults.standard.set(newValue, forKey: "watch_manual") }
    }

    /// 最近一次请求成功的地址，发现失败时可回退
    func remember(_ url: String) {
        UserDefaults.standard.set(url, forKey: "watch_base_last_ok")
    }

    private var lastDiscoverAt = Date.distantPast

    /// 请求失败时顺手重新发现一次（20 秒内不重复触发，避免打转）
    func maybeRediscover() {
        guard !manualOverride else { return }
        guard Date().timeIntervalSince(lastDiscoverAt) > 20 else { return }
        lastDiscoverAt = Date()
        WatchDiscovery.shared.start(timeout: 5)
    }

    /// 手表时钟相对手机的偏差（毫秒，>0 表示手表快）。用于时间重基。
    static func clockSkewMs(serverNow: Double) -> Double {
        guard serverNow > 0 else { return 0 }
        return serverNow - Date().timeIntervalSince1970 * 1000
    }

    /// 探活：能 ping 通就记住这个地址
    func ensureReachable(completion: @escaping (Bool) -> Void) {
        getJSON("/ping") { j in
            if j?["ok"] as? Bool == true {
                self.remember(self.baseURL)
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    /// 一体化同步：健康 + 位置 + 时间戳
    func sync(steps: Double, heartRate: Double,
              lat: Double, lon: Double, name: String,
              completion: @escaping (String) -> Void) {
        guard let url = URL(string: baseURL + "/sync") else {
            DispatchQueue.main.async { completion("地址无效") }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "steps": Int(steps),
            "heart_rate": Int(heartRate),
            "latitude": lat,
            "longitude": lon,
            "name": name,
            "epoch_ms": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion("同步失败: \(err.localizedDescription)")
                } else if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    completion("同步成功")
                } else {
                    completion("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                }
            }
        }.resume()
    }

    /// 手表传感器快照（上行：手表 → 手机）
    func fetchSensors(completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + "/sensors") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var dict: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict = j
            }
            DispatchQueue.main.async { completion(dict) }
        }.resume()
    }

    /// 下行推送：发文本消息到手表显示
    func pushMessage(_ text: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + "/notify") else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            DispatchQueue.main.async {
                completion((resp as? HTTPURLResponse)?.statusCode == 200)
            }
        }.resume()
    }

    /// 下发定位（手表据此刷新天气）
    func pushLocation(lat: Double, lon: Double, name: String,
                      completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + "/location") else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "latitude": lat, "longitude": lon, "name": name,
        ])
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            DispatchQueue.main.async {
                completion((resp as? HTTPURLResponse)?.statusCode == 200)
            }
        }.resume()
    }

    /// 下发配置：手表测量间隔（分钟，0=仅手动测量）
    func pushConfig(measureIntervalMin: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + "/config") else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["measure_interval_min": measureIntervalMin])
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            DispatchQueue.main.async {
                completion((resp as? HTTPURLResponse)?.statusCode == 200)
            }
        }.resume()
    }

    /// 测试连通性
    func ping(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + "/ping") else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            DispatchQueue.main.async {
                completion((resp as? HTTPURLResponse)?.statusCode == 200)
            }
        }.resume()
    }

    // MARK: - 闹钟（手表自建闹钟引擎，系统级精确响铃）

    func fetchAlarms(completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + "/alarms") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 6)) { data, resp, _ in
            var j: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            DispatchQueue.main.async { completion(j) }
        }.resume()
    }

    func alarmOp(_ op: String, id: Int = 0, hour: Int = 7, minute: Int = 30,
                 days: [Int] = [], label: String = "",
                 completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + "/alarms") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "op": op, "id": id, "hour": hour, "minute": minute,
            "days": days, "label": label,
        ])
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var j: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            DispatchQueue.main.async { completion(j) }
        }.resume()
    }

    // MARK: - 手表真实运动（ExerciseClient）

    func sportAction(_ action: String, type: String = "running",
                     completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + "/sport") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action, "type": type])
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var j: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            DispatchQueue.main.async { completion(j) }
        }.resume()
    }

    func sportSnapshot(completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + "/sport") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 6)) { data, resp, _ in
            var j: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            DispatchQueue.main.async { completion(j) }
        }.resume()
    }

    /// 手表是否拿到「悬浮窗」豁免（Android 14 后台弹界面的必要条件）
    func overlayStatus(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + "/overlay") else {
            DispatchQueue.main.async { completion(false) }; return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 6)) { data, _, _ in
            var ok = false
            if let data = data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                ok = j["allowed"] as? Bool ?? false
            }
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    // MARK: - 本机表盘（手表系统真实枚举 / 切换）

    func fetchWatchfaces(completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + "/watchfaces") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 10)) { data, resp, _ in
            var j: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            DispatchQueue.main.async { completion(j) }
        }.resume()
    }

    func applyWatchface(pkg: String, index: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + "/watchfaces") else {
            DispatchQueue.main.async { completion(false) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["pkg": pkg, "index": index])
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var ok = false
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                ok = j["ok"] as? Bool ?? false
            }
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    func openWatchfaceChooser(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + "/watchfaces/chooser") else {
            DispatchQueue.main.async { completion(false) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            DispatchQueue.main.async {
                completion((resp as? HTTPURLResponse)?.statusCode == 200)
            }
        }.resume()
    }

    // MARK: - 自定义表盘（配置在手机端编辑，手表端只负责渲染）

    func fetchFaceConfig(completion: @escaping ([String: Any]?) -> Void) {
        getJSON("/customface") { j in completion(j?["config"] as? [String: Any]) }
    }

    func pushFaceConfig(_ cfg: [String: Any], completion: @escaping (Bool) -> Void) {
        postJSON("/customface", body: ["config": cfg]) { j in
            completion(j?["ok"] as? Bool ?? false)
        }
    }

    // MARK: - 运动记录

    func fetchSportRecords(limit: Int = 20, since: Int64 = 0,
                           completion: @escaping ([String: Any]?) -> Void) {
        var path = "/sport/records?limit=\(limit)"
        if since > 0 { path += "&since=\(since)" }   // 有游标就只拉增量
        getJSON(path) { j in completion(j) }
    }

    func removeSportRecord(id: Double, completion: @escaping (Bool) -> Void) {
        postJSON("/sport/records", body: ["action": "remove", "id": id]) { j in
            completion(j?["ok"] as? Bool ?? false)
        }
    }

    // MARK: - 通知中心

    func fetchNotifications(limit: Int = 30, since: Int64 = 0,
                            completion: @escaping ([String: Any]?) -> Void) {
        var path = "/notifications?limit=\(limit)"
        if since > 0 { path += "&since=\(since)" }
        getJSON(path) { j in completion(j) }
    }

    func clearNotifications(completion: @escaping (Bool) -> Void) {
        postJSON("/notifications", body: ["action": "clear"]) { j in
            completion(j?["ok"] as? Bool ?? false)
        }
    }

    func sendNotification(app: String, title: String, body: String,
                          completion: @escaping (Bool) -> Void) {
        postJSON("/notify", body: ["app": app, "title": title, "body": body]) { j in
            completion(j?["ok"] as? Bool ?? false)
        }
    }

    // MARK: - 通用请求

    func getJSON(_ path: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + path) else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var out: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                out = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                self.remember(self.baseURL)
            } else {
                self.maybeRediscover()
            }
            DispatchQueue.main.async { completion(out) }
        }.resume()
    }

    func postJSON(_ path: String, body: [String: Any],
                  completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseURL + path) else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var out: [String: Any]?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                out = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                self.remember(self.baseURL)
            } else {
                self.maybeRediscover()
            }
            DispatchQueue.main.async { completion(out) }
        }.resume()
    }
}
