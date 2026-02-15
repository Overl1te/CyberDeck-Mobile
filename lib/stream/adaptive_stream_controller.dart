import 'dart:math';

import 'stream_offer_parser.dart';

enum AdaptiveSwitchReason {
  none,
  fpsDrop,
  rttHigh,
  recovered,
}

class AdaptiveDecision {
  final AdaptiveSwitchReason reason;
  final int oldWidth;
  final int newWidth;
  final bool switched;
  final bool cooldownBlocked;
  final int lastSwitchMsAgo;
  final int sustainedBadMs;
  final int sustainedGoodMs;
  final double currentRttMs;
  final double effectiveFps;

  const AdaptiveDecision({
    required this.reason,
    required this.oldWidth,
    required this.newWidth,
    required this.switched,
    required this.cooldownBlocked,
    required this.lastSwitchMsAgo,
    required this.sustainedBadMs,
    required this.sustainedGoodMs,
    required this.currentRttMs,
    required this.effectiveFps,
  });

  String get reasonLabel {
    switch (reason) {
      case AdaptiveSwitchReason.fpsDrop:
        return 'fps_drop';
      case AdaptiveSwitchReason.rttHigh:
        return 'rtt_high';
      case AdaptiveSwitchReason.recovered:
        return 'recovered';
      case AdaptiveSwitchReason.none:
        return 'none';
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'reason': reasonLabel,
      'old_profile': oldWidth,
      'new_profile': newWidth,
      'switched': switched,
      'cooldown_blocked': cooldownBlocked,
      'last_switch_ms_ago': lastSwitchMsAgo,
      'sustained_bad_ms': sustainedBadMs,
      'sustained_good_ms': sustainedGoodMs,
      'current_rtt_ms': currentRttMs,
      'effective_fps': effectiveFps,
    };
  }
}

class AdaptiveStreamController {
  final List<int> _ladder;
  final int _targetFps;
  final int _rttHighMs;
  final int _rttLowMs;
  final int _minSwitchIntervalMs;
  final double _hysteresisRatio;
  final int _downgradeSustainMs;
  final int _upgradeSustainMs;
  final int _minRecoveredSustainMs;
  final double _fpsDropThreshold;

  int _currentWidth;
  int? _lastSwitchAtMs;
  int _badMs = 0;
  int _goodMs = 0;

  AdaptiveStreamController({
    required List<int> ladder,
    required int targetFps,
    required int initialWidth,
    required int rttHighMs,
    required int rttLowMs,
    required int minSwitchIntervalMs,
    required double hysteresisRatio,
    required int downgradeSustainMs,
    required int upgradeSustainMs,
    int minRecoveredSustainMs = 0,
    required double fpsDropThreshold,
  })  : _ladder = List<int>.from(ladder)..sort((a, b) => b.compareTo(a)),
        _targetFps = max(1, targetFps),
        _rttHighMs = max(60, rttHighMs),
        _rttLowMs = min(max(40, rttLowMs), max(60, rttHighMs)),
        _minSwitchIntervalMs = max(500, minSwitchIntervalMs),
        _hysteresisRatio = hysteresisRatio.clamp(0.01, 0.95),
        _downgradeSustainMs = max(500, downgradeSustainMs),
        _upgradeSustainMs = max(500, upgradeSustainMs),
        _minRecoveredSustainMs = max(0, minRecoveredSustainMs),
        _fpsDropThreshold = fpsDropThreshold.clamp(0.3, 0.95),
        _currentWidth = initialWidth {
    _currentWidth = _normalizeWidth(_currentWidth);
  }

  factory AdaptiveStreamController.fromHint({
    required StreamAdaptiveHint hint,
    required int targetFps,
    required int initialWidth,
    int minSwitchIntervalFloorMs = 0,
    int minRecoveredSustainMs = 0,
  }) {
    return AdaptiveStreamController(
      ladder: hint.widthLadder,
      targetFps: targetFps,
      initialWidth: initialWidth,
      rttHighMs: hint.rttHighMs,
      rttLowMs: hint.rttLowMs,
      minSwitchIntervalMs:
          max(hint.minSwitchIntervalMs, max(0, minSwitchIntervalFloorMs)),
      hysteresisRatio: hint.hysteresisRatio,
      downgradeSustainMs: hint.downgradeSustainMs,
      upgradeSustainMs: hint.upgradeSustainMs,
      minRecoveredSustainMs: minRecoveredSustainMs,
      fpsDropThreshold: hint.fpsDropThreshold,
    );
  }

  int get currentWidth => _currentWidth;
  List<int> get ladder => List<int>.unmodifiable(_ladder);
  int get minSwitchIntervalMs => _minSwitchIntervalMs;
  double get hysteresisRatio => _hysteresisRatio;

