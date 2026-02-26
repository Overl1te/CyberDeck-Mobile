import 'dart:convert';

import 'package:cyberdeck_mobile/network/api_client.dart';
import 'package:cyberdeck_mobile/network/host_port.dart';

class PairingResult {
  final String host;
  final int port;
  final String scheme;
  final String token;
  final String serverName;
  final int? protocolVersion;
  final Set<String> features;

  const PairingResult({
    required this.host,
    required this.port,
    this.scheme = 'http',
    required this.token,
    required this.serverName,
    this.protocolVersion,
    this.features = const <String>{},
  });
}

class PairingService {
  const PairingService();

  Future<PairingResult> qrLogin({
    required String host,
    required int port,
    String scheme = 'http',
    String? qrToken,
    String? nonce,
    required String clientId,
    required String deviceName,
  }) async {
    final normalizedScheme = _normalizeScheme(scheme);
    final normalizedQrToken = qrToken?.trim();
    final normalizedNonce = nonce?.trim();

    if ((normalizedQrToken == null || normalizedQrToken.isEmpty) &&
        (normalizedNonce == null || normalizedNonce.isEmpty)) {
      throw const ApiException('invalid_or_expired_qr_token');
    }

    final api = ApiClient(
      host: host,
      port: port,
      scheme: normalizedScheme,
      maxRetries: 1,
    );
    try {
      final body = <String, dynamic>{
        'device_id': clientId,
        'device_name': deviceName,
      };
      if (normalizedQrToken != null && normalizedQrToken.isNotEmpty) {
        body['qr_token'] = normalizedQrToken;
      } else if (normalizedNonce != null && normalizedNonce.isNotEmpty) {
        body['nonce'] = normalizedNonce;
      }

      final response = await api.postJson(
        '/api/qr/login',
        body,
        authorized: false,
      );
      final payload = _decodeJsonObject(response.body);
      if (_isApprovalPending(payload, response.statusCode)) {
        throw const ApiException('approval_pending');
      }
      if (response.statusCode == 501) {
        throw const ApiException('QR login is not supported by the server');
      }
      if (response.statusCode != 200) {
        final details = _extractErrorDetails(payload);
        throw ApiException(
          details ?? 'QR login failed',
          statusCode: response.statusCode,
        );
      }
      if (payload == null) {
        throw ApiException(
          'Invalid JSON in response',
          statusCode: response.statusCode,
        );
      }
      final token = payload['token']?.toString().trim();
      if (token == null || token.isEmpty) {
        throw const ApiException('Invalid response: missing token');
      }
      return PairingResult(
        host: host,
        port: port,
        scheme: normalizedScheme,
        token: token,
        serverName: payload['server_name']?.toString() ?? 'Unknown PC',
        protocolVersion: _toInt(payload['protocol_version']),
        features: _parseFeatures(payload['features']),
      );
    } finally {
      api.close();
    }
  }

  Future<PairingResult> handshake({
    required List<HostPort> candidates,
    required String code,
    required String clientId,
    required String deviceName,
    String scheme = 'http',
  }) async {
    if (candidates.isEmpty) {
      throw const ApiException('Invalid host or port');
    }

    final normalizedScheme = _normalizeScheme(scheme);
    Object? lastError;
    for (final candidate in candidates) {
      final api = ApiClient(
        host: candidate.host,
        port: candidate.port,
        scheme: normalizedScheme,
        maxRetries: 1,
      );
      try {
        final response = await api.postJson(
          '/api/handshake',
          <String, dynamic>{
            'code': code,
            'device_id': clientId,
            'device_name': deviceName,
          },
          authorized: false,
        );
        Map<String, dynamic>? payload;
        try {
          payload = api.decodeJsonMap(response);
        } catch (_) {
          payload = null;
        }
        if (_isApprovalPending(payload, response.statusCode)) {
          lastError = const ApiException('approval_pending');
          break;
        }
        if (response.statusCode != 200) {
          lastError =
              ApiException('Handshake failed', statusCode: response.statusCode);
          continue;
        }
        if (payload == null) {
          lastError = const ApiException('Invalid response: missing token');
          continue;
        }
        final token = payload['token']?.toString().trim();
        if (token == null || token.isEmpty) {
          lastError = const ApiException('Invalid response: missing token');
          continue;
        }
        return PairingResult(
          host: candidate.host,
          port: candidate.port,
          scheme: normalizedScheme,
          token: token,
          serverName: payload['server_name']?.toString() ?? 'Unknown PC',
          protocolVersion: _toInt(payload['protocol_version']),
          features: _parseFeatures(payload['features']),
        );
      } catch (e) {
        lastError = e;
      } finally {
        api.close();
      }
    }

    throw lastError ??
        const ApiException('Could not connect. Check code, host and port.');
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Set<String> _parseFeatures(dynamic raw) {
    final out = <String>{};
    if (raw is List) {
      for (final feature in raw) {
        final text = feature.toString().trim();
        if (text.isNotEmpty) {
          out.add(text);
        }
      }
      return out;
    }
    if (raw is Map) {
      raw.forEach((key, value) {
        final text = key.toString().trim();
        if (text.isEmpty) return;
        if (_isTruthyFeature(value)) {
          out.add(text);
        }
      });
      return out;
    }
    return const <String>{};
  }

  bool _isTruthyFeature(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.trim().toLowerCase();
      return text == 'true' || text == '1' || text == 'yes' || text == 'on';
    }
    return false;
  }

  bool _isApprovalPending(Map<String, dynamic>? payload, int statusCode) {
    if (payload != null) {
      final approved = _toBool(payload['approved']);
      if (approved == false) {
        return true;
      }

      final approvalPending = _toBool(payload['approval_pending']);
      if (approvalPending == true) {
        return true;
      }

      final status = payload['status']?.toString().trim().toLowerCase();
      if (status == 'approval_pending') {
        return true;
      }
    }

    return statusCode == 202;
  }

  bool? _toBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return null;
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  Map<String, dynamic>? _decodeJsonObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  String? _extractErrorDetails(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    for (final key in const <String>['detail', 'error', 'message']) {
      final value = payload[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String _normalizeScheme(String raw) {
    final value = raw.trim().toLowerCase();
    return value == 'https' ? 'https' : 'http';
  }

  static bool isQrLoginFallbackError(Object error) {
    if (error is! ApiException) return false;
    if (error.statusCode == 404 || error.statusCode == 501) return true;
    final message = error.message.toLowerCase();
    return message.contains('invalid_or_expired_qr_token') ||
        message.contains('qr login is not supported');
  }

  static bool isInvalidQrTokenError(Object error) {
    if (error is! ApiException) return false;
    final message = error.message.toLowerCase();
    return message.contains('invalid_or_expired_qr_token');
  }

  static bool isApprovalPendingError(Object error) {
    if (error is! ApiException) return false;
    final message = error.message.toLowerCase();
    return message.contains('approval_pending');
  }

  static bool isInsecureTlsError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('certificate') ||
        message.contains('handshakeexception') ||
        message.contains('self signed');
  }
}
