import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'pilot_socket.dart';
import 'transport_native.dart'
    if (dart.library.js_interop) 'transport_web.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PilotApi {
  PilotApi(this.baseUrl, this.token);
  final String baseUrl, token;
  final _transport = ApiTransport();
  Future<http.Client> client() => _transport.client();
  Future<PilotSocket> connectSocket(String path) {
    final endpoint = uri(path);
    return _transport.connect(
      endpoint.replace(scheme: endpoint.scheme == 'https' ? 'wss' : 'ws'),
    );
  }

  Uri uri(String path) {
    final base = Uri.parse(baseUrl);
    if (!isAllowedPilotUri(base)) {
      throw ApiException('HTTPS server URL required');
    }
    return Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
  }

  Future<Map<String, dynamic>> health() async {
    final r = await (await client())
        .get(uri('/health'))
        .timeout(const Duration(seconds: 10));
    return decode(r);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await (await client())
        .post(
          uri(path),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 35));
    return decode(r);
  }

  Future<Map<String, dynamic>> image(Uint8List bytes, int revision) async {
    final req = http.MultipartRequest('POST', uri('/v1/recognize/image'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['revision'] = '$revision'
      ..fields['provider'] = 'mathpix'
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'equation.jpg'),
      );
    return decode(
      await http.Response.fromStream(
        await (await client()).send(req).timeout(const Duration(seconds: 35)),
      ).timeout(const Duration(seconds: 35)),
    );
  }

  Map<String, dynamic> decode(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'Server returned an invalid response (${response.statusCode})',
      );
    }
    if (response.statusCode >= 400) {
      final detail = data is Map ? data['detail'] : null;
      throw ApiException(
        detail is String
            ? detail
            : detail is Map && detail['message'] is String
            ? detail['message'] as String
            : 'Server error (${response.statusCode})',
      );
    }
    return Map<String, dynamic>.from(data as Map);
  }

  void close() {
    _transport.close();
  }
}

String defaultPilotUrl() {
  const configured = String.fromEnvironment('PILOT_URL');
  if (configured.isNotEmpty) return configured;
  return kIsWeb ? '${Uri.base.origin}/api' : 'https://localhost:8443';
}

bool isAllowedPilotUri(Uri uri) =>
    uri.host.isNotEmpty &&
    (uri.scheme == 'https' ||
        (kIsWeb &&
            uri.scheme == 'http' &&
            uri.origin == Uri.base.origin &&
            ['localhost', '127.0.0.1', '::1'].contains(uri.host)));
