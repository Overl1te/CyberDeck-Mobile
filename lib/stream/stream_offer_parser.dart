class ParsedStreamCandidate {
  final Uri uri;
  final String mime;
  final String transport;
  final String backend;
  final String signature;

  const ParsedStreamCandidate({
    required this.uri,
    required this.mime,
    required this.transport,
    required this.backend,
    required this.signature,
  });
}

class ProtocolNegotiationResult {
  final bool legacyMode;
  final int? protocolVersion;
  final int? minSupportedProtocolVersion;
  final Set<String> features;

  const ProtocolNegotiationResult({
    required this.legacyMode,
    required this.protocolVersion,
    required this.minSupportedProtocolVersion,
    required this.features,
  });

  factory ProtocolNegotiationResult.legacy() {
    return const ProtocolNegotiationResult(
      legacyMode: true,
      protocolVersion: null,
      minSupportedProtocolVersion: null,
      features: <String>{},
    );
  }

  factory ProtocolNegotiationResult.fromPayload(dynamic payload) {
    if (payload is! Map) {
      return ProtocolNegotiationResult.legacy();
    }
    final data = _normalizeMap(payload);
    return ProtocolNegotiationResult(
      legacyMode: false,
      protocolVersion: _toInt(data['protocol_version']),
      minSupportedProtocolVersion:
          _toInt(data['min_supported_protocol_version']),
      features: _parseFeatures(data['features']),
    );
  }
}

class StreamFallbackPolicy {
  final int candidateTimeoutMs;
  final int stallSeconds;

  const StreamFallbackPolicy({
    required this.candidateTimeoutMs,
    required this.stallSeconds,
  });
}

class StreamAdaptiveHint {
  static const List<int> defaultWidthLadder = <int>[
    1920,
    1600,
    1440,
    1366,
    1280,
    1152,
    1024,
    960,
    854,
    768,
    640,
  ];

  final int minFps;
  final int minMaxWidth;
  final int minQuality;
  final int maxFps;
  final int maxMaxWidth;
  final int maxQuality;
  final int downStepFps;
  final int downStepMaxWidth;
  final int downStepQuality;
  final int upStepFps;
  final int upStepMaxWidth;
  final int upStepQuality;
  final int rttHighMs;
  final int rttLowMs;
  final double fpsDropThreshold;
  final double lowFpsRatio;
  final int stableWindowSeconds;
  final List<int> widthLadder;
  final int minSwitchIntervalMs;
  final double hysteresisRatio;
  final int minWidthFloor;
  final int downgradeSustainMs;
  final int upgradeSustainMs;
  final bool preferQualityBeforeResize;

  const StreamAdaptiveHint({
    required this.minFps,
    required this.minMaxWidth,
    required this.minQuality,
    required this.maxFps,
    required this.maxMaxWidth,
    required this.maxQuality,
    required this.downStepFps,
    required this.downStepMaxWidth,
    required this.downStepQuality,
    required this.upStepFps,
    required this.upStepMaxWidth,
    required this.upStepQuality,
    required this.rttHighMs,
    required this.rttLowMs,
    required this.fpsDropThreshold,
    required this.lowFpsRatio,
    required this.stableWindowSeconds,
    required this.widthLadder,
    required this.minSwitchIntervalMs,
    required this.hysteresisRatio,
    required this.minWidthFloor,
    required this.downgradeSustainMs,
    required this.upgradeSustainMs,
    required this.preferQualityBeforeResize,
  });

  factory StreamAdaptiveHint.defaults({
    required int baseFps,
    required int baseMaxWidth,
    required int baseQuality,
  }) {
    return StreamAdaptiveHint(
      minFps: 10,
      minMaxWidth: 640,
      minQuality: 25,
      maxFps: baseFps,
      maxMaxWidth: baseMaxWidth,
      maxQuality: baseQuality,
      downStepFps: 5,
      downStepMaxWidth: 160,
      downStepQuality: 8,
      upStepFps: 3,
      upStepMaxWidth: 120,
      upStepQuality: 5,
      rttHighMs: 300,
      rttLowMs: 140,
      fpsDropThreshold: 0.6,
      lowFpsRatio: 0.6,
      stableWindowSeconds: 8,
      widthLadder: _normalizedWidthLadder(
        defaultWidthLadder,
        minWidthFloor: 640,
        maxWidthCeiling: baseMaxWidth,
      ),
      minSwitchIntervalMs: 6500,
      hysteresisRatio: 0.12,
      minWidthFloor: 640,
      downgradeSustainMs: 3000,
      upgradeSustainMs: 8000,
      preferQualityBeforeResize: false,
    );
  }

