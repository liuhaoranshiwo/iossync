import SwiftUI
import WebKit
import Combine

/// 身份验证 WebView：完成小米「登录保护」短信确认，拦截 ticket 回调换 serviceToken
struct MiVerifyView: View {
    let verifyUrl: String
    @Environment(\.presentationMode) var present
    @State private var status = "请输入收到的短信验证码完成验证"
    @State private var done = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text(status)
                    .font(.caption)
                    .foregroundColor(MiTheme.subText)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.06))
                VerifyWeb(url: verifyUrl) { ticket in
                    status = "验证成功，正在换取登录凭证…"
                    MiCloud.shared.exchangeTicket(ticket) { ok, msg in
                        DispatchQueue.main.async {
                            status = msg
                            if ok {
                                done = true
                                present.wrappedValue.dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("小米账号验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { present.wrappedValue.dismiss() }
                }
            }
        }
    }
}

struct VerifyWeb: UIViewRepresentable {
    let url: String
    let onTicket: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        if let u = URL(string: url) { wv.load(URLRequest(url: u)) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coord { Coord(onTicket: onTicket) }

    class Coord: NSObject, WKNavigationDelegate {
        let onTicket: (String) -> Void
        init(onTicket: @escaping (String) -> Void) { self.onTicket = onTicket }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url?.absoluteString ?? ""
            let host = action.request.url?.host ?? ""
            // 只在真正的 STS 回调域名上取票，避免掐断验证流程内部的 ticket 参数
            let isCallback = host.contains("sts.api.io.mi.com") || (url.contains("ticket=ST-"))
            if isCallback, let r = url.range(of: "ticket=") {
                let rest = String(url[r.upperBound...])
                let ticket = rest.split(separator: "&").first.map(String.init) ?? ""
                if !ticket.isEmpty {
                    decisionHandler(.cancel)
                    onTicket(ticket)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}
