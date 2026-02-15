import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

class TransferException implements Exception {
  final String message;
  final int? statusCode;

  const TransferException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

class TransferService {
  final Dio _dio;

  TransferService([Dio? dio]) : _dio = dio ?? Dio();

  Future<void> uploadFile({
    required Uri uri,
    required String token,
    required String filePath,
    required CancelToken cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final checksum = await _sha256OfFile(File(filePath));
    final data = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(filePath),
    });
    try {
      final response = await _dio.postUri<dynamic>(
        uri,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'X-File-Sha256': checksum,
          },
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45),
        ),
        onSendProgress: onSendProgress,
      );

      if (response.statusCode != 200) {
        final serverError = _extractServerErrorCode(response.data);
        if (serverError == 'upload_checksum_mismatch') {
          throw TransferException(
            'upload_checksum_mismatch',
            statusCode: response.statusCode,
          );
        }
        throw TransferException(
          serverError ?? 'Upload failed',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      final serverError = _extractServerErrorCode(e.response?.data);
      if (serverError == 'upload_checksum_mismatch') {
        throw TransferException(
          'upload_checksum_mismatch',
          statusCode: e.response?.statusCode,
        );
      }
      throw TransferException(
        serverError ?? 'Upload failed',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> downloadFile({
    required Uri uri,
    required String outputPath,
    required CancelToken cancelToken,
    ProgressCallback? onReceiveProgress,
    String? expectedSha256,
    bool acceptRanges = false,
    int maxResumeRetries = 4,
    int maxChecksumRetries = 2,
  }) async {
    final target = File(outputPath);
    final part = File('$outputPath.part');
    if (!part.parent.existsSync()) {
      await part.parent.create(recursive: true);
    }

    final normalizedExpected = expectedSha256?.trim().toLowerCase();
    var checksumAttempt = 0;
    while (true) {
      try {
        await _downloadWithResume(
          uri: uri,
          file: part,
          acceptRanges: acceptRanges,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
          maxResumeRetries: maxResumeRetries,
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        throw TransferException(
          'Download failed',
          statusCode: e.response?.statusCode,
        );
      } on SocketException {
        throw const TransferException('Download failed');
      }

      if (normalizedExpected == null || normalizedExpected.isEmpty) {
        await _promotePartToTarget(part: part, target: target);
        return;
      }

      final actual = await _sha256OfFile(part);
      if (actual.toLowerCase() == normalizedExpected) {
        await _promotePartToTarget(part: part, target: target);
        return;
      }

      checksumAttempt++;
      if (checksumAttempt > maxChecksumRetries) {
        throw const TransferException('Checksum mismatch');
      }
      if (part.existsSync()) {
        await part.delete();
      }
    }
  }

  Future<void> _downloadWithResume({
    required Uri uri,
    required File file,
    required bool acceptRanges,
    required CancelToken cancelToken,
    ProgressCallback? onReceiveProgress,
    required int maxResumeRetries,
  }) async {
    var resumeRetry = 0;
    while (true) {
      final offset = await _safeLength(file);
      final useRange = acceptRanges && offset > 0;
      final headers =
          useRange ? <String, String>{'Range': 'bytes=$offset-'} : null;

      try {
        final response = await _dio.getUri<ResponseBody>(
          uri,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            sendTimeout: const Duration(seconds: 45),
            receiveTimeout: const Duration(seconds: 45),
            validateStatus: (code) => code != null && code >= 200 && code < 500,
          ),
        );

        final status = response.statusCode ?? 0;
        if (status != 200 && status != 206) {
          throw TransferException('Download failed', statusCode: status);
        }

        if (useRange && status == 200 && file.existsSync()) {
          await file.delete();
        }

        final total = _resolveTotalBytes(response.headers, status, offset);
        final sink = file.openWrite(mode: FileMode.append);
        var received = await _safeLength(file);
        try {
          await for (final chunk in response.data!.stream) {
            sink.add(chunk);
            received += chunk.length;
            onReceiveProgress?.call(received, total);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
        return;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        if (!acceptRanges || resumeRetry >= maxResumeRetries) rethrow;
        resumeRetry++;
        await Future<void>.delayed(Duration(milliseconds: 250 * resumeRetry));
      } on SocketException {
        if (!acceptRanges || resumeRetry >= maxResumeRetries) rethrow;
        resumeRetry++;
        await Future<void>.delayed(Duration(milliseconds: 250 * resumeRetry));
      }
    }
  }

  int _resolveTotalBytes(Headers headers, int status, int offset) {
    if (status == 206) {
      final contentRange = headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final slash = contentRange.lastIndexOf('/');
        if (slash >= 0 && slash + 1 < contentRange.length) {
          final total = int.tryParse(contentRange.substring(slash + 1).trim());
          if (total != null) return total;
        }
      }
    }
    final contentLength = headers.value(HttpHeaders.contentLengthHeader);
    final length = int.tryParse(contentLength ?? '');
    if (length == null) return -1;
    return status == 206 ? offset + length : length;
  }

  Future<int> _safeLength(File file) async {
    if (!file.existsSync()) return 0;
    return file.length();
  }

  Future<void> _promotePartToTarget({
    required File part,
    required File target,
  }) async {
    if (target.existsSync()) {
      await target.delete();
    }
    await part.rename(target.path);
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String? _extractServerErrorCode(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final map = raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      for (final key in const <String>['error', 'detail', 'message', 'code']) {
        final value = map[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return null;
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static bool shouldFallbackToBrowser({
    required bool browserFallbackEnabled,
    required bool permissionGranted,
    Object? error,
  }) {
    if (!browserFallbackEnabled) return false;
    if (!permissionGranted) return true;
    return error != null;
  }

  void dispose() {
    _dio.close(force: true);
  }
}
