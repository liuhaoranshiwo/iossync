import Foundation

/// 手表自动发现（Bonjour / mDNS）
///
/// 路由器每天给手表换 IP，写死地址必然失效。手表端用 NsdManager 注册了
/// `_iossync._tcp`，这里用 NetServiceBrowser 找到它，把 baseURL 自动切成
/// `http://<name>.local:8787`，从此不用手改 IP。
final class WatchDiscovery: NSObject, ObservableObject {
    static let shared = WatchDiscovery()

    @Published private(set) var status = "未搜索"
    @Published private(set) var searching = false
    @Published private(set) var found: String = ""

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var finished = false

    /// 开始搜索；超时后给出结论，不无限转圈
    func start(timeout: TimeInterval = 6) {
        stop()
        finished = false
        searching = true
        status = "搜索中…"
        let b = NetServiceBrowser()
        b.delegate = self
        browser = b
        b.searchForServices(ofType: "_iossync._tcp.", inDomain: "local.")

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, self.searching else { return }
            self.searching = false
            if self.found.isEmpty {
                self.status = "未发现手表（确认手表与手机在同一 Wi-Fi，且手表 App 在运行）"
            }
        }
    }

    func stop() {
        browser?.stop()
        browser = nil
        services.forEach { $0.stop() }
        services.removeAll()
        searching = false
    }

    /// 拿不到地址时回退到上次成功过的地址，避免一次发现失败就完全不可用
    func fallbackToCached() {
        let cached = UserDefaults.standard.string(forKey: "watch_base_last_ok") ?? ""
        if !cached.isEmpty {
            WatchClient.shared.baseURL = cached
            status = "发现失败，已回退到上次地址 \(cached)"
        }
    }
}

extension WatchDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 === service }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        searching = false
        status = "搜索失败：本地网络权限未开？"
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender.port > 0 else { return }
        // 优先用解析出来的 IPv4 地址。
        // 用 hostName（形如 iOSync.local）时 URLSession 会报
        // "A server with the specified hostname could not be found" —— iOS 的
        // mDNS 解析在 App 内并不可靠，IP 直连才是稳的。
        let host: String
        if let ip = Self.ipv4(of: sender) {
            host = ip
        } else if let hostRaw = sender.hostName {
            host = hostRaw.hasSuffix(".") ? String(hostRaw.dropLast()) : hostRaw
        } else {
            return
        }
        found = "\(host):\(sender.port)"
        searching = false
        finished = true
        status = "已发现手表 \(found)"

        // 用户手动填过的地址优先，否则自动切换
        if !WatchClient.shared.manualOverride {
            WatchClient.shared.baseURL = "http://\(found)"
        }
        stop()
    }

    /// 从 NetService 的地址列表里取第一个 IPv4
    static func ipv4(of service: NetService) -> String? {
        guard let addrs = service.addresses else { return nil }
        for data in addrs {
            var ip: String?
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress else { return }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return }
                let sin = base.assumingMemoryBound(to: sockaddr_in.self)
                var addr = sin.pointee.sin_addr
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    ip = String(cString: buf)
                }
            }
            if let ip = ip, !ip.isEmpty, ip != "0.0.0.0" { return ip }
        }
        return nil
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        status = "解析失败，继续尝试…"
    }
}
