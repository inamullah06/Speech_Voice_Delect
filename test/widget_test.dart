import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_app/main.dart';

void main() {
  testWidgets('App loads title smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeechToTextApp());
    expect(find.text('Voice Transcriber'), findsOneWidget);
  });
}
