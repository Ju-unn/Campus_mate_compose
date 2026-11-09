import 'package:campus_mate/core/app_update/update_requirement.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 문구 ARB(1.0.2 B8)를 앱 루트에 거는 배선(main.dart)을 지킨다 — 위임자 · 지원 언어. 위젯 시험은 각 `MaterialApp` 이 같은 위임자를
/// 스스로 달므로(⑧-c, `test/l10n/test_app_delegates_test.dart`) 앱 본체가 실제로 켜는지는 여기서만 본다.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        return <String, Object>{};
      }
      return true;
    });
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  Future<void> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        signOutProvider.overrideWithValue(() async {}),
        updateRequirementProvider.overrideWith((ref) async => const UpdateNotRequired()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('앱 루트는 문구 위임자를 켜고 지원 언어는 한국어 하나다', (tester) async {
    await pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.localizationsDelegates, AppLocalizations.localizationsDelegates);
    expect(app.supportedLocales, const [Locale('ko')]);
  });

  testWidgets('머티리얼 기본 문구가 한국어로 나온다 — 뒤로가기 툴팁 · 새로고침 · 붙여넣기', (tester) async {
    await pumpApp(tester);

    final material = MaterialLocalizations.of(tester.element(find.byType(Navigator).first));
    expect(material.backButtonTooltip, '뒤로');
    expect(material.refreshIndicatorSemanticLabel, '새로고침');
    expect(material.pasteButtonLabel, '붙여넣기');
  });
}
