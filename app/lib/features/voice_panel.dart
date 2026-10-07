import 'dart:async';
import 'dart:convert';
import '../core/pilot_socket.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../core/model.dart';
import 'equation_editor_sheet.dart';

class VoicePanel extends StatefulWidget {
  const VoicePanel({super.key, required this.model});
  final AppModel model;
  @override
  State<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<VoicePanel> with WidgetsBindingObserver {
  final recorder = AudioRecorder();
  PilotSocket? socket;
  StreamSubscription<dynamic>? incoming;
  StreamSubscription<dynamic>? audio;
  bool listening = false, connecting = false, stopping = false;
  String transcript = '', session = '', message = '';
  bool disposed = false;
  bool startInFlight = false;
  int startGeneration = 0;
  Timer? closeTimer;
  final List<String> committed = [];
  void repaint() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.model.onDraftChanged = contextChanged;
  }

  void contextChanged(String source, String? segmentId) {
    final active = socket;
    if (active == null || !active.isOpen || disposed) {
      return;
    }
    try {
      active.add(
        jsonEncode({
          'type': 'context',
          'latex': widget.model.latex,
          'revision': widget.model.revision,
          'source': source,
          'segmentId': segmentId,
        }),
      );
    } on StateError {
      // onDone handles the close; an edit remains valid in the local document.
    }
  }

  bool currentStart(int generation) =>
      !disposed && generation == startGeneration;

  bool currentSocket(PilotSocket active, String activeSession) =>
      !disposed && identical(socket, active) && session == activeSession;

  Future<void> start() async {
    if (connecting || listening || stopping) return;
    final generation = ++startGeneration;
    startInFlight = true;
    connecting = true;
    message = '';
    committed.clear();
    transcript = '';
    repaint();
    try {
      final permitted = await recorder.hasPermission();
      if (!currentStart(generation)) return;
      if (!permitted) {
        throw Exception(
          widget.model.s.t(
            'Permite el acceso al micrófono.',
            'Allow microphone access.',
          ),
        );
      }
      session = const Uuid().v4();
      final activeSession = session;
      final activeSocket = await widget.model.api.connectSocket(
        '/v1/dictation',
      );
      if (!currentStart(generation)) {
        await activeSocket.close();
        return;
      }
      socket = activeSocket;
      final ready = Completer<void>();
      incoming = activeSocket.stream.listen(
        (dynamic event) {
          if (!currentSocket(activeSocket, activeSession) || event is! String) {
            return;
          }
          final data = jsonDecode(event) as Map<String, dynamic>;
          if (data['sessionId'] != null && data['sessionId'] != session) return;
          switch (data['type']) {
            case 'ready':
              if (!ready.isCompleted) ready.complete();
            case 'transcript':
              transcript = data['text'] as String? ?? '';
              if (data['final'] == true) {
                committed.add(transcript);
                transcript = '';
              }
              repaint();
            case 'proposal':
              if (!widget.model.acceptProposal(
                data['latex'] as String,
                data['baseRevision'] as int,
                warnings: List<String>.from(data['ambiguities'] ?? []),
                segmentId: data['segmentId'] as String?,
              )) {
                message = widget.model.s.t(
                  'Se conservó tu corrección manual.',
                  'Your manual correction was preserved.',
                );
                repaint();
              }
            case 'error':
              message = data['message'] as String? ?? 'Voice error';
              if (!ready.isCompleted) ready.completeError(Exception(message));
              repaint();
          }
        },
        onError: (Object e) {
          if (!currentSocket(activeSocket, activeSession)) return;
          if (!ready.isCompleted) ready.completeError(e);
          message = e.toString();
          stop();
        },
        onDone: () {
          if (!currentSocket(activeSocket, activeSession)) return;
          if (!ready.isCompleted) {
            ready.completeError(Exception('Connection closed'));
          }
          unawaited(finishSession(activeSocket));
        },
      );
      activeSocket.add(
        jsonEncode({
          'type': 'start',
          'token': widget.model.token,
          'sessionId': session,
          'provider': widget.model.voiceProvider,
          'language': widget.model.language,
          'latex': widget.model.latex,
          'revision': widget.model.revision,
        }),
      );
      await ready.future.timeout(const Duration(seconds: 15));
      if (!currentStart(generation) ||
          !currentSocket(activeSocket, activeSession)) {
        return;
      }
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 24000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      if (!currentStart(generation) ||
          !currentSocket(activeSocket, activeSession)) {
        // A microphone start can finish after pause/stop. Do not leave it active.
        await recorder.stop();
        return;
      }
      listening = true;
      audio = stream.listen(
        (bytes) {
          if (currentSocket(activeSocket, activeSession) &&
              activeSocket.isOpen) {
            activeSocket.add(bytes);
          }
        },
        onError: (Object e) {
          if (!currentSocket(activeSocket, activeSession)) return;
          message = e.toString();
          stop();
        },
      );
    } catch (e) {
      if (currentStart(generation)) {
        message = e.toString();
        await stop();
      }
    } finally {
      startInFlight = false;
      connecting = false;
      repaint();
    }
  }

