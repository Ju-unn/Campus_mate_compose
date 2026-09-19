import 'package:campus_mate/auth/model/school_info_repository_provider.dart';
import 'package:campus_mate/auth/model/school_name_provider.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/view/school_info_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_school_info_repository.dart';
import '../model/fake_verification_gate_repository.dart';

/// 학교명 조회가 이미 끝난 기본 상태. 학교명은 인증(3b)으로 정해진 값이라 화면이 바꾸지 못한다.
const AsyncValue<String> _loadedSchoolName = AsyncData<String>('서울대학교');

void main() {
  late FakeSchoolInfoRepository repository;

  setUp(() => repository = FakeSchoolInfoRepository());

  Future<void> pumpScreen(
    WidgetTester tester, {
    AsyncValue<String> schoolName = _loadedSchoolName,
  }) async {
    final container = ProviderContainer(
      overrides: [
        schoolInfoRepositoryProvider.overrideWithValue(repository),
        schoolNameProvider.overrideWithValue(schoolName),
        // 제출에 성공하면 ViewModel 이 게이트를 다시 조회한다(A10)
        verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SchoolInfoScreen()),
      ),
    );
  }

  ElevatedButton findCallToAction(WidgetTester tester) {
    return tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '다음'));
  }

  Future<void> enterSchoolInfo(WidgetTester tester, String department, String studentNumber) async {
    await tester.enterText(find.byType(TextField).at(0), department);
    await tester.enterText(find.byType(TextField).at(1), studentNumber);
    await tester.pump();
  }

  group('SchoolInfoScreen', () {
    testWidgets('학교명을 불러오는 동안에는 스피너만 보여준다', (tester) async {
      await pumpScreen(tester, schoolName: const AsyncLoading<String>());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('다음'), findsNothing);
    });

    testWidgets('학교명 조회가 실패하면 안내와 다시 시도만 보여준다', (tester) async {
      await pumpScreen(
        tester,
        schoolName: AsyncError<String>(Exception('조회 실패'), StackTrace.empty),
      );

      expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('DESIGN.md 화면 3c 확정 카피를 보여준다', (tester) async {
      await pumpScreen(tester);

      expect(find.text('학생 인증'), findsOneWidget); // 앱바 제목
      expect(find.text('학과와 학번을 알려주세요'), findsOneWidget);
      expect(find.text('학교는 인증으로 확인했어요. 학과와 학번은 직접 알려주셔야 해요.'), findsOneWidget);
      expect(find.text('학교·학과·학번은 카드와 프로필에 공개돼요.'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
    });

    testWidgets('인증으로 확인된 학교명을 확인됨 뱃지와 함께 읽기 전용으로 보여준다', (tester) async {
      await pumpScreen(tester);

      expect(find.text('서울대학교'), findsOneWidget);
      expect(find.text('확인됨'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // 학교명은 입력칸이 아니다
    });

    testWidgets('학과·학번 입력칸의 라벨과 플레이스홀더를 보여준다', (tester) async {
      await pumpScreen(tester);

      expect(find.text('학과 · 필수'), findsOneWidget);
      expect(find.text('예: 컴퓨터공학과'), findsOneWidget);
      expect(find.text('학번 · 필수'), findsOneWidget);
      expect(find.text('예: 21'), findsOneWidget);
    });

    testWidgets('학과·학번이 모두 비어 있으면 CTA 가 비활성이다', (tester) async {
      await pumpScreen(tester);

      expect(findCallToAction(tester).enabled, isFalse);
    });

    testWidgets('학과만 입력하면 CTA 가 여전히 비활성이다', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).at(0), '컴퓨터공학과');
      await tester.pump();

      expect(findCallToAction(tester).enabled, isFalse);
    });

    testWidgets('학과와 학번을 모두 입력하면 CTA 가 활성화된다', (tester) async {
      await pumpScreen(tester);

      await enterSchoolInfo(tester, '컴퓨터공학과', '21');

      expect(findCallToAction(tester).enabled, isTrue);
    });

    testWidgets('CTA 를 누르면 입력한 학과·학번을 그대로 제출한다', (tester) async {
      await pumpScreen(tester);
      await enterSchoolInfo(tester, '컴퓨터공학과', '21');

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      expect(repository.submittedDepartments.single.toRequestValue(), '컴퓨터공학과');
      expect(repository.submittedStudentNumbers.single.toRequestValue(), '21');
    });

    testWidgets('제출이 실패하면 안내 문구와 함께 입력값이 남는다', (tester) async {
      repository.nextSubmitResult = const FailureResult<void>(NetworkFailure());
      await pumpScreen(tester);
      await enterSchoolInfo(tester, '컴퓨터공학과', '21');

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
      expect(find.text('컴퓨터공학과'), findsOneWidget);
      expect(findCallToAction(tester).enabled, isTrue); // 바로 다시 제출할 수 있다
    });
  });
}
