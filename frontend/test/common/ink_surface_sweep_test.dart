import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/auth/model/school_info_repository_provider.dart';
import 'package:campus_mate/auth/model/school_name_provider.dart';
import 'package:campus_mate/auth/model/student_verification_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/view/school_info_screen.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/student_verification_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/profile/model/appearance_type_repository_provider.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/model/survey_repository_provider.dart';
import 'package:campus_mate/profile/view/appearance_type_screen.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:campus_mate/profile/view/avatar_source_screen.dart';
import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:campus_mate/profile/view/bio_draft_loading_screen.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/view/ideal_note_screen.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/view/survey_screen.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/model/fake_auth_repository.dart';
import '../auth/model/fake_face_detector.dart';
import '../auth/model/fake_image_compressor.dart';
import '../auth/model/fake_school_info_repository.dart';
import '../auth/model/fake_student_verification_repository.dart';
import '../auth/model/fake_verification_gate_repository.dart';
import '../chat/model/fake_chat_repository.dart';
import '../matching/model/fake_card_repository.dart';
import '../profile/model/fake_appearance_type_repository.dart';
import '../profile/model/fake_avatar_repository.dart';
import '../profile/model/fake_basic_info_repository.dart';
import '../profile/model/fake_bio_repository.dart';
import '../profile/model/fake_ideal_conditions_repository.dart';
import '../profile/model/fake_ideal_note_repository.dart';
import '../profile/model/fake_kakao_id_repository.dart';
import '../profile/model/fake_onboarding_repository.dart';
import '../profile/model/fake_photos_repository.dart';
import '../profile/model/fake_survey_repository.dart';

/// 가입~온보딩 화면의 잉크 위젯이 전부 자기 칸 크기의 `Material` 위에 그려지는지 훑는다(COMMON §4-2).
///
/// InkWell·InkResponse·Ink·ListTile 은 눌림 효과를 가장 가까운 조상 Material 위에 좌표로 그린다.
/// 그 Material 이 Scaffold 것(화면 전체)이면 스크롤·전환 때 효과가 제자리에 남아 공중에 뜬다.
/// 그래서 "가장 가까운 Material 이 화면 전체 크기인 잉크 위젯"을 결함으로 센다.
void main() {
  group('검사 함수 자체', () {
    testWidgets('Scaffold 위 ListView 안의 맨 InkWell 을 잡는다(헛통과 막기)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [InkWell(onTap: () {}, child: const SizedBox(height: 48))]),
          ),
        ),
      );

      final sweep = _InkSweep.of(tester, '자기 점검');

      expect(sweep.inkCount, 1);
      expect(sweep.problems, hasLength(1));
      expect(sweep.problems.single, contains('InkWell'));
      expect(sweep.problems.single, contains('800.0×600.0'));
    });

    testWidgets('자기 Material 로 감싼 InkWell 은 통과시킨다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: () {}, child: const SizedBox(height: 48)),
                ),
              ],
            ),
          ),
        ),
      );

      final sweep = _InkSweep.of(tester, '자기 점검');

      expect(sweep.inkCount, 1);
      expect(sweep.problems, isEmpty);
    });
  });

  group('가입·온보딩 화면의 잉크는 화면 전체 Material 위에 그려지지 않는다', () {
    for (final screen in _screens) {
      testWidgets(screen.name, (tester) async {
        await _pumpScreen(tester, screen);

        final sweep = _InkSweep.of(tester, screen.name);
        if (screen.hasInk) {
          expect(sweep.inkCount, greaterThan(0), reason: '${screen.name}: 잉크 위젯을 하나도 못 찾았다 — 헛통과');
        }
        expect(sweep.problems, isEmpty, reason: sweep.problems.join('\n'));
      });
    }
  });
}

/// 훑을 화면 하나. [settle] 은 첫 프레임 뒤 비동기 조회·전환을 흘려보내는 만큼의 추가 pump 수다.
class _Screen {
  const _Screen(
    this.name,
    this.build, {
    this.hasInk = true,
    this.settle = 1,
    this.avatar = FakeAvatarRepository.new,
    this.drive,
  });

