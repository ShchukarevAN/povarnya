/// Build-time configuration for the self-updater.
///
/// The Android build script may override this URL through --dart-define.
abstract final class UpdateConfig {
  static const latestReleaseUrl = String.fromEnvironment(
    'POVARNYA_UPDATE_URL',
    defaultValue:
        'https://api.github.com/repos/ShchukarevAN/povarnya/releases/latest',
  );

  static const apkAssetName = String.fromEnvironment(
    'POVARNYA_UPDATE_ASSET',
    defaultValue: 'povarnya-android.apk',
  );

  static const requireSha256 = bool.fromEnvironment(
    'POVARNYA_UPDATE_REQUIRE_SHA256',
    defaultValue: true,
  );

  static const requestTimeout = Duration(seconds: 30);
  static const downloadTimeout = Duration(minutes: 15);
}
