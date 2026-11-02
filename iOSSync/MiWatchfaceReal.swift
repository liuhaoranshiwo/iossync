import SwiftUI

/// 官方表盘商店客户端（watch-appstore.iot.mi.com）
/// 官方接口签名（反编译 g83.java）：GET /api/watchface/prize/tabs?model=&page=&size=&firmware_version=
/// 注意：不能带 locale 参数（会命中国际版 fantasy 目录，与本机无关）
final class MiWatchfaceStore: ObservableObject {
    struct Face: Identifiable {
        let id: String
        let name: String
        let icon: String
    }
    struct Tab: Identifiable {
        let id: Int
        let name: String
        var faces: [Face]
    }

    static let shared = MiWatchfaceStore()
    @Published var tabs: [Tab] = []
    @Published var loading = false
    @Published var err = ""
    /// 诊断信息：显示当前使用的 model 与回退过程
    @Published var diag = ""

    private let host = "https://watch-appstore.iot.mi.com"

    private func parseTabs(_ d: Data) -> [Tab] {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = j["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { t in
            guard let tid = (t["tab_id"] as? Int) ?? Int(t["tab_id"] as? String ?? "") else { return nil }
            let name = t["tab_name"] as? String ?? "推荐"
            let items = t["list"] as? [[String: Any]] ?? []
            let faces: [Face] = items.compactMap { it in
                guard let fid = (it["id"] as? String) ?? (it["id_v2"] as? String),
                      let ic = it["icon"] as? String else { return nil }
                return Face(id: fid, name: it["display_name"] as? String ?? fid, icon: ic)
            }
            return Tab(id: tid, name: name, faces: faces)
        }
    }

    private func fetch(_ query: String, done: @escaping ([Tab]) -> Void) {
        guard let url = URL(string: host + "/api/watchface/prize/tabs?" + query) else { done([]); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                done(data.map { self.parseTabs($0) } ?? [])
            }
        }.resume()
    }

    /// 依次尝试：绑定设备型号 → 官方无 model 目录 → 直接失败
    func load() {
        guard !loading else { return }
        loading = true
        err = ""
        let model = UserDefaults.standard.string(forKey: "mi_device_model") ?? ""
        let devName = UserDefaults.standard.string(forKey: "mi_device_name") ?? ""
        let raw = UserDefaults.standard.string(forKey: "mi_bound_raw") ?? ""
        var attempts: [(String, String)] = []
        if !model.isEmpty {
            attempts.append(("本机型号 " + model,
                             "model=\(model)&page=0&size=30"))
        }
        attempts.append(("官方默认目录", "page=0&size=30"))
        self.diag = "缓存型号[\(model)] 设备[\(devName)] 绑定返回[\(String(raw.prefix(160)))]"

        func tryNext(_ i: Int) {
            guard i < attempts.count else {
                self.loading = false
                self.err = "表盘接口无数据"
                return
            }
            let (label, q) = attempts[i]
            fetch(q) { tabs in
                if !tabs.isEmpty && tabs.contains(where: { !$0.faces.isEmpty }) {
                    self.tabs = tabs
                    self.loading = false
                    self.diag = (i == 0 ? "✓ " : "⚠ 回退 ") + label
                } else {
                    tryNext(i + 1)
                }
            }
        }
        tryNext(0)
    }
}

/// 真实表盘市场页
struct MiWatchfaceRealView: View {
    @ObservedObject var store = MiWatchfaceStore.shared
    @State private var sel = 0

    private var current: MiWatchfaceStore.Tab? {
        store.tabs.indices.contains(sel) ? store.tabs[sel] : store.tabs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.diag.isEmpty {
                Text(store.diag)
                    .font(.system(size: 9)).foregroundColor(MiTheme.subText)
                    .lineLimit(2).padding(.horizontal, 12).padding(.top, 4)
            }
            if !store.tabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(store.tabs.enumerated()), id: \.element.id) { idx, t in
                            Text(t.name)
                                .font(.caption)
                                .foregroundColor(sel == idx ? .white : MiTheme.text)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(sel == idx ? MiTheme.orange : Color.gray.opacity(0.1)))
                                .onTapGesture { sel = idx }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            if store.loading {
                Spacer(); ProgressView("加载官方表盘…"); Spacer()
            } else if let tab = current, !tab.faces.isEmpty {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(tab.faces) { f in
                            VStack(spacing: 8) {
                                AsyncImage(url: URL(string: f.icon)) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 20).fill(Color.gray.opacity(0.15))
                                            .overlay(Image(systemName: "square.grid.2x2").foregroundColor(.gray))
                                    }
                                }
                                .frame(width: 96, height: 116)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                                Text(f.name).font(.caption).foregroundColor(MiTheme.text).lineLimit(1)
                                Text(f.id).font(.system(size: 8)).foregroundColor(MiTheme.subText).lineLimit(1)
                            }
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(MiTheme.cardStyle())
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 90)
                }
            } else {
                VStack(spacing: 8) {
                    Text(store.err.isEmpty ? "暂无表盘" : store.err)
                        .font(.caption).foregroundColor(MiTheme.subText)
                    Button("重新加载") { store.tabs = []; store.load() }
                        .font(.caption.bold()).foregroundColor(MiTheme.orange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("表盘市场")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if UserDefaults.standard.string(forKey: "mi_device_model")?.isEmpty != false {
                MiHealth.shared.fetchBoundDevices { _ in }
            }
            store.load()
        }
    }
}
