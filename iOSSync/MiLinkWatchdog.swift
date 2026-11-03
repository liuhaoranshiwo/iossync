import Foundation
import SwiftUI

/// 链路看门狗（借鉴 watch-bridge 的 "self-healing link"）
///
/// 它们踩到的坑和我们一模一样：GATT/HTTP 链路会**静默死亡**——没有错误回调、
/// 没有断开事件，App 以为自己还连着，实际所有请求都在黑洞里。
/// watch-bridge 的做法是 180 秒 PING，连续两次没 PONG 就强制断开重连。
///
/// 这里是同一思路的 iOS 侧实现：
///  - 前台每 60 秒打一次 /ping
///  - 连续 2 次失败 → 判定链路僵尸，强制重新发现 + 清空连接态
///  - 任意一次成功 → 复位计数并记住该地址
final class MiLinkWatchdog: ObservableObject {
    static let shared = MiLinkWatchdog()

    enum State: String {
        case unknown, healthy, zombie

        var text: String {
            switch self {
            case .unknown: return "未检测"
            case .healthy: return "链路正常"
            case .zombie: return "链路失联"
            }
        }
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var lastSeen: Date?

    /// 60 秒一次；两个周期没响应才判定死亡（避免一次抖动就重连）
    private let interval: TimeInterval = 60
    private let maxMissed = 2
    private var missed = 0
    private var timer: Timer?
    private var checking = false

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()          // 立刻探一次，别等 60 秒
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !checking else { return }
        guard !WatchClient.shared.baseURL.isEmpty else {
            // 连地址都没有：直接重新发现
            state = .zombie
            WatchDiscovery.shared.start(timeout: 5)
            return
        }
        checking = true
        WatchClient.shared.ensureReachable { ok in
            self.checking = false
            if ok {
                let recovered = (self.state != .healthy)
                self.missed = 0
                self.state = .healthy
                self.lastSeen = Date()
                if recovered {
                    // 链路刚恢复：立刻让各页面拉一次，不用用户手动点
                    MiSyncBus.shared.syncNow(reason: "link-up")
                }
            } else {
                self.missed += 1
                if self.missed >= self.maxMissed {
                    self.state = .zombie
                    self.missed = 0
                    // 僵尸链路：地址失效或服务假死。重新发现 + 让队列稍后重试。
                    WatchDiscovery.shared.start(timeout: 5)
                }
            }
        }
    }
}
