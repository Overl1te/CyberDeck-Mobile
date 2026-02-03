import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'device_storage.dart';
import 'theme.dart';

class FileTransfer {
  static Future<void> handleIncomingFile(
    BuildContext context,
    Map<String, dynamic> data,
    DeviceSettings settings,
  ) async {
    final filename = (data['filename'] ?? 'file').toString();
    final urlString = (data['url'] ?? '').toString();

    if (urlString.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Некорректные данные передачи (нет ссылки)'), backgroundColor: kErrorColor),
      );
      return;
    }

    bool accept = true;
    if (settings.confirmDownloads) {
      final size = data['size'];
      String sizeLabel = '';
      if (size is num) {
        sizeLabel = '${(size / 1024 / 1024).toStringAsFixed(2)} \u041c\u0411';
      }

      final res = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kPanelColor,
          title: const Text('Запрос файла', style: TextStyle(color: kAccentColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Принять: $filename', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 6),
              Text(sizeLabel, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('СКАЧАТЬ', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      accept = res == true;
    }

    if (!accept) return;

    String savePath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloadsDir = await getDownloadsDirectory();
      final baseDir = downloadsDir ?? await getApplicationDocumentsDirectory();
      savePath = '${baseDir.path}${Platform.pathSeparator}$filename';
    } else if (Platform.isAndroid) {
      savePath = '/storage/emulated/0/Download/$filename';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      savePath = '${dir.path}${Platform.pathSeparator}$filename';
    }

    bool hasPermission = true;
    if (Platform.isAndroid) {
      hasPermission = false;
      final deviceInfo = await DeviceInfoPlugin().androidInfo;

      if (deviceInfo.version.sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) status = await Permission.manageExternalStorage.request();
        hasPermission = status.isGranted;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        hasPermission = status.isGranted;
      }
    }

    if (!hasPermission) {
      if (settings.browserFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет прав на память. Открываю браузер...'), backgroundColor: Colors.orange),
        );
        final uri = Uri.parse(urlString);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет прав на доступ к памяти'), backgroundColor: kErrorColor),
        );
      }
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скачивание...')));

      File file = File(savePath);
      int i = 1;
      while (file.existsSync()) {
        final nameParts = filename.split('.');
        final ext = nameParts.length > 1 ? '.${nameParts.last}' : '';
        final name = nameParts.length > 1 ? nameParts.sublist(0, nameParts.length - 1).join('.') : filename;
        final parent = file.parent.path;
        file = File('$parent${Platform.pathSeparator}$name($i)$ext');
        i++;
      }

      if (!file.parent.existsSync()) {
        await file.parent.create(recursive: true);
      }

      final request = http.Request('GET', Uri.parse(urlString));
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.stream.pipe(sink);
        await sink.close();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сохранено: ${file.path.split(Platform.pathSeparator).last}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        throw 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      if (settings.browserFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e. Открываю браузер...'), backgroundColor: kErrorColor),
        );
        final uri = Uri.parse(urlString);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка скачивания: $e'), backgroundColor: kErrorColor),
        );
      }
    }
  }
}
