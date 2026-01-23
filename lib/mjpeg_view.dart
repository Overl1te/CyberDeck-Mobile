import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MjpegView extends StatefulWidget {
  final String streamUrl;
  final Widget? errorBuilder;
  final Widget? loadingBuilder;

  const MjpegView({
    super.key,
    required this.streamUrl,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  ImageProvider? _image;
  StreamSubscription? _subscription;
  http.Client? _client;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _isVisible = false;
    _subscription?.cancel();
    _client?.close();
    super.dispose();
  }

  void _startStream() async {
    try {
      _client = http.Client();
      final request = http.Request("GET", Uri.parse(widget.streamUrl));
      final response = await _client!.send(request);

      List<int> buffer = [];
      
      _subscription = response.stream.listen((chunk) {
        if (!_isVisible) return;
        
        buffer.addAll(chunk);
        
        // Оптимизированный поиск заголовков JPEG
        // Ищем конец кадра (FF D9)
        int endIndex = -1;
        for (int i = 0; i < buffer.length - 1; i++) {
          if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
            endIndex = i + 2;
            break; // Берем первый же кадр
          }
        }

        if (endIndex != -1) {
          // Ищем начало (FF D8) внутри найденного куска
          int startIndex = -1;
          for (int i = 0; i < endIndex - 1; i++) {
             if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
               startIndex = i;
               break;
             }
          }

          if (startIndex != -1) {
            final frameBytes = Uint8List.fromList(buffer.sublist(startIndex, endIndex));
            
            if (mounted) {
              setState(() {
                _image = MemoryImage(frameBytes);
              });
            }
          }
          // ВАЖНО: Очищаем буфер полностью после кадра.
          // Если мы отстаем, лучше пропустить кадр, чем копить лаг.
          buffer.clear(); 
        }
        
        // Защита от переполнения памяти
        if (buffer.length > 500000) buffer.clear(); 
        
      }, onError: (e) {
        print("Stream error: $e");
      });

    } catch (e) {
      print("Connection error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return widget.loadingBuilder ?? 
          const Center(child: CircularProgressIndicator(color: Color(0xFF00FF9D)));
    }
    return Image(
      image: _image!,
      gaplessPlayback: true, // Убирает мерцание
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
    );
  }
}