import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../network/host_port.dart';
import '../theme.dart';
import 'error_catalog.dart';

class ErrorHelpScreen extends StatefulWidget {
  const ErrorHelpScreen({
    super.key,
    this.initialQuery = '',
    this.host,
    this.port,
    this.scheme = 'http',
  });

  final String initialQuery;
  final String? host;
  final int? port;
  final String scheme;

  @override
  State<ErrorHelpScreen> createState() => _ErrorHelpScreenState();
}

class _ErrorHelpScreenState extends State<ErrorHelpScreen> {
  late final TextEditingController _queryController;
  bool _loading = false;
  String _loadError = '';
  List<ErrorArticle> _remote = <ErrorArticle>[];
  List<ErrorArticle> _items = <ErrorArticle>[];

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _applyFilter();
    _loadRemoteCatalog();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadRemoteCatalog() async {
    final endpoint = _resolveEndpoint();
    if (endpoint == null) return;

    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = '';
      });
    }

    final api = ApiClient(
      host: endpoint.host,
      port: endpoint.port,
      scheme: widget.scheme,
      maxRetries: 1,
    );
    try {
      final response = await api.get(
        '/api/errors/catalog',
        queryParameters: const <String, String>{'limit': '500'},
        authorized: false,
        timeout: const Duration(seconds: 5),
      );
      final data = api.decodeJsonMap(response);
      final rawItems = data['items'];
      final rows = <ErrorArticle>[];
      if (rawItems is List) {
        for (final entry in rawItems) {
          final article = _parseRemoteArticle(entry);
          if (article != null) {
            rows.add(article);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _remote = rows;
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _formatLoadError(e);
      });
    } finally {
      api.close();
    }
  }

  HostPort? _resolveEndpoint() {
    final rawHost = (widget.host ?? '').trim();
    if (rawHost.isEmpty) return null;

    final explicitPort = widget.port ?? 0;

    final asUri = Uri.tryParse(rawHost);
    if (asUri != null && asUri.hasScheme && asUri.host.trim().isNotEmpty) {
      final uriPort = asUri.hasPort ? asUri.port : 0;
      final port = uriPort > 0 ? uriPort : explicitPort;
      if (port <= 0) return null;
      return HostPort(host: asUri.host.trim(), port: port);
    }

    final parsed = parseHostPort(
      rawHost,
      defaultPort: explicitPort > 0 ? explicitPort : null,
      requirePort: explicitPort <= 0,
    );
    return parsed;
  }

  ErrorArticle? _parseRemoteArticle(dynamic entry) {
    if (entry is! Map) return null;
    final item = Map<String, dynamic>.from(
      entry.map((key, value) => MapEntry(key.toString(), value)),
    );
    final code = (item['code'] ?? '').toString().trim().toUpperCase();
    if (code.isEmpty) return null;

    final stepsRaw = item['steps'];
    final steps = <String>[];
    if (stepsRaw is List) {
      for (final step in stepsRaw) {
        final text = step.toString().trim();
        if (text.isNotEmpty) {
          steps.add(text);
        }
      }
    }

    final tagsRaw = item['tags'];
    final tags = <String>[];
    if (tagsRaw is List) {
      for (final tag in tagsRaw) {
        final text = tag.toString().trim();
        if (text.isNotEmpty) {
          tags.add(text);
        }
      }
    }

    final title = (item['title'] ?? '').toString().trim();
    final summary = (item['hint'] ?? item['summary'] ?? '').toString().trim();

    return ErrorArticle(
      code: code,
      number: _toInt(item['number']),
      status: _toInt(item['status']),
      slug: (item['slug'] ?? '').toString().trim(),
      docsUrl: (item['docs_url'] ?? '').toString().trim(),
      title: title.isEmpty ? code : title,
      summary: summary,
      steps: steps,
      tags: tags,
    );
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _formatLoadError(Object error) {
    if (error is ApiException) {
      final parts = <String>[];
      if (error.hasCatalogCode) {
        parts.add(error.code.trim());
      }
      if (error.statusCode != null) {
        parts.add('HTTP ${error.statusCode}');
      }
      final message = error.message.trim();
      if (message.isNotEmpty) {
        parts.add(message);
      }
      if (parts.isNotEmpty) {
        return parts.join(' | ');
      }
    }
    return error.toString();
  }

  void _applyFilter() {
    setState(() {
      _items = searchErrorCatalog(
        _queryController.text,
        extra: _remote,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: const Text('Error Guide'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _queryController,
              onChanged: (_) => _applyFilter(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search code, number, status, title, tags...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _applyFilter,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Found: ${_items.length}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _loadRemoteCatalog,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            if (_loading)
              const LinearProgressIndicator(color: kAccentColor)
            else
              const SizedBox(height: 4),
            if (_loadError.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Remote catalog load failed: $_loadError',
                style: const TextStyle(color: kErrorColor),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? const Center(
                      child: Text(
                        'No errors found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final meta = <String>[
                          if (item.number != null) '#${item.number}',
                          if (item.status != null) 'HTTP ${item.status}',
                        ].join('  ');
                        return Card(
                          color: kPanelColor,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Text(
                                      item.code,
                                      style: const TextStyle(
                                        color: kAccentColor,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    if (meta.isNotEmpty) ...<Widget>[
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          meta,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (item.summary.trim().isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 6),
                                  Text(
                                    item.summary,
                                    style:
                                        const TextStyle(color: Colors.white70),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                if (item.steps.isNotEmpty)
                                  ...item.steps.map(
                                    (step) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          const Text(
                                            '- ',
                                            style: TextStyle(
                                                color: Colors.white70),
                                          ),
                                          Expanded(
                                            child: Text(
                                              step,
                                              style: const TextStyle(
                                                  color: Colors.white70),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  const Text(
                                    'No detailed steps provided by server.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                if (item.tags.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tags: ${item.tags.join(', ')}',
                                    style:
                                        const TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
