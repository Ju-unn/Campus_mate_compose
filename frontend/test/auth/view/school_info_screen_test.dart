import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/school_info_repository_provider.dart';
import 'package:campus_mate/auth/model/school_name_provider.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/view/school_info_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../model/fake_school_info_repository.dart';
import '../model/fake_verification_gate_repository.dart';

/// 학교명 조회가 이미 끝난 기본 상태. 학교명은 인증(3b)으로 정해진 값이라 화면이 바꾸지 못한다.
const AsyncValue<String> _loadedSchoolName = AsyncData<String>('서울대학교');

const _logoUrl = 'https://logo.test/snu.webp';

/// 학교 로고 그림(간격 Padding 을 뺀 자리).
final _logo = find.descendant(
  of: find.byWidgetPredicate((w) => w is Image && w.image == const NetworkImage(_logoUrl)),
  matching: find.byType(RawImage),
);

/// 로고 요청을 받기만 하고 답하지 않는 HttpClient — 로고는 "아직 오는 중"이라 자리만 잡는다(계정 화면 테스트와 같은 방식).
class _PendingHttpClient extends Mock implements HttpClient {}

class _PendingHttpOverrides extends HttpOverrides {
  _PendingHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _client;
}

void main() {
  late FakeSchoolInfoRepository repository;
  final previousOverrides = HttpOverrides.current;
  setUpAll(() {
    registerFallbackValue(Uri());
    final client = _PendingHttpClient();
    when(() => client.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
    HttpOverrides.global = _PendingHttpOverrides(client);
  });
  tearDownAll(() => HttpOverrides.global = previousOverrides);

  setUp(() => repository = FakeSchoolInfoRepository());

  Future<void> pumpScreen(
    WidgetTester tester, {
    AsyncValue<String> schoolName = _loadedSchoolName,
    Map<String, String> logos = const {},
  }) async {
    final container = ProviderContainer(
      overrides: [
        schoolInfoRepositoryProvider.overrideWithValue(repository),
        schoolNameProvider.overrideWithValue(schoolName),
        universityLogosProvider.overrideWith((ref) => logos),
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

    // pen 03c 화면 `B9Hu7` 학교 줄(대장 전달 값): [원 40 · 3D 졸업모 22 | 학교 로고 18 + 학교명 16/600 #222 | 확인됨 12/600 · 아이콘 14],
    // 328×68 · 안쪽 14 · surfaceSoft · 모서리 14. pen 에 없는 "학교" 작은 글자 줄은 없다.
    group('학교 줄(pen `B9Hu7`)', () {
      Finder row() => find.ancestor(of: find.byType(SchoolLabel), matching: find.byType(Container)).last;

      testWidgets('줄은 328×68 · 안쪽 14 · surfaceSoft · 모서리 14 이고 "학교" 작은 글자가 없다', (tester) async {
        tester.view.physicalSize = const Size(376, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpScreen(tester, logos: const {'서울대학교': _logoUrl});
        await tester.pump();

        expect(tester.getSize(row()), const Size(328, 68));
        final box = tester.widget<Container>(row());
        expect(box.padding, const EdgeInsets.all(14));
        expect(box.decoration, BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.md)));
        expect(find.text('학교'), findsNothing);
      });

      testWidgets('왼쪽 원 40 안에 3D 졸업모 22', (tester) async {
        await pumpScreen(tester);

        final icon = tester.widget<Icon3d>(find.byType(Icon3d));
        expect(icon.icon, AppIcon3d.graduationCap);
        expect(tester.getSize(find.byType(Icon3d)), const Size(22, 22));
        final circle = find.ancestor(of: find.byType(Icon3d), matching: find.byType(Container)).first;
        expect(tester.getSize(circle), const Size(40, 40));
      });

      testWidgets('학교명은 SchoolLabel 16/600 ink 로 그리고 로고는 18', (tester) async {
        await pumpScreen(tester, logos: const {'서울대학교': _logoUrl});
        await tester.pump();

        final label = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
        expect(label.university, '서울대학교');
        expect(label.style, AppTypography.bodyStrong.copyWith(color: AppColors.ink));
        expect(tester.getSize(_logo), const Size(18, 18));
      });

      testWidgets('로고가 없는 학교(logo_path null)는 학교 이름만 보인다', (tester) async {
        await pumpScreen(tester);
        await tester.pump();

        expect(_logo, findsNothing);
        expect(find.text('서울대학교'), findsOneWidget);
      });

      testWidgets('"확인됨" 은 12/600 primary-text, 아이콘 14', (tester) async {
        await pumpScreen(tester);

        final text = tester.widget<Text>(find.text('확인됨'));
        expect(text.style!.fontSize, 12);
        expect(text.style!.fontWeight, FontWeight.w600);
        expect(text.style!.color, AppColors.primaryText);
        final badge = find.ancestor(of: find.text('확인됨'), matching: find.byType(Row)).first;
        final icon = tester.widget<Icon>(find.descendant(of: badge, matching: find.byType(Icon)));
        expect(icon.icon, AppIcons.badgeCheck);
        expect(icon.size, 14);
        // pen 실측(B9Hu7 KzZH8) 안쪽 여백 가로 10 · 세로 6.
        final pill = tester.widget<Container>(find.ancestor(of: badge, matching: find.byType(Container)).first);
        expect(pill.padding, const EdgeInsets.symmetric(horizontal: 10, vertical: 6));
      });
    });

    testWidgets('학과·학번 입력칸의 라벨과 플레이스홀더를 보여준다', (tester) async {
      await pumpScreen(tester);

      expect(find.text('학과 · 필수'), findsOneWidget);
      expect(find.text('예: 컴퓨터공학과'), findsOneWidget);
      expect(find.text('학번 · 필수'), findsOneWidget);
      expect(find.text('예: 21'), findsOneWidget);
    });

    // 디자인 공통 PR 뒤 창별_할일(온보딩): 입력 상자 모서리 input 12 · 테두리 hairline, placeholder muted.
    testWidgets('학과 · 학번 입력 상자는 52 · 모서리 12 · 테두리 hairline, placeholder 는 muted 다', (tester) async {
      await pumpScreen(tester);

      for (final field in [find.byType(TextField).at(0), find.byType(TextField).at(1)]) {
        final container = find.ancestor(of: field, matching: find.byType(Container)).first;
        final box = tester.widget<Container>(container).decoration! as BoxDecoration;
        // TDM1r 56 → 52. 글자 한 줄(16 × 1.6)이 상자 안에서 잘리지 않아야 한다.
        expect(tester.getSize(container).height, 52);
        expect(tester.getSize(find.descendant(of: field, matching: find.byType(EditableText))).height,
            greaterThanOrEqualTo(16 * 1.6));
        expect(box.borderRadius, BorderRadius.circular(AppRadius.input));
        expect(box.border, Border.all(color: AppColors.hairline));
        expect(tester.widget<TextField>(field).decoration!.hintStyle!.color, AppColors.muted);
      }
    });

    // 52 는 최소값이다 — 글자 배율 2.0 에서 고정 52 면 한 줄(16 × 1.6 × 2)이 잘린다(LabeledField 와 같이 minHeight).
    testWidgets('글자 배율 2.0 에서 학과 · 학번 상자가 늘어나 글자가 잘리지 않는다', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester);

      for (final field in [find.byType(TextField).at(0), find.byType(TextField).at(1)]) {
        // 글자칸이 제 한 줄 높이보다 낮으면 잘린 것이다.
        final text = tester.renderObject<RenderBox>(find.descendant(of: field, matching: find.byType(EditableText)));
        expect(text.size.height, greaterThanOrEqualTo(text.getMinIntrinsicHeight(text.size.width)));
      }
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
