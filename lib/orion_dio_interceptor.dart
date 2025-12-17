/// OrionDioInterceptor
///
/// Usage:
/// ```
/// Dio dio = Dio()
///   ..interceptors.add(OrionDioInterceptor());
/// ```
///
/// - Automatically tracks request/response/errors per screen.
/// - Make sure OrionNetworkTracker.currentScreenName is always correct.
/// - Used with OrionManualTracker + OrionFlutterPlugin.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:orion_flutter/orion_network_tracker.dart';
import 'package:orion_flutter/orion_logger.dart';
import 'orion_flutter.dart';

class OrionDioInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!OrionFlutter.isAndroid) return handler.next(options);

    options.extra['startTime'] = DateTime.now().millisecondsSinceEpoch;
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (OrionFlutter.isAndroid) {
      // Extract processingtime header (default to 0 if missing or invalid)
      final processingTimeStr = response.headers['x-response-time']?.first;
      final processingTime = int.tryParse(processingTimeStr ?? '') ?? 0;

      _track(
        response.requestOptions,
        response.statusCode ?? -1,
        payload: response.data,
        contentType: response.headers[HttpHeaders.contentTypeHeader]?.first,
        actualTime: processingTime,
      );
    }

    super.onResponse(response, handler);
  }

  @override
  void onError(DioError err, ErrorInterceptorHandler handler) {
    if (OrionFlutter.isAndroid) {
      final statusCode = err.response?.statusCode ?? -1;
      orionPrint("🔴 OrionDioInterceptor - onError: [${err.requestOptions.method}] ${err.requestOptions.uri} | ${err.message}");

      _track(
        err.requestOptions,
        statusCode,
        error: err.message,
        contentType: err.response?.headers[HttpHeaders.contentTypeHeader]?.first,
        actualTime: 0, // Default 0 for failed requests
      );
    }

    super.onError(err, handler);
  }

  void _track(
      RequestOptions options,
      int statusCode, {
        String? error,
        dynamic payload,
        String? contentType,
        int actualTime = 0,
      }) {
    final startTime = options.extra['startTime'] as int?;
    final endTime = DateTime.now().millisecondsSinceEpoch;

    if (startTime == null) {
      orionPrint("⚠️ OrionDioInterceptor - Missing startTime for ${options.uri}");
      return;
    }

    final duration = endTime - startTime;
    final screen = OrionNetworkTracker.currentScreenName ?? "UnknownScreen";
    final payloadSize = _getPayloadSize(payload);

    OrionNetworkTracker.addRequest(screen, {
      "method": options.method,
      "url": options.uri.toString(),
      "statusCode": statusCode,
      "startTime": startTime,
      "endTime": endTime,
      "duration": duration,
      "payloadSize": payloadSize,
      "contentType": contentType,
      "responseType": options.responseType.toString(),
      "errorMessage": error,
      "actualTime": actualTime,
    });
  }

  int? _getPayloadSize(dynamic data) {
    if (data == null) return null;
    if (data is List<int>) return data.length;
    if (data is String) return data.length;
    if (data is Map || data is List) return data.toString().length;
    return null;
  }
}