  final String name;
  final Widget Function() build;
  final bool hasInk;
  final int settle;
  final FakeAvatarRepository Function() avatar;

  /// 첫 상태 뒤 기존 테스트가 여는 두 번째 상태로 가는 조작. 없으면 첫 상태만 본다.
  final Future<void> Function(WidgetTester tester)? drive;
}

/// 설문 "다음" 을 [times] 번 누른다(`survey_screen_test.dart` 의 `next` 와 같다).
Future<void> _surveyNext(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
  }
}

FakeAvatarRepository _readyAvatar() =>
    FakeAvatarRepository()..nextResult = const Success(AvatarReady('https://example.com/avatar.png'));

final UniversityEmail _email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

/// `lib/core/router/app_router.dart` 의 가입·온보딩 경로 전부 + 준비 중 탭 두 개.
final List<_Screen> _screens = [
  _Screen('SplashScreen', () => const SplashScreen(), hasInk: false),
  _Screen('SignUpScreen', () => const SignUpScreen()),
  _Screen('VerifyCodeScreen', () => VerifyCodeScreen(email: _email)),
  _Screen('StudentVerificationScreen', () => const StudentVerificationScreen(), settle: 2),
  _Screen('SchoolInfoScreen', () => const SchoolInfoScreen()),
  _Screen('BasicInfoScreen', () => const BasicInfoScreen()),
  _Screen('KakaoIdScreen', () => const KakaoIdScreen()),
  _Screen('PhotosScreen', () => const PhotosScreen()),
  _Screen('AvatarSourceScreen', () => const AvatarSourceScreen()),
  // 만드는 중(첫 상태)에는 누를 곳이 없다 — 버튼이 있는 완성 상태도 본다(기존 테스트와 같은 가짜 값).
  _Screen('AvatarGenerationScreen', () => const AvatarGenerationScreen(), hasInk: false),
  _Screen('AvatarGenerationScreen(완성)', () => const AvatarGenerationScreen(), avatar: _readyAvatar),
  _Screen('AppearanceTypeScreen', () => const AppearanceTypeScreen()),
  _Screen('TagPickerScreen(interests)', () => const TagPickerScreen(kind: TagPickerKind.interests)),
  _Screen('TagPickerScreen(myTraits)', () => const TagPickerScreen(kind: TagPickerKind.myTraits)),
  _Screen('SurveyScreen', () => const SurveyScreen()),
  // 종교·흡연 칸(_ChoiceCell)은 10·11번째 쪽에만 나온다.
  _Screen('SurveyScreen(종교)', () => const SurveyScreen(), drive: (tester) => _surveyNext(tester, 9)),
  _Screen(
    'SurveyScreen(흡연)',
    () => const SurveyScreen(),
    drive: (tester) async {
      await _surveyNext(tester, 9);
      await tester.tap(find.text('무교'));
      await tester.pump();
      await _surveyNext(tester, 1);
    },
  ),
  _Screen('IdealConditionsScreen', () => const IdealConditionsScreen()),
  _Screen('TagPickerScreen(idealTraits)', () => const TagPickerScreen(kind: TagPickerKind.idealTraits)),
  _Screen('IdealNoteScreen', () => const IdealNoteScreen()),
  _Screen('BioDraftLoadingScreen', () => const BioDraftLoadingScreen(), settle: 0),
  // 초안이 도착하면 같은 경로가 06-3 BioScreen 으로 바뀐다.
  _Screen('BioDraftLoadingScreen→BioScreen', () => const BioDraftLoadingScreen(), settle: 3),
  _Screen('ComingSoonScreen(me)', () => const ComingSoonScreen(tab: AppTab.me)),
  _Screen('ComingSoonScreen(community)', () => const ComingSoonScreen(tab: AppTab.community)),
];

