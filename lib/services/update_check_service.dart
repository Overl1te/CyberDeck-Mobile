import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_version.dart';

const String kCyberDeckLatestReleaseApi =
    'https://api.github.com/repos/Overl1te/CyberDeck/releases/latest';
const String kCyberDeckMobileLatestReleaseApi =
    'https://api.github.com/repos/Overl1te/CyberDeck-Mobile/releases/latest';

class ReleaseChannelStatus {
  final String currentVersion;
  final String latestTag;
  final String releaseUrl;
  final bool hasUpdate;
  final String error;

  const ReleaseChannelStatus({
    required this.currentVersion,
    required this.latestTag,
    required this.releaseUrl,
    required this.hasUpdate,
    required this.error,
  });
}

class UpdateCheckResult {
  final DateTime checkedAt;
  final ReleaseChannelStatus server;
  final ReleaseChannelStatus mobile;

  const UpdateCheckResult({
    required this.checkedAt,
    required this.server,
    required this.mobile,
  });
}

class UpdateCheckService {
  final http.Client _client;
  final bool _ownsClient;

  UpdateCheckService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<UpdateCheckResult> checkLatestTags({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final now = DateTime.now();
    final futures = <Future<_GithubReleaseResult>>[
      _fetchLatestTag(kCyberDeckLatestReleaseApi, timeout: timeout),
      _fetchLatestTag(kCyberDeckMobileLatestReleaseApi, timeout: timeout),
    ];
    final results = await Future.wait(futures);
    final serverResult = results[0];
    final mobileResult = results[1];

    return UpdateCheckResult(
      checkedAt: now,
      server: ReleaseChannelStatus(
        currentVersion: kCyberDeckServerVersion,
        latestTag: serverResult.latestTag,
        releaseUrl: serverResult.releaseUrl,
        hasUpdate:
            _isNewerVersion(serverResult.latestTag, kCyberDeckServerVersion),
        error: serverResult.error,
      ),
      mobile: ReleaseChannelStatus(
        currentVersion: kMobileAppVersion,
        latestTag: mobileResult.latestTag,
        releaseUrl: mobileResult.releaseUrl,
        hasUpdate: _isNewerVersion(mobileResult.latestTag, kMobileAppVersion),
        error: mobileResult.error,
      ),
    );
  }

  Future<_GithubReleaseResult> _fetchLatestTag(
    String apiUrl, {
    required Duration timeout,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse(apiUrl),
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'CyberDeck-Mobile/1.1.1',
        },
      ).timeout(timeout);
      if (response.statusCode != 200) {
        return _GithubReleaseResult(
          latestTag: '',
          releaseUrl: '',
          error: 'http_${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const _GithubReleaseResult(
          latestTag: '',
          releaseUrl: '',
          error: 'invalid_json_shape',
        );
      }
      final payload = Map<String, dynamic>.from(decoded);
      final tag = (payload['tag_name'] ?? '').toString().trim();
      final releaseUrl = (payload['html_url'] ?? '').toString().trim();
      if (tag.isEmpty) {
        return const _GithubReleaseResult(
          latestTag: '',
          releaseUrl: '',
          error: 'missing_tag_name',
        );
      }
      return _GithubReleaseResult(
        latestTag: tag,
        releaseUrl: releaseUrl,
        error: '',
      );
    } on TimeoutException {
      return const _GithubReleaseResult(
        latestTag: '',
        releaseUrl: '',
        error: 'timeout',
      );
    } catch (e) {
      return _GithubReleaseResult(
        latestTag: '',
        releaseUrl: '',
        error: e.runtimeType.toString().toLowerCase(),
      );
    }
  }

  static bool _isNewerVersion(String latestTag, String currentVersion) {
    final latest = _versionTuple(latestTag);
    final current = _versionTuple(currentVersion);
    if (latest == null || current == null) return false;
    return latest[0] > current[0] ||
        (latest[0] == current[0] && latest[1] > current[1]) ||
        (latest[0] == current[0] &&
            latest[1] == current[1] &&
            latest[2] > current[2]);
  }

  static List<int>? _versionTuple(String rawVersion) {
    final text = rawVersion.trim().toLowerCase().startsWith('v')
        ? rawVersion.trim().substring(1)
        : rawVersion.trim();
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$').firstMatch(text);
    if (match == null) return null;
    return <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }
}

class _GithubReleaseResult {
  final String latestTag;
  final String releaseUrl;
  final String error;

  const _GithubReleaseResult({
    required this.latestTag,
    required this.releaseUrl,
    required this.error,
  });
}
