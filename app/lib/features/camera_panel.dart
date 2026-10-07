import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../core/strings.dart';

Uint8List normalizePhoto(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Invalid image');
  var result = img.bakeOrientation(image);
  if (result.width > 2000 || result.height > 2000) {
    result = img.copyResize(
      result,
      width: result.width >= result.height ? 2000 : null,
      height: result.height > result.width ? 2000 : null,
    );
  }
  return Uint8List.fromList(img.encodeJpg(result, quality: 90));
}

class CameraPanel extends StatefulWidget {
  const CameraPanel({
    super.key,
    required this.photo,
    required this.onPhoto,
    required this.onClear,
    required this.onRecognize,
    required this.strings,
    required this.busy,
  });
  final Uint8List? photo;
  final ValueChanged<Uint8List> onPhoto;
  final VoidCallback onClear, onRecognize;
  final Strings strings;
  final bool busy;
  @override
  State<CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends State<CameraPanel> with WidgetsBindingObserver {
  CameraController? camera;
  String? error;
  bool working = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.photo == null) initialize();
  }

  Future<void> initialize() async {
    final request = ++generation;
    try {
      final all = await availableCameras();
      if (all.isEmpty) {
        throw Exception(
          widget.strings.t('Cámara no disponible', 'Camera unavailable'),
        );
      }
      final c = CameraController(
        all.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => all.first,
        ),
        ResolutionPreset.high,
        enableAudio: false,
      );
      await c.initialize();
      if (!mounted || request != generation) {
        await c.dispose();
        return;
      }
      setState(() {
        camera = c;
        error = null;
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = e.toString());
      }
    }
  }

  Future<void> closeCamera() async {
    generation++;
    final c = camera;
    camera = null;
    await c?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On web, focusing MathLive's iframe can make Flutter inactive while the
    // page is still visible. Release the camera when the page is hidden instead.
    if ((!kIsWeb && state == AppLifecycleState.inactive) ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      closeCamera();
    } else if (state == AppLifecycleState.resumed &&
        widget.photo == null &&
        camera == null &&
        !working) {
      initialize();
    }
  }

  Future<void> capture({bool gallery = false}) async {
    if (working) return;
    setState(() => working = true);
    try {
      final file = gallery
          ? await ImagePicker().pickImage(source: ImageSource.gallery)
          : await camera?.takePicture();
      if (file == null) return;
      if (!mounted) return;
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        compressFormat: ImageCompressFormat.jpg,
        maxWidth: 2000,
        maxHeight: 2000,
        uiSettings: [
          if (kIsWeb)
            WebUiSettings(
              context: context,
              size: CropperSize(
                width: (MediaQuery.sizeOf(context).width - 128)
                    .clamp(180, 760)
                    .toInt(),
                height: (MediaQuery.sizeOf(context).height - 260)
                    .clamp(140, 480)
                    .toInt(),
              ),
              translations: WebTranslations(
                title: widget.strings.t(
                  'Recorta la ecuación',
                  'Crop the equation',
                ),
                rotateLeftTooltip: widget.strings.t(
                  'Girar a la izquierda',
                  'Rotate left',
                ),
                rotateRightTooltip: widget.strings.t(
                  'Girar a la derecha',
                  'Rotate right',
                ),
                cancelButton: widget.strings.t('Cancelar', 'Cancel'),
                cropButton: widget.strings.t('Recortar', 'Crop'),
              ),
            ),
          AndroidUiSettings(
            toolbarTitle: widget.strings.t(
              'Recorta la ecuación',
              'Crop the equation',
            ),
          ),
          IOSUiSettings(
            title: widget.strings.t('Recorta la ecuación', 'Crop the equation'),
          ),
        ],
      );
      if (cropped != null) {
        final bytes = await compute(
          normalizePhoto,
          await cropped.readAsBytes(),
        );
        if (mounted) {
          widget.onPhoto(bytes);
          await closeCamera();
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => working = false);
        if (widget.photo == null && camera == null) initialize();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    closeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: .05),
              child: SizedBox.expand(
                child: widget.photo != null
                    ? Image.memory(widget.photo!, fit: BoxFit.contain)
                    : error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(error!),
                        ),
                      )
                    : camera?.value.isInitialized == true
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: camera!.value.aspectRatio,
                          child: CameraPreview(camera!),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: widget.photo == null
              ? [
                  IconButton(
                    tooltip: s.t('Abrir imagen', 'Open image'),
                    onPressed: working ? null : () => capture(gallery: true),
                    icon: const Icon(Icons.photo_library_outlined),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: working || camera == null ? null : capture,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(s.t('Capturar', 'Capture')),
                  ),
                ]
              : [
                  TextButton.icon(
                    onPressed: widget.busy
                        ? null
                        : () {
                            widget.onClear();
                            initialize();
                          },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(s.t('Repetir', 'Retake')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.busy ? null : widget.onRecognize,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(s.t('Reconocer', 'Recognize')),
                  ),
                ],
        ),
      ],
    );
  }
}
