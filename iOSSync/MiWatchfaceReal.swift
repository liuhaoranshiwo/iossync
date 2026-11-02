import SwiftUI

/// 本机表盘：直接读取手表上真实已安装的 Wear OS 表盘
/// —— 名字来自各表盘服务 label，预览图来自服务 metaData 里的官方 preview 资源
/// （由手表端 createPackageContext 从 MiWatchFace.apk 资源里解出，base64 传上来）。
/// 事实依据：Watch 2 Pro 是 Wear OS 设备，内置 35 个小米原生表盘，
/// 小米在线表盘商店只服务 Watch S 系列/手环，本机不适用（固件里也没有 /product/dwf）。
final class MiWatchfaceStore: ObservableObject {
    struct Face: Identifiable {
        let id: Int
        let name: String
        let pkg: String
        let svc: String
        let active: Bool
        let preview: UIImage?
    }

    static let shared = MiWatchfaceStore()
    @Published var faces: [Face] = []
    @Published var loading = false
    @Published var err = ""
    @Published var busy = false

    var activeFace: Face? { faces.first(where: { $0.active }) }

    func load() {
        loading = true
        err = ""
        WatchClient.shared.fetchWatchfaces { j in
            self.loading = false
            guard let j = j, j["ok"] as? Bool == true else {
                self.err = "读取失败：手表未连接（确认手机与手表同一 Wi-Fi，手表端 App 已打开）"
                return
            }
            let list = j["list"] as? [[String: Any]] ?? []
            self.faces = list.compactMap { o in
                guard let idx = o["index"] as? Int else { return nil }
                var img: UIImage? = nil
                if let b64 = o["preview"] as? String, !b64.isEmpty,
                   let data = Data(base64Encoded: b64) {
                    img = UIImage(data: data)
                }
                return Face(id: idx,
                            name: o["label"] as? String ?? "表盘 \(idx)",
                            pkg: o["pkg"] as? String ?? "",
                            svc: o["svc"] as? String ?? "",
                            active: o["active"] as? Bool ?? false,
                            preview: img)
            }
            // 使用中的排最前
            self.faces.sort { a, b in
                if a.active != b.active { return a.active }
                return a.id < b.id
            }
        }
    }

    /// 打开系统表盘选择器（官方机制，带实时渲染预览）
    func openChooser(_ done: @escaping (Bool) -> Void) {
        WatchClient.shared.openWatchfaceChooser { ok in done(ok) }
    }

    /// 切到指定表盘
    func apply(_ face: Face, done: @escaping (Bool, String) -> Void) {
        busy = true
        WatchClient.shared.applyWatchface(pkg: face.pkg, index: face.id) { ok in
            self.busy = false
            done(ok, face.name)
        }
    }
}

struct MiWatchfaceRealView: View {
    @ObservedObject var store = MiWatchfaceStore.shared
    @State private var toast = ""
    @State private var toastOK = true

    private let cols = [GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                heroCard

                MiCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("手表内置表盘").font(.subheadline.weight(.semibold))
                                .foregroundColor(MiTheme.text)
                            Text("\(store.faces.count)").font(.caption2)
                                .foregroundColor(MiTheme.subText)
                            Spacer()
                            if store.loading {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Button("重新读取") { store.load() }
                                    .font(.caption).foregroundColor(MiTheme.orange)
                            }
                        }

                        if store.faces.isEmpty && !store.loading {
                            Text(store.err.isEmpty ? "暂无表盘" : store.err)
                                .font(.caption2).foregroundColor(MiTheme.subText)
                                .padding(.vertical, 12)
                        } else {
                            LazyVGrid(columns: cols, spacing: 14) {
                                ForEach(store.faces) { f in
                                    faceCell(f)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                MiCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("关于表盘来源").font(.subheadline.weight(.semibold))
                            .foregroundColor(MiTheme.text)
                        Text("这 \(store.faces.count) 个表盘是手表系统里真实安装的（MiWatchFace.apk），预览图直接从各表盘服务的官方 preview 资源读取，不是网图也不是模拟图。Watch 2 Pro 是 Wear OS 设备，小米在线表盘商店只服务 Watch S 系列/手环，所以这里不接商店，接的是本机真实表盘。")
                            .font(.system(size: 10)).foregroundColor(MiTheme.subText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !toast.isEmpty {
                    Text(toast)
                        .font(.caption2)
                        .foregroundColor(toastOK ? MiTheme.subText : Color.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).padding(.bottom, 60)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("表盘")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if store.faces.isEmpty { store.load() } }
    }

    // MARK: - 当前表盘

    private var heroCard: some View {
        MiCard {
            VStack(spacing: 12) {
                if let a = store.activeFace {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.25)).frame(width: 168, height: 168)
                        if let img = a.preview {
                            Image(uiImage: img)
                                .resizable().scaledToFit()
                                .frame(width: 164, height: 164)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "applewatch")
                                .font(.system(size: 46)).foregroundColor(MiTheme.subText)
                        }
                    }
                    VStack(spacing: 4) {
                        Text("当前表盘").font(.caption).foregroundColor(MiTheme.subText)
                        Text(a.name).font(.title3.bold()).foregroundColor(MiTheme.text)
                    }
                } else {
                    Text(store.loading ? "读取中…" : "未读到表盘")
                        .font(.subheadline).foregroundColor(MiTheme.subText)
                        .padding(.vertical, 30)
                }

                Button {
                    store.openChooser { ok in
                        toastOK = ok
                        toast = ok ? "已在手表上打开表盘选择器，转表冠挑选" : "打开失败：手表未连接"
                    }
                } label: {
                    Text("在手表上打开表盘选择器")
                        .font(.subheadline.bold()).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 24).fill(MiTheme.orange))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 单个表盘

    private func faceCell(_ f: MiWatchfaceStore.Face) -> some View {
        Button {
            guard !f.active else {
                toastOK = true; toast = "「\(f.name)」正在使用中"
                return
            }
            store.apply(f) { ok, name in
                toastOK = ok
                toast = ok
                    ? "已发送切换指令「\(name)」，在手表上点确认即生效"
                    : "切换失败：手表未连接"
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.2)).frame(width: 84, height: 84)
                    if let img = f.preview {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 26)).foregroundColor(MiTheme.subText)
                    }
                    if f.active {
                        Circle().stroke(MiTheme.orange, lineWidth: 2.5)
                            .frame(width: 84, height: 84)
                    }
                }
                Text(f.name)
                    .font(.system(size: 10))
                    .foregroundColor(f.active ? MiTheme.orange : MiTheme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if f.active {
                    Text("使用中").font(.system(size: 8)).foregroundColor(MiTheme.orange)
                } else {
                    Text(" ").font(.system(size: 8))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
