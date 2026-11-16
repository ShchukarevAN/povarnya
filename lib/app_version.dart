import 'package:package_info_plus/package_info_plus.dart';

/// Единственный источник версии во время выполнения. Значение берётся из
/// `version` в pubspec.yaml, которое Flutter переносит в метаданные сборки.
final Future<String> appVersion = PackageInfo.fromPlatform().then(
  (info) => info.version,
);
