import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/main.dart';

void main() {
  testWidgets('основной экран ждёт и данные, и полный цикл заставки', (
    tester,
  ) async {
    final preparation = Completer<void>();
    VoidCallback? completeVideoCycle;

    await tester.pumpWidget(
      PovarnyaStartupApp(
        prepareApplication: (_) => preparation.future,
        loadingBuilder: (onFirstCycleCompleted) {
          completeVideoCycle = onFirstCycleCompleted;
          return const ColoredBox(
            key: ValueKey('startup'),
            color: Color(0xFFDCD2CC),
          );
        },
        applicationBuilder: (_) => const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('application-ready'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('startup')), findsOneWidget);

    preparation.complete();
    await tester.pump();
    expect(find.byKey(const ValueKey('startup')), findsOneWidget);

    completeVideoCycle!();
    await tester.pump();
    expect(find.text('application-ready'), findsOneWidget);
  });

  testWidgets('ошибка подготовки показывается внизу заставки', (tester) async {
    await tester.pumpWidget(
      PovarnyaStartupApp(
        prepareApplication: (_) async => throw StateError('database failed'),
        loadingBuilder: (_) => const ColoredBox(
          key: ValueKey('startup'),
          color: Color(0xFFDCD2CC),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('startup')), findsOneWidget);
    expect(find.byKey(const ValueKey('startup-error')), findsOneWidget);
    expect(find.textContaining('Ошибка запуска:'), findsOneWidget);
    expect(find.textContaining('database failed'), findsOneWidget);
  });
}
