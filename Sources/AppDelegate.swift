import UIKit
import WebKit
import UserNotifications

// MARK: - 应用入口

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .all
    }
}

// MARK: - 主界面：WKWebView 承载线上应用

final class MainViewController: UIViewController {

    // 线上应用地址（含网关分享码）。首次访问后网页端会自动剥离 sharecode，
    // 之后由会话 cookie + 应用口令维持访问。
    private let appURLString = "https://todo-attendance.app.workbuddy.host/?sharecode=GKDGWPCAGF"

    private var webView: WKWebView!
    private let messageHandlerName = "todoNative"

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupNotificationCenter()
        loadApp()
    }

    // MARK: WKWebView 配置

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // 使用持久化数据存储：会话 cookie 得以保留，用户不必每次启动都重输口令。
        // 安全性说明：API 响应均带 Cache-Control: no-store，业务数据不会进 Web 缓存；
        // 本地只保留一个 HttpOnly 的会话 token，可通过网页内的「退出」清除。
        config.websiteDataStore = .default()

        let controller = WKUserContentController()
        controller.add(self, name: messageHandlerName)
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func loadApp() {
        guard let url = URL(string: appURLString) else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        webView.load(request)
    }

    // MARK: 原生通知

    private func setupNotificationCenter() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self.callJS("window.__nativeNotifyEnabled && window.__nativeNotifyEnabled(true)")
                }
            }
        }
    }

    private func callJS(_ code: String) {
        webView?.evaluateJavaScript(code) { _, _ in }
    }

    /// 把 JS 传来的提醒请求转成系统通知
    private func scheduleNativeReminder(id: String, title: String, body: String, delaySeconds: Double) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "待办提醒" : title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delaySeconds), repeats: false)
        let request = UNNotificationRequest(identifier: "todo_\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func cancelNativeReminder(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["todo_\(id)"])
    }
}

// MARK: - JS 桥接

extension MainViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let action = body["action"] as? String ?? ""

        switch action {
        case "notify":
            guard let id = body["id"] as? String else { return }
            let title = body["title"] as? String ?? ""
            let msg = body["body"] as? String ?? ""
            let delay = body["delay"] as? Double ?? 0
            scheduleNativeReminder(id: id, title: title, body: msg, delaySeconds: delay)
        case "cancelNotify":
            if let id = body["id"] as? String { cancelNativeReminder(id: id) }
        case "notifyPermission":
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let ok = settings.authorizationStatus == .authorized
                DispatchQueue.main.async {
                    // 注意：Swift 的 Bool 插值会输出 true/false，不能在插值里再写嵌套字符串字面量
                    self.callJS("window.__nativeNotifyPermission && window.__nativeNotifyPermission(\(ok))")
                }
            }
        default:
            break
        }
    }
}

// MARK: - 导航与权限

extension MainViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        // 只允许在应用域名内导航；外部链接交给系统浏览器
        if url.host == "todo-attendance.app.workbuddy.host" {
            decisionHandler(.allow)
        } else if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}

extension MainViewController: WKUIDelegate {
    // 相机权限：让网页内的 getUserMedia 能拿到授权（拍照识别用）
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}

// MARK: - 通知展示

extension MainViewController: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async {
                self.callJS("window.scrollTo(0,0)")
            }
        }
        completionHandler()
    }
}
