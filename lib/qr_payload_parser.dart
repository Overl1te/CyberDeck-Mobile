import 'dart:convert';

import 'network/host_port.dart';

class CyberdeckQrData {
  final String scheme;
  final String? host;
  final int? port;
  final String? code;
  final String? qrToken;
  final String? type;
  final String? serverId;
  final String? hostname;
  final String? version;
  final String? nonce;
  final int? ts;

  const CyberdeckQrData({
    this.scheme = 'http',
    this.host,
    this.port,
    this.code,
    this.qrToken,
    this.type,
    this.serverId,
    this.hostname,
    this.version,
    this.nonce,
    this.ts,
  });
}

CyberdeckQrData? parseCyberdeckQrPayload(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  final uri = Uri.tryParse(s);
  if (uri != null && uri.hasScheme) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme.startsWith('cyberdeck') ||
        scheme == 'http' ||
        scheme == 'https') {
      final data = _parseCyberdeckQrUri(uri);
      if (data != null) return data;
    }
  }

  if (s.startsWith('{') && s.endsWith('}')) {
    final data = _parseCyberdeckQrJson(s);
    if (data != null) return data;
  }

  final dataPipe = _parsePipeFormat(s);
  if (dataPipe != null) return dataPipe;

  final dataSpace = _parseSpaceFormat(s);
  if (dataSpace != null) return dataSpace;

  final hp = _splitHostPort(s);
  if (hp != null) {
    return CyberdeckQrData(host: hp.$1, port: hp.$2);
  }

  return null;
}

CyberdeckQrData? _parseCyberdeckQrUri(Uri uri) {
  final qp = uri.queryParameters;

  final type = qp['type'];
  final isCyberdeckTyped =
      type != null && type.toLowerCase().startsWith('cyberdeck_qr_');
  final isCyberdeckScheme = uri.scheme.toLowerCase().startsWith('cyberdeck');

  if (!isCyberdeckScheme && !isCyberdeckTyped) {
    final maybeCode = qp['code'];
    if (maybeCode == null || maybeCode.trim().isEmpty) return null;
  }

  final host = (qp['host'] ?? qp['ip'] ?? qp['addr'])?.trim().isNotEmpty == true
      ? (qp['host'] ?? qp['ip'] ?? qp['addr'])!.trim()
      : (uri.host.trim().isNotEmpty ? uri.host.trim() : null);

  final port =
      int.tryParse(qp['port'] ?? '') ?? (uri.hasPort ? uri.port : null);

  final code = qp['code']?.trim();
  final qrToken = qp['qr_token'] ?? qp['token'];
  final nonce = qp['nonce'];
  final serverId = qp['server_id'];
  final hostname = qp['hostname'];
  final version = qp['version'];
  final ts = int.tryParse(qp['ts'] ?? '');

  if (host == null &&
      port == null &&
      code == null &&
      (qrToken == null || qrToken.isEmpty) &&
      (nonce == null || nonce.isEmpty)) {
    return null;
  }

  return CyberdeckQrData(
    scheme: _normalizeHttpScheme(
      qp['scheme'] ?? (uri.scheme == 'https' ? 'https' : null),
    ),
    host: host,
    port: port,
    code: code,
    qrToken: (qrToken?.trim().isNotEmpty == true) ? qrToken!.trim() : null,
    type: type,
    serverId: serverId,
    hostname: hostname,
    version: version,
    nonce: (nonce?.trim().isNotEmpty == true) ? nonce!.trim() : null,
    ts: ts,
  );
}

CyberdeckQrData? _parseCyberdeckQrJson(String s) {
  try {
    final obj = jsonDecode(s);
    if (obj is! Map) return null;

    final host = (obj['host'] ?? obj['ip'] ?? obj['addr'])?.toString();
    final port = (obj['port'] is num)
        ? (obj['port'] as num).toInt()
        : int.tryParse((obj['port'] ?? '').toString());
    final code =
        (obj['code'] ?? obj['pairing_code'] ?? obj['pairingCode'])?.toString();
    final qrToken = (obj['qr_token'] ?? obj['token'])?.toString();
    final nonce = obj['nonce']?.toString();
    return CyberdeckQrData(
      scheme: _normalizeHttpScheme(obj['scheme']?.toString()),
      host: host,
      port: port,
      code: code,
      qrToken: qrToken,
      type: obj['type']?.toString(),
      serverId: obj['server_id']?.toString(),
      hostname: obj['hostname']?.toString(),
      version: obj['version']?.toString(),
      nonce: nonce,
      ts: (obj['ts'] is num)
          ? (obj['ts'] as num).toInt()
          : int.tryParse((obj['ts'] ?? '').toString()),
    );
  } catch (_) {
    return null;
  }
}

CyberdeckQrData? _parsePipeFormat(String s) {
  final partsPipe = s.split('|');
  if (partsPipe.length < 2) return null;
  final a = partsPipe[0].trim();
  final b = partsPipe[1].trim();
  final hp = _splitHostPort(a);
  if (hp == null) return null;
  return CyberdeckQrData(host: hp.$1, port: hp.$2, code: b);
}

CyberdeckQrData? _parseSpaceFormat(String s) {
  final partsSpace = s.split(RegExp(r'\s+'));
  if (partsSpace.length < 2) return null;
  final hp = _splitHostPort(partsSpace[0]);
  if (hp == null) return null;
  return CyberdeckQrData(host: hp.$1, port: hp.$2, code: partsSpace[1]);
}

(String, int)? _splitHostPort(String hostPort) {
  final hp = parseHostPort(hostPort, requirePort: true);
  if (hp == null) return null;
  return (hp.host, hp.port);
}

String _normalizeHttpScheme(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value == 'https') return 'https';
  return 'http';
}
