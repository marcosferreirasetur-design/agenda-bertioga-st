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
    // AGENDA_ST_LOGIN_INLINE_V136
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["AGENDA_ST_UI_TEST"] == "1",
              let email = env["AGENDA_ST_TEST_EMAIL"], !email.isEmpty,
              let password = env["AGENDA_ST_TEST_PASSWORD"], !password.isEmpty else { return }
        print("AGENDA_ST_V136_DIDFINISH:", webView.url?.absoluteString ?? "sem-url")
        func jsLiteral(_ value: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: [value])
            let array = String(data: data, encoding: .utf8)!
            return String(array.dropFirst().dropLast())
        }
        let javascript = """
        (function(){
          const email=\(jsLiteral(email)), password=\(jsLiteral(password));
          const inputs=Array.from(document.querySelectorAll("input"));
          const em=document.querySelector("input[type=email]") || inputs.find(x=>/e-?mail/i.test((x.placeholder||"")+" "+(x.name||"")+" "+(x.id||"")));
          const pw=document.querySelector("input[type=password]") || inputs.find(x=>/senha|password/i.test((x.placeholder||"")+" "+(x.name||"")+" "+(x.id||"")));
          function put(el,v){if(!el)return false;const proto=Object.getPrototypeOf(el),d=Object.getOwnPropertyDescriptor(proto,"value");if(d&&d.set)d.set.call(el,v);else el.value=v;el.dispatchEvent(new Event("input",{bubbles:true}));el.dispatchEvent(new Event("change",{bubbles:true}));return true;}
          const a=put(em,email), b=put(pw,password);
          const btn=Array.from(document.querySelectorAll("button,input[type=submit]")).find(x=>/entrar/i.test((x.innerText||x.value||x.textContent||"").trim()));
          const r={href:location.href,emailFound:!!em,passwordFound:!!pw,emailSet:a,passwordSet:b,buttonFound:!!btn};
          if(a&&b&&btn){btn.click();r.action="clicked";} else if(a&&b&&pw&&pw.form){pw.form.requestSubmit?pw.form.requestSubmit():pw.form.submit();r.action="submitted";} else r.action="none";
          return JSON.stringify(r);
        })();
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            webView.evaluateJavaScript(javascript) { result, error in
                if let error = error { print("AGENDA_ST_V136_JS_ERROR:", error.localizedDescription) }
                else { print("AGENDA_ST_V136_JS_RESULT:", String(describing: result)) }
            }
        }
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
