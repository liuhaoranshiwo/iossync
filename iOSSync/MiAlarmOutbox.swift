import Foundation

/// 下发队列（闹钟等写操作）
///
/// 手表 IP 会变、会息屏、会离开 Wi-Fi，任何一次 HTTP 失败都不该让用户的设置丢失。
/// 策略：先落盘入队 → 立刻尝试发送（多条合并成一次 /batch，一条连接发完）→
/// 失败的留队、每 12 秒重试；Wi-Fi 不通时改走蓝牙（手表端 BLE 复用同一套 HTTP 路由）。
final class AlarmOutbox: ObservableObject {
    static let shared = AlarmOutbox()

    private let key = "alarm_outbox_v1"
    private let batchSize = 5
    @Published private(set) var pending: [[String: Any]] = []
    private var timer: Timer?

    init() {
        pending = (UserDefaults.standard.array(forKey: key) as? [[String: Any]]) ?? []
    }

    private func save() {
        UserDefaults.standard.set(pending, forKey: key)
    }

    var count: Int { pending.count }

    /// 入队并立刻尝试发送
    func submit(_ op: [String: Any], completion: @escaping (Bool) -> Void) {
        pending.append(op)
        save()
        flush { ok in completion(ok) }
    }

    /// 顺序补发；多条合并成一次 /batch 请求
    func flush(completion: ((Bool) -> Void)? = nil) {
        guard !pending.isEmpty else {
            completion?(true)
            return
        }
        if pending.count > 1 {
            let batch = Array(pending.prefix(batchSize))
            let reqs: [[String: Any]] = batch.map { op in
                ["path": "/alarms", "body": op]
            }
            WatchClient.shared.postJSON("/batch", body: ["requests": reqs]) { j in
                if let j = j, j["ok"] as? Bool == true {
                    self.dropPrefix(batch.count)
                    self.flush(completion: completion)
                } else {
                    // 批量失败就退回逐条（旧版手表没有 /batch）
                    self.flushSingle(completion)
                }
            }
            return
        }
        flushSingle(completion)
    }

    private func flushSingle(_ completion: ((Bool) -> Void)?) {
        guard let op = pending.first else {
            completion?(true)
            return
        }
        WatchClient.shared.postJSON("/alarms", body: op) { j in
            if let j = j, j["ok"] as? Bool == true {
                self.dropPrefix(1)
                self.flush(completion: completion)
                return
            }
            // Wi-Fi 不通 → 蓝牙兜底：手表端 BleServer 收到 {path, body} 走同一套路由
            BleSync.shared.send(json: ["path": "/alarms", "body": op]) { msg in
                if msg.contains("成功") {
                    self.dropPrefix(1)
                    self.flush(completion: completion)
                } else {
                    completion?(false)
                }
            }
        }
    }

    private func dropPrefix(_ n: Int) {
        pending.removeFirst(min(n, pending.count))
        save()
    }

    /// 页面前台时每 12 秒重试一次
    func startAutoFlush() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    func stopAutoFlush() {
        timer?.invalidate()
        timer = nil
    }
}
