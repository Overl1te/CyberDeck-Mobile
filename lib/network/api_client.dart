import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String code;
  final int? number;
  final String? incidentId;
  final String? hint;

  const ApiException(
    this.message, {
    this.statusCode,
    this.code = '',
    this.number,
    this.incidentId,
    this.hint,
  });

  bool get hasCatalogCode => code.trim().isNotEmpty;

  String get userText {
    final normalizedMessage = message.trim();
    if (hasCatalogCode) {
      if (normalizedMessage.isEmpty) return code;
      return '[$code] $normalizedMessage';
    }
    return normalizedMessage.isEmpty ? 'Request failed' : normalizedMessage;
  }

  @override
  String toString() {
    final base = userText;
    final incidentSuffix = (incidentId == null || incidentId!.trim().isEmpty)
        ? ''
        : ' (#${incidentId!.trim()})';
    if (statusCode == null) return '$base$incidentSuffix';
    return '$base$incidentSuffix (HTTP $statusCode)';
  }
}

class ApiClient {
  final String host;
  final int port;
  final String scheme;
  final String? token;
  final Duration defaultTimeout;
  final int maxRetries;
  final http.Client _client;

  ApiClient({
    required this.host,
    required this.port,
    this.scheme = 'http',
    this.token,
    http.Client? client,
    this.defaultTimeout = const Duration(seconds: 6),
    this.maxRetries = 1,
  }) : _client = client ?? http.Client();

  String get _normalizedScheme =>
      scheme.trim().toLowerCase() == 'https' ? 'https' : 'http';

  Uri uri(String path, {Map<String, String>? queryParameters}) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri(
      scheme: _normalizedScheme,
      host: host,
      port: port,
      path: normalized,
      queryParameters:
          queryParameters?.isEmpty == true ? null : queryParameters,
    );
  }

  Map<String, String> _headers({
    bool json = false,
    bool authorized = true,
    Map<String, String>? extra,
  }) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (authorized && token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool authorized = true,
    Duration? timeout,
  }) {
    return _withRetry(
      () => _client
          .get(
            uri(path, queryParameters: queryParameters),
            headers: _headers(authorized: authorized, extra: headers),
          )
          .timeout(timeout ?? defaultTimeout),
    );
  }

  Future<http.Response> post(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool authorized = true,
    Duration? timeout,
  }) {
    return _withRetry(
      () => _client
          .post(
            uri(path, queryParameters: queryParameters),
            headers: _headers(authorized: authorized, extra: headers),
            body: body,
          )
          .timeout(timeout ?? defaultTimeout),
    );
  }

  Future<http.Response> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool authorized = true,
    Duration? timeout,
  }) {
    return _withRetry(
      () => _client
          .post(
            uri(path, queryParameters: queryParameters),
            headers:
                _headers(json: true, authorized: authorized, extra: headers),
            body: jsonEncode(body),
          )
          .timeout(timeout ?? defaultTimeout),
    );
  }

  Future<http.StreamedResponse> postMultipartFile(
    String path, {
    required String fieldName,
    required String filePath,
    Map<String, String>? queryParameters,
    Map<String, String>? fields,
    bool authorized = true,
    Duration? timeout,
  }) {
    return _withRetry(() async {
      final request = http.MultipartRequest(
        'POST',
        uri(path, queryParameters: queryParameters),
      );
      request.headers.addAll(
          _headers(authorized: authorized, extra: const <String, String>{}));
      if (fields != null) request.fields.addAll(fields);
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      return _client.send(request).timeout(timeout ?? defaultTimeout);
    });
  }

  Map<String, dynamic> decodeJsonMap(
    http.Response response, {
    Set<int> expectedStatuses = const <int>{200},
  }) {
    if (!expectedStatuses.contains(response.statusCode)) {
      throw _extractApiException(response);
    }

    final body = _responseBody(response);
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw ApiException(
        'Invalid JSON in response',
        statusCode: response.statusCode,
        code: 'CD-MOB-1001',
      );
    }
    if (decoded is! Map) {
      throw ApiException(
        'Expected JSON object in response',
        statusCode: response.statusCode,
        code: 'CD-MOB-1002',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  ApiException _extractApiException(http.Response response) {
    final body = _responseBody(response).trim();
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        payload = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    final errorBlock = _extractErrorBlock(payload);
    final message =
        _extractErrorMessage(response, payload: payload) ?? 'Request failed';
    return ApiException(
      message,
      statusCode: response.statusCode,
      code: (errorBlock?['code'] ?? '').toString().trim(),
      number: _toInt(errorBlock?['number']),
      incidentId: (errorBlock?['incident_id'] ?? '').toString().trim().isEmpty
          ? null
          : (errorBlock?['incident_id'] ?? '').toString().trim(),
      hint: (errorBlock?['hint'] ?? '').toString().trim().isEmpty
          ? null
          : (errorBlock?['hint'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic>? _extractErrorBlock(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final raw = payload['error'];
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String? _extractErrorMessage(
    http.Response response, {
    Map<String, dynamic>? payload,
  }) {
    final body = _responseBody(response).trim();
    if (body.isEmpty) return null;

    final decoded = payload ??
        (() {
          try {
            final value = jsonDecode(body);
            if (value is Map) return Map<String, dynamic>.from(value);
          } catch (_) {}
          return null;
        }).call();

    if (decoded != null) {
      final errorBlock = _extractErrorBlock(decoded);
      if (errorBlock != null) {
        for (final key in const <String>['title', 'message', 'hint']) {
          final value = errorBlock[key];
          if (value == null) continue;
          final text = value.toString().trim();
          if (text.isNotEmpty) return text;
        }
      }
      for (final key in const <String>['detail', 'error', 'message']) {
        final value = decoded[key];
        if (value != null) {
          final text = value.toString().trim();
          if (text.isNotEmpty) return text;
        }
      }
    }

    if (body.length > 180) return '${body.substring(0, 180)}...';
    return body;
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    var attempt = 0;
    while (true) {
      try {
        return await action();
      } catch (error) {
        final retryable = error is TimeoutException ||
            error is SocketException ||
            error is http.ClientException;
        if (!retryable || attempt >= maxRetries) rethrow;
        attempt++;
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
  }

  void close() {
    _client.close();
  }

  String _responseBody(http.Response response) {
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
}