  int normalizeWidth(int width) {
    if (widthLadder.isEmpty) return width.clamp(minWidthFloor, maxMaxWidth);
    for (final candidate in widthLadder) {
      if (candidate <= width) return candidate;
    }
    return widthLadder.last;
  }
}

class ParsedStreamOffer {
  final List<ParsedStreamCandidate> candidates;
  final StreamFallbackPolicy fallbackPolicy;
  final StreamAdaptiveHint adaptiveHint;
  final int reconnectHintMs;
  final int? protocolVersion;
  final int? minSupportedProtocolVersion;
  final Set<String> features;
  final String backend;
  final Map<String, dynamic> raw;

  const ParsedStreamOffer({
    required this.candidates,
    required this.fallbackPolicy,
    required this.adaptiveHint,
    required this.reconnectHintMs,
    required this.protocolVersion,
    required this.minSupportedProtocolVersion,
    required this.features,
    required this.backend,
    required this.raw,
  });
}

ParsedStreamOffer parseStreamOffer(
  dynamic payload, {
  required Uri Function(String raw) resolveCandidateUri,
  required String token,
  bool includeAuthQueryToken = false,
  bool lowLatency = true,
  required int maxWidth,
  required int quality,
  required int fps,
}) {
  final fallback = StreamAdaptiveHint.defaults(
    baseFps: fps,
    baseMaxWidth: maxWidth,
    baseQuality: quality,
  );
  if (payload is! Map) {
    return ParsedStreamOffer(
      candidates: const <ParsedStreamCandidate>[],
      fallbackPolicy: const StreamFallbackPolicy(
        candidateTimeoutMs: 2800,
        stallSeconds: 8,
      ),
      adaptiveHint: fallback,
      reconnectHintMs: 1200,
      protocolVersion: null,
      minSupportedProtocolVersion: null,
      features: const <String>{},
      backend: 'unknown',
      raw: const <String, dynamic>{},
    );
  }

  final data = _normalizeMap(payload);
  final backend = _toNonEmptyString(
        data['backend'] ?? data['stream_backend'] ?? data['active_backend'],
      ) ??
      'unknown';

  final parsedCandidates = _parseCandidates(
    data,
    resolveCandidateUri: resolveCandidateUri,
    token: token,
    includeAuthQueryToken: includeAuthQueryToken,
    lowLatency: lowLatency,
    maxWidth: maxWidth,
    quality: quality,
    fps: fps,
    defaultBackend: backend,
  );

  final fallbackPolicy = _parseFallbackPolicy(data);
  final adaptiveHint = _parseAdaptiveHint(
    data,
    fallback: fallback,
    baseFps: fps,
    baseMaxWidth: maxWidth,
    baseQuality: quality,
  );

  return ParsedStreamOffer(
    candidates: parsedCandidates,
    fallbackPolicy: fallbackPolicy,
    adaptiveHint: adaptiveHint,
    reconnectHintMs:
        (_toInt(data['reconnect_hint_ms']) ?? 1200).clamp(100, 30000),
    protocolVersion: _toInt(data['protocol_version']),
    minSupportedProtocolVersion: _toInt(data['min_supported_protocol_version']),
    features: _parseFeatures(data['features']),
    backend: backend,
    raw: data,
  );
}

List<ParsedStreamCandidate> parseStreamOfferCandidates(
  dynamic payload, {
  required Uri Function(String raw) resolveCandidateUri,
  required String token,
  bool includeAuthQueryToken = false,
  bool lowLatency = true,
  required int maxWidth,
  required int quality,
  required int fps,
}) {
  return parseStreamOffer(
    payload,
    resolveCandidateUri: resolveCandidateUri,
    token: token,
    includeAuthQueryToken: includeAuthQueryToken,
    lowLatency: lowLatency,
    maxWidth: maxWidth,
    quality: quality,
    fps: fps,
  ).candidates;
}

