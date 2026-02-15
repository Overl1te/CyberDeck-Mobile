class HostPort {
  final String host;
  final int port;

  const HostPort({required this.host, required this.port});
}

HostPort? parseHostPort(
  String input, {
  int? defaultPort,
  bool requirePort = false,
}) {
  final raw = input.trim();
  if (raw.isEmpty) return null;

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
