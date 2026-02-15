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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await widget.loadSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _copyReport() async {
    final snap = _snapshot;
    if (snap == null) return;
    await Clipboard.setData(ClipboardData(text: snap.reportJson));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic report copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _copyReport,
            icon: const Icon(Icons.copy),
            tooltip: 'Copy diagnostic report',
          ),
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _snapshot;
    if (s == null) {
      return const Center(child: Text('No diagnostics available'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _row('Candidate', s.activeCandidate),
        _row('Backend', s.backend),
        _row('FPS', s.fps.toStringAsFixed(1)),
        _row('Decode', '${s.decodeMs} ms'),
        _row('RTT', '${s.rttMs.toStringAsFixed(0)} ms'),
        _row('Reconnects', s.reconnectCount.toString()),
        _row(
            'Protocol',
            s.legacyMode
                ? 'legacy'
                : (s.protocolVersion?.toString() ?? 'unknown')),
        _row('Last error', s.lastError.isEmpty ? 'none' : s.lastError),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _copyReport,
          icon: const Icon(Icons.copy),
          label: const Text('Copy diagnostic report'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
