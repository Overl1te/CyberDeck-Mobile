import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../network/api_client.dart';

class ControlStatsData {
  final String cpu;
  final String ram;
  final double rttMs;
  final String lastError;
  final int? volumePercent;
  final bool? volumeMuted;
  final bool? volumeSupported;

  const ControlStatsData({
    required this.cpu,
    required this.ram,
    required this.rttMs,
    required this.lastError,
    this.volumePercent,
    this.volumeMuted,
    this.volumeSupported,
  });

  static const ControlStatsData initial = ControlStatsData(
      cpu: '0%',
      ram: '',
      rttMs: 0,
      lastError: '',
      volumePercent: null,
      volumeMuted: null,
      volumeSupported: null);
}

class ControlStatsController {
  final ApiClient api;
  final Duration interval;
  final ValueNotifier<ControlStatsData> stats =
      ValueNotifier<ControlStatsData>(ControlStatsData.initial);

  Timer? _timer;
  bool _inFlight = false;

  ControlStatsController({
    required this.api,
    this.interval = const Duration(seconds: 3),
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    if (_inFlight) return;
    _inFlight = true;
    final sw = Stopwatch()..start();
    try {
      final response = await api.get(
        '/api/stats',
        timeout: const Duration(seconds: 3),
      );
      final rttMs = sw.elapsedMilliseconds.toDouble();
      if (response.statusCode != 200) {
        stats.value = ControlStatsData(
          cpu: stats.value.cpu,
          ram: stats.value.ram,
          rttMs: rttMs,
          lastError: 'stats HTTP ${response.statusCode}',
          volumePercent: stats.value.volumePercent,
          volumeMuted: stats.value.volumeMuted,
          volumeSupported: stats.value.volumeSupported,
        );
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        stats.value = ControlStatsData(
          cpu: stats.value.cpu,
          ram: stats.value.ram,
          rttMs: rttMs,
          lastError: 'stats invalid payload',
          volumePercent: stats.value.volumePercent,
          volumeMuted: stats.value.volumeMuted,
          volumeSupported: stats.value.volumeSupported,
        );
        return;
      }

      final cpu = decoded['cpu'];
      final ram = decoded['ram'] ??
          decoded['memory'] ??
          decoded['mem'] ??
          decoded['ram_used'];
      final volumePercent = _toInt(decoded['volume_percent']);
      final volumeMuted = _toBool(decoded['volume_muted']);
      final volumeSupported = _toBool(decoded['volume_supported']);

      var cpuLabel = stats.value.cpu;
      if (cpu != null) {
        cpuLabel =
            cpu is num ? '${cpu.toStringAsFixed(0)}%' : '${cpu.toString()}%';
      }

      var ramLabel = stats.value.ram;
      if (ram != null) {
        ramLabel = ram is num ? '${ram.toStringAsFixed(0)}%' : ram.toString();
      }

      stats.value = ControlStatsData(
        cpu: cpuLabel,
        ram: ramLabel,
        rttMs: rttMs,
        lastError: '',
        volumePercent: volumePercent ?? stats.value.volumePercent,
        volumeMuted: volumeMuted ?? stats.value.volumeMuted,
        volumeSupported: volumeSupported ?? stats.value.volumeSupported,
      );
    } catch (e) {
      stats.value = ControlStatsData(
        cpu: stats.value.cpu,
        ram: stats.value.ram,
        rttMs: sw.elapsedMilliseconds.toDouble(),
        lastError: e.toString(),
        volumePercent: stats.value.volumePercent,
        volumeMuted: stats.value.volumeMuted,
        volumeSupported: stats.value.volumeSupported,
      );
    } finally {
      _inFlight = false;
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString().trim());
  }

  bool? _toBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on' ||
        normalized == '1') {
      return true;
    }
    if (normalized == 'false' ||
        normalized == 'no' ||
        normalized == 'off' ||
        normalized == '0') {
      return false;
    }
    return null;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    stats.dispose();
  }
}
