import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nomowear/core/network/api_constants.dart';
import 'package:nomowear/core/network/api_exception.dart';

class ApiClient {
  final http.Client _client;
  final String baseUrl;

  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? ApiConstants.baseUrl;

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final segment = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$root$segment');
  }

  Map<String, String> _headers({
    String? authToken,
    bool jsonBody = false,
  }) {
    final headers = <String, String>{};
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? authToken,
  }) async {
    // Encode once so the log is the exact string written to the socket.
    final encodedBody = jsonEncode(body);
    _logRequest(method: 'POST', path: path, body: body);
    if (kDebugMode && path.contains('cart')) {
      debugPrint('[CART_DEBUG] POST $path');
      debugPrint('[CART_DEBUG] FINAL HTTP BODY = $encodedBody');
      return _postCartWithNetworkTrace(
        path: path,
        encodedBody: encodedBody,
        authToken: authToken,
      );
    }
    return _request(
      () => _client.post(
        _uri(path),
        headers: _headers(authToken: authToken, jsonBody: true),
        body: encodedBody,
      ),
    );
  }

  Future<Map<String, dynamic>> _postCartWithNetworkTrace({
    required String path,
    required String encodedBody,
    String? authToken,
  }) async {
    final uri = _uri(path);
    final request = http.Request('POST', uri);
    request.headers.addAll(_headers(authToken: authToken, jsonBody: true));
    request.body = encodedBody;

    final start = DateTime.now();
    if (kDebugMode) {
      debugPrint('[CART_NETWORK] POST_START timestamp=${start.toIso8601String()}');
    }
    try {
      final requestSentAt = DateTime.now();
      if (kDebugMode) {
        debugPrint(
          '[CART_NETWORK] REQUEST_SENT timestamp=${requestSentAt.toIso8601String()}',
        );
      }
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));

      final headersReceivedAt = DateTime.now();
      final headersLatencyMs = headersReceivedAt.difference(requestSentAt).inMilliseconds;
      if (kDebugMode) {
        debugPrint(
          '[CART_NETWORK] RESPONSE_HEADERS_RECEIVED timestamp=${headersReceivedAt.toIso8601String()} duration_since_sent=${headersLatencyMs}ms',
        );
      }

      DateTime? firstByteAt;
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        firstByteAt ??= DateTime.now();
        bytes.addAll(chunk);
      }
      final completeAt = DateTime.now();

      final networkDurationMs = completeAt.difference(start).inMilliseconds;
      final firstByteMs = firstByteAt == null
          ? -1
          : firstByteAt.difference(start).inMilliseconds;
      final transferMs = firstByteAt == null
          ? -1
          : completeAt.difference(firstByteAt).inMilliseconds;

      if (kDebugMode) {
        if (firstByteAt != null) {
          debugPrint(
            '[CART_NETWORK] RESPONSE_FIRST_BYTE timestamp=${firstByteAt.toIso8601String()}',
          );
        }
        debugPrint(
          '[CART_NETWORK] POST_COMPLETE timestamp=${completeAt.toIso8601String()}',
        );
        debugPrint('[CART_NETWORK] NETWORK_DURATION=${networkDurationMs}ms');
        debugPrint('[CART_NETWORK] HEADERS_WAIT=${headersLatencyMs}ms');
        debugPrint(
          '[CART_NETWORK] LIKELY_SERVER_OR_NETWORK_WAIT=${headersLatencyMs > 500}',
        );
        debugPrint('[CART_NETWORK] TIME_TO_FIRST_BYTE=${firstByteMs}ms');
        debugPrint('[CART_NETWORK] RESPONSE_TRANSFER_DURATION=${transferMs}ms');
      }

      final parseSw = Stopwatch()..start();
      final bodyString = utf8.decode(bytes);
      final response = http.Response(
        bodyString,
        streamed.statusCode,
        headers: streamed.headers,
        request: streamed.request,
        reasonPhrase: streamed.reasonPhrase,
        isRedirect: streamed.isRedirect,
        persistentConnection: streamed.persistentConnection,
      );
      final decoded = _decodeResponse(response);
      parseSw.stop();
      if (kDebugMode) {
        debugPrint('[CART_NETWORK] PARSE_DURATION=${parseSw.elapsedMilliseconds}ms');
      }
      return decoded;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Unable to connect. Check your network and server.',
      );
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    required String authToken,
    Map<String, String>? queryParameters,
  }) async {
    _logRequest(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
    );
    var uri = _uri(path);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    return _request(
      () => _client.get(
        uri,
        headers: _headers(authToken: authToken),
      ),
    );
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    required String authToken,
  }) async {
    _logRequest(method: 'PUT', path: path, body: body);
    return _request(
      () => _client.put(
        _uri(path),
        headers: _headers(authToken: authToken, jsonBody: true),
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    required String authToken,
    bool jsonBody = true,
  }) async {
    _logRequest(method: 'DELETE', path: path);
    return _request(
      () => _client.delete(
        _uri(path),
        headers: _headers(authToken: authToken, jsonBody: jsonBody),
      ),
    );
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    String? authToken,
  }) async {
    return _sendMultipart('POST', path, fields: fields, files: files, authToken: authToken);
  }

  Future<Map<String, dynamic>> putMultipart(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    required String authToken,
  }) async {
    return _sendMultipart('PUT', path, fields: fields, files: files, authToken: authToken);
  }

  Future<Map<String, dynamic>> _sendMultipart(
    String method,
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
    String? authToken,
  }) async {
    _logRequest(
      method: method,
      path: path,
      fields: fields,
      fileNames: files.map((file) => file.filename ?? file.field).toList(),
    );
    return _request(() async {
      final request = http.MultipartRequest(method, _uri(path));
      if (authToken != null && authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }
      request.fields.addAll(fields);
      request.files.addAll(files);
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    });
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send,
  ) async {
    try {
      final response = await send().timeout(const Duration(seconds: 30));
      return _decodeResponse(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Unable to connect. Check your network and server.',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(response.body);
      decoded = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } catch (_) {
      throw const ApiException('Invalid response from server');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _logResponse(response.statusCode, decoded);
      return decoded;
    }

    _logResponse(response.statusCode, decoded);

    final message =
        decoded['message']?.toString() ?? 'Request failed (${response.statusCode})';
    throw ApiException(message, statusCode: response.statusCode);
  }

  void _logRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    Map<String, String>? fields,
    List<String>? fileNames,
  }) {
    if (!kDebugMode) return;

    final buffer = StringBuffer()
      ..writeln('──────── API Request ────────')
      ..writeln('$method ${_uri(path)}');

    if (queryParameters != null && queryParameters.isNotEmpty) {
      buffer.writeln(
        'Query: ${const JsonEncoder.withIndent('  ').convert(queryParameters)}',
      );
    }
    if (body != null) {
      buffer.writeln(
        'Body: ${const JsonEncoder.withIndent('  ').convert(body)}',
      );
    }
    if (fields != null && fields.isNotEmpty) {
      buffer.writeln(
        'Fields: ${const JsonEncoder.withIndent('  ').convert(fields)}',
      );
    }
    if (fileNames != null && fileNames.isNotEmpty) {
      buffer.writeln('Files: ${fileNames.join(', ')}');
    }
    buffer.writeln('────────────────────────────');

    debugPrint(buffer.toString());
  }

  void _logResponse(int statusCode, Map<String, dynamic> body) {
    if (!kDebugMode) return;

    final buffer = StringBuffer()
      ..writeln('──────── API Response ────────')
      ..writeln('Status: $statusCode')
      ..writeln(
        'Body: ${const JsonEncoder.withIndent('  ').convert(body)}',
      )
      ..writeln('────────────────────────────');

    debugPrint(buffer.toString());
  }
}
