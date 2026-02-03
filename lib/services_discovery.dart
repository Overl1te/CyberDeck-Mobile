import 'dart:convert';
import 'dart:io';
import 'dart:async';

class DiscoveredDevice {
  final String ip;
  final String name;
  final int port;
  final String version;

  DiscoveredDevice(this.ip, this.name, this.port, this.version);
}

class DiscoveryService {
  RawDatagramSocket? _socket;
  final StreamController<DiscoveredDevice> _deviceController = StreamController.broadcast();

  Stream<DiscoveredDevice> get onDeviceFound => _deviceController.stream;

  Future<void> startScanning({Duration? timeout}) async {
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

    final data = utf8.encode("CYBERDECK_DISCOVER");
    _socket!.send(data, InternetAddress('255.255.255.255'), 5555);

    if (timeout != null) {
      Future.delayed(timeout, stop);
    }
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stop();
    _deviceController.close();
  }
}
