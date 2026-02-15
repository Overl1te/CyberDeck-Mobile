import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../network/api_client.dart';

class ControlStatsData {
  final String cpu;
  final String ram;
  final double rttMs;
  final String lastError;

  const ControlStatsData({
    required this.cpu,
    required this.ram,
    required this.rttMs,
    required this.lastError,
  });

  static const ControlStatsData initial =
      ControlStatsData(cpu: '0%', ram: '', rttMs: 0, lastError: '');
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
        );
        return;
      }

      final cpu = decoded['cpu'];
      final ram = decoded['ram'] ??
          decoded['memory'] ??
          decoded['mem'] ??
          decoded['ram_used'];

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
      );
    } catch (e) {
      stats.value = ControlStatsData(
        cpu: stats.value.cpu,
        ram: stats.value.ram,
        rttMs: sw.elapsedMilliseconds.toDouble(),
        lastError: e.toString(),
      );
    } finally {
      _inFlight = false;
    }
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
