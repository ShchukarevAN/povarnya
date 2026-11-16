import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:povarnya/app_info.dart';
import 'package:povarnya/startup_loading_video.dart';
import 'package:povarnya/update/update_screen.dart';
import 'package:povarnya/update/update_service.dart';

void main() {
  testWidgets('кнопка обновления стоит под текущей версией', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              Builder(
                builder: (context) => IconButton(
                  key: const ValueKey('reference-button'),
                  onPressed: () => showSettingsPopover(context),
                  icon: const Icon(Icons.menu_book_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('reference-button')));
    await tester.pumpAndSettle();

    final version = find.textContaining('Версия:');
    final update = find.text('Проверить обновления');
    expect(version, findsOneWidget);
    expect(update, findsOneWidget);
    expect(
      tester.getTopLeft(update).dy,
      greaterThan(tester.getTopLeft(version).dy),
    );
  });

  testWidgets('полноэкранная загрузка сменяется точной ошибкой', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateScreen(
          loadingBuilder: (onFirstCycleCompleted) {
            onFirstCycleCompleted();
            return const PovarnyaLoadingVideo(initializePlayer: false);
          },
          serviceBuilder: (onProgress, onLog) => UpdateService(
            client: client,
            onProgress: onProgress,
            onLog: onLog,
            latestReleaseUrl: 'https://api.github.com/repos/ShchukarevAN/povarnya/releases/latest',
            installedVersionOverride: '0.5.0',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PovarnyaLoadingVideo), findsOneWidget);
    expect(find.text('Обновление «Поварни»'), findsNothing);

    response.complete(
      http.Response(
        jsonEncode({'message': 'Not Found'}),
        404,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'x-github-request-id': 'UI-TEST-ID',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Релиз GitHub не найден'), findsOneWidget);
    expect(find.textContaining('GITHUB_HTTP_404'), findsOneWidget);
    expect(find.text('Вернуться в текущую версию'), findsOneWidget);
  });
}
