import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_web_adapter/dio_web_adapter.dart';
import 'package:web/web.dart' as web;

// Writes that survive the page going away.
//
// Dio does not start a request when it is asked to: it runs its interceptor
// chain first, and every step of that chain is a `Future(...)` — a separate
// turn of the event loop. A favorite clicked just before a reload or a typed
// URL can lose that race outright: the page unloads before Dio reaches the
// network, the request is never sent, and the heart the reader saw fill in
// was never saved.
//
// Two changes close it:
//
// * Every write is recorded the moment the generated client asks for it
//   ([UnloadSafeDio.fetch] runs synchronously inside `api.favorite(...)`).
// * Writes go out as `fetch(..., {keepalive: true})`, which the browser
//   finishes after the page is gone, and on `pagehide` anything recorded but
//   not yet sent is sent that way immediately.
//
// If the page comes back from the back/forward cache, Dio's chain resumes
// and reaches the adapter, which finds the request already sent and answers
// with that response instead of sending it twice.

/// A browser [Dio] that records every write as soon as it is requested.
final class UnloadSafeDio extends DioForBrowser {
  UnloadSafeDio(this.adapter) {
    httpClientAdapter = adapter;
  }

  final UnloadSafeAdapter adapter;

  @override
  Future<Response<T>> fetch<T>(RequestOptions requestOptions) {
    adapter.track(requestOptions);
    return super.fetch<T>(requestOptions);
  }
}

/// Sends writes with keepalive `fetch`; reads go through Dio's usual adapter.
final class UnloadSafeAdapter implements HttpClientAdapter {
  UnloadSafeAdapter({HttpClientAdapter? fallback})
    : _fallback = fallback ?? BrowserHttpClientAdapter();

  /// Browsers cap keepalive bodies at 64 KiB in flight; a long article is
  /// sent the ordinary way.
  static const maxKeepaliveBody = 60 * 1024;

  static const _idKey = 'conduit.write';

  final HttpClientAdapter _fallback;

  var _nextId = 0;
  final _unsent = <int, RequestOptions>{};
  final _sentEarly = <int, Future<web.Response>>{};

  /// How many writes have been asked for and not yet handed to the network.
  int get unsent => _unsent.length;

  /// Records [options] if it is a write. Must run synchronously when the
  /// request is made, before Dio's first asynchronous step.
  void track(RequestOptions options) {
    if (!_isWrite(options)) return;
    final id = _nextId++;
    options.extra[_idKey] = id;
    _unsent[id] = options;
  }

  /// Sends every recorded write that has not been sent yet. Wired to
  /// `pagehide`, the last moment a page can still start a request.
  void flush() {
    for (final MapEntry(key: id, value: options) in _unsent.entries.toList()) {
      _unsent.remove(id);
      final data = options.data;
      final body = data == null ? null : utf8.encode(jsonEncode(data));
      _sentEarly[id] = _send(options, body);
    }
  }

  /// Listens for `pagehide` on [window] and [flush]es.
  void flushOnPageHide(web.Window window) {
    window.addEventListener('pagehide', ((web.Event _) => flush()).toJS);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final id = options.extra[_idKey];
    if (id is int) {
      _unsent.remove(id);
      final early = _sentEarly.remove(id);
      if (early != null) return _responseBody(options, early);
    }
    if (!_isWrite(options)) {
      return _fallback.fetch(options, requestStream, cancelFuture);
    }

    final body = requestStream == null ? null : await _collect(requestStream);
    if (body != null && body.length > maxKeepaliveBody) {
      return _fallback.fetch(options, Stream.value(body), cancelFuture);
    }
    return _responseBody(options, _send(options, body));
  }

  @override
  void close({bool force = false}) => _fallback.close(force: force);

  static bool _isWrite(RequestOptions options) {
    final method = options.method.toUpperCase();
    return method != 'GET' && method != 'HEAD' && method != 'OPTIONS';
  }

  /// Starts the request now — `window.fetch` is called before this returns.
  static Future<web.Response> _send(RequestOptions options, Uint8List? body) {
    final headers = web.Headers();
    options.headers.forEach((name, value) {
      if (value != null) headers.set(name, '$value');
    });
    if (body != null && headers.get('content-type') == null) {
      headers.set(
        'content-type',
        options.contentType ?? Headers.jsonContentType,
      );
    }
    return web.window
        .fetch(
          options.uri.toString().toJS,
          web.RequestInit(
            method: options.method.toUpperCase(),
            headers: headers,
            body: body?.toJS,
            keepalive: true,
          ),
        )
        .toDart;
  }

  static Future<ResponseBody> _responseBody(
    RequestOptions options,
    Future<web.Response> pending,
  ) async {
    final web.Response response;
    final Uint8List bytes;
    try {
      response = await pending;
      bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    } on Object catch (error) {
      // fetch rejects only when no response arrived at all: what an XHR
      // reports as a connection error, and the app shows as "Unable to
      // connect" either way.
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'the request could not be sent',
        error: error,
      );
    }
    return ResponseBody.fromBytes(
      bytes,
      response.status,
      statusMessage: response.statusText,
      headers: {
        for (final name in const [
          'content-type',
          'www-authenticate',
          'x-request-id',
        ])
          if (response.headers.get(name) case final value?) name: [value],
      },
    );
  }

  static Future<Uint8List> _collect(Stream<Uint8List> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
