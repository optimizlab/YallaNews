import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Crawls news sources using a real WebView so that JavaScript-rendered
/// (SPA) websites are fully hydrated before links and content are extracted.
///
/// The WebView is rendered as a fully-transparent overlay so the user never
/// sees a browser window, but the platform WebView still loads and executes
/// the page's JavaScript. After the page finishes loading (plus a hydration
/// delay) we read the rendered DOM via `runJavaScriptReturningResult` and
/// return every absolute http(s) link found.
class WebViewCrawlerService {
  WebViewCrawlerService._internal();
  static final WebViewCrawlerService instance = WebViewCrawlerService._internal();

  /// Extract article URLs from [url] using a headless WebView.
  ///
  /// Returns absolute http(s) URLs found in `<a href>` tags of the fully
  /// rendered page. Returns an empty list on timeout or failure.
  Future<List<String>> extractArticleUrls({
    required BuildContext context,
    required String url,
    Duration loadTimeout = const Duration(seconds: 20),
  }) async {
    if (url.isEmpty) return const <String>[];

    final foundUrls = <String>{};
    final completer = Completer<List<String>>();
    Timer? timeoutTimer;
    OverlayEntry? overlayEntry;
    bool _finished = false;

    late final WebViewController controller;

    void finish() {
      if (_finished) return;
      _finished = true;
      timeoutTimer?.cancel();
      overlayEntry?.remove();
      if (!completer.isCompleted) {
        completer.complete(foundUrls.toList());
      }
    }

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            // Give SPA frameworks time to hydrate and inject links into the DOM.
            await Future.delayed(const Duration(seconds: 3));
            try {
              final raw = await controller.runJavaScriptReturningResult(
                '''JSON.stringify(
                  Array.from(document.querySelectorAll('a[href]'))
                    .map(a => a.href)
                    .filter(h => h && h.startsWith('http') && h.length > 10)
                )''',
              );
              if (raw != null) {
                final String json;
                if (raw is String) {
                  json = raw;
                } else {
                  json = const JsonEncoder().convert(raw);
                }
                final decoded = jsonDecode(json) as List<dynamic>;
                for (final u in decoded) {
                  final s = u.toString().trim();
                  if (s.isNotEmpty &&
                      (s.startsWith('http://') || s.startsWith('https://'))) {
                    foundUrls.add(s);
                  }
                }
              }
            } catch (_) {
              // JS evaluation failed — return whatever we have.
            }
            finish();
          },
          onWebResourceError: (error) {
            // Non-fatal: the page may still have usable content after load.
          },
        ),
      );

    overlayEntry = OverlayEntry(
      builder: (_) => Opacity(
        opacity: 0.0,
        child: SizedBox(
          width: 200,
          height: 200,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );

    try {
      Overlay.of(context).insert(overlayEntry!);

      await controller.loadRequest(Uri.parse(url));

      timeoutTimer = Timer(loadTimeout, finish);

      return completer.future;
    } catch (e) {
      finish();
      return const <String>[];
    }
  }
}
