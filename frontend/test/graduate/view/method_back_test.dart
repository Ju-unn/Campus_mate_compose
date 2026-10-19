import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:campus_mate/graduate/view/method_back.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_verification_gate_repository.dart';
import '../model/fake_graduate_verification_repository.dart';

void main() {
  late FakeGraduateVerificationRepository repository;
  late FakeVerificationGateRepository gateRepository;

  setUp(() {
    repository = FakeGraduateVerificationRepository();
    gateRepository = FakeVerificationGateRepository();
  });

  /// [methodBack] 이 돌려주는 함수를 화면 밖에서 꺼낸다 — 화살표와 시스템 뒤로가 같은 함수를 받는지 보려고.
  Future<VoidCallback> pumpBack(WidgetTester tester, {required bool isBusy}) async {
    late VoidCallback callback;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        graduateVerificationRepositoryProvider.overrideWithValue(repository),
        verificationGateRepositoryProvider.overrideWithValue(gateRepository),
      ],
      child: Consumer(builder: (context, ref, _) {
        callback = methodBack(ref, isBusy: isBusy);
        return const SizedBox();
      }),
    ));
    return callback;
  }

  testWidgets('사진을 올리는 중(isBusy)에는 눌러도 서버를 부르지 않는다', (tester) async {
    final back = await pumpBack(tester, isBusy: true);

    back();
    await tester.pump();

    expect(repository.chosen, isEmpty);
  });

  testWidgets('평소에는 눌리면 서버 값을 비운다(null)', (tester) async {
    final back = await pumpBack(tester, isBusy: false);

    back();
    await tester.pump();

    expect(repository.chosen, [null]);
  });

  testWidgets('연타해도 서버 값 비우기는 한 번이다', (tester) async {
    final back = await pumpBack(tester, isBusy: false);

    back();
    back();
    await tester.pump();

    expect(repository.chosen, hasLength(1));
  });
}
