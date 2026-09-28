import 'dart:async';

import 'package:campus_mate/core/auth/session_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late StreamController<AuthState> authChanges;
  late int builds;
  late Provider<int> probe;

  setUp(() {
    authChanges = StreamController<AuthState>();
    builds = 0;
    // 한 컨테이너 안에서는 한 번만 만들어진다 — 숫자가 오르면 컨테이너가 새것이다.
    probe = Provider<int>((ref) => ++builds);
  });
  tearDown(() => authChanges.close());

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(SessionScope(
      authChanges: authChanges.stream,
      child: Consumer(
        builder: (context, ref, _) => Text('${ref.watch(probe)}', textDirection: TextDirection.ltr),
      ),
    ));
  }

  testWidgets('로그아웃 뒤 다른 계정으로 들어오면 앞 사람 값이 아니라 새 사람 값이 보인다', (tester) async {
    // 회귀: provider 가 autoDispose 가 아니라 앞 사람의 내 프로필 · 카드가 그대로 보이던 자리다.
    var currentUser = 'A';
    final profile = FutureProvider<String>((ref) async => '$currentUser 의 프로필');
    await tester.pumpWidget(SessionScope(
      authChanges: authChanges.stream,
      child: Consumer(
        builder: (context, ref, _) =>
            Text(ref.watch(profile).value ?? '', textDirection: TextDirection.ltr),
      ),
    ));
    await tester.pump();
    expect(find.text('A 의 프로필'), findsOneWidget);

    authChanges.add(const AuthState(AuthChangeEvent.signedOut, null));
    currentUser = 'B';
    authChanges.add(const AuthState(AuthChangeEvent.signedIn, null));
    // 실제 스트림(비동기 전달)이라 pump 한 번은 이벤트가 아직 안 온 상태 · 두 번째에서야
    // 새 ProviderScope 로 갈아끼워지고, FutureProvider 는 그 다음 pump 에서야 값을 낸다.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('A 의 프로필'), findsNothing);
    expect(find.text('B 의 프로필'), findsOneWidget);
  });

  testWidgets('로그아웃하면 provider 가 기억하던 값을 버리고 새로 만든다', (tester) async {
    await pump(tester);
    expect(find.text('1'), findsOneWidget);

    authChanges.add(const AuthState(AuthChangeEvent.signedOut, null));
    // 실제 스트림이라 pump 한 번으로는 이벤트가 아직 안 왔다 — 두 번째 pump 에서 새 ProviderScope 가 보인다.
    await tester.pump();
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('토큰 갱신 · 로그인에는 그대로 둔다', (tester) async {
    // 로그인 중(인증코드 확인)인 ViewModel 을 중간에 버리면 안 된다.
    await pump(tester);

    authChanges
      ..add(const AuthState(AuthChangeEvent.tokenRefreshed, null))
      ..add(const AuthState(AuthChangeEvent.signedIn, null));
    // 실제 스트림이라 pump 한 번은 이벤트가 아직 안 온 상태 — 두 번째 pump 까지 봐야 그대로인지 알 수 있다.
    await tester.pump();
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('인증 스트림 오류에 넘어지지 않는다', (tester) async {
    // gotrue 는 세션 복구 실패 같은 것을 스트림 오류로도 보낸다 — onError 가 없으면 잡히지 않은 오류가 된다.
    await pump(tester);

    authChanges.addError(AuthException('refresh failed'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
  });
}
