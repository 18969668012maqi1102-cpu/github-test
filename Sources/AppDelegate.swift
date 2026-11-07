import UIKit
import WebKit
import UserNotifications

// MARK: - 应用入口

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // Info.plist 未声明 UIApplicationSceneManifest → 走旧的应用生命周期，
    // 必须自己创建 window 并设置 rootViewController，否则启动就是黑屏。
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = MainViewController()
        w.makeKeyAndVisible()
        window = w
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

    // 加载失败兜底（网络不通 / 域名解析失败等），避免白屏无从下手
    private var errorView: UIView?
    private var loadingView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupWebView()
        setupNotificationCenter()
        showLoading()
        loadApp()
    }

    // MARK: 加载状态提示

    private func showLoading() {
        let v = UIView(frame: view.bounds)
        v.backgroundColor = .white
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 260, height: 60))
        label.text = "正在加载…"
        label.textAlignment = .center
        label.textColor = UIColor(white: 0.45, alpha: 1)
        label.font = UIFont.systemFont(ofSize: 15)
        label.center = v.center
        v.addSubview(label)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(v)
        loadingView = v
    }

    private func hideLoading() {
        loadingView?.removeFromSuperview()
        loadingView = nil
    }

    private func showError(_ message: String) {
        hideLoading()
        errorView?.removeFromSuperview()

        let v = UIView(frame: view.bounds)
        v.backgroundColor = .white
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let icon = UILabel(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        icon.text = "⚠️"
        icon.font = UIFont.systemFont(ofSize: 32)
        icon.center = CGPoint(x: v.bounds.midX, y: v.bounds.midY - 70)
        v.addSubview(icon)

        let title = UILabel(frame: CGRect(x: 0, y: 0, width: 300, height: 30))
        title.text = "无法连接到服务器"
        title.textAlignment = .center
        title.textColor = UIColor(white: 0.15, alpha: 1)
        title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        title.center = CGPoint(x: v.bounds.midX, y: v.bounds.midY - 30)
        v.addSubview(title)

        let detail = UILabel(frame: CGRect(x: 0, y: 0, width: 300, height: 70))
        detail.text = message
        detail.textAlignment = .center
        detail.numberOfLines = 4
        detail.textColor = UIColor(white: 0.5, alpha: 1)
        detail.font = UIFont.systemFont(ofSize: 13)
        detail.center = CGPoint(x: v.bounds.midX, y: v.bounds.midY + 12)
        v.addSubview(detail)

        let retry = UIButton(type: .system)
        retry.setTitle("重新加载", for: .normal)
        retry.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        retry.backgroundColor = UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1)
        retry.setTitleColor(.white, for: .normal)
        retry.layer.cornerRadius = 9
        retry.frame = CGRect(x: 0, y: 0, width: 160, height: 44)
        retry.center = CGPoint(x: v.bounds.midX, y: v.bounds.midY + 75)
        retry.addTarget(self, action: #selector(retryLoad), for: .touchUpInside)
        v.addSubview(retry)

        view.addSubview(v)
        errorView = v
    }

    @objc private func retryLoad() {
        errorView?.removeFromSuperview()
        errorView = nil
        showLoading()
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
        // 在文档开始时注入桥接函数：页面刷新/导航后依然存在
        let bridge = WKUserScript(source: """
        window.__nativeScheduleReminders = function(items) {
          try {
            window.webkit.messageHandlers.todoNative.postMessage({action:'schedule', items: items});
          } catch (e) {}
        };
        window.__nativeNotifyEnabled = function(ok) { window.__nativeNotifyOK = !!ok; };
        window.__nativeNotifyPermission = function(ok) { window.__nativeNotifyPermOK = !!ok; };
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(bridge)
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
        guard let url = URL(string: appURLString) else {
            showError("应用地址无效")
            return
        }
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
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["todo_\(id)"])
    }

    /// 取消测试提醒：只清测试相关的通知，不动用户真实的待办提醒
    private func cancelTestReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }.filter { $0.hasPrefix("todo_test") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map { $0.identifier }.filter { $0.hasPrefix("todo_test") }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// 把未来的提醒排成本地系统通知。
    /// 本地通知由 iOS 调度，**不需要 App 在运行**，因此后台/关闭都能响。
    private func scheduleLocalReminders(items: [[String: Any]]) {
        let center = UNUserNotificationCenter.current()
        // 先清掉之前排的（用固定前缀标识本应用排的）
        center.getPendingNotificationRequests { pending in
            let mine = pending.map { $0.identifier }.filter { $0.hasPrefix("todo_rem_") }
            center.removePendingNotificationRequests(withIdentifiers: mine)

            for it in items {
                guard let id = it["id"] as? String,
                      let hour = it["hour"] as? Int,
                      let minute = it["minute"] as? Int else { continue }
                let title = (it["title"] as? String) ?? "待办提醒"
                let dateStr = (it["due"] as? String) ?? ""
                // 注意：repeat 是 Swift 保留关键字，不能用作变量名
                let repInfo = it["repeat"] as? [String: Any]
                let repType = (repInfo?["type"] as? String) ?? ""

                // 通知内容
                let content = UNMutableNotificationContent()
                content.title = "待办提醒 · \(title)"
                content.body = dateStr.isEmpty ? "" : "\(dateStr) \(String(format: "%02d:%02d", hour, minute))"
                content.sound = .default

                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute
                dateComponents.second = 0

                // 本项目约定 days: 1=周一 ... 7=周日
                // UNCalendarNotificationTrigger 的 weekday: 1=周日 ... 7=周六
                // 换算：un_weekday = (our_day % 7) + 1
                func unWeekday(_ our: Int) -> Int { return (our % 7) + 1 }

                var triggers: [UNCalendarNotificationTrigger] = []

                if repType == "daily" {
                    // 每天：只设时刻，不限定星期
                    triggers = [UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)]
                } else if repType == "workday" {
                    // 工作日：周一至周五各排一条
                    for d in 1...5 {
                        var c = dateComponents
                        c.weekday = unWeekday(d)
                        triggers.append(UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
                    }
                } else if repType == "weekly",
                          let days = repInfo?["days"] as? [Int], !days.isEmpty {
                    for d in days {
                        var c = dateComponents
                        c.weekday = unWeekday(d)
                        triggers.append(UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
                    }
                } else if repType == "monthly", let dom = repInfo?["day_of_month"] as? Int {
                    var c = dateComponents
                    c.day = dom
                    triggers = [UNCalendarNotificationTrigger(dateMatching: c, repeats: true)]
                } else if repType == "yearly" {
                    var c = dateComponents
                    c.month = 1
                    c.day = 1
                    triggers = [UNCalendarNotificationTrigger(dateMatching: c, repeats: true)]
                } else {
                    // 一次性：指定完整日期
                    let parts = dateStr.split(separator: "-").compactMap { Int($0) }
                    if parts.count == 3 {
                        dateComponents.year = parts[0]
                        dateComponents.month = parts[1]
                        dateComponents.day = parts[2]
                    }
                    triggers = [UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)]
                }

                var idx = 0
                for t in triggers {
                    let req = UNNotificationRequest(identifier: "todo_rem_\(id)_\(idx)",
                                                    content: content, trigger: t)
                    center.add(req) { _ in }
                    idx += 1
                }
            }
        }
    }
}

// MARK: - JS 桥接

extension MainViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let action = body["action"] as? String ?? ""

        switch action {
        case "schedule":
            // 网页把未来提醒一次性交给原生，由 iOS 排本地通知（App 不运行也能响）
            let items = body["items"] as? [[String: Any]] ?? []
            scheduleLocalReminders(items: items)
        case "openExternal":
            // 用系统浏览器打开（webcal:// 会唤起 iOS 的「添加到日历」流程）
            if let u = body["url"] as? String, let url = URL(string: u) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        case "notify":
            guard let id = body["id"] as? String else { return }
            let title = body["title"] as? String ?? ""
            let msg = body["body"] as? String ?? ""
            let delay = body["delay"] as? Double ?? 0
            scheduleNativeReminder(id: id, title: title, body: msg, delaySeconds: delay)
        case "cancelNotify":
            if let id = body["id"] as? String { cancelNativeReminder(id: id) }
        case "cancelTest":
            // 取消测试提醒：只清测试通知，保留用户真实待办的预排通知
            cancelTestReminders()
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
    // 加载完成 → 隐藏 loading
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLoading()
    }

    // 加载失败 → 显示可读的错误提示（而不是白屏）
    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        showError(Self.describe(error))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        showError(Self.describe(error))
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotFindHost:
                return "找不到服务器。请检查网络连接，或确认能访问 todo-attendance.app.workbuddy.host。"
            case NSURLErrorNotConnectedToInternet:
                return "设备没有网络连接。"
            case NSURLErrorTimedOut:
                return "连接超时，请检查网络后重试。"
            case NSURLErrorCannotConnectToHost:
                return "无法连接到服务器，请稍后重试。"
            default:
                break
            }
        }
        return ns.localizedDescription
    }

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