List<ParsedStreamCandidate> appendFallbackCandidateIfMissing({
  required List<ParsedStreamCandidate> candidates,
  required ParsedStreamCandidate fallback,
}) {
  final exists = candidates.any((c) => c.signature == fallback.signature);
  if (exists) return candidates;
  return <ParsedStreamCandidate>[...candidates, fallback];
}

Set<String> _parseFeatures(dynamic raw) {
  final out = <String>{};
  if (raw is List) {
    for (final feature in raw) {
      final value = _toNonEmptyString(feature);
      if (value != null) {
        out.add(value);
      }
    }
    return out;
  }
  if (raw is Map) {
    raw.forEach((key, value) {
      final feature = _toNonEmptyString(key);
      if (feature == null) return;
      if (_toBool(value) == true) {
        out.add(feature);
      }
    });
    return out;
  }
  return const <String>{};
}

List<ParsedStreamCandidate> _parseCandidates(
  Map<String, dynamic> payload, {
  required Uri Function(String raw) resolveCandidateUri,
  required String token,
  required bool includeAuthQueryToken,
  required bool lowLatency,
  required int maxWidth,
  required int quality,
  required int fps,
  required String defaultBackend,
}) {
  final rawCandidates = payload['candidates'];
  if (rawCandidates is! List) return const <ParsedStreamCandidate>[];

  final out = <ParsedStreamCandidate>[];
  for (final raw in rawCandidates) {
    if (raw is! Map) continue;
    final normalized = _normalizeMap(raw);
    final parsed = _parseOne(
      normalized,
      resolveCandidateUri: resolveCandidateUri,
      token: token,
      includeAuthQueryToken: includeAuthQueryToken,
      lowLatency: lowLatency,
      maxWidth: maxWidth,
      quality: quality,
      fps: fps,
      defaultBackend: defaultBackend,
    );
    if (parsed != null) {
      out.add(parsed);
    }
  }
  return out;
}

StreamFallbackPolicy _parseFallbackPolicy(Map<String, dynamic> payload) {
  final raw = payload['fallback_policy'];
  if (raw is String) {
    final mode = raw.trim().toLowerCase();
    if (mode == 'ordered_candidates' || mode == 'ordered') {
      return const StreamFallbackPolicy(
          candidateTimeoutMs: 2800, stallSeconds: 8);
    }
  }
  if (raw is! Map) {
    return const StreamFallbackPolicy(
        candidateTimeoutMs: 2800, stallSeconds: 8);
  }
  final map = _normalizeMap(raw);
  final timeoutMs = _toInt(
        map['candidate_timeout_ms'] ??
            map['candidate_fail_timeout_ms'] ??
            map['switch_timeout_ms'],
      )?.clamp(1600, 12000) ??
      2800;
  final stallSeconds = _toInt(
        map['stall_seconds'] ??
            map['stall_timeout_s'] ??
            map['stall_timeout_sec'],
      )?.clamp(4, 20) ??
      8;
  return StreamFallbackPolicy(
    candidateTimeoutMs: timeoutMs,
    stallSeconds: stallSeconds,
  );
}

