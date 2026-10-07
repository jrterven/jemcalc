import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/core/model.dart';
import 'package:jem_calc/core/store.dart';
import 'package:jem_calc/core/strings.dart';
import 'package:jem_calc/features/ink_pad.dart';

class _MemoryStore extends NotebookStore {
  @override
  Future<void> set(String key, dynamic value) async {}
}

void main() {
  Future<AppModel> mount(
    WidgetTester tester, {
    VoidCallback? onRecognize,
  }) async {
    final model = AppModel(store: _MemoryStore());
    addTearDown(model.dispose);
    // Match the production controlled-widget wiring. A child-only rebuild
    // cannot update strokes unless AppModel also notifies its listeners.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 500,
              child: ListenableBuilder(
                listenable: model,
                builder: (context, _) => InkPad(
                  strokes: model.ink,
                  onChanged: model.updateInk,
                  onRecognize: onRecognize ?? () {},
                  strings: const Strings('en'),
                  busy: model.busy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return model;
  }

  Future<void> draw(
    WidgetTester tester,
    Offset start, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final gesture = await tester.startGesture(start, kind: kind);
    await tester.pump();
    await gesture.moveBy(const Offset(30, 10));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 15));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  }

  IconButton tool(WidgetTester tester, String name) =>
      tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == name,
        ),
      );
  FilledButton recognize(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Recognize equation'),
  );

  testWidgets(
    'first touch stroke on an empty canvas persists and enables tools',
    (tester) async {
      var recognitions = 0;
      final model = await mount(tester, onRecognize: () => recognitions++);
      expect(find.text('Write an equation'), findsOneWidget);
      expect(tool(tester, 'Undo').onPressed, isNull);
      expect(recognize(tester).onPressed, isNull);
      final rect = tester.getRect(find.byKey(const ValueKey('ink-canvas')));
      final start = rect.topLeft + const Offset(60, 75);
      await draw(tester, start);
      expect(model.ink, hasLength(1));
      expect(model.ink.single, hasLength(3));
      expect(model.ink.single.first.dx, closeTo(100, 1e-8));
      expect(model.ink.single.last.dx, greaterThan(model.ink.single.first.dx));
      expect(find.text('Write an equation'), findsNothing);
      expect(tool(tester, 'Undo').onPressed, isNotNull);
      expect(recognize(tester).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Recognize equation'));
      expect(recognitions, 1);
    },
  );

  testWidgets(
    'drawing works after undo to empty and after erasing all strokes',
    (tester) async {
      final model = await mount(tester);
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('ink-canvas')),
      );
      final first = origin + const Offset(70, 80);
      final second = origin + const Offset(70, 180);
      await draw(tester, first);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(model.ink, isEmpty);
      expect(find.text('Write an equation'), findsOneWidget);
      expect(recognize(tester).onPressed, isNull);
      expect(tool(tester, 'Redo').onPressed, isNotNull);
      await draw(tester, first);
      await draw(tester, second);
      expect(model.ink, hasLength(2));
      expect(tool(tester, 'Redo').onPressed, isNull);
      await tester.tap(find.byTooltip('Stroke eraser'));
      await tester.pump();
      await tester.tapAt(first);
      await tester.pump();
      expect(model.ink, hasLength(1));
      expect(model.ink.single.first.dy, closeTo(300, 1e-8));
      await tester.tapAt(second);
      await tester.pump();
      expect(model.ink, isEmpty);
      expect(tool(tester, 'Undo').onPressed, isNull);
      expect(recognize(tester).onPressed, isNull);
      await tester.tap(find.byTooltip('Stroke eraser'));
      await tester.pump();
      await draw(tester, first);
      expect(model.ink, hasLength(1));
      expect(recognize(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'pen-only mode ignores fingers but still accepts the first stylus stroke',
    (tester) async {
      final model = await mount(tester);
      await tester.tap(find.text('Pen only'));
      await tester.pump();
      final point = tester.getCenter(find.byKey(const ValueKey('ink-canvas')));
      await draw(tester, point);
      expect(model.ink, isEmpty);
      await draw(tester, point, kind: PointerDeviceKind.stylus);
      expect(model.ink, hasLength(1));
      expect(recognize(tester).onPressed, isNotNull);
    },
  );
}
