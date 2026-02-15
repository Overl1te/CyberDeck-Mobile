import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'device_storage.dart';
import 'l10n/app_localizations.dart';
import 'services/transfer_service.dart';
import 'theme.dart';

class FileTransfer {
  static Future<void> handleIncomingFile(
    BuildContext context,
    Map<String, dynamic> data,
    DeviceSettings settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final rawFilename = (data['filename'] ?? 'file').toString();
    final filename = _sanitizeFilename(rawFilename);
    final urlString = (data['url'] ?? '').toString().trim();
    final transferId = (data['transfer_id'] ?? '').toString().trim();
    final expectedSha256 = (data['sha256'] ?? '').toString().trim();
    final acceptRanges = _parseBool(data['accept_ranges']);
    final expiresAtRaw = data['expires_at']?.toString().trim();
    final expiresAt = expiresAtRaw == null || expiresAtRaw.isEmpty
        ? null
        : DateTime.tryParse(expiresAtRaw);

    if (urlString.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.invalidTransferPayload),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    if (expiresAt != null &&
        DateTime.now().toUtc().isAfter(expiresAt.toUtc())) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Transfer expired'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    final uri = Uri.tryParse(urlString);
    if (uri == null || !uri.hasScheme) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.invalidDownloadUrl),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    var accept = true;
    if (settings.confirmDownloads) {
      final size = data['size'];
      var sizeLabel = '';
      if (size is num) {
        sizeLabel = l10n.sizeMb((size / 1024 / 1024).toStringAsFixed(2));
      }

      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kPanelColor,
          title: Text(l10n.incomingFile,
              style: const TextStyle(color: kAccentColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.acceptFile(filename),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(sizeLabel, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.no)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l10n.download,
                style: const TextStyle(
                    color: kAccentColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      accept = result == true;
    }

    if (!accept) return;

    final hasPermission = await _ensurePermission();
    final shouldFallbackWithoutPermission =
        TransferService.shouldFallbackToBrowser(
      browserFallbackEnabled: settings.browserFallback,
      permissionGranted: hasPermission,
    );
    if (!hasPermission) {
      if (!context.mounted) return;
      if (shouldFallbackWithoutPermission) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.noStoragePermissionOpeningBrowser),
            backgroundColor: Colors.orange,
          ),
        );
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.noStoragePermission),
            backgroundColor: kErrorColor,
          ),
        );
      }
      return;
    }

    final savePath = await _buildSavePath(filename);
    var file = File(savePath);
    var i = 1;
    while (file.existsSync()) {
      final dot = filename.lastIndexOf('.');
      final base = dot > 0 ? filename.substring(0, dot) : filename;
      final ext = dot > 0 ? filename.substring(dot) : '';
      final parent = file.parent.path;
      file = File('$parent${Platform.pathSeparator}$base($i)$ext');
      i++;
    }

    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    if (!context.mounted) return;

    final transfer = TransferService();
    final cancelToken = CancelToken();
    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;
    var canceled = false;

    _showProgressDialog(
      context,
      progress: progress,
      title: l10n.downloadInProgress,
      cancelLabel: l10n.cancel,
      onCancel: () {
        canceled = true;
        cancelToken.cancel('user_cancelled');
        dialogOpen = false;
      },
    );

    try {
      await transfer.downloadFile(
        uri: uri,
        outputPath: file.path,
        cancelToken: cancelToken,
        expectedSha256: expectedSha256.isEmpty ? null : expectedSha256,
        acceptRanges: acceptRanges,
        maxChecksumRetries: _checksumRetriesByPreset(settings.transferPreset),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress.value = received / total;
          }
        },
      );

      if (!context.mounted || canceled) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            transferId.isEmpty
                ? l10n.savedFile(file.path.split(Platform.pathSeparator).last)
                : '${l10n.savedFile(file.path.split(Platform.pathSeparator).last)} (id: $transferId)',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!context.mounted || canceled) return;
      if (e is DioException && CancelToken.isCancel(e)) return;

      final shouldFallbackOnError = TransferService.shouldFallbackToBrowser(
        browserFallbackEnabled: settings.browserFallback,
        permissionGranted: true,
        error: e,
      );
      if (shouldFallbackOnError) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.downloadErrorOpeningBrowser(e.toString())),
            backgroundColor: kErrorColor,
          ),
        );
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.downloadError(e.toString())),
            backgroundColor: kErrorColor,
          ),
        );
      }
    } finally {
      progress.dispose();
      transfer.dispose();
      if (dialogOpen && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  static void _showProgressDialog(
    BuildContext context, {
    required ValueNotifier<double> progress,
    required String title,
    required String cancelLabel,
    required VoidCallback onCancel,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: kPanelColor,
          title: Text(title),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) {
              final normalized = value.clamp(0.0, 1.0);
              final percent = (normalized * 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(
                    value: normalized > 0 ? normalized : null,
                    color: kAccentColor,
                  ),
                  const SizedBox(height: 10),
                  Text('$percent%'),
                ],
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                onCancel();
                Navigator.of(dialogContext).pop();
              },
              child: Text(cancelLabel),
            ),
          ],
        );
      },
    );
  }

  static Future<String> _buildSavePath(String filename) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloadsDir = await getDownloadsDirectory();
      final baseDir = downloadsDir ?? await getApplicationDocumentsDirectory();
      return '${baseDir.path}${Platform.pathSeparator}$filename';
    }
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download/$filename';
    }
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}$filename';
  }

  static Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) return true;

    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    if (deviceInfo.version.sdkInt >= 30) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      return status.isGranted;
    }

    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  static String _sanitizeFilename(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'file';

    final sanitized = trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'[\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');

    final cleaned = sanitized.isEmpty || sanitized == '.' || sanitized == '..'
        ? 'file'
        : sanitized;
    if (cleaned.length <= 180) return cleaned;
    return cleaned.substring(0, 180);
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static int _checksumRetriesByPreset(String preset) {
    switch (preset) {
      case 'ultra_safe':
        return 4;
      case 'safe':
        return 3;
      default:
        return 2;
    }
  }
}
