import 'dart:convert';

/// Результат разбора QR-пейлоада CyberDeck.
///
/// Поля заполняются по возможности: один и тот же QR может содержать
/// только часть информации (например, только `host/port`, или `code`, или
/// метаданные типа `hostname/version`).
class CyberdeckQrData {
  /// IP/хост сервера (например, `192.168.0.201`).
  final String? host;

  /// Порт сервера (например, `8080`).
  final int? port;

  /// Код привязки/пары (то, что вводится в поле "КОД ПАРЫ").
  final String? code;

  /// Токен для QR-логина (если сервер поддерживает `/api/qr/login`).
  final String? qrToken;

  /// Тип протокола/формата QR (например, `cyberdeck_qr_v1`).
  final String? type;

  /// ID сервера (если передан в QR как `server_id`).
  final String? serverId;

  /// Имя ПК/хоста для отображения (если передано в QR как `hostname`).
  final String? hostname;

  /// Версия сервера для отображения (если передана в QR как `version`).
  final String? version;

  /// Nonce (одноразовый идентификатор, если присутствует).
  final String? nonce;

  /// Timestamp (секунды), если присутствует.
  final int? ts;

  const CyberdeckQrData({
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

/// Разбирает строку из QR-кода в [CyberdeckQrData].
///
/// Поддерживаемые варианты (по приоритету):
/// - `http/https` ссылка с `type=cyberdeck_qr_*` (новый формат)
/// - `cyberdeck://...` (старый формат со своей схемой)
/// - JSON (`{"ip":"...","port":...,"code":"..."}`)
/// - `host:port|code`
/// - `host:port code`
/// - `host:port`
///
/// Возвращает `null`, если строка не похожа на QR CyberDeck.
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
  final serverId = qp['server_id'];
  final hostname = qp['hostname'];
  final version = qp['version'];
  final nonce = qp['nonce'];
  final ts = int.tryParse(qp['ts'] ?? '');

  if (host == null &&
      port == null &&
      code == null &&
      (qrToken == null || qrToken.isEmpty)) {
    return null;
  }

  return CyberdeckQrData(
    host: host,
    port: port,
    code: code,
    qrToken: (qrToken?.trim().isNotEmpty == true) ? qrToken!.trim() : null,
    type: type,
    serverId: serverId,
    hostname: hostname,
    version: version,
    nonce: nonce,
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
    return CyberdeckQrData(
      host: host,
      port: port,
      code: code,
      qrToken: qrToken,
      type: obj['type']?.toString(),
      serverId: obj['server_id']?.toString(),
      hostname: obj['hostname']?.toString(),
      version: obj['version']?.toString(),
      nonce: obj['nonce']?.toString(),
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
  final t = hostPort.trim();
  if (!t.contains(':')) return null;
  final parts = t.split(':');
  if (parts.isEmpty) return null;
  final host = parts.first.trim();
  if (host.isEmpty) return null;
  final port = int.tryParse(parts.length > 1 ? parts[1].trim() : '');
  if (port == null) return null;
  return (host, port);
}