StreamAdaptiveHint _parseAdaptiveHint(
  Map<String, dynamic> payload, {
  required StreamAdaptiveHint fallback,
  required int baseFps,
  required int baseMaxWidth,
  required int baseQuality,
}) {
  final raw = payload['adaptive_hint'];
  if (raw is! Map) return fallback;

  final map = _normalizeMap(raw);
  final minFps = (_toInt(map['min_fps']) ?? fallback.minFps).clamp(10, baseFps);
  final minMaxWidth =
      (_toInt(map['min_max_w'] ?? map['min_max_width']) ?? fallback.minMaxWidth)
          .clamp(640, baseMaxWidth);
  final minQuality = (_toInt(map['min_quality']) ?? fallback.minQuality)
      .clamp(10, baseQuality);

  final maxFps = (_toInt(map['max_fps']) ?? baseFps).clamp(minFps, 120);
  final maxMaxWidth =
      (_toInt(map['max_max_w'] ?? map['max_max_width']) ?? baseMaxWidth)
          .clamp(minMaxWidth, 4096);
  final maxQuality =
      (_toInt(map['max_quality']) ?? baseQuality).clamp(minQuality, 95);

  final downStepFps =
      (_toInt(map['down_step_fps']) ?? fallback.downStepFps).clamp(1, 15);
  final downStepMaxWidth =
      (_toInt(map['down_step_max_w'] ?? map['down_step_max_width']) ??
              fallback.downStepMaxWidth)
          .clamp(64, 512);
  final downStepQuality =
      (_toInt(map['down_step_quality']) ?? fallback.downStepQuality)
          .clamp(1, 20);

  final upStepFps =
      (_toInt(map['up_step_fps']) ?? fallback.upStepFps).clamp(1, 15);
  final upStepMaxWidth =
      (_toInt(map['up_step_max_w'] ?? map['up_step_max_width']) ??
              fallback.upStepMaxWidth)
          .clamp(64, 512);
  final upStepQuality =
      (_toInt(map['up_step_quality']) ?? fallback.upStepQuality).clamp(1, 20);

  final rttHighMs =
      (_toInt(map['rtt_high_ms']) ?? fallback.rttHighMs).clamp(120, 5000);
  final rttLowMs =
      (_toInt(map['rtt_low_ms']) ?? fallback.rttLowMs).clamp(40, rttHighMs);
  final fpsDropThreshold = (_toDouble(map['fps_drop_threshold']) ??
          _toDouble(map['fps_low_ratio']) ??
          fallback.fpsDropThreshold)
      .clamp(0.35, 0.9);

  final lowFpsRatio = (_toDouble(map['low_fps_ratio']) ?? fallback.lowFpsRatio)
      .clamp(0.3, 0.95);
  final stableWindowSeconds = (_toInt(map['stable_window_seconds']) ??
          _toInt(map['stable_window_s']) ??
          fallback.stableWindowSeconds)
      .clamp(4, 30);
  final minWidthFloor =
      (_toInt(map['min_width_floor']) ?? fallback.minWidthFloor)
          .clamp(640, maxMaxWidth);
  final widthLadder = _normalizedWidthLadder(
    map['width_ladder'],
    minWidthFloor: minWidthFloor,
    maxWidthCeiling: maxMaxWidth,
    fallback: fallback.widthLadder,
  );
  final minSwitchIntervalMs = (_toInt(map['min_switch_interval_ms']) ??
          _toInt(map['min_switch_interval']) ??
          fallback.minSwitchIntervalMs)
      .clamp(1500, 120000);
  final hysteresisRatio =
      (_toDouble(map['hysteresis_ratio']) ?? fallback.hysteresisRatio)
          .clamp(0.05, 0.5);
  final downgradeSustainMs = (_toInt(map['downgrade_sustain_ms']) ??
          _toInt(map['downgrade_window_ms']) ??
          fallback.downgradeSustainMs)
      .clamp(1500, 10000);
  final upgradeSustainMs = (_toInt(map['upgrade_sustain_ms']) ??
          _toInt(map['upgrade_window_ms']) ??
          fallback.upgradeSustainMs)
      .clamp(3000, 20000);
  final preferQualityBeforeResize =
      _toBool(map['prefer_quality_before_resize']) ??
          _toBool(map['prefer_quality']) ??
          fallback.preferQualityBeforeResize;

  return StreamAdaptiveHint(
    minFps: minFps,
    minMaxWidth: minMaxWidth,
    minQuality: minQuality,
    maxFps: maxFps,
    maxMaxWidth: maxMaxWidth,
    maxQuality: maxQuality,
    downStepFps: downStepFps,
    downStepMaxWidth: downStepMaxWidth,
    downStepQuality: downStepQuality,
    upStepFps: upStepFps,
    upStepMaxWidth: upStepMaxWidth,
    upStepQuality: upStepQuality,
    rttHighMs: rttHighMs,
    rttLowMs: rttLowMs,
    fpsDropThreshold: fpsDropThreshold,
    lowFpsRatio: lowFpsRatio,
    stableWindowSeconds: stableWindowSeconds,
    widthLadder: widthLadder,
    minSwitchIntervalMs: minSwitchIntervalMs,
    hysteresisRatio: hysteresisRatio,
    minWidthFloor: minWidthFloor,
    downgradeSustainMs: downgradeSustainMs,
    upgradeSustainMs: upgradeSustainMs,
    preferQualityBeforeResize: preferQualityBeforeResize,
  );
}

