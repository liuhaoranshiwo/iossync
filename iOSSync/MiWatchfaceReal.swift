import SwiftUI

/// 本机表盘（来自手表系统真实枚举，42 个 Xiaomi 原生表盘）
/// 关键事实：Watch 2 Pro 是 Wear OS 设备，小米官网明确「内置 30+ 表盘，更多表盘从 Google 下载」，
/// 它的表盘体系不经过小米在线商店（那是 Watch S 系列/手环的路径）。
final class MiWatchfaceStore: ObservableObject {
    struct Face: Identifiable {
        let id: Int          // 序号（1..42）
        let name: String
        let pkg: String
        let active: Bool
    }

    static let shared = MiWatchfaceStore()
    @Published var faces: [Face] = []
    @Published var loading = false
    @Published var err = ""
    @Published var activeName = ""

    func load() {
        loading = true; err = ""
        WatchClient.shared.fetchWatchfaces { j in
            self.loading = false
            guard let j = j, j["ok"] as? Bool == true else {
                self.err = "读取失败：手表未连接（检查同一 Wi-Fi）"
                return
            }
            let list = j["list"] as? [[String: Any]] ?? []
            self.faces = list.compactMap { o in
                guard let idx = o["index"] as? Int else { return nil }
                return Face(id: idx,
                            name: o["label"] as? String ?? "表盘 \(idx)",
                            pkg: o["pkg"] as? String ?? "",
                            active: o["active"] as? Bool ?? false)
            }
            self.activeName = self.faces.first(where: { $0.active })?.name ?? ""
        }
    }

    /// 打开系统表盘选择器（带真实预览，官方机制）
    func openChooser(_ done: @escaping (Bool) -> Void) {
        WatchClient.shared.openWatchfaceChooser { ok in done(ok) }
    }

    /// 指定表盘（系统选择器定位到该表盘）
    func apply(_ face: Face, done: @escaping (Bool) -> Void) {
        WatchClient.shared.applyWatchface(pkg: face.pkg, index: face.id) { ok in done(ok) }
    }
}

struct MiWatchfaceRealView: View {
    @ObservedObject var store = MiWatchfaceStore.shared
    @State private var toast = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // 当前表盘 + 系统选择器
                MiCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("当前表盘")
                                    .font(.caption).foregroundColor(MiTheme.subText)
                                Text(store.activeName.isEmpty ? "读取中…" : store.activeName)
                                    .font(.headline).foregroundColor(MiTheme.text)
                            }
                            Spacer()
                            Text("共 \(store.faces.count) 个")
                                .font(.caption2).foregroundColor(MiTheme.subText)
                        }
                        Button {
                            store.openChooser { ok in
                                toast = ok ? "已在手表上打开表盘选择器，转表冠挑选" : "打开失败：手表未连接"
                            }
                        } label: {
                            Text("在手表上打开表盘选择器")
                                .font(.subheadline.bold()).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 24).fill(MiTheme.orange))
                        }
                        Text("表盘预览由手表系统渲染，选择器中可逐一看图切换（这是这台 Wear OS 手表的官方表盘机制；小米在线商店仅服务 Watch S 系列/手环，本机不适用）")
                            .font(.system(size: 9)).foregroundColor(MiTheme.subText)
                    }
                }

                // 本机表盘清单
                MiCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("手表内置表盘").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                            Spacer()
                            Button("重新读取") { store.load() }.font(.caption).foregroundColor(MiTheme.orange)
                        }
                        if store.loading {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                        } else if store.faces.isEmpty {
                            Text(store.err.isEmpty ? "暂无表盘" : store.err)
                                .font(.caption2).foregroundColor(MiTheme.subText)
                        } else {
                            ForEach(store.faces) { f in
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", f.id))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(MiTheme.subText).frame(width: 22)
                                    Text(f.name).font(.caption).foregroundColor(MiTheme.text)
                                    if f.active {
                                        Text("使用中")
                                            .font(.system(size: 9)).foregroundColor(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(MiTheme.orange))
                                    }
                                    Spacer()
                                    Button {
                                        store.apply(f) { ok in
                                            toast = ok ? "已定位「\(f.name)」，在手表上确认即可" : "切换失败"
                                        }
                                    } label: {
                                        Text("切换").font(.caption2).foregroundColor(MiTheme.orange)
                                    }
                                }
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }

                if !toast.isEmpty {
                    Text(toast).font(.caption2).foregroundColor(MiTheme.subText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).padding(.bottom, 60)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("表盘")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.load() }
    }
}
