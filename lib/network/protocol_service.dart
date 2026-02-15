import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../stream/stream_offer_parser.dart';
import 'api_client.dart';

class ProtocolService {
  static const int clientProtocolVersion = 1;

  Future<ProtocolNegotiationResult> fetchProtocol(ApiClient api) async {
    try {
      final response = await api.get(
        '/api/protocol',
        timeout: const Duration(seconds: 3),
      );
      if (response.statusCode == 404) {
        debugPrint('[CyberDeck][Protocol] /api/protocol 404 -> legacy mode');
        return ProtocolNegotiationResult.legacy();
      }
      if (response.statusCode != 200) {
        debugPrint(
          '[CyberDeck][Protocol] /api/protocol HTTP ${response.statusCode}, fallback to legacy mode',
        );
        return ProtocolNegotiationResult.legacy();
      }
      final payload = jsonDecode(response.body);
      final parsed = ProtocolNegotiationResult.fromPayload(payload);
      debugPrint(
        '[CyberDeck][Protocol] negotiated version=${parsed.protocolVersion ?? clientProtocolVersion} features=${parsed.features.join(',')}',
      );
      return parsed;
    } catch (e) {
      debugPrint(
        '[CyberDeck][Protocol] /api/protocol failed: $e, fallback to legacy mode',
      );
      return ProtocolNegotiationResult.legacy();
    }
  }
}
