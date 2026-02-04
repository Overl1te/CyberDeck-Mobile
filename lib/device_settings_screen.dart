import 'package:flutter/material.dart';

import 'device_storage.dart';
import 'theme.dart';

class DeviceSettingsScreen extends StatefulWidget {
  final SavedDevice device;
  const DeviceSettingsScreen({super.key, required this.device});

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  bool _loading = true;
  late DeviceSettings _s;
  late TextEditingController _alias;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await DeviceStorage.getDeviceSettings(widget.device.id);
    _alias = TextEditingController(text: s.alias);
    if (!mounted) return;
    setState(() {
      _s = s;
      _loading = false;
    });
  }

  @override
  void dispose() {
    if (!_loading) _alias.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = _s.copyWith(alias: _alias.text.trim());
    await DeviceStorage.saveDeviceSettings(widget.device.id, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u0421\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u043e'), backgroundColor: Colors.green));
  }

  Future<void> _reset() async {
    setState(() {
      _s = DeviceSettings.defaults();
      _alias.text = '';
    });
    await DeviceStorage.saveDeviceSettings(widget.device.id, _s);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.device.name;

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: Text('\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438: $title'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reset),
          IconButton(icon: const Icon(Icons.save), onPressed: _loading ? null : _save),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccentColor))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('\u0418\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441'),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('\u0418\u043c\u044f (\u043d\u0435\u043e\u0431\u044f\u0437\u0430\u0442\u0435\u043b\u044c\u043d\u043e)', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _alias,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF111111),
                          hintText: '\u0418\u043c\u044f \u0432 \u0441\u043f\u0438\u0441\u043a\u0435',
                          hintStyle: TextStyle(color: Colors.grey[700]),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                _section('\u0422\u0430\u0447\u043f\u0430\u0434'),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sliderRow(
                        label: '\u0427\u0443\u0432\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u044c\u043d\u043e\u0441\u0442\u044c',
                        value: _s.touchSensitivity,
                        min: 0.5,
                        max: 5.0,
                        divisions: 18,
                        format: (v) => v.toStringAsFixed(2),
                        onChanged: (v) => setState(() => _s = _s.copyWith(touchSensitivity: v)),
                      ),
                      const SizedBox(height: 12),
                      _sliderRow(
                        label: '\u0421\u043a\u043e\u0440\u043e\u0441\u0442\u044c \u0441\u043a\u0440\u043e\u043b\u043b\u0430',
                        value: _s.scrollFactor,
                        min: 1.0,
                        max: 10.0,
                        divisions: 18,
                        format: (v) => v.toStringAsFixed(1),
                        onChanged: (v) => setState(() => _s = _s.copyWith(scrollFactor: v)),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: _s.haptics,
                        onChanged: (v) => setState(() => _s = _s.copyWith(haptics: v)),
                        title: const Text('\u0412\u0438\u0431\u0440\u043e\u043e\u0442\u043a\u043b\u0438\u043a'),
                        subtitle: const Text('\u0412\u0438\u0431\u0440\u0430\u0446\u0438\u044f \u043f\u0440\u0438 \u043d\u0430\u0436\u0430\u0442\u0438\u044f\u0445', style: TextStyle(color: Colors.grey)),
                        activeColor: kAccentColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                _section('\u041f\u0435\u0440\u0435\u0434\u0430\u0447\u0430 \u0444\u0430\u0439\u043b\u043e\u0432'),
                _card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _s.confirmDownloads,
                        onChanged: (v) => setState(() => _s = _s.copyWith(confirmDownloads: v)),
                        title: const Text('\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0430\u0442\u044c \u0441\u043a\u0430\u0447\u0438\u0432\u0430\u043d\u0438\u0435'),
                        subtitle: const Text('\u0421\u043f\u0440\u0430\u0448\u0438\u0432\u0430\u0442\u044c \u043f\u0435\u0440\u0435\u0434 \u0441\u043a\u0430\u0447\u0438\u0432\u0430\u043d\u0438\u0435\u043c \u0441 \u041f\u041a', style: TextStyle(color: Colors.grey)),
                        activeColor: kAccentColor,
                      ),
                      SwitchListTile(
                        value: _s.browserFallback,
                        onChanged: (v) => setState(() => _s = _s.copyWith(browserFallback: v)),
                        title: const Text('\u041e\u0442\u043a\u0440\u044b\u0432\u0430\u0442\u044c \u0432 \u0431\u0440\u0430\u0443\u0437\u0435\u0440\u0435'),
                        subtitle: const Text('\u0415\u0441\u043b\u0438 \u043f\u0440\u0430\u0432\u0430 \u043d\u0430 \u043f\u0430\u043c\u044f\u0442\u044c \u043d\u0435 \u0434\u0430\u043b\u0438, \u043e\u0442\u043a\u0440\u044b\u0442\u044c \u0441\u0441\u044b\u043b\u043a\u0443 \u0432 \u0431\u0440\u0430\u0443\u0437\u0435\u0440\u0435', style: TextStyle(color: Colors.grey)),
                        activeColor: kAccentColor,
                      ),
                      ListTile(
                        title: const Text('\u0420\u0435\u0436\u0438\u043c \u043f\u0435\u0440\u0435\u0434\u0430\u0447\u0438'),
                        subtitle: const Text('\u0412\u043b\u0438\u044f\u0435\u0442 \u043d\u0430 \u0437\u0430\u0434\u0435\u0440\u0436\u043a\u0438/\u0444\u043e\u043b\u0431\u044d\u043a\u0438', style: TextStyle(color: Colors.grey)),
                        trailing: DropdownButton<String>(
                          value: _s.transferPreset,
                          dropdownColor: kPanelColor,
                          items: const [
                            DropdownMenuItem(value: 'fast', child: Text('\u0411\u044b\u0441\u0442\u0440\u043e')),
                            DropdownMenuItem(value: 'balanced', child: Text('\u0421\u0431\u0430\u043b\u0430\u043d\u0441\u0438\u0440\u043e\u0432\u0430\u043d\u043e')),
                            DropdownMenuItem(value: 'safe', child: Text('\u041d\u0430\u0434\u0435\u0436\u043d\u043e')),
                            DropdownMenuItem(value: 'ultra_safe', child: Text('\u041c\u0430\u043a\u0441. \u043d\u0430\u0434\u0435\u0436\u043d\u043e')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _s = _s.copyWith(transferPreset: v));
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                _card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline, color: kAccentColor),
                    title: const Text('\u0414\u0430\u043d\u043d\u044b\u0435 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u044f'),
                    subtitle: Text('${widget.device.ip}:${widget.device.port}', style: const TextStyle(color: Colors.grey, fontFamily: 'monospace')),
                  ),
                ),

                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: kAccentColor, foregroundColor: Colors.black),
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('\u0421\u041e\u0425\u0420\u0410\u041d\u0418\u0422\u042c', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),

                _section('\u0412\u0438\u0434\u0435\u043e'),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _slider(
                        label: '\u041c\u0430\u043a\u0441. \u0448\u0438\u0440\u0438\u043d\u0430 (px)',
                        value: _s.streamMaxWidth.toDouble(),
                        min: 480,
                        max: 1920,
                        divisions: 18,
                        format: (v) => v.toInt().toString(),
                        onChanged: (v) => setState(() => _s = _s.copyWith(streamMaxWidth: v.toInt())),
                      ),
                      _slider(
                        label: '\u041a\u0430\u0447\u0435\u0441\u0442\u0432\u043e JPEG',
                        value: _s.streamQuality.toDouble(),
                        min: 10,
                        max: 70,
                        divisions: 60,
                        format: (v) => v.toInt().toString(),
                        onChanged: (v) => setState(() => _s = _s.copyWith(streamQuality: v.toInt())),
                      ),
                      _slider(
                        label: 'FPS',
                        value: _s.streamFps.toDouble(),
                        min: 5,
                        max: 60,
                        divisions: 55,
                        format: (v) => v.toInt().toString(),
                        onChanged: (v) => setState(() => _s = _s.copyWith(streamFps: v.toInt())),
                      ),
                      SwitchListTile(
                        value: _s.showCursor,
                        onChanged: (v) => setState(() => _s = _s.copyWith(showCursor: v)),
                        title: const Text('\u041f\u043e\u043a\u0430\u0437\u044b\u0432\u0430\u0442\u044c \u043a\u0443\u0440\u0441\u043e\u0440'),
                        subtitle: const Text('\u0414\u043e\u0431\u0430\u0432\u043b\u044f\u0435\u0442 \u043e\u0432\u0435\u0440\u043b\u0435\u0439 \u043a\u0443\u0440\u0441\u043e\u0440\u0430 \u043f\u043e\u0432\u0435\u0440\u0445 \u043f\u043e\u0442\u043e\u043a\u0430', style: TextStyle(color: Colors.grey)),
                        activeColor: kAccentColor,
                      ),
                      SwitchListTile(
                        value: _s.lowLatency,
                        onChanged: (v) => setState(() => _s = _s.copyWith(lowLatency: v)),
                        title: const Text('\u041d\u0438\u0437\u043a\u0430\u044f \u0437\u0430\u0434\u0435\u0440\u0436\u043a\u0430'),
                        subtitle: const Text('\u0410\u0433\u0440\u0435\u0441\u0441\u0438\u0432\u043d\u043e \u043f\u0440\u043e\u043f\u0443\u0441\u043a\u0430\u0442\u044c \u043a\u0430\u0434\u0440\u044b, \u0447\u0442\u043e\u0431\u044b \u043d\u0435 \u043a\u043e\u043f\u0438\u0442\u044c \u043b\u0430\u0433', style: TextStyle(color: Colors.grey)),
                        activeColor: kAccentColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(title.toUpperCase(), style: const TextStyle(color: kAccentColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
      );

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kPanelColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: child,
      );

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
            Text(format(value), style: const TextStyle(color: Colors.grey, fontFamily: 'monospace')),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: kAccentColor,
          onChanged: onChanged,
        )
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    return _sliderRow(
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      format: format,
      onChanged: onChanged,
    );
  }
}
