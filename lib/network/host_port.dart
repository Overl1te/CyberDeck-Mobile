import 'dart:io';

class HostPort {
  final String host;
  final int port;

  const HostPort({required this.host, required this.port});
}

int? _defaultPortForEndpointScheme(String scheme) {
  switch (scheme.trim().toLowerCase()) {
    case 'https':
    case 'wss':
      return 443;
    case 'http':
    case 'ws':
      return 80;
    default:
      return null;
  }
}

String normalizeEndpointScheme(String? input, {String fallback = 'http'}) {
  final raw = (input ?? '').trim();
  if (raw.isEmpty) return fallback;
  final parsed = raw.contains('://') ? Uri.tryParse(raw) : null;
  final scheme = (parsed?.scheme ?? raw).trim().toLowerCase();
  switch (scheme) {
    case 'https':
    case 'wss':
      return 'https';
    case 'http':
    case 'ws':
      return 'http';
    default:
      return fallback;
  }
}

bool isPrivateOrLocalHost(String? input) {
  final host = (input ?? '').trim().toLowerCase();
  if (host.isEmpty) return true;
  if (host == 'localhost' || host == '0.0.0.0' || host == '::' || host == '::1') {
    return true;
  }
  if (host.endsWith('.local') || !host.contains('.')) {
    return true;
  }

  final parsed = InternetAddress.tryParse(host);
  if (parsed == null) {
    return false;
  }

  if (parsed.type == InternetAddressType.IPv4) {
    final octets = host.split('.');
    if (octets.length != 4) return false;
    final a = int.tryParse(octets[0]) ?? -1;
    final b = int.tryParse(octets[1]) ?? -1;
    if (a == 10 || a == 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;
    return false;
  }

  final normalized = host.replaceAll(RegExp(r'%.*$'), '');
  return normalized == '::1' ||
      normalized.startsWith('fe80:') ||
      normalized.startsWith('fc') ||
      normalized.startsWith('fd');
}

bool shouldPreferCompatibleRelayTransport(String? host) {
  final normalized = (host ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (normalized.endsWith('.trycloudflare.com')) return true;
  return !isPrivateOrLocalHost(normalized);
}

bool shouldRestrictToCompatibleRelayTransport(String? host) {
  final normalized = (host ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return shouldPreferCompatibleRelayTransport(normalized);
}

Uri resolveUriAgainstEndpoint(
  String raw, {
  required String scheme,
  required HostPort endpoint,
}) {
  final text = raw.trim();
  final normalizedScheme = normalizeEndpointScheme(scheme);
  final base = Uri(
    scheme: normalizedScheme,
    host: endpoint.host,
    port: endpoint.port,
    path: '/',
  );
  final parsed = Uri.tryParse(text);
  if (parsed == null || !parsed.hasScheme) {
    return base.resolve(text);
  }
  if (!_shouldRewriteAbsoluteOrigin(
    parsed,
    scheme: normalizedScheme,
    endpoint: endpoint,
  )) {
    return parsed;
  }
  return Uri(
    scheme: normalizedScheme,
    host: endpoint.host,
    port: endpoint.port,
    path: parsed.path.isEmpty ? '/' : parsed.path,
    query: parsed.hasQuery ? parsed.query : null,
    fragment: parsed.hasFragment ? parsed.fragment : null,
  );
}

bool _shouldRewriteAbsoluteOrigin(
  Uri uri, {
  required String scheme,
  required HostPort endpoint,
}) {
  final candidateHost = uri.host.trim().toLowerCase();
  final activeHost = endpoint.host.trim().toLowerCase();
  if (candidateHost.isEmpty || activeHost.isEmpty) return false;

  final activeIsPublic = !isPrivateOrLocalHost(activeHost);
  final candidateIsLocal = isPrivateOrLocalHost(candidateHost);
  final candidateScheme = normalizeEndpointScheme(uri.scheme, fallback: scheme);
  final candidatePort =
      uri.hasPort ? uri.port : (_defaultPortForEndpointScheme(uri.scheme) ?? endpoint.port);

  if (candidateHost == activeHost) {
    return candidateScheme != scheme || candidatePort != endpoint.port;
  }
  if (!activeIsPublic) {
    return false;
  }
  return candidateIsLocal;
}

HostPort? parseHostPort(
  String input, {
  int? defaultPort,
  bool requirePort = false,
}) {
  final raw = input.trim();
  if (raw.isEmpty) return null;

  if (raw.contains('://')) {
    final uri = Uri.tryParse(raw);
    final host = uri?.host.trim() ?? '';
    if (uri == null || host.isEmpty) return null;
    final inferredPort =
        uri.hasPort
            ? uri.port
            : (_defaultPortForEndpointScheme(uri.scheme) ?? defaultPort);
    if (inferredPort == null ||
        inferredPort <= 0 ||
        inferredPort > 65535) {
      return null;
    }
    return HostPort(host: host, port: inferredPort);
  }

  if (raw.startsWith('[')) {
    final end = raw.indexOf(']');
    if (end <= 1) return null;
    final host = raw.substring(1, end).trim();
    if (host.isEmpty) return null;

    if (end == raw.length - 1) {
      if (requirePort || defaultPort == null) return null;
      return HostPort(host: host, port: defaultPort);
    }

    if (raw.length <= end + 1 || raw[end + 1] != ':') return null;
    final port = int.tryParse(raw.substring(end + 2).trim());
    if (port == null || port <= 0 || port > 65535) return null;
    return HostPort(host: host, port: port);
  }

  final lastColon = raw.lastIndexOf(':');
  if (lastColon > 0 && raw.indexOf(':') == lastColon) {
    final host = raw.substring(0, lastColon).trim();
    final port = int.tryParse(raw.substring(lastColon + 1).trim());
    if (host.isNotEmpty && port != null && port > 0 && port <= 65535) {
      return HostPort(host: host, port: port);
    }
  }

  if (requirePort || defaultPort == null) return null;
  return HostPort(host: raw, port: defaultPort);
}
