import 'dart:async';
import 'dart:io';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/support_email.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/view/graduate_application_screen.dart';
import 'package:campus_mate/graduate/viewmodel/graduate_application_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/view/pretendard.dart';
import 'gate_screen_harness.dart';

/// pen 02-g 졸업생 인증 `JPJAd` · 02-g-3 반려 다시 제출 `u38Oyy`(값표 §3 · §5).
void main() {
  late GateHarness harness;
  final photo = File('picked.jpg');

  setUpAll(loadPretendard);
  setUp(() => harness = GateHarness());

  const consentLabel = '졸업증명서 사진을 확인에 쓰는 것에 동의해요';

  Future<void> pump(WidgetTester tester, {double textScale = 1, bool disableAnimations = false}) async {
    await harness.pump(tester, const GraduateApplicationScreen(), textScale: textScale, disableAnimations: disableAnimations);
    // 반려 정보 읽기가 끝나게 한다.
    await tester.pump();
    await tester.pump();
    // 임시 폴더 사본 지우기는 플랫폼 통로(path_provider)를 부르므로 시험에서는 비운다.
    harness.container.read(graduateApplicationViewModelProvider.notifier).deleteCopy = (_) async {};
  }

  GraduateApplicationViewModel model() => harness.container.read(graduateApplicationViewModelProvider.notifier);

  Finder slot() => find.byKey(graduatePhotoSlotKey);
  Finder removeButton() => find.byKey(graduatePhotoRemoveKey);
  Finder submitButton(String label) => find.widgetWithText(ElevatedButton, label);

  /// 갤러리에서 [photo] 를 고른 것으로 하고 사진 칸을 누른다.
  Future<void> pickPhoto(WidgetTester tester) async {
    model().pickFromGallery = () async => photo;
    await tester.tap(slot());
    await tester.pump();
  }

  Future<void> agree(WidgetTester tester) async {
    await tester.tap(find.text(consentLabel));
    await tester.pump();
  }

  void rejected(GraduateRejectReason? reason, {int attemptsLeft = 2}) {
    harness.repository.stateResult = Success(GraduateRejected(reason: reason, attemptsLeft: attemptsLeft));
  }

  group('처음 신청하는 폼 — 문구 · 구성 (값표 §3)', () {
    testWidgets('제목 · 설명 · 라벨 · 안내 · 입력 자리값 · [제출하기] 가 pen 문구 그대로다', (tester) async {
      await pump(tester);

      expect(find.text('졸업증명서로 인증해요'), findsOneWidget);
      expect(find.text('졸업증명서 사진 한 장을 올려 주세요. 문서확인번호와 학교 이름이 보이게 찍어 주세요.'), findsOneWidget);
      expect(find.text('졸업증명서 사진'), findsOneWidget);
      expect(find.text('0/1장'), findsOneWidget);
      expect(find.text('이전 학교 이메일 (선택)'), findsOneWidget);
      expect(find.text('예: hong@snu.ac.kr'), findsOneWidget);
      expect(find.text('졸업 전에 쓰던 학교 메일이에요. 몰라도 괜찮아요.'), findsOneWidget);
      expect(find.text('사진은 확인이 끝나면 바로 지워져요'), findsOneWidget);
      expect(find.text('제출하기'), findsOneWidget);
      expect(find.text('다시 제출하기'), findsNothing);
      expect(find.textContaining('반려 사유'), findsNothing);
    });

    testWidgets('앱바에 뒤로 화살표(48×48, 높이 56, 왼쪽 12)가 있다 (`zQjoc`)', (tester) async {
      await pump(tester);

      expect(tester.getSize(find.byType(AppBar)).height, 56);
      final arrow = find.byTooltip(onboardingBackLabel);
      expect(tester.getSize(arrow), const Size(48, 48));
      expect(tester.getTopLeft(arrow).dx, 12);
      expect(find.byIcon(AppIcons.arrowLeft), findsOneWidget);
    });

    testWidgets('제목 24/700 ink · 설명 16 body 줄높이 1.5 · 라벨 14/600 body · 개수 12 muted · 힌트 12/1.5 muted', (tester) async {
      await pump(tester);

      final title = styleOf(tester, '졸업증명서로 인증해요');
      expect((title.fontSize, title.fontWeight, title.color), (24.0, FontWeight.w700, AppColors.ink));
      final body = styleOf(tester, '졸업증명서 사진 한 장을 올려 주세요. 문서확인번호와 학교 이름이 보이게 찍어 주세요.');
      expect((body.fontSize, body.color, body.height), (16.0, AppColors.body, 1.5));
      final label = styleOf(tester, '졸업증명서 사진');
      expect((label.fontSize, label.fontWeight, label.color), (14.0, FontWeight.w600, AppColors.body));
      final count = styleOf(tester, '0/1장');
      expect((count.fontSize, count.color), (12.0, AppColors.muted));
      final hint = styleOf(tester, '졸업 전에 쓰던 학교 메일이에요. 몰라도 괜찮아요.');
      expect((hint.fontSize, hint.color, hint.height), (12.0, AppColors.muted, 1.5));
    });

    testWidgets('본문 왼쪽 16 · 제목 위 72(앱바 56 + 16) · 사진 칸 위 212 · 개수는 라벨 오른쪽 8', (tester) async {
      await pump(tester);

      expect(tester.getTopLeft(find.text('졸업증명서로 인증해요')), const Offset(16, 72));
      expect(tester.getTopLeft(slot()).dx, 16);
      expect(tester.getTopLeft(slot()).dy, closeTo(212, 1.5));
      final gap = tester.getTopLeft(find.text('0/1장')).dx - tester.getTopRight(find.text('졸업증명서 사진')).dx;
      expect(gap, 8);
    });

    testWidgets('안내 줄은 공용 HintLine(파란 느낌표 3D 18 + 14 muted)이다 (`YiiwS` · 마스터 `MOmaZ`)', (tester) async {
      await pump(tester);

      final style = styleOf(tester, '사진은 확인이 끝나면 바로 지워져요');
      expect((style.fontSize, style.color), (14.0, AppColors.muted));
      final icon = find.byWidgetPredicate((w) => w is Image && w.width == 18 && w.height == 18);
      expect(icon, findsOneWidget);
    });
  });

  group('사진 칸 (값표 §3 `gCJ2p` · `oaPh3`)', () {
    testWidgets('빈 칸: 104×104 · 바탕 #EBEBEB · 모서리 14 · image 아이콘 28 #929292, 삭제 X 없음', (tester) async {
      await pump(tester);

      expect(tester.getSize(slot()), const Size(104, 104));
      final decoration = tester.widget<Ink>(find.descendant(of: slot(), matching: find.byType(Ink))).decoration! as BoxDecoration;
      expect(decoration.color, AppColors.hairlineSoft);
      expect(decoration.borderRadius, BorderRadius.circular(14));
      final icon = tester.widget<Icon>(find.descendant(of: slot(), matching: find.byIcon(AppIcons.image)));
      expect((icon.size, icon.color), (28.0, AppColors.disabled));
      expect(removeButton(), findsNothing);
    });

    testWidgets('사진 칸을 누르면 갤러리를 부르고, 고르면 개수가 1/1장이 되며 삭제 X 가 오른쪽 위(x72 · y4)에 28×28 로 생긴다', (tester) async {
      await pump(tester);

      await pickPhoto(tester);

      expect(find.text('1/1장'), findsOneWidget);
      final x = tester.widget<Container>(
        find.descendant(of: removeButton(), matching: find.byType(Container)).last,
      );
      final decoration = x.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color!.toARGB32(), 0x99000000);
      final circle = find.descendant(of: removeButton(), matching: find.byWidget(x));
      expect(tester.getSize(circle), const Size(28, 28));
      expect(tester.getTopLeft(circle) - tester.getTopLeft(slot()), const Offset(72, 4));
      final icon = tester.widget<Icon>(find.descendant(of: removeButton(), matching: find.byIcon(AppIcons.x)));
      expect((icon.size, icon.color), (14.0, AppColors.onInk));
    });

    testWidgets('삭제 X 를 누르면 사진이 빠지고 칸은 다시 빈 칸이다 — 누르는 넓이는 44 이상', (tester) async {
      await pump(tester);
      await pickPhoto(tester);
      expect(tester.getSize(removeButton()).shortestSide, greaterThanOrEqualTo(44));

      await tester.tap(removeButton());
      await tester.pump();

      expect(removeButton(), findsNothing);
      expect(find.text('0/1장'), findsOneWidget);
      expect(harness.container.read(graduateApplicationViewModelProvider).photo, isNull);
    });

    testWidgets('고르지 않고 갤러리를 닫으면 빈 칸 그대로다', (tester) async {
      await pump(tester);
      model().pickFromGallery = () async => null;

      await tester.tap(slot());
      await tester.pump();

      expect(find.text('0/1장'), findsOneWidget);
    });

    testWidgets('낭독: 빈 칸은 "졸업증명서 사진 추가" 버튼, 고른 뒤에는 "졸업증명서 사진 바꾸기"', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(find.bySemanticsLabel('졸업증명서 사진 추가'), findsOneWidget);

      await pickPhoto(tester);

      expect(find.bySemanticsLabel('졸업증명서 사진 바꾸기'), findsOneWidget);
      expect(find.bySemanticsLabel('사진 빼기'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('사진 칸 눌림 효과는 칸 크기 Material 위에 그려진다(COMMON §4-2)', (tester) async {
      await pump(tester);

      final material = find.ancestor(of: find.descendant(of: slot(), matching: find.byType(InkWell)), matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(104, 104));
    });
  });

  group('이전 학교 이메일 · 동의 · 제출', () {
    testWidgets('이메일을 비워 둬도 사진과 동의가 있으면 [제출하기] 가 켜진다', (tester) async {
      await pump(tester);
      expect(tester.widget<ElevatedButton>(submitButton('제출하기')).onPressed, isNull);

      await pickPhoto(tester);
      expect(tester.widget<ElevatedButton>(submitButton('제출하기')).onPressed, isNull, reason: '동의 전');
      await agree(tester);

      expect(tester.widget<ElevatedButton>(submitButton('제출하기')).onPressed, isNotNull);
    });

    testWidgets('이메일 형식이 틀리면 오류 줄이 뜨고 [제출하기] 가 꺼진다', (tester) async {
      await pump(tester);
      await pickPhoto(tester);
      await agree(tester);

      await tester.enterText(find.byType(TextField), 'a@');
      await tester.pump();

      expect(find.text('이전 학교 메일 형식을 다시 확인해 주세요'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(submitButton('제출하기')).onPressed, isNull);
    });

    testWidgets('입력칸은 52 높이 · 바탕 surface-soft · 모서리 12 · 자리값 muted (마스터 `PccKZ`)', (tester) async {
      await pump(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!;
      expect(decoration.fillColor, AppColors.surfaceSoft);
      expect(decoration.hintStyle!.color, AppColors.muted);
      expect(decoration.constraints!.minHeight, 52);
      expect(field.keyboardType, TextInputType.emailAddress);
    });

    testWidgets('동의 줄: 체크 24 · 줄 높이 48 이상, 누르면 켜진다', (tester) async {
      await pump(tester);

      expect(find.text('필수'), findsOneWidget);
      final row = find.ancestor(of: find.text(consentLabel), matching: find.byType(InkWell)).first;
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      await agree(tester);
      expect(harness.container.read(graduateApplicationViewModelProvider).agreed, isTrue);
    });

    testWidgets('[제출하기] 를 누르면 압축본과 이메일이 서버로 나간다', (tester) async {
      await pump(tester);
      await pickPhoto(tester);
      await agree(tester);
      await tester.enterText(find.byType(TextField), 'Old@Univ.ac.kr');
      await tester.pump();

      await tester.tap(submitButton('제출하기'));
      await tester.pump();

      expect(harness.repository.submitted, [(photo.path, 'old@univ.ac.kr')]);
    });

    testWidgets('보내는 중: 버튼에 도는 표시, 사진 칸 · 삭제 X · 입력칸이 잠기고 연타해도 한 번만 나간다', (tester) async {
      harness.repository.holdSubmit = Completer<void>();
      await pump(tester);
      await pickPhoto(tester);
      await agree(tester);
      await tester.tap(submitButton('제출하기'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.tap(removeButton());
      await tester.pump();
      var picked = false;
      model().pickFromGallery = () async {
        picked = true;
        return null;
      };
      await tester.tap(slot());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(harness.repository.submitted, hasLength(1));
      expect(harness.container.read(graduateApplicationViewModelProvider).photo, photo, reason: '보내는 중에는 사진이 안 빠진다');
      expect(picked, isFalse);
      expect(tester.widget<IgnorePointer>(find.byKey(graduateEmailLockKey)).ignoring, isTrue);
      harness.repository.holdSubmit!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('실패하면 토스트로 알리고 사진 · 입력은 그대로다', (tester) async {
      harness.repository.submitResult = const FailureResult(NetworkFailure());
      await pump(tester);
      await pickPhoto(tester);
      await agree(tester);

      await tester.tap(submitButton('제출하기'));
      await tester.pump();
      await tester.pump();

      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      expect(find.text('1/1장'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(submitButton('제출하기')).onPressed, isNotNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('압축이 사진을 못 읽으면 고르는 순간 "사진을 다시 확인해 주세요" 토스트고 사진 칸은 빈 채다', (tester) async {
      harness.compressor.nextError = PlatformException(code: 'bad');
      await pump(tester);

      await pickPhoto(tester);
      await tester.pump();

      expect(find.text(graduatePhotoUnreadableMessage), findsOneWidget);
      expect(find.text('0/1장'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('반려 뒤 다시 신청하는 폼 (값표 §5 `u38Oyy`)', () {
    testWidgets('알림 `parki`: 폭 328 · 바탕 errorWash · 아이콘 20 error · 제목 14/600 error · 캡션 12 muted, 높이 약 65', (tester) async {
      rejected(GraduateRejectReason.notCertificate);
      await pump(tester);

      expect(find.text('반려 사유: 졸업증명서가 아니에요'), findsOneWidget);
      expect(find.text('졸업증명서 사진을 다시 올려 주세요 · 남은 신청 2번'), findsOneWidget);
      final alert = find.byKey(graduateRejectAlertKey);
      expect(tester.getTopLeft(alert), const Offset(16, 72));
      expect(tester.getSize(alert).width, 328);
      // 남은 횟수를 붙여도 "다시 올려 주세요" 캡션은 한 줄에 들어가 pen 높이(64.67)가 그대로다.
      expect(tester.getSize(alert).height, closeTo(64.67, 1.5));
      expect((tester.widget<Container>(alert).decoration! as BoxDecoration).color, AppColors.errorWash);
      final icon = tester.widget<Icon>(find.descendant(of: alert, matching: find.byIcon(AppIcons.alertTriangle)));
      expect((icon.size, icon.color), (20.0, AppColors.error));
      final title = styleOf(tester, '반려 사유: 졸업증명서가 아니에요');
      expect((title.fontSize, title.fontWeight, title.color, title.height), (14.0, FontWeight.w600, AppColors.error, 1.5));
      final caption = styleOf(tester, '졸업증명서 사진을 다시 올려 주세요 · 남은 신청 2번');
      expect((caption.fontSize, caption.color, caption.height), (12.0, AppColors.muted, 1.5));
    });

    testWidgets('제목은 알림 아래 16 에서 시작하고 사진 칸은 빈 칸으로 시작하며 버튼 글자는 "다시 제출하기"다', (tester) async {
      rejected(GraduateRejectReason.notCertificate);
      await pump(tester);

      final alertBottom = tester.getBottomLeft(find.byKey(graduateRejectAlertKey)).dy;
      expect(tester.getTopLeft(find.text('졸업증명서로 인증해요')).dy - alertBottom, 16);
      expect(find.text('0/1장'), findsOneWidget);
      expect(removeButton(), findsNothing);
      expect(find.text('다시 제출하기'), findsOneWidget);
      expect(find.text('제출하기'), findsNothing);
    });

    const reasonTexts = <GraduateRejectReason, String>{
      // 앞 셋은 값표 §5 사유 예시 3개, 넷째는 값표에 없어 서버 푸시 문구(graduate_notice.py)를 쓴다.
      GraduateRejectReason.unreadable: '사진이 잘 안 보여요',
      GraduateRejectReason.notCertificate: '졸업증명서가 아니에요',
      GraduateRejectReason.unverifiable: '확인할 수 없는 번호예요',
      GraduateRejectReason.schoolUnsupported: '아직 지원하지 않는 학교예요',
    };
    reasonTexts.forEach((reason, text) {
      testWidgets('사유 ${reason.code} → "반려 사유: $text"', (tester) async {
        rejected(reason);
        await pump(tester);

        expect(find.text('반려 사유: $text'), findsOneWidget);
      });
    });

    testWidgets('남은 횟수가 캡션에 그 숫자로 붙는다', (tester) async {
      rejected(GraduateRejectReason.unreadable, attemptsLeft: 1);
      await pump(tester);

      expect(find.text('졸업증명서 사진을 다시 올려 주세요 · 남은 신청 1번'), findsOneWidget);
    });

    testWidgets('지원하지 않는 학교(school_unsupported)는 다른 길을 알려 주는 캡션이다', (tester) async {
      rejected(GraduateRejectReason.schoolUnsupported, attemptsLeft: 2);
      await pump(tester);

      expect(find.text('반려 사유: 아직 지원하지 않는 학교예요'), findsOneWidget);
      expect(find.text('뒤로 가서 학교 이메일로 인증할 수도 있어요 · 남은 신청 2번'), findsOneWidget);
      expect(find.textContaining('다시 올려 주세요'), findsNothing);
      // 이 캡션은 한 줄에 안 들어가 두 줄로 접힌다(알림이 캡션 한 줄 18 만큼 높다). 넘침은 없다.
      expect(tester.getSize(find.byKey(graduateRejectAlertKey)).height, closeTo(64.67 + 18, 1.5));
    });

    testWidgets('캡션이 접혀도 알림은 폭 328 이고 넘침이 없다 — 글자 2배도 같다', (tester) async {
      rejected(GraduateRejectReason.schoolUnsupported);
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(graduateRejectAlertKey)).width, 328);
    });

    testWidgets('서버가 모르는 사유(null)여도 반려 알림은 뜬다', (tester) async {
      rejected(null);
      await pump(tester);

      expect(find.byKey(graduateRejectAlertKey), findsOneWidget);
      expect(find.text('졸업증명서 확인이 반려됐어요'), findsOneWidget);
    });
  });

  group('신청 횟수를 다 쓴 상태 (값표 §7 — 시안 없음)', () {
    testWidgets('폼 대신 문의 안내를 보이고 문의 메일을 글자로 보인다 — 제출 · 사진 칸은 없다', (tester) async {
      rejected(GraduateRejectReason.notCertificate, attemptsLeft: 0);
      await pump(tester);

      expect(find.text('신청 횟수를 모두 썼어요'), findsOneWidget);
      expect(find.text(supportEmail), findsOneWidget);
      expect(slot(), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byTooltip(onboardingBackLabel), findsOneWidget, reason: '다른 방법으로 돌아갈 길은 남긴다');
    });

    testWidgets('보내다 429 를 받으면 폼이 문의 안내로 바뀐다', (tester) async {
      harness.repository.submitResult = const FailureResult(RateLimitedFailure());
      await pump(tester);
      await pickPhoto(tester);
      await agree(tester);

      await tester.tap(submitButton('제출하기'));
      await tester.pump();
      await tester.pump();

      expect(find.text('신청 횟수를 모두 썼어요'), findsOneWidget);
      expect(slot(), findsNothing);
    });
  });

  group('뒤로가기 — 화살표와 시스템 뒤로는 같은 함수 한 번', () {
    late int exitCalls;

    setUp(() => exitCalls = 0);

    Future<void> watchExit(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls++;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    }

    testWidgets('화살표: 서버 값을 비우는 호출 한 번(null)', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pump();

      expect(harness.repository.chosen, [null]);
    });

    testWidgets('시스템 뒤로: 같은 호출 한 번, 종료 안내 토스트는 없다', (tester) async {
      await watchExit(tester);
      await pump(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(harness.repository.chosen, [null]);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    testWidgets('반려 변형도 같다', (tester) async {
      rejected(GraduateRejectReason.unreadable);
      await pump(tester);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pump();

      expect(harness.repository.chosen, [null]);
    });

    testWidgets('사진을 올리는 중에는 화살표가 보이지만 눌러도 호출 0회다', (tester) async {
      harness.repository.holdSubmit = Completer<void>();
      await pump(tester);
      await pickPhoto(tester);
      await agree(tester);
      await tester.tap(submitButton('제출하기'));
      await tester.pump();
      await tester.pump();

      expect(find.byTooltip(onboardingBackLabel), findsOneWidget);
      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(harness.repository.chosen, isEmpty);
      harness.repository.holdSubmit!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('비우기에 실패하면 이 화면에 머물고 안내 토스트가 뜬다', (tester) async {
      harness.repository.chooseResult = const FailureResult(NetworkFailure());
      await pump(tester);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pump();
      await tester.pump();

      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      expect(find.text('졸업증명서로 인증해요'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('글자 확대 · 터치 영역 · 동작 줄이기', () {
    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 $scale배: 처음 폼 · 반려 변형 · 문의 안내 모두 넘침 예외가 없다', (tester) async {
        await pump(tester, textScale: scale);
        expect(tester.takeException(), isNull, reason: '처음 폼');
      });

      testWidgets('글자 $scale배 반려 변형(사진 고른 뒤)에서도 넘침 예외가 없다', (tester) async {
        rejected(GraduateRejectReason.unverifiable);
        await pump(tester, textScale: scale);
        await pickPhoto(tester);

        expect(tester.takeException(), isNull);
      });

      testWidgets('글자 $scale배 문의 안내에서도 넘침 예외가 없다', (tester) async {
        rejected(GraduateRejectReason.unreadable, attemptsLeft: 0);
        await pump(tester, textScale: scale);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('글자 2배에서 [제출하기] 까지 스크롤로 닿는다', (tester) async {
      await pump(tester, textScale: 2);

      await tester.scrollUntilVisible(find.text('제출하기'), 200, scrollable: find.byType(Scrollable).first);

      expect(find.text('제출하기'), findsOneWidget);
    });

    testWidgets('동작 줄이기를 켜도 pumpAndSettle 이 끝난다', (tester) async {
      await pump(tester, disableAnimations: true);

      await pickPhoto(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
