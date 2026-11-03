import Foundation

/// 闹钟下发队列
///
/// 手表息屏/离开 Wi-Fi 时 HTTP 会失败，以前是「点了没反应、设置直接丢」。
/// 这里把每次操作持久化进队列，连上后按顺序补发，保证手机上设的闹钟最终一定到手表。
final class AlarmOutbox: ObservableObject {
    static let shared = AlarmOutbox()

    private let key = "alarm_outbox_v1"
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

    /// 顺序补发：成功一条就删一条，失败就停，等下一轮
    func flush(completion: ((Bool) -> Void)? = nil) {
        guard let op = pending.first else {
            completion?(true)
            return
        }
        WatchClient.shared.postJSON("/alarms", body: op) { j in
            if let j = j, j["ok"] as? Bool == true {
                self.ack(completion)
            } else {
                // Wi-Fi 不通（手表息屏/不在同一网络）→ 走蓝牙兜底：
                // 手表端 BleServer 收到 {path, body} 会走与 HTTP 完全相同的路由
                BleSync.shared.send(json: ["path": "/alarms", "body": op]) { msg in
                    if msg.contains("成功") {
                        self.ack(completion)
                    } else {
                        completion?(false)
                    }
                }
            }
        }
    }

    /// 成功一条：出队并继续发下一条
    private func ack(_ completion: ((Bool) -> Void)?) {
        if !pending.isEmpty { pending.removeFirst() }
        save()
        flush(completion: completion)
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
