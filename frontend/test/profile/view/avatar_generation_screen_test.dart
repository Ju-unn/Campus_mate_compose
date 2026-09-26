import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/progress_dots.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_avatar_repository.dart';
import '../model/fake_onboarding_repository.dart';

const _url = 'https://x.supabase.co/storage/v1/object/public/avatars/aa/avatar.png';

void main() {
  late FakeAvatarRepository repository;
  late FakeOnboardingRepository onboardingRepository;

  setUp(() {
    repository = FakeAvatarRepository();
    onboardingRepository = FakeOnboardingRepository();
  });

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        avatarRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AvatarGenerationScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('결과 화면은 다 찬 설문 막대를 그대로 둔다', (tester) async {
    // 05-12 계열은 6점 묶음이 아니다(pen) — 여기 오는 사람은 설문까지 이미 끝냈다.
    await pump(tester);

    expect(find.byType(ProgressDots), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first);
    expect(bar.value, 1.0);
  });

  testWidgets('완성 화면은 제목과 부제를 pen 문구 그대로 보여 준다', (tester) async {
    // 부제(pen `srOuh`)가 없으면 "다음" 이 무엇을 하는 버튼인지, 나중에 다시 만들 수 있는지를 아무도 모른다.
    repository.nextResult = const Success(AvatarReady(_url));

    await pump(tester);

    expect(find.text('아바타가 완성됐어요'), findsOneWidget);
    expect(
      find.text('마음에 들면 다음 단계로 넘어가요. 나중에 설정에서 다시 만들 수 있어요.'),
      findsOneWidget,
    );
  });

  testWidgets('다음을 누르기 전에는 다음 단계를 묻지 않는다', (tester) async {
    // 받자마자 다음 단계를 물으면 라우터가 06-1 로 화면을 바꿔 버려서,
    // 애써 만든 아바타도 05-12d 의 보상 안내도 사람이 못 본다. 넘어가는 시점은 사람이 고른다.
    repository.nextResult = const Success(AvatarReady(_url));

    await pump(tester);

    expect(onboardingRepository.fetchCount, 0);

    await tester.tap(find.text('다음'));
    await tester.pump();

    expect(onboardingRepository.fetchCount, 1);
  });

  testWidgets('기본 아바타로 대신했어도 같은 완성 화면을 두고 시트로만 알린다', (tester) async {
    // pen 에 기본 아바타 전용 화면은 없다 — 05-12c 위에 05-12d 시트(`Q7VmU`)를 얹는다.
    repository.nextResult = const Success(AvatarFallback(_url, 10));

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('기본 아바타로 시작해요'), findsNothing);
    expect(find.text('아바타가 완성됐어요'), findsOneWidget);
    expect(find.text('기본 아바타로 대신했어요'), findsOneWidget);
    expect(
      find.text('서버 오류로 하트 10개 드렸어요. 설정 > 아바타 재생성 에서 다시 만들 수 있어요.'),
      findsOneWidget,
    );
    // 시트 버튼은 "확인" 하나다(pen 의 취소 버튼은 꺼져 있다).
    expect(find.text('확인'), findsOneWidget);
    expect(find.text('취소'), findsNothing);
  });

  testWidgets('그림을 못 불러와도 카드 크기를 지키고 예외 없이 그린다', (tester) async {
    // 테스트 환경의 이미지 요청은 늘 400 이다 — 운영에서 주소가 상했을 때와 같은 자리다.
    // 아바타는 서버에 이미 있다. 빈 카드로 두고 다음으로 갈 길만 남긴다(pen 에 대체 문구가 없다).
    repository.nextResult = const Success(AvatarReady(_url));

    await pump(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Image)), const Size(180, 180));
    final card = find.ancestor(of: find.byType(Image), matching: find.byType(Container)).first;
    expect(tester.getSize(card).height, 280);
    expect(find.text('다음'), findsOneWidget);
  });
}
