import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
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
  web.HTMLIFrameElement? frame;
  bool ready = false;
  String? _browserLatex;
  late final JSFunction listener;
  @override
  void initState() {
    super.initState();
    listener = ((web.Event event) {
      final message = event as web.MessageEvent;
      if (message.origin != Uri.base.origin ||
          message.source != frame?.contentWindow ||
          message.data == null ||
          !message.data.isA<JSString>()) {
        return;
      }
      final dynamic data;
      try {
        data = jsonDecode((message.data as JSString).toDart);
      } catch (_) {
        return;
      }
      if (data is! Map || data['channel'] != 'jem-editor') return;
      if (data['type'] == 'ready') {
        ready = true;
        configure(restoreDraft: true);
      } else if (data['type'] == 'input' && data['latex'] is String) {
        _browserLatex = data['latex'] as String;
        widget.onChanged(_browserLatex!);
      } else if (data['type'] == 'submit') {
        widget.onSubmit();
      }
    }).toJS;
    web.window.addEventListener('message', listener);
  }

  void createElement(Object element) {
    final iframe = element as web.HTMLIFrameElement;
    frame = iframe;
    iframe
      ..title = 'Editor matemático'
      ..setAttribute('sandbox', 'allow-scripts allow-same-origin')
      ..src = Uri.base.resolve('assets/assets/editor/index.html').toString();
    iframe.style
      ..width = '100%'
      ..height = '100%'
      ..border = '0';
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => configure(restoreDraft: restoreDraft),
    );
  }

  void configure({bool restoreDraft = false}) {
    if (!ready || !mounted) return;
    if (restoreDraft) _browserLatex = widget.latex;
    frame?.contentWindow?.postMessage(
      jsonEncode({
        'channel': 'jem-editor',
        'type': 'configure',
        'configuration': {
          'dark': Theme.of(context).brightness == Brightness.dark,
          'palette': JemPalette.editor(Theme.of(context).colorScheme),
          'language': widget.language,
          'keyboard': widget.showKeyboard,
          'focusRequest': widget.focusRequest,
          if (restoreDraft) 'latex': widget.latex,
        },
      }).toJS,
      Uri.base.origin.toJS,
    );
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A modal above the editor must receive pointer events instead of the iframe.
    frame?.style.pointerEvents = (ModalRoute.of(context)?.isCurrent ?? true)
        ? 'auto'
        : 'none';
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: HtmlElementView.fromTagName(
        tagName: 'iframe',
        onElementCreated: createElement,
      ),
    );
  }
}
