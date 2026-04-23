//
//  WebView.swift
//  Linkding It Later
//

import SwiftUI
import WebKit
import AppKit

struct WebView: NSViewRepresentable {
    let url: URL
    let fallbackURL: URL?
    @Binding var isLoading: Bool
    @Binding var currentURL: URL?
    var onLinkTapped: ((URL) -> Void)?
    var onWebViewCreated: ((WKWebView) -> Void)?

    init(url: URL, isLoading: Binding<Bool>, fallbackURL: URL? = nil, currentURL: Binding<URL?> = .constant(nil), onLinkTapped: ((URL) -> Void)? = nil, onWebViewCreated: ((WKWebView) -> Void)? = nil) {
        self.url = url
        self._isLoading = isLoading
        self.fallbackURL = fallbackURL
        self._currentURL = currentURL
        self.onLinkTapped = onLinkTapped
        self.onWebViewCreated = onWebViewCreated
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        onWebViewCreated?(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL == url {
            return
        }
        context.coordinator.loadedURL = url
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var loadedURL: URL?

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            if let currentURL = webView.url {
                parent.currentURL = currentURL
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let targetURL = navigationAction.request.url {
                decisionHandler(.cancel)
                if let onLinkTapped = parent.onLinkTapped {
                    onLinkTapped(targetURL)
                } else {
                    NSWorkspace.shared.open(targetURL)
                }
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                if httpResponse.statusCode >= 500 {
                    if let fallback = parent.fallbackURL {
                        decisionHandler(.cancel)
                        DispatchQueue.main.async {
                            webView.load(URLRequest(url: fallback))
                        }
                        return
                    }
                }

                if httpResponse.statusCode == 404 || httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    if let components = URLComponents(url: parent.url, resolvingAgainstBaseURL: false),
                       let scheme = components.scheme,
                       let host = components.host {
                        var loginComponents = URLComponents()
                        loginComponents.scheme = scheme
                        loginComponents.host = host
                        loginComponents.port = components.port
                        loginComponents.path = "/login/"
                        if let loginURL = loginComponents.url {
                            decisionHandler(.cancel)
                            DispatchQueue.main.async {
                                webView.load(URLRequest(url: loginURL))
                            }
                            return
                        }
                    }
                }
            }
            decisionHandler(.allow)
        }
    }
}
