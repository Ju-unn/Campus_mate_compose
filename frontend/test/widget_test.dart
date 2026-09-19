import 'package:campus_mate/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // main.dart 가 실제 Supabase 세션을 읽으므로(A10), 이 스모크 테스트도
  // 더미 값으로나마 초기화해 둬야 CampusMateApp 이 죽지 않는다.
  // shared_preferences 는 새 의존성을 추가하지 않고 플랫폼 채널만 흉내 낸다.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        return <String, Object>{};
      }
      return null;
    });
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('앱을 실행하면 로그인 화면으로 진입한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CampusMateApp()));
    await tester.pumpAndSettle();

    expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
  });
}
