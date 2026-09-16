import Foundation
import WebKit
#if DEBUG
// AGENDA_ST_DEBUG_JS_LOGIN_V132
enum AgendaSTDebugWebLogin {
 static func run(on webView: WKWebView) {
  let env=ProcessInfo.processInfo.environment
  guard env["AGENDA_ST_UI_TEST"]=="1",
        let email=env["AGENDA_ST_TEST_EMAIL"], !email.isEmpty,
        let password=env["AGENDA_ST_TEST_PASSWORD"], !password.isEmpty else { return }
  func lit(_ v:String)->String {
   let d=try! JSONSerialization.data(withJSONObject:[v])
   let a=String(data:d,encoding:.utf8)!
   return String(a.dropFirst().dropLast())
  }
  let js="""
  (function(){
   const email=\(lit(email)),password=\(lit(password));
   const a=Array.from(document.querySelectorAll('input'));
   const e=document.querySelector('input[type="email"]')||a.find(x=>/e-?mail/i.test((x.placeholder||'')+' '+(x.name||'')+' '+(x.id||'')));
   const p=document.querySelector('input[type="password"]')||a.find(x=>/senha|password/i.test((x.placeholder||'')+' '+(x.name||'')+' '+(x.id||'')));
   function put(el,v){if(!el)return false;const q=Object.getPrototypeOf(el),d=Object.getOwnPropertyDescriptor(q,'value');if(d&&d.set)d.set.call(el,v);else el.value=v;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return true;}
   const x=put(e,email),y=put(p,password);
   const b=Array.from(document.querySelectorAll('button,input[type="submit"]')).find(z=>/entrar/i.test((z.innerText||z.value||z.textContent||'').trim()));
   if(x&&y&&b){b.click();return 'clicked';}
   if(x&&y&&p&&p.form){p.form.requestSubmit?p.form.requestSubmit():p.form.submit();return 'submitted';}
   return 'fields='+x+','+y+';button='+!!b;
  })();
  """
  for delay in [4.0,7.0,11.0] {
   DispatchQueue.main.asyncAfter(deadline:.now()+delay) {
    webView.evaluateJavaScript(js) { result,error in
     if let error=error { print("AGENDA_ST_DEBUG_LOGIN_ERROR",error.localizedDescription) }
     else { print("AGENDA_ST_DEBUG_LOGIN_RESULT",String(describing:result)) }
    }
   }
  }
 }
}
#endif
