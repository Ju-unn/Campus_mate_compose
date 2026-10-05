import 'package:campus_mate/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'area1.dart';
import 'area3.dart';
import 'area4.dart';
import 'area2.dart';
import 'area2_c.dart';
import 'area2_b.dart';
import 'area2_d.dart';
import 'area2_two_poll.dart';
import 'support.dart';

/// 가설 하나 = 앱을 한 번 켜서 도는 것. 진행 프로그램(`python -m e2e run`)이 앱을 켜고 우편함에 `{"case": 번호}` 를 넣는다.
/// 빌드: `flutter build apk --debug -t integration_test/e2e_test.dart --dart-define-from-file=e2e.env`.
/// 가설이 Map 을 돌려주면 pass 말에 같이 실어 보낸다(누른 시각 · 걸린 시간 같은 PC 판정 재료).
final Map<String, Future<Object?> Function(WidgetTester tester, Map<String, dynamic> job)> cases = {
  ...area1Cases,
  ...area3Cases,
  ...area4Cases,
  ...area2Cases,
  ...area2cCases,
  ...area2bCases,
  ...area2dCases,
  ...area2TwoPollCases,
  // 앱이 켜져 첫 화면이 그려지고 우편함 왕복이 된다.
  'SMOKE': (tester, job) async {
    await pumpUntil(tester, find.byType(Scaffold));
    return null;
  },
  // 실패가 진행 프로그램까지 fail 로 닿는지 — 없는 글자를 짧게 기다린다.
  'SMOKE-FAIL': (tester, job) async {
    await pumpUntil(tester, find.text('E2E 에 없는 글자'), timeout: const Duration(seconds: 3));
    return null;
  },
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('e2e 가설 하나', (tester) async {
    final job = await hear();
    final name = job['case'] as String;
    final run = cases[name];
    if (run == null) {
      await say({'case': name, 'result': 'blocked', 'note': '앱에 없는 가설'});
      return;
    }
    await app.main();
    try {
      final extra = await run(tester, job);
      // 넘침 같은 프레임 오류도 실패로 본다.
      final error = tester.takeException();
      if (error != null) throw TestFailure('$error');
      await say({'case': name, 'result': 'pass', if (extra is Map<String, Object?>) ...extra});
    } on E2eBlocked catch (blocked) {
      await say({'case': name, 'result': 'blocked', 'note': '$blocked'});
    } catch (error) {
      await say({'case': name, 'result': 'fail', 'note': '$error'});
      rethrow;
    }
  });
}
