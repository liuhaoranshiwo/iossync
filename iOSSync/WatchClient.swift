import Foundation

/// 手表端 HTTP 客户端（与手表 iOSSync App 的 /sync 端点对接）
final class WatchClient {
    static let shared = WatchClient()
    static let defaultBase = "http://192.168.2.76:8787"

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
}
