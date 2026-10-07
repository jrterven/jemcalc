import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'pilot_socket.dart';

class ApiTransport {
  HttpClient? _transport;
  IOClient? _client;
  Future<HttpClient> _http() async {
    if (_transport != null) return _transport!;
    final context = SecurityContext(withTrustedRoots: true);
    try {
      final data = await rootBundle.load('assets/pilot/server.pem');
      try {
        context.setTrustedCertificatesBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } on TlsException {
        if (!Platform.isIOS) rethrow;
        final der = await rootBundle.load('assets/pilot/server.der');
        context.setTrustedCertificatesBytes(
          der.buffer.asUint8List(der.offsetInBytes, der.lengthInBytes),
        );
      }
    } on FlutterError {
      // Optional public development certificate; never disable TLS validation.
    }
    _transport = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 10);
    return _transport!;
  }

  Future<IOClient> client() async => _client ??= IOClient(await _http());

  Future<PilotSocket> connect(Uri uri) async {
    var expired = false;
    final socket =
        await WebSocket.connect(uri.toString(), customClient: await _http())
            .then((socket) {
              if (expired) {
                unawaited(socket.close());
                throw StateError('Connection timed out');
              }
              return socket;
            })
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () {
                expired = true;
                throw TimeoutException('Connection timed out');
              },
            );
    return PilotSocket(IOWebSocketChannel(socket));
  }

  void close() {
    _client?.close();
    _transport?.close(force: true);
  }
}
