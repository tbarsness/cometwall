import Foundation
import WebKit

/// Watches each page for a visible password field and asks the store to fill it.
/// Runs in an isolated content world, so the page's own scripts cannot call the
/// message handler or see this code.
enum AutoLogin {
    static let handlerName = "cometwallLogin"
    static let world = WKContentWorld.world(name: "CometWallAutoLogin")

    static let watcher = WKUserScript(source: """
        (() => {
          let last = 0;
          const check = () => {
            const pw = document.querySelector('input[type=password]');
            if (!pw || pw.offsetParent === null || pw.value) return;
            const now = Date.now();
            if (now - last < 5000) return;
            last = now;
            window.webkit.messageHandlers.\(handlerName).postMessage(location.host);
          };
          new MutationObserver(check).observe(document.documentElement, { childList: true, subtree: true });
          check();
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world)

    /// Sets the password the way a typed value would arrive (frameworks like Vue
    /// listen for input events, not value changes), then presses the login button.
    static let fill = """
        const pw = document.querySelector('input[type=password]');
        if (!pw) return false;
        const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        pw.focus();
        setValue.call(pw, password);
        pw.dispatchEvent(new Event('input', { bubbles: true }));
        pw.dispatchEvent(new Event('change', { bubbles: true }));
        await new Promise(r => setTimeout(r, 150));
        const button = [...document.querySelectorAll('button, input[type=submit]')]
          .find(b => /log\\s*in|sign\\s*in|login/i.test(b.textContent || b.value || ''));
        if (button) button.click();
        else if (pw.form) pw.form.requestSubmit();
        else pw.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
        return true;
        """
}

/// Breaks the retain cycle between WKUserContentController and the store.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: PaneStore?
    init(_ target: PaneStore) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.loginPageAppeared(message) }
    }
}
