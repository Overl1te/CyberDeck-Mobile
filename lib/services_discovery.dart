import 'dart:convert';
import 'dart:io';
import 'dart:async';

void _addBroadcastCandidate(Set<String> out, List<int> octets) {
  if (octets.length != 4) return;
  if (octets.any((value) => value < 0 || value > 255)) return;
  out.add('${octets[0]}.${octets[1]}.${octets[2]}.${octets[3]}');
}

Set<String> buildDiscoveryBroadcastAddresses(Iterable<String> ipv4Addresses) {
  final out = <String>{'255.255.255.255'};
  for (final raw in ipv4Addresses) {
    final parts = raw.trim().split('.');
    if (parts.length != 4) continue;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);
    final d = int.tryParse(parts[3]);
    if (a == null ||
        b == null ||
        c == null ||
        d == null ||
        a < 0 ||
        a > 255 ||
        b < 0 ||
        b > 255 ||
        c < 0 ||
        c > 255 ||
        d < 0 ||
        d > 255) {
      continue;
    }
    if (a == 127) continue;
    if (a == 169 && b == 254) continue;
    _addBroadcastCandidate(out, <int>[a, b, c, 255]);
    _addBroadcastCandidate(out, <int>[a, b, 255, 255]);
    if (a == 10) {
      _addBroadcastCandidate(out, <int>[10, 255, 255, 255]);
    } else if (a == 172 && b >= 16 && b <= 31) {
      _addBroadcastCandidate(out, <int>[172, 31, 255, 255]);
    } else if (a == 192 && b == 168) {
      _addBroadcastCandidate(out, <int>[192, 168, 255, 255]);
    } else if (a == 100 && b >= 64 && b <= 127) {
      _addBroadcastCandidate(out, <int>[100, 127, 255, 255]);
    }
  }
  return out;
}

class DiscoveredDevice {
  final String ip;
  final String name;
  final int port;
  final String version;

  DiscoveredDevice(this.ip, this.name, this.port, this.version);
}

class DiscoveryService {
  RawDatagramSocket? _socket;
  Timer? _probeTimer;
  final Set<InternetAddress> _broadcastTargets = <InternetAddress>{};
  final StreamController<DiscoveredDevice> _deviceController =
      StreamController.broadcast();

  Stream<DiscoveredDevice> get onDeviceFound => _deviceController.stream;

  Future<void> startScanning({Duration? timeout}) async {
    stop();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;

    _socket!.listen((RawSocketEvent e) {
      if (e == RawSocketEvent.read) {
        Datagram? d = _socket!.receive();
        if (d == null) return;

        try {
          String msg = utf8.decode(d.data);
          Map<String, dynamic> data = jsonDecode(msg);

          if (data.containsKey('id') && data.containsKey('name')) {
            final port = (data['port'] as num?)?.toInt() ?? 8080;
            final version = data['version']?.toString() ?? '';
            _deviceController.add(DiscoveredDevice(
              d.address.address,
              data['name'],
              port,
              version,
            ));
          }
        } catch (_) {}
      }
    });

    _broadcastTargets
      ..clear()
      ..addAll(await _resolveBroadcastTargets());
    _sendProbeBurst();
    var bursts = 1;
    _probeTimer = Timer.periodic(const Duration(milliseconds: 320), (timer) {
      if (_socket == null) {
        timer.cancel();
        _probeTimer = null;
        return;
      }
      if (bursts >= 3) {
        timer.cancel();
        _probeTimer = null;
        return;
      }
      bursts += 1;
      _sendProbeBurst();
    });

    if (timeout != null) {
      Future.delayed(timeout, stop);
    }
  }

  Future<Set<InternetAddress>> _resolveBroadcastTargets() async {
    final out = <InternetAddress>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          final value = addr.address.trim();
          if (value.isNotEmpty) {
            ips.add(value);
          }
        }
      }
      final targets = buildDiscoveryBroadcastAddresses(ips);
      for (final value in targets) {
        try {
          out.add(InternetAddress(value));
        } catch (_) {}
      }
    } catch (_) {
      out.add(InternetAddress('255.255.255.255'));
    }
    if (out.isEmpty) {
      out.add(InternetAddress('255.255.255.255'));
    }
    return out;
  }

  void _sendProbeBurst() {
    final socket = _socket;
    if (socket == null) return;
    final payload = utf8.encode('CYBERDECK_DISCOVER');
    if (_broadcastTargets.isEmpty) {
      try {
        socket.send(payload, InternetAddress('255.255.255.255'), 5555);
      } catch (_) {}
      return;
    }
    for (final target in _broadcastTargets) {
      try {
        socket.send(payload, target, 5555);
      } catch (_) {}
    }
  }

  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _socket?.close();
    _socket = null;
    _broadcastTargets.clear();
  }

  void dispose() {
    stop();
    _deviceController.close();
  }
}
