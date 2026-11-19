import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/services/offline_speech_recognizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled Zipformer2 model extracts into the configured data directory',
    () async {
      await OfflineSpeechRecognizer.instance.prepare();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
