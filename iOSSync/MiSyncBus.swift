import Foundation
import SwiftUI

/// 自动同步总线
///
/// 之前每个页面只在 `.onAppear` 拉一次——链路恢复、手表上线、切回前台都不会刷新，
/// 用户只能一直点「同步」。这里把"什么时候该刷新"统一起来：
///
///  1. 链路从断开/未知 → 正常（看门狗判定或发现成功）时立刻广播一次
///  2. App 回到前台时立刻广播
///  3. 前台且链路正常时，每 30 秒广播一次
///
/// 页面只需要 `.onReceive(...) { load() }`，不需要各自实现轮询。
extension Notification.Name {
    /// 链路刚恢复（含首次连通）
    static let miLinkUp = Notification.Name("mi.link.up")
    /// 周期性静默刷新
    static let miSyncTick = Notification.Name("mi.sync.tick")
}

final class MiSyncBus {
    static let shared = MiSyncBus()

    /// 前台周期刷新间隔。手表端是本地服务，30 秒足够新，又不至于耗电。
    private let period: TimeInterval = 30
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: period, repeats: true) { _ in
            // 链路不通就不打扰，避免每次失败都刷一堆错误提示
            guard MiLinkWatchdog.shared.state == .healthy || !WatchClient.shared.baseURL.isEmpty else { return }
            NotificationCenter.default.post(name: .miSyncTick, object: nil)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 立刻同步一次（链路恢复 / 回到前台时调用）
    func syncNow(reason: String) {
        NotificationCenter.default.post(name: .miSyncTick, object: nil)
        if reason == "link-up" {
            NotificationCenter.default.post(name: .miLinkUp, object: nil)
        }
    }
}
