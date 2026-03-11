import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DiagnosticsSnapshot {
  final String activeCandidate;
  final String backend;
  final double fps;
  final int decodeMs;
  final double rttMs;
  final int reconnectCount;
  final String lastError;
  final bool legacyMode;
  final int? protocolVersion;
  final String reportJson;
  final int collectedAtMs;
  final String connectionState;
  final String streamStatus;
  final String audioStatus;

  const DiagnosticsSnapshot({
    required this.activeCandidate,
    required this.backend,
    required this.fps,
    required this.decodeMs,
    required this.rttMs,
    required this.reconnectCount,
    required this.lastError,
    required this.legacyMode,
    required this.protocolVersion,
    required this.reportJson,
    required this.collectedAtMs,
    required this.connectionState,
    required this.streamStatus,
    required this.audioStatus,
  });
}

class DiagnosticsScreen extends StatefulWidget {
  final Future<DiagnosticsSnapshot> Function() loadSnapshot;

  const DiagnosticsScreen({
    super.key,
    required this.loadSnapshot,
  });

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticsSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  bool _liveMode = true;
  final Duration _liveInterval = const Duration(seconds: 1);
  Timer? _liveTimer;
  final List<DiagnosticsSnapshot> _history = <DiagnosticsSnapshot>[];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh(silent: false));
    _restartLiveTimer();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  void _restartLiveTimer() {
    _liveTimer?.cancel();
    if (!_liveMode) return;
    _liveTimer = Timer.periodic(_liveInterval, (_) {
      unawaited(_refresh(silent: true));
    });
  }

  Future<void> _refresh({required bool silent}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final snap = await widget.loadSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
        _error = null;
        _history.add(snap);
        if (_history.length > 120) {
          _history.removeRange(0, _history.length - 120);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyReport() async {
    final snap = _snapshot;
    if (snap == null) return;
    await Clipboard.setData(ClipboardData(text: snap.reportJson));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Диагностический отчет скопирован')),
    );
  }

  _SeriesStats _statsFrom(Iterable<num> values) {
    var count = 0;
    var min = 0.0;
    var max = 0.0;
    var sum = 0.0;
    for (final value in values) {
      final v = value.toDouble();
      if (count == 0) {
        min = v;
        max = v;
      } else {
        if (v < min) min = v;
        if (v > max) max = v;
      }
      sum += v;
      count++;
    }
    if (count == 0) {
      return const _SeriesStats(min: 0, avg: 0, max: 0, count: 0);
    }
    return _SeriesStats(min: min, avg: sum / count, max: max, count: count);
  }

  String _formatStamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _snapshot != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_liveMode ? 'Диагностика (LIVE)' : 'Диагностика'),
        actions: [
          IconButton(
            onPressed: hasData ? _copyReport : null,
            icon: const Icon(Icons.copy),
            tooltip: 'Скопировать отчет',
          ),
          IconButton(
            onPressed: () {
              setState(() => _liveMode = !_liveMode);
              _restartLiveTimer();
            },
            icon: Icon(_liveMode ? Icons.pause_circle : Icons.play_circle),
            tooltip: _liveMode ? 'Пауза live' : 'Включить live',
          ),
          IconButton(
            onPressed: () => unawaited(_refresh(silent: false)),
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading && !hasData
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _snapshot;
    if (s == null) {
      return const Center(child: Text('Нет данных диагностики'));
    }

    final recent = _history.length <= 20
        ? _history
        : _history.sublist(_history.length - 20);
    final rttStats = _statsFrom(recent.map((item) => item.rttMs));
    final fpsStats = _statsFrom(recent.map((item) => item.fps));
    final decodeStats = _statsFrom(recent.map((item) => item.decodeMs));

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x22FF5A5A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x99FF5A5A)),
            ),
            child: Text(
              'Ошибка обновления live: $_error',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        _sectionCard(
          title: 'Текущий статус',
          child: Column(
            children: [
              _row('Время', _formatStamp(s.collectedAtMs)),
              _row('Состояние', s.connectionState),
              _row('Кандидат', s.activeCandidate),
              _row('Backend', s.backend),
              _row(
                  'Протокол',
                  s.legacyMode
                      ? 'legacy'
                      : (s.protocolVersion?.toString() ?? 'unknown')),
              _row('Stream статус',
                  s.streamStatus.isEmpty ? 'нет' : s.streamStatus),
              _row('Audio статус',
                  s.audioStatus.isEmpty ? 'нет' : s.audioStatus),
              _row('Последняя ошибка',
                  s.lastError.isEmpty ? 'нет' : s.lastError),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _sectionCard(
          title: 'Реал-тайм метрики',
          subtitle: 'Окно: ${recent.length} сэмплов',
          child: Column(
            children: [
              _trendRow('RTT (ms)', rttStats),
              const SizedBox(height: 8),
              _trendRow('FPS', fpsStats),
              const SizedBox(height: 8),
              _trendRow('Decode (ms)', decodeStats),
              const SizedBox(height: 8),
              _row('Reconnect count', s.reconnectCount.toString()),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _sectionCard(
          title: 'Последние сэмплы',
          subtitle: 'Новые сверху',
          child: Column(
            children: recent.reversed.take(12).map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        _formatStamp(item.collectedAtMs),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'FPS ${item.fps.toStringAsFixed(1)} | '
                        'RTT ${item.rttMs.toStringAsFixed(0)} ms | '
                        'DEC ${item.decodeMs} ms',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(growable: false),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _copyReport,
          icon: const Icon(Icons.copy),
          label: const Text('Скопировать диагностический отчет'),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141A17),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _trendRow(String label, _SeriesStats stats) {
    final suffix = stats.count <= 0
        ? 'нет данных'
        : 'min ${stats.min.toStringAsFixed(1)} | '
            'avg ${stats.avg.toStringAsFixed(1)} | '
            'max ${stats.max.toStringAsFixed(1)}';
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            suffix,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

class _SeriesStats {
  final double min;
  final double avg;
  final double max;
  final int count;

  const _SeriesStats({
    required this.min,
    required this.avg,
    required this.max,
    required this.count,
  });
}