/// 각 화면의 기존 테스트가 쓰는 가짜 저장소를 한 컨테이너에 모두 건다. 테마는 앱과 같다(`main.dart`).
Future<void> _pumpScreen(WidgetTester tester, _Screen screen) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      studentVerificationRepositoryProvider.overrideWithValue(FakeStudentVerificationRepository()),
      faceDetectorProvider.overrideWithValue(FakeFaceDetector()),
      imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
      schoolInfoRepositoryProvider.overrideWithValue(FakeSchoolInfoRepository()),
      schoolNameProvider.overrideWithValue(const AsyncData<String>('서울대학교')),
      verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
      onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
      basicInfoRepositoryProvider.overrideWithValue(FakeBasicInfoRepository()),
      kakaoIdRepositoryProvider.overrideWithValue(FakeKakaoIdRepository()),
      photosRepositoryProvider.overrideWithValue(FakePhotosRepository()),
      avatarRepositoryProvider.overrideWithValue(screen.avatar()),
      appearanceTypeRepositoryProvider.overrideWithValue(FakeAppearanceTypeRepository()),
      surveyRepositoryProvider.overrideWithValue(FakeSurveyRepository()),
      idealConditionsRepositoryProvider.overrideWithValue(FakeIdealConditionsRepository()),
      idealNoteRepositoryProvider.overrideWithValue(FakeIdealNoteRepository()),
      bioRepositoryProvider.overrideWithValue(FakeBioRepository()),
      chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: screen.build()),
    ),
  );
  for (var i = 0; i < screen.settle; i++) {
    await tester.pump(Duration.zero);
  }
  await screen.drive?.call(tester);
}

/// 지금 트리의 잉크 위젯을 모두 모아, 가장 가까운 Material 이 화면 전체 크기인 것을 결함으로 적는다.
class _InkSweep {
  _InkSweep._(this.inkCount, this.problems);

  factory _InkSweep.of(WidgetTester tester, String screenName) {
    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final inks = find.byWidgetPredicate((w) => w is InkResponse || w is Ink).evaluate().toList();
    final problems = <String>[];
    for (final ink in inks) {
      final material = _nearestMaterial(ink);
      final size = material?.size;
      if (material == null || size == screenSize) {
        problems.add(
          '[$screenName] ${ink.widget.runtimeType} — 가장 가까운 Material '
          '${size == null ? '없음' : '${size.width}×${size.height}'}(화면 전체), 위치 ${_source(ink)}',
        );
      }
    }
    return _InkSweep._(inks.length, problems);
  }

  final int inkCount;
  final List<String> problems;

  static Element? _nearestMaterial(Element ink) {
    Element? found;
    ink.visitAncestorElements((element) {
      if (element.widget is Material) {
        found = element;
        return false;
      }
      return true;
    });
    return found;
  }

  /// 잉크 위젯(또는 그것을 품은 가장 가까운 앱 코드 위젯)이 만들어진 `파일:줄` 과 그 위의 앱 위젯 이름.
  static String _source(Element ink) {
    Element? local = debugIsWidgetLocalCreation(ink.widget) ? ink : null;
    final owners = <String>[];
    ink.visitAncestorElements((element) {
      final isLocal = debugIsWidgetLocalCreation(element.widget);
      local ??= isLocal ? element : null;
      final name = element.widget.runtimeType.toString();
      if (isLocal && (name.startsWith('_') || name.endsWith('Screen'))) {
        owners.add(name);
      }
      return owners.length < 2;
    });
    return '${local == null ? '알 수 없음' : '${local!.widget.runtimeType} @ ${_location(local!)}'}'
        ' ← ${owners.join(' ← ')}';
  }

  static String _location(Element element) {
    // 위젯 생성 위치는 flutter test 가 켜 둔 track-widget-creation 이 심는다 — 인스펙터 직렬화로만 읽힌다.
    final json = element.toDiagnosticsNode().toJsonMap(
      InspectorSerializationDelegate(service: WidgetInspectorService.instance, subtreeDepth: 0),
    );
    final location = json['creationLocation'] as Map<String, Object?>?;
    if (location == null) {
      return '?';
    }
    final file = location['file']! as String;
    final start = file.lastIndexOf('/lib/');
    return '${start < 0 ? file : file.substring(start + 1)}:${location['line']}';
  }
}
