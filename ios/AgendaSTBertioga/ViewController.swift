import UIKit
import WebKit

final class ViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var nativeBridge: NativeSecurityBridge!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        let bootstrap = WKUserScript(
            source: Self.nativeBootstrap,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(bootstrap)
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        nativeBridge = NativeSecurityBridge(webView: webView)
        controller.add(nativeBridge, name: "AgendaSTNativeSecurity")

        var components = URLComponents(string: "https://agenda-externa-st.web.app/")!
        components.queryItems = [
            URLQueryItem(name: "native", value: "ios"),
            URLQueryItem(name: "build", value: "ios-1.0.0")
        ]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }

    // AGENDA_ST_DEBUG_LOGIN_DIDFINISH_V135
    private let agendaSTProbeV136 = "AGENDA_ST_BINARY_PROBE_V136_VIEWCONTROLLER"
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if DEBUG
        guard ProcessInfo.processInfo.environment["AGENDA_ST_UI_TEST"] == "1" else { return }
        print("AGENDA_ST_V135_DIDFINISH:", webView.url?.absoluteString ?? "sem-url")
        AgendaSTDebugWebLogin.run(on: webView)
#endif
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "AgendaSTNativeSecurity")
    }

    private static let nativeBootstrap = #"""
    (function(){
      if (window.AgendaSTNativeSecurity && window.AgendaSTNativeSecurity.platform === 'ios-native') return;
      const pending = {};
      window.__agendaSTIOSPending = pending;
      window.__agendaSTNativeReceive = function(result){
        try {
          if (typeof result === 'string') result = JSON.parse(result);
          const id = result && result.requestId;
          if (!id || !pending[id]) return;
          const entry = pending[id];
          delete pending[id];
          if (result.ok === true) entry.resolve(result);
          else entry.reject(result);
        } catch(e) { console.error('AgendaST iOS bridge:', e); }
      };
      window.AgendaSTNativeSecurity = {
        platform: 'ios-native',
        verifyPresence: function(payload){
          return new Promise(function(resolve,reject){
            const id='ios-'+Date.now()+'-'+Math.random().toString(16).slice(2);
            pending[id]={resolve:resolve,reject:reject};
            window.webkit.messageHandlers.AgendaSTNativeSecurity.postMessage({requestId:id,payload:payload||{}});
          });
        },
        deviceId: function(){ return 'ios-native-device'; }
      };
    })();
    """#
}
