import 'package:web_socket_channel/web_socket_channel.dart';

/// Shared lifecycle for native TLS sockets and browser WebSockets.
class PilotSocket {
  PilotSocket(this.channel);
  final WebSocketChannel channel;
  bool _open = true;
  bool get isOpen => _open && channel.closeCode == null;

  Stream<dynamic> get stream async* {
    try {
      yield* channel.stream;
    } finally {
      _open = false;
    }
  }

  void add(Object data) {
    if (!isOpen) throw StateError('Socket closed');
    channel.sink.add(data);
  }

  Future<void> close() async {
    _open = false;
    await channel.sink.close();
  }
}
