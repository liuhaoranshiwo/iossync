import SwiftUI

/// 官方表盘商店客户端（watch-appstore.iot.mi.com，匿名可读）
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

    private let host = "https://watch-appstore.iot.mi.com"

    func load() {
        guard tabs.isEmpty, !loading else { return }
        loading = true
        let urlStr = host + "/api/watchface/prize/tabs?locale=zh_CN"
        guard let url = URL(string: urlStr) else { loading = false; return }
        URLSession.shared.dataTask(with: url) { data, _, e in
            DispatchQueue.main.async {
                self.loading = false
                guard let d = data,
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let arr = j["data"] as? [[String: Any]] else {
                    self.err = "表盘接口无数据：\(e?.localizedDescription ?? "解析失败")"
                    return
                }
                self.tabs = arr.compactMap { t in
                    guard let tid = t["tab_id"] as? Int else { return nil }
                    let name = t["tab_name"] as? String ?? "推荐"
                    let items = t["list"] as? [[String: Any]] ?? []
                    let faces: [Face] = items.compactMap { it in
                        guard let fid = it["id"] as? String,
                              let ic = it["icon"] as? String else { return nil }
                        return Face(id: fid, name: it["display_name"] as? String ?? fid, icon: ic)
                    }
                    return Tab(id: tid, name: name, faces: faces)
                }
            }
        }.resume()
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
        .onAppear { store.load() }
    }
}
