import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../core/model.dart';
import '../math/latex.dart';
import 'camera_panel.dart';
import 'graph.dart';
import 'ink_pad.dart';
import 'math_editor.dart';
import 'settings.dart';
import 'voice_panel.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _editorKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) ref.read(notebookProvider).save();
  }

  void graph(AppModel m) {
    try {
      final ast = m.graphExpression();
      final formula = astToLatex(ast);
      if (!m.curves.any(
        (c) => c['latex'] == formula && c['angleMode'] == m.angleMode,
      )) {
        if (m.curves.length == 4) {
          m.report(
            m.s.t(
              'Quita una curva antes de añadir otra.',
              'Remove a curve before adding another.',
            ),
          );
          return;
        }
        m.curves.add({'ast': ast, 'latex': formula, 'angleMode': m.angleMode});
        m.scheduleSave();
      }
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => GraphScreen(
            curves: m.curves,
            strings: m.s,
            onChanged: m.scheduleSave,
          ),
        ),
      );
    } catch (e) {
      m.report(e);
    }
  }

  void history(AppModel m) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: HistoryPanel(model: m, onSelect: () => Navigator.pop(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(notebookProvider);
    final s = m.s;
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemStatusBarContrastEnforced: false,
          ),
      child: Scaffold(
        body: !m.loaded
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 850 && !m.maximized;
                    final workspace = Row(
                      children: [
                        if (wide)
                          SizedBox(width: 280, child: HistoryPanel(model: m)),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              wide ? 12 : 8,
                              4,
                              8,
                              8,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: s.t('Historial', 'History'),
                                      onPressed: () => history(m),
                                      icon: const Icon(Icons.history_rounded),
                                    ),
                                    IconButton(
                                      tooltip: s.t('Configuración', 'Settings'),
                                      onPressed: () => showSettings(context, m),
                                      icon: const Icon(Icons.tune_rounded),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: m.toggleAngle,
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: Text(
                                        m.angleMode.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: m.latex.isEmpty
                                          ? null
                                          : () => graph(m),
                                      icon: const Icon(
                                        Icons.show_chart_rounded,
                                        size: 20,
                                      ),
                                      label: Text(s.t('Graficar', 'Graph')),
                                    ),
                                    IconButton(
                                      tooltip: m.maximized
                                          ? s.t(
                                              'Restaurar pantalla',
                                              'Restore display',
                                            )
                                          : s.t(
                                              'Maximizar pantalla',
                                              'Maximize display',
                                            ),
                                      onPressed: m.expand,
                                      icon: Icon(
                                        m.maximized
                                            ? Icons.close_fullscreen_rounded
                                            : Icons.open_in_full_rounded,
                                        size: 19,
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: colors.outlineVariant.withValues(
                                          alpha: .65,
                                        ),
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: Column(
                                      children: [
                                        Flexible(
                                          flex: m.mode == InputMode.keyboard
                                              ? 1
                                              : 0,
                                          fit: FlexFit.tight,
                                          child: SizedBox(
                                            height: m.mode == InputMode.keyboard
                                                ? null
                                                : m.maximized
                                                ? 90
                                                : 120,
                                            child: MathEditor(
                                              key: _editorKey,
                                              latex: m.latex,
                                              language: m.language,
                                              showKeyboard:
                                                  m.mode ==
                                                      InputMode.keyboard &&
                                                  !m.maximized,
                                              onChanged: m.edit,
                                              onSubmit: m.calculate,
                                            ),
                                          ),
                                        ),
                                        if (m.result != null && !m.maximized)
                                          ResultCard(model: m),
                                        if (m.error != null ||
                                            m.notice != null ||
                                            m.ambiguities.isNotEmpty)
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxHeight: 78,
                                            ),
                                            child: SingleChildScrollView(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 5,
                                                    ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      m.error != null
                                                          ? Icons
                                                                .error_outline_rounded
                                                          : Icons
                                                                .check_circle_outline_rounded,
                                                      size: 16,
                                                      color: m.error != null
                                                          ? colors.error
                                                          : colors.primary,
                                                    ),
                                                    const SizedBox(width: 7),
                                                    Expanded(
                                                      child: Text(
                                                        m.error ??
                                                            (m
                                                                    .ambiguities
                                                                    .isNotEmpty
                                                                ? m.ambiguities
                                                                      .join(
                                                                        ' · ',
                                                                      )
                                                                : m.notice!),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: m.error != null
                                                              ? colors.error
                                                              : colors
                                                                    .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                    InkWell(
                                                      onTap: m.clearMessage,
                                                      child: const Icon(
                                                        Icons.close,
                                                        size: 15,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        _Actions(model: m),
                                        if (m.mode != InputMode.keyboard) ...[
                                          const Divider(height: 22),
                                          Expanded(
                                            child: switch (m.mode) {
                                              InputMode.ink => InkPad(
                                                strokes: m.ink,
                                                onChanged: m.updateInk,
                                                onRecognize: m.recognizeInk,
                                                strings: s,
                                                busy: m.busy,
                                              ),
                                              InputMode.camera => CameraPanel(
                                                photo: m.photo,
                                                onPhoto: m.setPhoto,
                                                onClear: m.clearPhoto,
                                                onRecognize: m.recognizePhoto,
                                                strings: s,
                                                busy: m.busy,
                                              ),
                                              InputMode.voice => VoicePanel(
                                                model: m,
                                              ),
                                              _ => const SizedBox.shrink(),
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: InputMode.values.map((mode) {
                                    final active = m.mode == mode;
                                    final (icon, label) = switch (mode) {
                                      InputMode.keyboard => (
                                        Icons.keyboard_alt_outlined,
                                        s.t('Teclado', 'Keyboard'),
                                      ),
                                      InputMode.ink => (
                                        Icons.draw_outlined,
                                        s.t('Escribir', 'Write'),
                                      ),
                                      InputMode.camera => (
                                        Icons.camera_alt_outlined,
                                        s.t('Cámara', 'Camera'),
                                      ),
                                      InputMode.voice => (
                                        Icons.mic_none_rounded,
                                        s.t('Voz', 'Voice'),
                                      ),
                                    };
                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        child: Semantics(
                                          selected: active,
                                          button: true,
                                          label: label,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            onTap: () => m.setMode(mode),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 180,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: active
                                                    ? colors.primary
                                                    : colors
                                                          .surfaceContainerLow,
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    icon,
                                                    size: 23,
                                                    color: active
                                                        ? colors.onPrimary
                                                        : colors
                                                              .onSurfaceVariant,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    label,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: active
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: active
                                                          ? colors.onPrimary
                                                          : colors
                                                                .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: SizedBox(
                        height: constraints.maxHeight < 600
                            ? 600
                            : constraints.maxHeight,
                        child: workspace,
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) {
    final m = model, s = m.s;
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          tooltip: s.t('Nueva ecuación', 'New equation'),
          onPressed: () => m.edit(''),
          icon: const Icon(Icons.add_rounded, size: 20),
        ),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: m.operation,
              style: TextStyle(color: colors.onSurface, fontSize: 12),
              items:
                  [
                        'evaluate',
                        'exact',
                        'simplify',
                        'expand',
                        'factor',
                        'solve',
                        'differentiate',
                        'integrate',
                        'limit',
                      ]
                      .map(
                        (op) => DropdownMenuItem(
                          value: op,
                          child: Text(s.operation(op)),
                        ),
                      )
                      .toList(),
              onChanged: (v) {
                if (v == null) return;
                m.setOperation(v);
                if (v == 'limit' && !m.latex.contains('\\lim')) {
                  m.edit(
                    '\\lim_{${m.variable}\\to 0}\\left(${m.latex}\\right)',
                  );
                }
              },
            ),
          ),
        ),
        if ([
              'solve',
              'differentiate',
              'integrate',
              'limit',
            ].contains(m.operation) &&
            !m.hasBoundVariable)
          PopupMenuButton<String>(
            tooltip: s.t('Variable', 'Variable'),
            initialValue: m.variable,
            onSelected: m.setVariable,
            itemBuilder: (_) => [
              'x',
              'y',
              'z',
              't',
            ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                m.variable,
                style: TextStyle(
                  color: colors.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: m.busy || m.latex.isEmpty ? null : m.calculate,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          ),
          child: m.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.t('Resolver', 'Solve')),
        ),
      ],
    );
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) {
    final result = model.result!, s = model.s;
    final colors = Theme.of(context).colorScheme;
    final verification = result['verification'] as Map?;
    final latex = result['latex'] as String? ?? '';
    final plain = result['text'] as String? ?? '';
    final approximation = result['approximation'] as String?;
    final details = [
      ...(result['conditions'] as List? ?? []).map((c) => c.toString()),
      if (verification?['detail'] != null) verification!['detail'].toString(),
    ].join('\n');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      s.status(result['status'] as String),
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    if (verification?['status'] == 'verified') ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.verified_outlined,
                        size: 14,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 60),
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: latex.isEmpty
                          ? Text(
                              plain,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 14,
                              ),
                            )
                          : Math.tex(
                              latex,
                              textStyle: TextStyle(
                                color: colors.onSurface,
                                fontSize: 24,
                              ),
                              onErrorFallback: (_) => Text(
                                plain,
                                style: const TextStyle(fontSize: 19),
                              ),
                            ),
                    ),
                  ),
                ),
                if (approximation != null &&
                    approximation.isNotEmpty &&
                    result['status'] == 'exact')
                  Text(
                    '≈ $approximation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (details.isNotEmpty)
            IconButton(
              tooltip: s.t('Dominio y comprobación', 'Domain and verification'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t(
                            'Dominio y comprobación',
                            'Domain and verification',
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        SelectableText(details),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.info_outline_rounded, size: 19),
            ),
          IconButton(
            tooltip: s.t('Copiar resultado', 'Copy result'),
            onPressed: () => Clipboard.setData(
              ClipboardData(text: latex.isNotEmpty ? latex : plain),
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.model, this.onSelect});
  final AppModel model;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) {
    final s = model.s, colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
          child: Row(
            children: [
              Text(
                s.t('Historial', 'History'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                tooltip: s.t('Vaciar historial', 'Clear history'),
                onPressed: model.history.isEmpty
                    ? null
                    : () async {
                        await model.clearHistory();
                        onSelect?.call();
                      },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: model.history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 32,
                          color: colors.primary.withValues(alpha: .5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          s.t(
                            'Tus ideas matemáticas,\nun cálculo a la vez.',
                            'Your mathematical ideas,\none calculation at a time.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: model.history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = model.history[index];
                    final result = entry['result'] as Map;
                    return Material(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          model.restore(entry);
                          onSelect?.call();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${s.operation(entry['operation'] as String)} · ${(entry['angleMode'] as String).toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Math.tex(
                                  entry['source'] as String,
                                  textStyle: TextStyle(
                                    fontSize: 17,
                                    color: colors.onSurface,
                                  ),
                                  onErrorFallback: (_) =>
                                      Text(entry['source'] as String),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Math.tex(
                                  result['latex'] as String? ?? '',
                                  textStyle: TextStyle(
                                    fontSize: 19,
                                    color: colors.primary,
                                  ),
                                  onErrorFallback: (_) =>
                                      Text(result['text'] as String? ?? ''),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