  AdaptiveDecision evaluate({
    required int nowMs,
    required double effectiveFps,
    required double rttMs,
    required int sampleIntervalMs,
  }) {
    final sampleMs = max(200, sampleIntervalMs);
    final fpsBad = effectiveFps > 0 &&
        effectiveFps < _targetFps.toDouble() * _fpsDropThreshold;
    final rttBad = rttMs > 0 && rttMs >= _rttHighMs;
    final bad = fpsBad || rttBad;
    final good = !bad &&
        (effectiveFps <= 0 || effectiveFps >= _targetFps.toDouble() * 0.9) &&
        (rttMs <= 0 || rttMs <= _rttLowMs);

    if (bad) {
      _badMs += sampleMs;
      _goodMs = 0;
    } else if (good) {
      _goodMs += sampleMs;
      _badMs = 0;
    } else {
      _badMs = 0;
      _goodMs = 0;
    }

    AdaptiveSwitchReason reason = AdaptiveSwitchReason.none;
    bool downgrade = false;
    final recoveredThresholdMs = max(_upgradeSustainMs, _minRecoveredSustainMs);

    if (_badMs >= _downgradeSustainMs) {
      reason =
          rttBad ? AdaptiveSwitchReason.rttHigh : AdaptiveSwitchReason.fpsDrop;
      downgrade = true;
    } else if (_goodMs >= recoveredThresholdMs) {
      reason = AdaptiveSwitchReason.recovered;
      downgrade = false;
    }

    var cooldownBlocked = false;
    final lastSwitchMsAgo =
        _lastSwitchAtMs == null ? -1 : nowMs - _lastSwitchAtMs!;
    if (reason == AdaptiveSwitchReason.none) {
      return AdaptiveDecision(
        reason: reason,
        oldWidth: _currentWidth,
        newWidth: _currentWidth,
        switched: false,
        cooldownBlocked: false,
        lastSwitchMsAgo: lastSwitchMsAgo,
        sustainedBadMs: _badMs,
        sustainedGoodMs: _goodMs,
        currentRttMs: rttMs,
        effectiveFps: effectiveFps,
      );
    }

    final nextWidth = downgrade
        ? _selectNextLowerByHysteresis(_currentWidth)
        : _selectNextUpperByHysteresis(_currentWidth);
    if (nextWidth == null || nextWidth == _currentWidth) {
      return AdaptiveDecision(
        reason: reason,
        oldWidth: _currentWidth,
        newWidth: _currentWidth,
        switched: false,
        cooldownBlocked: false,
        lastSwitchMsAgo: lastSwitchMsAgo,
        sustainedBadMs: _badMs,
        sustainedGoodMs: _goodMs,
        currentRttMs: rttMs,
        effectiveFps: effectiveFps,
      );
    }

    if (_lastSwitchAtMs != null && lastSwitchMsAgo < _minSwitchIntervalMs) {
      cooldownBlocked = true;
      return AdaptiveDecision(
        reason: reason,
        oldWidth: _currentWidth,
        newWidth: nextWidth,
        switched: false,
        cooldownBlocked: cooldownBlocked,
        lastSwitchMsAgo: lastSwitchMsAgo,
        sustainedBadMs: _badMs,
        sustainedGoodMs: _goodMs,
        currentRttMs: rttMs,
        effectiveFps: effectiveFps,
      );
    }

    final sustainedBadMs = _badMs;
    final sustainedGoodMs = _goodMs;
    final old = _currentWidth;
    _currentWidth = nextWidth;
    _lastSwitchAtMs = nowMs;
    _badMs = 0;
    _goodMs = 0;
    return AdaptiveDecision(
      reason: reason,
      oldWidth: old,
      newWidth: nextWidth,
      switched: true,
      cooldownBlocked: cooldownBlocked,
      lastSwitchMsAgo: lastSwitchMsAgo,
      sustainedBadMs: sustainedBadMs,
      sustainedGoodMs: sustainedGoodMs,
      currentRttMs: rttMs,
      effectiveFps: effectiveFps,
    );
  }

  int _normalizeWidth(int width) {
    for (final candidate in _ladder) {
      if (candidate <= width) return candidate;
    }
    return _ladder.isEmpty ? width : _ladder.last;
  }

  int? _selectNextLowerByHysteresis(int current) {
    if (_ladder.isEmpty) return null;
    final minDelta = max(1.0, current * _hysteresisRatio);
    for (final width in _ladder) {
      if (width >= current) continue;
      if ((current - width) >= minDelta) return width;
    }
    return null;
  }

  int? _selectNextUpperByHysteresis(int current) {
    if (_ladder.isEmpty) return null;
    final minDelta = max(1.0, current * _hysteresisRatio);
    for (var i = _ladder.length - 1; i >= 0; i--) {
      final width = _ladder[i];
      if (width <= current) continue;
      if ((width - current) >= minDelta) return width;
    }
    return null;
  }
}
