import SwiftUI
import Combine

// MARK: - 主题（小米运动健康：浅色 + 橙色 #FF6900）

enum MiTheme {
    static let orange = Color(red: 1.0, green: 0.41, blue: 0.0)
    static let bg = Color(red: 0.968, green: 0.973, blue: 0.980)   // #F7F8FA
    static let card = Color.white
    static let text = Color(red: 0.13, green: 0.15, blue: 0.18)
    static let subText = Color.gray.opacity(0.55)

    static func cardStyle() -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.045), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}

/// 通用卡片容器
struct MiCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MiTheme.cardStyle())
    }
}

// MARK: - 会话（小米账号）

final class MiSession: ObservableObject {
    static let shared = MiSession()
    @Published var isLoggedIn = UserDefaults.standard.bool(forKey: "mi_logged_in")
    @Published var nickname = UserDefaults.standard.string(forKey: "mi_nick") ?? ""
    @Published var phone = UserDefaults.standard.string(forKey: "mi_phone") ?? ""

    func login(nick: String, phone: String) {
        nickname = nick.isEmpty ? "小米用户" + String(phone.suffix(4)) : nick
        self.phone = phone
        isLoggedIn = true
        let d = UserDefaults.standard
        d.set(true, forKey: "mi_logged_in")
        d.set(nickname, forKey: "mi_nick")
        d.set(phone, forKey: "mi_phone")
    }

    func logout() {
        isLoggedIn = false
        UserDefaults.standard.set(false, forKey: "mi_logged_in")
    }
}

// MARK: - 手表传感器轮询

final class MiSensorStore: ObservableObject {
    static let shared = MiSensorStore()
    @Published var hr = 0
    @Published var spo2 = 0.0
    @Published var temp = 0.0
    @Published var steps = 0
    @Published var online = false
    private var timer: Timer?

    func startPolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in self.refresh() }
    }

    func refresh() {
        WatchClient.shared.fetchSensors { d in
            guard let j = d else { self.online = false; return }
            self.online = true
            self.hr = j["heart_rate"] as? Int ?? 0
            self.spo2 = j["spo2"] as? Double ?? 0
            self.temp = j["body_temp"] as? Double ?? 0
            self.steps = j["steps_today"] as? Int ?? 0
        }
    }
}

// MARK: - 登录页（1:1 复刻小米账号登录）

struct MiLoginView: View {
    @ObservedObject var session = MiSession.shared
    @Environment(\.presentationMode) var present
    @State private var phone = ""
    @State private var password = ""
    @State private var agreed = false
    @State private var err = ""
    @State private var showSmsInfo = false
    @State private var showVerify = false
    @State private var verifyUrl = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 70)
            // 小米 logo 圈
            ZStack {
                Circle().fill(MiTheme.orange).frame(width: 72, height: 72)
                Text("MI").font(.system(size: 30, weight: .bold)).foregroundColor(.white)
            }
            Text("登录小米账号").font(.title2.bold()).padding(.top, 18)
            Text("同步健康数据到小米运动健康云").font(.caption).foregroundColor(MiTheme.subText).padding(.top, 4)

            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    Text("+86").foregroundColor(MiTheme.text).padding(.trailing, 8)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 18)
                    TextField("手机号码", text: $phone)
                        .keyboardType(.numberPad)
                        .padding(.leading, 8)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))

                SecureField("密码", text: $password)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))

                if !err.isEmpty {
                    Text(err).font(.caption).foregroundColor(.red)
                }

                Button {
                    doLogin()
                } label: {
                    Text("登录")
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 24).fill(MiTheme.orange))
                }
                .disabled(phone.count < 5 || password.isEmpty)

                Text("本地会话模式 · 小米云同步二期接入")
                    .font(.caption2).foregroundColor(MiTheme.subText)

                Button {
                    showSmsInfo = true
                } label: {
                    Text("短信验证码登录").font(.subheadline).foregroundColor(MiTheme.orange)
                }
                .alert("短信登录通道", isPresented: $showSmsInfo) {
                    Button("知道了", role: .cancel) {}
                } message: {
                    Text("短信验证码登录需要小米云验证服务，将在小米云接入后开放。当前请使用密码登录（本地会话模式，设备功能不受影响）。")
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)

            Spacer()

            Button { agreed.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(agreed ? MiTheme.orange : .gray)
                    Text("已阅读并同意 小米账号协议 和 隐私政策")
                        .font(.caption2).foregroundColor(MiTheme.subText)
                }
            }
            .padding(.bottom, 24)

            Button { present.wrappedValue.dismiss() } label: {
                Text("先逛逛 >").font(.caption).foregroundColor(.gray).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MiTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showVerify) { MiVerifyView(verifyUrl: verifyUrl) }
    }

    private func doLogin() {
        guard agreed else { err = "请先勾选同意协议"; return }
        guard phone.count >= 5 else { err = "请输入正确的手机号"; return }
        err = "登录中…"
        MiCloud.shared.login(user: phone, password: password) { msg in
            DispatchQueue.main.async {
                if msg.hasPrefix("VERIFY|") {
                    self.verifyUrl = String(msg.dropFirst(7))
                    self.showVerify = true
                    self.err = "需要身份验证：请完成短信确认"
                    return
                }
                self.err = msg
                if MiCloud.shared.isLoggedIn {
                    // 会话状态变更会自动关闭登录页（根视图 onChange）
                    self.session.login(nick: "", phone: phone)
                }
            }
        }
    }
}
