import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

class ReaderWebMessage {
  const ReaderWebMessage(this.channel, this.message);

  final String channel;
  final String message;
}

abstract class ReaderWebView {
  factory ReaderWebView.create() =>
      Platform.isWindows ? _WindowsReaderWebView() : _MobileReaderWebView();

  Stream<ReaderWebMessage> get messages;
  Stream<String> get errors;
  Future<void> initialize();
  Future<void> loadHtml(String html);
  Future<void> runJavaScript(String script);
  Widget buildView();
  Future<void> dispose();
}

class _MobileReaderWebView implements ReaderWebView {
  final _messages = StreamController<ReaderWebMessage>.broadcast();
  final _errors = StreamController<String>.broadcast();
  late final WebViewController _controller;
  bool _disposed = false;

  @override
  Stream<ReaderWebMessage> get messages => _messages.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> initialize() async {
    _controller = WebViewController();
    await _controller.enableZoom(true);
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    for (final channel in [
      'ReaderReady',
      'Relocated',
      'Selection',
      'SelectionAction',
      'NoteTapped',
      'Footnote',
      'Toc',
      'ToggleUI',
      'ReaderError',
      'SearchResults',
      'AudioPage',
    ]) {
      await _controller.addJavaScriptChannel(
        channel,
        onMessageReceived: (message) {
          if (!_messages.isClosed) {
            _messages.add(ReaderWebMessage(channel, message.message));
          }
        },
      );
    }
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && !_errors.isClosed) {
            _errors.add('No se pudo cargar el lector: ${error.description}');
          }
        },
      ),
    );
  }

  @override
  Future<void> loadHtml(String html) => _controller.loadHtmlString(html);

  @override
  Future<void> runJavaScript(String script) =>
      _controller.runJavaScript(script);

  @override
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _messages.close();
    await _errors.close();
  }
}

class _WindowsReaderWebView implements ReaderWebView {
  final _controller = WebviewController();
  final _messages = StreamController<ReaderWebMessage>.broadcast();
  final _errors = StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _messageSubscription;
  StreamSubscription<dynamic>? _errorSubscription;
  bool _disposed = false;

  @override
  Stream<ReaderWebMessage> get messages => _messages.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> initialize() async {
    if (await WebviewController.getWebViewVersion() == null) {
      throw StateError(
        'Instala Microsoft Edge WebView2 Runtime para leer en Windows.',
      );
    }
    await _controller.initialize();
    _messageSubscription = _controller.webMessage.listen((event) {
      if (event is! Map) return;
      final channel = event['channel'];
      if (channel is! String) return;
      _messages.add(
        ReaderWebMessage(channel, event['message']?.toString() ?? ''),
      );
    });
    _errorSubscription = _controller.onLoadError.listen((_) {
      _errors.add('No se pudo cargar el lector.');
    });
    await _controller.setBackgroundColor(const Color(0xFF0F0E17));
  }

  @override
  Future<void> loadHtml(String html) => _controller.loadStringContent(html);

  @override
  Future<void> runJavaScript(String script) async {
    await _controller.executeScript(script);
  }

  @override
  Widget buildView() => Webview(_controller);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    if (_controller.value.isInitialized) await _controller.dispose();
    await _messages.close();
    await _errors.close();
  }
}

final readerWebViewFactoryProvider = Provider<ReaderWebView Function()>((ref) {
  return ReaderWebView.create;
});
