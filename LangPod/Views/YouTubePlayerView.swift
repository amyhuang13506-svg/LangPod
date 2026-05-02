import SwiftUI
import WebKit

/// SwiftUI wrapper around WKWebView that loads a YouTube video via the
/// YouTube IFrame Embed. Audio/video is streamed directly from YouTube —
/// the app does not host or redistribute, so this is YouTube's officially
/// supported embed flow (used by every video blogger), zero copyright risk.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    var autoplay: Bool = true

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false

        let html = embedHTML(videoId: videoId, autoplay: autoplay)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func embedHTML(videoId: String, autoplay: Bool) -> String {
        let autoplayFlag = autoplay ? 1 : 0
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
          html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
          .container { position: relative; width: 100%; height: 100%; }
          iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
        </style>
        </head>
        <body>
        <div class="container">
          <iframe
            src="https://www.youtube.com/embed/\(videoId)?playsinline=1&autoplay=\(autoplayFlag)&rel=0&modestbranding=1"
            allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen>
          </iframe>
        </div>
        </body>
        </html>
        """
    }
}
