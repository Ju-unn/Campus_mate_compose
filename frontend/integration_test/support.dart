import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// PC 우편함(e2e/tools.py Hub). 기기 쪽은 늘 127.0.0.1:8765 — `adb reverse` 가 PC 의 기기별 포트로 잇는다.
final _hub = Uri.parse('http://127.0.0.1:8765');

/// 진행 프로그램이 넣은 일감 하나를 기다려 받는다. 우편함은 5초씩 붙잡았다가 없으면 204 를 준다.
Future<Map<String, dynamic>> hear({Duration timeout = const Duration(minutes: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final res = await http.get(_hub.replace(path: '/hear'));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    // 204 는 곧바로 다시 묻는다. 그 밖(우편함 고장)은 바쁜 루프가 되지 않게 쉰다.
    if (res.statusCode != 204) await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw TimeoutException('우편함에 일감이 오지 않음', timeout);
}

/// 앱 쪽 준비가 안 됐다(가설을 판정할 수 없다) — e2e_test.dart 가 fail 이 아니라 blocked 로 보낸다.
class E2eBlocked implements Exception {
  E2eBlocked(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// 앱이 [name] 에서 멈추고 PC 가 무언가 하기를 기다린다(e2e/tools.py Run.phone 의 midway) — PC 가 go 를 넣으면 이어 간다.
Future<void> step(String name) async {
  await say({'step': name});
  await hear();
}

/// 진행 프로그램에 말한다(결과 · 중간 값).
Future<void> say(Map<String, Object?> message) async {
  await http.post(_hub.replace(path: '/say'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(message));
}

/// 진행이 관리자 generate_link 로 받은 1회용 token_hash 로 로그인한다 — 메일이 나가지 않는다.
/// 앱이 Supabase 를 초기화한 뒤(app.main 다음)에 부른다.
Future<void> signIn(String tokenHash) async {
  await Supabase.instance.client.auth.verifyOTP(type: OtpType.magiclink, tokenHash: tokenHash);
}

/// [finder] 가 나타날 때까지 프레임을 흘린다. 실제 네트워크를 기다리므로 pumpAndSettle 대신 쓴다.
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('${timeout.inSeconds}초 안에 안 나타남: $finder');
}
