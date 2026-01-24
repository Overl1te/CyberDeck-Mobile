import 'dart:convert';
import 'dart:io';
import 'dart:async';

class DiscoveredDevice {
  final String ip;
  final String name;
  final int port;

  DiscoveredDevice(this.ip, this.name, this.port);
}

class DiscoveryService {
  RawDatagramSocket? _socket;
  final StreamController<DiscoveredDevice> _deviceController = StreamController.broadcast();

  Stream<DiscoveredDevice> get onDeviceFound => _deviceController.stream;

  Future<void> startScanning() async {
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
            _deviceController.add(DiscoveredDevice(
              d.address.address, // IP отправителя
              data['name'],
              data['port']
            ));
          }
        } catch (_) {} 
      }
    });

    // Отправляем запрос "Кто здесь?"
    final data = utf8.encode("CYBERDECK_DISCOVER");
    _socket!.send(data, InternetAddress('255.255.255.255'), 5555);
  }

  void stop() {
    _socket?.close();
    _deviceController.close();
  }
}