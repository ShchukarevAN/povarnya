import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_theme.dart';
import 'data/app_settings.dart';
import 'presentation/project_analyzer_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings().load();
  runApp(ProjectAnalyzerApp(themeName: AppSettings().themeName));
}

class ProjectAnalyzerApp extends StatelessWidget {
  const ProjectAnalyzerApp({super.key, required this.themeName});
  final String themeName;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Анализатор проекта «Поварня»',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('ru')],
    theme: appTheme(themeName),
    home: const ProjectAnalyzerScreen(),
  );
}
