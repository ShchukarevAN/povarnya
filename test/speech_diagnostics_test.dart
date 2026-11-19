import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/services/speech_diagnostics.dart';

void main() {
  test('speech failures expose a stable stage and useful explanation', () {
    const failure = SpeechFailure(
      SpeechFailureStage.modelLoad,
      technicalDetails: 'bad model',
    );

    expect(failure.stage.code, 'MODEL_LOAD');
    expect(failure.userMessage, contains('Zipformer2'));
    expect(failure.userMessage, contains('Код: MODEL_LOAD'));
    expect(failure.toString(), contains('bad model'));
  });

  test('empty recognition is different from missing microphone audio', () {
    expect(SpeechFailureStage.noResult.code, 'NO_RESULT');
    expect(SpeechFailureStage.noSpeech.code, 'AUDIO_NO_SPEECH');
  });
}
