import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/palette.dart';

class MathEditor extends StatefulWidget {
  const MathEditor({
    super.key,
    this.focusRequest = 0,
    required this.latex,
    required this.language,
    required this.showKeyboard,
    required this.onChanged,
    required this.onSubmit,
  });
  final String latex, language;
  final int focusRequest;
  final bool showKeyboard;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  @override
  State<MathEditor> createState() => _MathEditorState();
}

class _MathEditorState extends State<MathEditor> {
  late final WebViewController controller;
  bool ready = false;
  String? _browserLatex;
  String? error;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'JemBridge',
        onMessageReceived: (message) {
          final data = jsonDecode(message.message) as Map<String, dynamic>;
          if (data['type'] == 'ready') {
            ready = true;
            configure(restoreDraft: true);
          }
          if (data['type'] == 'input') {
            _browserLatex = data['latex'] as String;
            widget.onChanged(_browserLatex!);
          }
          if (data['type'] == 'submit') widget.onSubmit();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) =>
              r.url.startsWith('file:') ||
                  r.url.startsWith('https://appassets.androidplatform.net/')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => error = e.description);
            }
          },
        ),
      )
      ..loadFlutterAsset('assets/editor/index.html');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    configure();
  }

  @override
  void didUpdateWidget(covariant MathEditor old) {
    super.didUpdateWidget(old);
    final restoreDraft =
        widget.latex != old.latex && widget.latex != _browserLatex;
    // Mode changes resize the platform view; show its keyboard after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      configure(restoreDraft: restoreDraft);
    });
  }

  void configure({bool restoreDraft = false}) {
    if (!ready || !mounted) return;
    final configuration = <String, dynamic>{
      'dark': Theme.of(context).brightness == Brightness.dark,
      'palette': JemPalette.editor(Theme.of(context).colorScheme),
      'language': widget.language,
      'keyboard': widget.showKeyboard,
      'focusRequest': widget.focusRequest,
      if (restoreDraft) 'latex': widget.latex,
    };
    if (restoreDraft) _browserLatex = widget.latex;
    controller.runJavaScript('window.configure(${jsonEncode(configuration)});');
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: error == null
        ? WebViewWidget(controller: controller)
        : Center(child: Text(error!)),
  );
}