  Future<void> stop() async {
    if (disposed || stopping) return;
    ++startGeneration;
    stopping = true;
    listening = false;
    connecting = startInFlight;
    repaint();
    final closingSocket = socket;
    final activeAudio = audio;
    try {
      // Keep the subscription until the recorder has flushed its last PCM frame.
      await recorder.stop();
    } catch (_) {
      // No recording may exist yet when start was cancelled during permission.
    }
    await activeAudio?.cancel();
    if (identical(audio, activeAudio)) audio = null;
    if (disposed || !identical(socket, closingSocket)) return;
    if (closingSocket != null) {
      closeTimer?.cancel();
      // Backend can spend 15s completing ASR + 30s interpreting + 3s on ACK.
      closeTimer = Timer(const Duration(seconds: 55), () {
        if (!disposed && identical(socket, closingSocket)) {
          if (message.isEmpty) {
            message = widget.model.s.t(
              'El dictado tardó demasiado. Se conservó la última ecuación.',
              'Dictation timed out. The last equation was preserved.',
            );
          }
          unawaited(closingSocket.close());
          repaint();
        }
      });
      try {
        if (closingSocket.isOpen) {
          closingSocket.add(jsonEncode({'type': 'stop'}));
        } else {
          await finishSession(closingSocket);
        }
      } on StateError {
        await finishSession(closingSocket);
      }
    } else {
      stopping = false;
    }
    repaint();
  }

  Future<void> finishSession(PilotSocket activeSocket) async {
    if (!identical(socket, activeSocket)) return;
    ++startGeneration;
    closeTimer?.cancel();
    closeTimer = null;
    socket = null;
    stopping = true;
    listening = false;
    connecting = startInFlight;
    final activeAudio = audio;
    audio = null;
    await activeAudio?.cancel();
    try {
      await recorder.stop();
    } catch (_) {}
    stopping = false;
    repaint();
  }

  Future<void> editEquation() => showEquationEditor(context, widget.model);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs can temporarily make the app inactive before recording.
    if (state == AppLifecycleState.paused ||
        (state == AppLifecycleState.inactive &&
            (listening || socket != null))) {
      stop();
    }
  }

  @override
  void dispose() {
    disposed = true;
    ++startGeneration;
    closeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.model.onDraftChanged = null;
    audio?.cancel();
    incoming?.cancel();
    socket?.close();
    recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.model.s;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 10),
        Text(
          s.t('HABLA EN MATEMÁTICAS', 'SPEAK IN MATH'),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  [
                        ...committed,
                        transcript,
                      ].where((v) => v.isNotEmpty).join(' ').isEmpty
                      ? s.t(
                          '“La integral de equis al cuadrado,\nentre cero y uno”',
                          '“The integral of x squared,\nfrom zero to one”',
                        )
                      : [...committed, transcript].join(' '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.6,
                    color: listening
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              message,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: FilledButton.tonalIcon(
                onPressed: connecting || stopping
                    ? null
                    : listening
                    ? stop
                    : start,
                icon: connecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                      ),
                label: Text(
                  stopping
                      ? s.t('Finalizando…', 'Finishing…')
                      : connecting
                      ? s.t('Conectando…', 'Connecting…')
                      : listening
                      ? s.t('Terminar dictado', 'Finish dictation')
                      : s.t('Comenzar dictado', 'Start dictation'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: s.t('Editar ecuación', 'Edit equation'),
              onPressed: editEquation,
              icon: const Icon(Icons.keyboard_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          s.t(
            'Puedes corregir la ecuación mientras hablas.',
            'You can edit the equation while speaking.',
          ),
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
