import 'package:http/browser_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'pilot_socket.dart';

class ApiTransport {
  final _client = BrowserClient();
  Future<BrowserClient> client() async => _client;
  Future<PilotSocket> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(const Duration(seconds: 12));
      return PilotSocket(channel);
    } catch (_) {
      await channel.sink.close();
      rethrow;
    }
  }

  void close() => _client.close();
}