ParsedStreamCandidate? _parseOne(
  Map<String, dynamic> raw, {
  required Uri Function(String raw) resolveCandidateUri,
  required String token,
  required bool includeAuthQueryToken,
  required bool lowLatency,
  required int maxWidth,
  required int quality,
  required int fps,
  required String defaultBackend,
}) {
  final mime = (raw['mime'] ??
          raw['content_type'] ??
          raw['contentType'] ??
          raw['type'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  final transport = _transportFromMime(mime);
  if (transport == null) return null;

  final urlRaw =
      (raw['url'] ?? raw['uri'] ?? raw['src'] ?? raw['path'] ?? raw['endpoint'])
          ?.toString()
          .trim();
  if (urlRaw == null || urlRaw.isEmpty) return null;

  final resolved = resolveCandidateUri(urlRaw);
  final uri = _augmentCandidateUri(
    resolved,
    token: token,
    includeAuthQueryToken: includeAuthQueryToken,
    lowLatency: lowLatency,
    maxWidth: maxWidth,
    quality: quality,
    fps: fps,
    includeMjpegParams: transport == 'mjpeg',
  );
  final backend = _toNonEmptyString(raw['backend']) ?? defaultBackend;
  final signature = '$transport|${resolved.path}|${backend.toLowerCase()}';

  return ParsedStreamCandidate(
    uri: uri,
    mime: mime,
    transport: transport,
    backend: backend,
    signature: signature,
  );
}

String? _transportFromMime(String mime) {
  if (mime.startsWith('video/mp2t')) return 'mpegTs';
  if (mime.startsWith('multipart/x-mixed-replace')) return 'mjpeg';
  return null;
}

Uri _augmentCandidateUri(
  Uri uri, {
  required String token,
  required bool includeAuthQueryToken,
  required bool lowLatency,
  required int maxWidth,
  required int quality,
  required int fps,
  required bool includeMjpegParams,
}) {
  final query = Map<String, String>.from(uri.queryParameters);
  if (includeAuthQueryToken && token.trim().isNotEmpty) {
    query['token'] = token;
  } else {
    query.remove('token');
  }
  query['low_latency'] = lowLatency ? '1' : '0';
  query['max_w'] = maxWidth.toString();
  if (includeMjpegParams) {
    query['quality'] = quality.toString();
    query['fps'] = fps.toString();
    query.putIfAbsent('cursor', () => '0');
  }
  return uri.replace(queryParameters: query);
}

Map<String, dynamic> _normalizeMap(Map raw) {
  final out = <String, dynamic>{};
  raw.forEach((k, v) {
    out[k.toString()] = v;
  });
  return out;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? _toDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

String? _toNonEmptyString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return text;
}

bool? _toBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
  }
  return null;
}

List<int> _normalizedWidthLadder(
  dynamic raw, {
  required int minWidthFloor,
  required int maxWidthCeiling,
  List<int>? fallback,
}) {
  final input = <int>[];
  if (raw is List) {
    for (final value in raw) {
      final parsed = _toInt(value);
      if (parsed != null) {
        input.add(parsed);
      }
    }
  }
  if (input.isEmpty && fallback != null && fallback.isNotEmpty) {
    input.addAll(fallback);
  }
  if (input.isEmpty) {
    input.addAll(StreamAdaptiveHint.defaultWidthLadder);
  }

  final seen = <int>{};
  final filtered = <int>[];
  for (final width in input) {
    final normalized = width.clamp(minWidthFloor, maxWidthCeiling).toInt();
    if (seen.add(normalized)) {
      filtered.add(normalized);
    }
  }
  filtered.sort((a, b) => b.compareTo(a));
  if (filtered.isEmpty || filtered.last > minWidthFloor) {
    filtered.add(minWidthFloor);
    filtered.sort((a, b) => b.compareTo(a));
  }
  return filtered;
}
