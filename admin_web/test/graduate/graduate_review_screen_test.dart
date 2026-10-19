import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/graduate_fakes.dart';
import '../helpers/heart_task_fakes.dart';

/// A10 졸업생 검수(pen pIuL0 · 1440×900). 값은 `CampusMate_문서/디자인_pen/졸업생_인증/값표.md` §6 (campus-pen 10-19 조회).
/// 값표에 없는 상태 · 칸(입력 칸 · 이력 · 확인 대화상자 · 409 문구)은 이 파일 주석에 "값표 밖"이라고 적는다.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  // 시험 기본 글꼴은 글자마다 정사각형이라 폭이 실제보다 넓다 — 실제 Pretendard 로 pen 폭을 잰다.
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  // 2026-10-19 11:32 한국 = 02:32 UTC — 기본 제출(02:20 UTC)은 "12분 전"
  final now = DateTime.utc(2026, 10, 19, 2, 32);

  FakeGraduateServer three() => FakeGraduateServer([
    graduateRow('g1'),
    graduateRow('g2', createdAt: '2026-10-19T02:11:00+00:00', attemptNo: 2, nickname: '닉네임B', universityName: '연세대학교'),
    graduateRow('g3', createdAt: '2026-10-19T02:02:00+00:00', nickname: '닉네임C', universityName: '고려대학교'),
  ]);

  Future<FakeGraduateServer> openA10(
    WidgetTester tester, {
    FakeGraduateServer? server,
    String path = '/graduates',
    Size size = const Size(1440, 900),
    bool settle = true,
  }) async {
    final fake = server ?? three();
    final image = await portraitTestImage(tester);
    await pumpAdminApp(
      tester,
      auth: FakeAdminAuth(mfa: aal2),
      api: fake.api(),
      initialPath: path,
      size: size,
      settle: settle,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        proofImageProvider.overrideWithValue((url) => TestProofImage(url, image)),
      ],
    );
    return fake;
  }

  Future<void> letToastGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  Finder row(String id) => find.byKey(ValueKey('graduate-row-$id'));
  Finder card() => find.byKey(const ValueKey('graduate-info'));
  Finder inCard(Finder f) => find.descendant(of: card(), matching: f);
  // 입력 칸 안의 글자도 find.text 에 잡히므로(EditableText) 카드 안 Text 위젯만 고른다
  Finder textIn(String text) => find.descendant(of: card(), matching: find.byWidgetPredicate((w) => w is Text && w.data == text));
  Finder fieldOf(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));
  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);
  Material materialOf(WidgetTester tester, Finder f) => tester.widget<Material>(find.descendant(of: f, matching: find.byType(Material)).first);
  RoundedRectangleBorder shapeOf(WidgetTester tester, Finder f) => materialOf(tester, f).shape! as RoundedRectangleBorder;
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;
  Finder approveButton() => find.widgetWithText(AdminButton, '승인');
  Finder dialog() => find.byKey(const ValueKey('graduate-confirm-dialog'));

  Future<void> confirmDialog(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: dialog(), matching: find.widgetWithText(AdminButton, label)));
    await tester.pumpAndSettle();
  }

  Future<void> approveWithConfirm(WidgetTester tester) async {
    await tester.tap(approveButton());
    await tester.pumpAndSettle();
    await confirmDialog(tester, '승인');
  }

  Future<void> rejectWithConfirm(WidgetTester tester, int option) async {
    await tester.tap(find.byKey(const ValueKey('reject-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('reject-option-$option')));
    await tester.pumpAndSettle();
    await confirmDialog(tester, '반려');
  }

  group('pen 배치(pIuL0 · 값표 §6)', () {
    testWidgets('내용 32 안쪽: 큐 칸 320(항목 80, 사이 12) · 사진 440 · 정보 카드 328, 모두 y96 에서 시작', (tester) async {
      await openA10(tester);

      expect(rectOf(tester, row('g1')), const Rect.fromLTWH(272, 96, 320, 80));
      expect(rectOf(tester, row('g2')), const Rect.fromLTWH(272, 188, 320, 80));
      expect(rectOf(tester, find.byKey(const ValueKey('certificate-viewer'))).topLeft, const Offset(616, 96));
      expect(rectOf(tester, find.byKey(const ValueKey('certificate-photo'))), const Rect.fromLTWH(616, 132, 440, 380));
      expect(rectOf(tester, card()).topLeft, const Offset(1080, 96));
      expect(rectOf(tester, card()).width, 328);
      expect(find.byType(AdminChip), findsNothing, reason: '칩 2종은 목록 API 에 근거 칸이 없어 그리지 않았다(보고)');
    });

    testWidgets('TopBar 제목은 "졸업생 검수", 메뉴 "졸업생"이 고른 상태', (tester) async {
      await openA10(tester);

      expect(find.text('졸업생 검수'), findsOneWidget);
      expect(materialOf(tester, find.byKey(const ValueKey('nav-graduates'))).color, AdminColors.primaryWash);
    });

    testWidgets('큐 항목: 안쪽 16 · 위 줄 26(닉네임 14/700 + 대기 배지) · 6 · "학교 · n분 전" 12 web-muted, 고른 줄 primary-wash + primary 2', (tester) async {
      await openA10(tester);

      final box = rectOf(tester, row('g2'));
      final title = find.descendant(of: row('g2'), matching: find.text('닉네임B'));
      final meta = find.descendant(of: row('g2'), matching: find.text('연세대학교 · 21분 전'));
      final badge = find.descendant(of: row('g2'), matching: find.byType(StatusBadge));
      expect(rectOf(tester, title).left - box.left, 16);
      expect(rectOf(tester, title).center.dy - box.top, 16 + 13);
      expect(rectOf(tester, meta).topLeft - box.topLeft, const Offset(16, 48));
      expect(rectOf(tester, badge).right, box.right - 16);
      expect(styleOf(tester, title).fontWeight, FontWeight.w700);
      expect((styleOf(tester, meta).fontSize, styleOf(tester, meta).color), (12, AdminColors.muted));
      expect(find.descendant(of: row('g1'), matching: find.text('닉네임A')), findsOneWidget);
      expect(find.descendant(of: row('g1'), matching: find.text('서울대학교 · 12분 전')), findsOneWidget);
      expect(find.descendant(of: row('g3'), matching: find.text('고려대학교 · 30분 전')), findsOneWidget);
      expect(tester.widget<StatusBadge>(badge).tone, StatusTone.warning);
      expect(tester.widget<StatusBadge>(badge).label, '대기');

      expect(materialOf(tester, row('g1')).color, AdminColors.primaryWash);
      expect(shapeOf(tester, row('g1')).side, const BorderSide(color: AdminColors.primary, width: 2));
      expect(materialOf(tester, row('g2')).color, AdminColors.surface);
      expect(shapeOf(tester, row('g2')).side, const BorderSide(color: AdminColors.outline));
      expect(shapeOf(tester, row('g2')).borderRadius, BorderRadius.circular(8));
    });

    testWidgets('닉네임 · 학교가 둘 다 null(탈퇴 계정)이면 "n번째 신청" · 지난 시간만, 제출자는 프로필 번호', (tester) async {
      final server = FakeGraduateServer([
        graduateRow('g1', nickname: null, universityName: null, profileId: 'abcdef12-0000-0000-0000-000000000001'),
        graduateRow('g2', attemptNo: 2, nickname: null, universityName: null),
      ]);
      await openA10(tester, server: server);

      expect(find.descendant(of: row('g1'), matching: find.text('첫 신청')), findsOneWidget);
      expect(find.descendant(of: row('g1'), matching: find.text('12분 전')), findsOneWidget);
      expect(find.descendant(of: row('g2'), matching: find.text('2번째 신청')), findsOneWidget);
      expect(inCard(find.text('abcdef12')), findsOneWidget);
    });

    testWidgets('닉네임만 있고 학교가 null 이면 메타는 지난 시간만, 학교만 있고 닉네임이 null 이면 제목은 "n번째 신청"', (tester) async {
      final server = FakeGraduateServer([
        graduateRow('g1', universityName: null),
        graduateRow('g2', nickname: null),
      ]);
      await openA10(tester, server: server);

      expect(find.descendant(of: row('g1'), matching: find.text('닉네임A')), findsOneWidget);
      expect(find.descendant(of: row('g1'), matching: find.text('12분 전')), findsOneWidget);
      expect(find.descendant(of: row('g2'), matching: find.text('첫 신청')), findsOneWidget);
      expect(find.descendant(of: row('g2'), matching: find.text('서울대학교 · 12분 전')), findsOneWidget);
    });

    testWidgets('사진 머리줄: 제목 16/700 web-ink + 알약 "1장"(12/600 web-muted · surface-strong · pill · [4,10])', (tester) async {
      await openA10(tester);

      final viewer = rectOf(tester, find.byKey(const ValueKey('certificate-viewer')));
      final title = find.text('졸업증명서 사진');
      final pill = find.byKey(const ValueKey('certificate-count'));
      final label = find.descendant(of: pill, matching: find.text('1장'));
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight, styleOf(tester, title).color), (16, FontWeight.w700, AdminColors.ink));
      expect(rectOf(tester, pill).right, viewer.right);
      expect(rectOf(tester, label).left - rectOf(tester, pill).left, 10);
      expect(rectOf(tester, label).top - rectOf(tester, pill).top, 4);
      expect((styleOf(tester, label).fontSize, styleOf(tester, label).fontWeight, styleOf(tester, label).color), (12, FontWeight.w600, AdminColors.muted));
      final decoration = tester.widget<Container>(pill).decoration! as BoxDecoration;
      expect(decoration.color, AdminColors.surfaceStrong);
      expect(decoration.borderRadius, BorderRadius.circular(9999));
    });

    testWidgets('큰 사진: surface-strong · outline 1 · 모서리 14, 눌러 크게 본다', (tester) async {
      await openA10(tester);

      final photo = find.byKey(const ValueKey('certificate-photo'));
      expect(materialOf(tester, photo).color, AdminColors.surfaceStrong);
      expect(shapeOf(tester, photo).side, const BorderSide(color: AdminColors.outline));
      expect(shapeOf(tester, photo).borderRadius, BorderRadius.circular(14));
      expect(find.descendant(of: photo, matching: find.byType(Image)), findsOneWidget);

      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proof-zoom')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('proof-zoom-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proof-zoom')), findsNothing);
    });

    testWidgets('정보 카드(NfTj6): 안쪽 24 · surface · outline 1 · 모서리 14, 제목 16/700 → 16 → 줄 2개(키 폭 88 · 사이 12)', (tester) async {
      await openA10(tester);

      final box = rectOf(tester, card());
      final title = find.text('졸업생 확인 정보');
      expect(rectOf(tester, title).left - box.left, 24);
      expect(rectOf(tester, title).top - box.top, 24);
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight, styleOf(tester, title).color), (16, FontWeight.w700, AdminColors.ink));
      final decoration = tester.widget<Container>(card()).decoration! as BoxDecoration;
      expect(decoration.color, AdminColors.surface);
      expect(decoration.borderRadius, BorderRadius.circular(14));

      expect(textIn('닉네임A'), findsOneWidget, reason: '제출자 값은 닉네임');
      final submitterKey = inCard(find.text('제출자'));
      final timeKey = inCard(find.text('제출 시각'));
      final time = inCard(find.text('2026-10-19 11:20'));
      expect((styleOf(tester, submitterKey).fontSize, styleOf(tester, submitterKey).color), (14, AdminColors.muted));
      expect(rectOf(tester, time).left - rectOf(tester, timeKey).left, 88 + 12);
      expect((styleOf(tester, time).fontSize, styleOf(tester, time).fontWeight, styleOf(tester, time).color), (14, FontWeight.w600, AdminColors.ink));
      expect(rectOf(tester, timeKey).top - rectOf(tester, submitterKey).top, 19 + 16);
    });

    testWidgets('읽어 둔 문서확인번호 블록: 키 12/600 muted → 6 → 값 16/700 ink → 6 → 힌트 12 muted "힌트일 뿐" 문구', (tester) async {
      await openA10(tester);

      final key = textIn('읽어 둔 문서확인번호');
      final value = textIn('A12B-3456-78CD');
      final hint = textIn('자동으로 읽은 값이에요. 직접 확인해 주세요');
      expect((styleOf(tester, key).fontSize, styleOf(tester, key).fontWeight, styleOf(tester, key).color), (12, FontWeight.w600, AdminColors.muted));
      expect((styleOf(tester, value).fontSize, styleOf(tester, value).fontWeight, styleOf(tester, value).color), (16, FontWeight.w700, AdminColors.ink));
      expect((styleOf(tester, hint).fontSize, styleOf(tester, hint).fontWeight, styleOf(tester, hint).color), (12, FontWeight.w400, AdminColors.muted));
      expect(rectOf(tester, value).top - rectOf(tester, key).bottom, 6);
      expect(rectOf(tester, hint).top - rectOf(tester, value).bottom, 6);
      expect(inCard(find.text('읽어 둔 학교 이름')), findsOneWidget);
      expect(styleOf(tester, textIn('서울대학교').first).fontWeight, FontWeight.w700);
    });

    testWidgets('학교 고르기: 라벨 12/600 muted + Select 폭 가득(280) 높이 44, 제안 학교가 미리 골라져 있다', (tester) async {
      await openA10(tester);

      final select = find.byKey(const ValueKey('school-select'));
      expect(inCard(find.text('학교 고르기')), findsOneWidget);
      expect(rectOf(tester, select).size, const Size(280, 44));
      expect(rectOf(tester, select).left, rectOf(tester, card()).left + 24);
      expect(find.descendant(of: select, matching: find.text('서울대학교')), findsOneWidget);
      expect(shapeOf(tester, select).side, const BorderSide(color: AdminColors.outlineStrong));
      expect(shapeOf(tester, select).borderRadius, BorderRadius.circular(8));
    });

    testWidgets('단추 줄: [승인] 높이 44 + 12 + [반려 ▾] Select 높이 44, 반려 사유 메뉴는 4개(280 · 44씩)', (tester) async {
      await openA10(tester);

      final approve = rectOf(tester, approveButton());
      final reject = rectOf(tester, find.byKey(const ValueKey('reject-select')));
      expect(approve.height, 44);
      expect(reject.height, 44);
      expect(reject.left - approve.right, 12);
      expect(reject.width, lessThanOrEqualTo(200));

      await tester.tap(find.byKey(const ValueKey('reject-select')));
      await tester.pumpAndSettle();
      final menu = rectOf(tester, find.byKey(const ValueKey('reject-menu')));
      expect(menu.size, const Size(280, 4 * 44)); // 테두리는 안쪽에 그린다(인증샷 사유 메뉴 280×132 와 같은 방식)
      for (final (i, reason) in GraduateRejectReason.values.indexed) {
        final option = find.byKey(ValueKey('reject-option-$i'));
        expect(rectOf(tester, option).height, 44);
        expect(find.descendant(of: option, matching: find.text(reason.label)), findsOneWidget);
        final style = styleOf(tester, find.descendant(of: option, matching: find.text(reason.label)));
        expect((style.fontSize, style.color), (14, AdminColors.ink));
        expect(rectOf(tester, find.descendant(of: option, matching: find.text(reason.label))).left - rectOf(tester, option).left, 16);
      }
    });

    testWidgets('안내 두 줄: "승인 · 반려하면 사진이 바로 지워져요" · "단축키: 승인 A · 반려 R"(12 web-muted, 사이 16)', (tester) async {
      await openA10(tester);

      final note = inCard(find.text('승인 · 반려하면 사진이 바로 지워져요'));
      final keys = inCard(find.text('단축키: 승인 A · 반려 R'));
      expect((styleOf(tester, note).fontSize, styleOf(tester, note).color), (12, AdminColors.muted));
      expect((styleOf(tester, keys).fontSize, styleOf(tester, keys).color), (12, AdminColors.muted));
      expect(rectOf(tester, keys).top - rectOf(tester, note).bottom, 16);
      expect(rectOf(tester, note).top, greaterThan(rectOf(tester, approveButton()).bottom));
    });
  });

  group('경고 · 이전 학교 메일', () {
    testWidgets('경고 줄(arX3b): warning-wash · 모서리 8 · 안쪽 12 · 아이콘 triangle-alert 18 + 8 + 14/normal warning', (tester) async {
      final server = three()
        ..detailOverrides['g1'] = {
          'previous_school_email': 'hong@snu.ac.kr',
          'warnings': [graduateWarning('school_email_in_use', profileId: 'p-9', profileStatus: 'active')],
        };
      await openA10(tester, server: server);

      final box = find.byKey(const ValueKey('graduate-warning-0'));
      final text = find.descendant(of: box, matching: find.text('이 학교 메일은 이미 다른 계정이 쓰고 있어요'));
      final icon = find.descendant(of: box, matching: find.byType(Icon));
      final decoration = tester.widget<Container>(box).decoration! as BoxDecoration;
      expect(decoration.color, AdminColors.warningWash);
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(rectOf(tester, box).width, 280);
      expect(rectOf(tester, icon).size, const Size(18, 18));
      expect(tester.widget<Icon>(icon).icon, LucideIcons.triangleAlert);
      expect(tester.widget<Icon>(icon).color, AdminColors.warning);
      expect(rectOf(tester, icon).left - rectOf(tester, box).left, 12);
      expect(rectOf(tester, text).left - rectOf(tester, icon).right, 8);
      expect(rectOf(tester, text).top - rectOf(tester, box).top, 12);
      expect((styleOf(tester, text).fontSize, styleOf(tester, text).fontWeight, styleOf(tester, text).color), (14, FontWeight.w400, AdminColors.warning));
    });

    testWidgets('경고 3종이 모두 줄로 보이고 사이는 8', (tester) async {
      final server = three()
        ..detailOverrides['g1'] = {
          'previous_school_email': 'hong@snu.ac.kr',
          'warnings': [
            graduateWarning('school_email_in_use', profileId: 'p-9', profileStatus: 'active'),
            graduateWarning('school_email_rejoin_blocked'),
            graduateWarning('document_seen', profileId: 'p-8'),
          ],
        };
      await openA10(tester, server: server);

      expect(inCard(find.text('이 학교 메일은 이미 다른 계정이 쓰고 있어요')), findsOneWidget);
      expect(inCard(find.text('이 학교 메일은 탈퇴 뒤 재가입이 제한된 메일이에요')), findsOneWidget);
      expect(inCard(find.text('같은 문서확인번호로 이미 승인된 다른 계정이 있어요')), findsOneWidget);
      final first = rectOf(tester, find.byKey(const ValueKey('graduate-warning-0')));
      final second = rectOf(tester, find.byKey(const ValueKey('graduate-warning-1')));
      expect(second.top - first.bottom, 8);
    });

    testWidgets('경고가 없으면 경고 줄이 없고, 이전 학교 메일이 없으면 그 줄도 없다', (tester) async {
      await openA10(tester);

      expect(find.byKey(const ValueKey('graduate-warning-0')), findsNothing);
      expect(inCard(find.text('이전 학교 이메일')), findsNothing);
    });

    testWidgets('이전 학교 메일이 있으면 키 12/600 muted + 값 14/600 ink', (tester) async {
      final server = three()..detailOverrides['g1'] = {'previous_school_email': 'hong@snu.ac.kr'};
      await openA10(tester, server: server);

      final key = inCard(find.text('이전 학교 이메일'));
      final value = inCard(find.text('hong@snu.ac.kr'));
      expect((styleOf(tester, key).fontSize, styleOf(tester, key).fontWeight, styleOf(tester, key).color), (12, FontWeight.w600, AdminColors.muted));
      expect((styleOf(tester, value).fontSize, styleOf(tester, value).fontWeight, styleOf(tester, value).color), (14, FontWeight.w600, AdminColors.ink));
    });
  });

  group('글자 인식 · 입력 칸(값표 밖: 칸 위치 · 안내 글자는 정하지 않은 것)', () {
    testWidgets('읽은 번호가 입력 칸에 미리 들어가 있고, 칸 아래에 정규화 안내가 있다', (tester) async {
      await openA10(tester);

      expect(tester.widget<TextField>(fieldOf('document-field')).controller!.text, 'A12B-3456-78CD');
      expect(tester.widget<TextField>(fieldOf('student-field')).controller!.text, '');
      expect(inCard(find.text(documentNumberGuide)), findsOneWidget);
      expect(inCard(find.text(studentNumberGuide)), findsOneWidget);
      expect(inCard(find.text('문서확인번호')), findsOneWidget);
      expect(inCard(find.text('학번 (선택)')), findsOneWidget);
    });

    testWidgets('글자 인식이 못 읽은 건: "읽지 못했어요"와 빈 칸 · 학교 미선택 · 승인 단추 잠김', (tester) async {
      final server = three()
        ..detailOverrides['g1'] = {
          'ocr': {'state': 'nothing_found', 'document_number': null, 'school_text': null, 'suggested_university_ids': <Object?>[]},
        };
      await openA10(tester, server: server);

      expect(inCard(find.text('읽지 못했어요')), findsNWidgets(2));
      expect(inCard(find.text('자동으로 읽은 값이에요. 직접 확인해 주세요')), findsNothing);
      expect(tester.widget<TextField>(fieldOf('document-field')).controller!.text, '');
      expect(find.descendant(of: find.byKey(const ValueKey('school-select')), matching: find.text('학교를 골라 주세요')), findsOneWidget);
      expect(tester.widget<AdminButton>(approveButton()).onPressed, isNull);
    });

    testWidgets('번호가 규칙에 안 맞으면 승인이 잠기고 칸 아래에 이유가 보인다', (tester) async {
      await openA10(tester);

      await tester.enterText(fieldOf('document-field'), 'AB1');
      await tester.pump();

      expect(tester.widget<AdminButton>(approveButton()).onPressed, isNull);
      expect(inCard(find.text('문서확인번호는 영문 · 숫자 4~40자로 입력해 주세요')), findsOneWidget);

      await tester.enterText(fieldOf('document-field'), 'ab-12 34');
      await tester.pump();

      expect(tester.widget<AdminButton>(approveButton()).onPressed, isNotNull);
      expect(inCard(find.text('문서확인번호는 영문 · 숫자 4~40자로 입력해 주세요')), findsNothing);
    });

    testWidgets('학번이 규칙에 안 맞으면 승인이 잠기고, 비우면 풀린다', (tester) async {
      await openA10(tester);

      await tester.enterText(fieldOf('student-field'), '학번');
      await tester.pump();
      expect(tester.widget<AdminButton>(approveButton()).onPressed, isNull);
      expect(inCard(find.text('학번은 영문 · 숫자 1~20자로 입력해 주세요')), findsOneWidget);

      await tester.enterText(fieldOf('student-field'), '');
      await tester.pump();
      expect(tester.widget<AdminButton>(approveButton()).onPressed, isNotNull);
    });

    testWidgets('입력 칸은 서버 상한(번호 40 · 학번 20)을 넘게 들어가지 않는다', (tester) async {
      await openA10(tester);

      await tester.enterText(fieldOf('document-field'), 'A' * 50);
      await tester.enterText(fieldOf('student-field'), '1' * 30);

      expect(tester.widget<TextField>(fieldOf('document-field')).controller!.text.length, 40);
      expect(tester.widget<TextField>(fieldOf('student-field')).controller!.text.length, 20);
    });

    testWidgets('학교를 다른 곳으로 바꾸면 그 학교로 승인한다', (tester) async {
      final server = await openA10(tester);

      await tester.tap(find.byKey(const ValueKey('school-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('school-select-option-2'))); // 이름순 고려 · 서울 · 연세 → 연세
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('school-select')), matching: find.text('연세대학교')), findsOneWidget);

      await approveWithConfirm(tester);
      await letToastGo(tester);

      expect(server.approvals.single['university_id'], 'u-yonsei');
    });
  });

  group('승인 · 반려 흐름', () {
    testWidgets('승인: 확인 대화상자(학교 이름 · 사진이 지워진다는 안내) → 승인 → 입력값 전송 · 토스트 · 다음 건', (tester) async {
      final server = await openA10(tester);
      await tester.enterText(fieldOf('student-field'), '2021-0001');
      await tester.pump();

      await tester.tap(approveButton());
      await tester.pumpAndSettle();
      expect(dialog(), findsOneWidget);
      expect(find.text('승인할까요?'), findsOneWidget);
      expect(find.textContaining('서울대학교'), findsWidgets);
      expect(find.textContaining('사진이 바로 지워져요'), findsWidgets);
      expect(server.reviews, isEmpty, reason: '확인 전에는 보내지 않는다');

      await confirmDialog(tester, '승인');

      expect(server.reviews, ['approve:g1']);
      expect(server.approvals.single, {'university_id': 'u-snu', 'document_number': 'A12B-3456-78CD', 'student_number': '2021-0001'});
      expect(find.byType(AdminToast), findsOneWidget);
      expect(find.text('처리했어요'), findsOneWidget);
      expect(row('g1'), findsNothing);
      expect(find.byKey(const ValueKey('graduate-row-g2')), findsOneWidget);
      // 앞 건의 학번은 비고, 다음 건의 칸이 새로 채워진다
      expect(tester.widget<TextField>(fieldOf('student-field')).controller!.text, '');
      await letToastGo(tester);
    });

    testWidgets('확인 대화상자에서 취소하면 아무것도 보내지 않고 입력도 그대로', (tester) async {
      final server = await openA10(tester);
      await tester.enterText(fieldOf('student-field'), '2021-0001');

      await tester.tap(approveButton());
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: dialog(), matching: find.widgetWithText(AdminButton, '취소')));
      await tester.pumpAndSettle();

      expect(server.reviews, isEmpty);
      expect(tester.widget<TextField>(fieldOf('student-field')).controller!.text, '2021-0001');
      expect(dialog(), findsNothing);
    });

    testWidgets('반려: 사유를 고르면 확인 대화상자 → 반려 요청 · 다음 건', (tester) async {
      final server = await openA10(tester);

      await tester.tap(find.byKey(const ValueKey('reject-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reject-option-2')));
      await tester.pumpAndSettle();
      expect(find.text('반려할까요?'), findsOneWidget);
      expect(find.textContaining('확인할 수 없는 번호예요'), findsWidgets);
      expect(server.reviews, isEmpty);
      await confirmDialog(tester, '반려');

      expect(server.reviews, ['reject:g1:unverifiable']);
      expect(find.byType(AdminToast), findsOneWidget);
      expect(row('g1'), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('반려 사유 4개가 각각 그 코드로 간다', (tester) async {
      final server = await openA10(tester);

      await rejectWithConfirm(tester, 3);
      await letToastGo(tester);

      expect(server.reviews, ['reject:g1:school_unsupported']);
    });

    testWidgets('처리 중: 승인 단추에 도는 아이콘, 반려 Select 는 잠긴다', (tester) async {
      final server = three()..holdReview = Completer<void>();
      await openA10(tester, server: server);

      await tester.tap(approveButton());
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: dialog(), matching: find.widgetWithText(AdminButton, '승인')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // 도는 아이콘은 끝나지 않는 움직임이라 settle 하지 않는다

      expect(find.descendant(of: approveButton(), matching: find.byType(AdminLoader)), findsOneWidget);
      expect(tester.widget<AdminButton>(approveButton()).loading, isTrue);
      await tester.tap(find.byKey(const ValueKey('reject-select')), warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('reject-menu')), findsNothing);

      server.holdReview!.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await letToastGo(tester);
    });

    for (final conflict in [
      GraduateConflict.alreadyVerified,
      GraduateConflict.accountWithdrawn,
      GraduateConflict.documentReused,
      GraduateConflict.studentReused,
      GraduateConflict.rejoinBlocked,
    ]) {
      testWidgets('409 ${conflict.code}: 카드 안 오류 줄에 한국어 문구, 건은 그대로', (tester) async {
        final server = three()..conflicts['g1'] = conflict.code;
        await openA10(tester, server: server);

        await approveWithConfirm(tester);

        final error = inCard(find.byType(ErrorRow));
        expect(error, findsOneWidget);
        expect(find.descendant(of: error, matching: find.text(conflict.message)), findsOneWidget);
        expect(row('g1'), findsOneWidget);
        expect(find.byType(AdminToast), findsNothing);
        expect(find.byKey(const ValueKey('admin-dialog')), findsNothing);
      });
    }

    testWidgets('409 already_reviewed: "이미 처리된 항목이에요" 대화상자 · 목록 새로 받기', (tester) async {
      final server = three()..conflicts['g1'] = 'already_reviewed';
      await openA10(tester, server: server);

      await approveWithConfirm(tester);

      expect(find.text('이미 처리된 항목이에요'), findsOneWidget);
      expect(find.text('다른 관리자가 먼저 처리했어요. 목록을 새로 불러올게요.'), findsOneWidget);
      await tester.tap(find.widgetWithText(AdminButton, '확인'));
      await tester.pumpAndSettle();
      expect(row('g1'), findsNothing);
      expect(row('g2'), findsOneWidget);
    });

    testWidgets('연결 실패는 일반 오류 줄 · 422 는 입력 확인 문구', (tester) async {
      final server = three()..reviewFailure = 0;
      await openA10(tester, server: server);

      await approveWithConfirm(tester);
      expect(inCard(find.text('처리하지 못했어요. 다시 시도해 주세요.')), findsOneWidget);

      server.reviewFailure = 422;
      await approveWithConfirm(tester);
      expect(inCard(find.text('입력한 값이 맞지 않아요. 문서확인번호 · 학번을 다시 확인해 주세요.')), findsOneWidget);
    });
  });

  group('단축키(인증샷 검수와 같은 규칙)', () {
    testWidgets('A 는 승인 확인, R 은 사유 펼침, Esc 는 접기', (tester) async {
      final server = await openA10(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reject-menu')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reject-menu')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(dialog(), findsOneWidget);
      expect(server.reviews, isEmpty, reason: 'A 도 확인 대화상자를 거친다');
      await confirmDialog(tester, '승인');
      expect(server.reviews, ['approve:g1']);
      await letToastGo(tester);
    });

    testWidgets('입력 칸에서 글자를 치는 중에는 A · R 이 단축키로 먹지 않는다', (tester) async {
      final server = await openA10(tester);

      await tester.tap(fieldOf('student-field'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(find.byKey(const ValueKey('reject-menu')), findsNothing);
      expect(server.reviews, isEmpty);
    });

    testWidgets('승인 조건이 안 맞으면(번호 비어 있음) A 는 아무 일도 하지 않는다', (tester) async {
      final server = await openA10(tester);
      await tester.enterText(fieldOf('document-field'), '');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(server.reviews, isEmpty);
    });
  });

  group('이력 · 제출자 · 사진 상태', () {
    testWidgets('지난 신청: 반려 · 자동 취소 줄이 보이고, 없으면 "없어요"', (tester) async {
      final server = three()
        ..detailOverrides['g1'] = {
          'history': [graduateHistory('rejected', reason: 'not_certificate'), graduateHistory('cancelled', decidedAt: '2026-10-10T02:20:00+00:00')],
        };
      await openA10(tester, server: server);

      final history = find.byKey(const ValueKey('certificate-history'));
      expect(find.descendant(of: history, matching: find.text('지난 신청')), findsOneWidget);
      expect(find.descendant(of: history, matching: find.text('반려 · 졸업증명서가 아니에요 · 2026-10-17 11:20')), findsOneWidget);
      expect(find.descendant(of: history, matching: find.text('자동 취소 · 2026-10-10 11:20')), findsOneWidget);

      await tester.tap(row('g2'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: history, matching: find.text('없어요')), findsOneWidget);
    });

    testWidgets('닉네임이 없으면 제출자 값은 사용자 상세로 가는 링크(프로필 번호 앞 8자)', (tester) async {
      final server = FakeGraduateServer([graduateRow('g1', nickname: null, universityName: null, profileId: 'abcdef12-0000-0000-0000-000000000001')]);
      await openA10(tester, server: server);

      await tester.tap(inCard(find.text('abcdef12')));
      await tester.pumpAndSettle();

      expect(locationOf(tester), '/users/abcdef12-0000-0000-0000-000000000001');
    });

    testWidgets('사진이 없으면 "사진 없음", 받는 중이면 도는 아이콘, 못 받으면 오류와 다시 시도', (tester) async {
      final server = three()..detailOverrides['g1'] = {'photo_url': null};
      await openA10(tester, server: server);
      final photo = find.byKey(const ValueKey('certificate-photo'));
      expect(find.descendant(of: photo, matching: find.text('사진 없음')), findsOneWidget);
      expect(find.descendant(of: photo, matching: find.byIcon(LucideIcons.imageOff)), findsOneWidget);
    });

    testWidgets('한 건을 받는 중에는 사진 칸에 도는 아이콘, 받지 못하면 "사진을 불러오지 못했어요" + 다시 시도', (tester) async {
      final server = three()..holdDetail = Completer<void>();
      await openA10(tester, server: server, settle: false);
      await tester.pump();
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('certificate-photo')), matching: find.byType(AdminLoader)), findsOneWidget);
      server.holdDetail!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('한 건 실패: 사진 칸 오류 · 다시 시도로 복구', (tester) async {
      final server = three()..detailFailure = 500;
      await openA10(tester, server: server);

      expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
      server.detailFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('certificate-photo')), findsOneWidget);
      expect(find.text('사진을 불러오지 못했어요'), findsNothing);
      expect(card(), findsOneWidget);
    });

    testWidgets('사진 서명이 만료되면 그 건만 다시 받아 새 주소로 그리고, 입력해 둔 번호는 남는다', (tester) async {
      final server = three()..brokenOnce.add('g1');
      await openA10(tester, server: server);
      await tester.enterText(fieldOf('student-field'), '2021-0001');
      await tester.pumpAndSettle();

      expect(server.detailFetches('g1'), 2);
      expect(tester.widget<TextField>(fieldOf('student-field')).controller!.text, '2021-0001');
    });
  });

  group('공통 상태 틀', () {
    testWidgets('목록을 받는 중: "졸업생 신청 목록을 불러오고 있어요"', (tester) async {
      final server = three()..holdList = Completer<void>();
      await openA10(tester, server: server, settle: false);
      await tester.pump();
      await tester.pump();

      expect(find.byType(AdminLoader), findsWidgets);
      expect(find.text('졸업생 신청 목록을 불러오고 있어요'), findsOneWidget);
      server.holdList!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('목록 실패: 제목 · 안내 · 다시 시도, 누르면 복구', (tester) async {
      final server = three()..listFailure = 500;
      await openA10(tester, server: server);

      expect(find.text('목록을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('인터넷 연결을 확인하고 다시 시도해 주세요.'), findsOneWidget);
      server.listFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();

      expect(row('g1'), findsOneWidget);
    });

    testWidgets('빈 목록: "검수할 졸업생 신청이 없어요"', (tester) async {
      await openA10(tester, server: FakeGraduateServer(const []));

      expect(find.byType(AdminTableEmpty), findsOneWidget);
      expect(find.text('검수할 졸업생 신청이 없어요'), findsOneWidget);
      expect(find.text('새 신청이 들어오면 여기에 보여요'), findsOneWidget);
    });

    testWidgets('마지막 건을 처리하면 빈 목록이 된다', (tester) async {
      await openA10(tester, server: FakeGraduateServer([graduateRow('g1')]));

      await approveWithConfirm(tester);
      await letToastGo(tester);

      expect(find.text('검수할 졸업생 신청이 없어요'), findsOneWidget);
    });

    testWidgets('학교 목록을 못 받으면 선택 칸 대신 오류 줄과 다시 받기, 받으면 복구', (tester) async {
      final server = three()..universitiesFailure = 500;
      await openA10(tester, server: server);

      expect(find.byKey(const ValueKey('school-select')), findsNothing);
      expect(inCard(find.text('학교 목록을 불러오지 못했어요')), findsOneWidget);
      server.universitiesFailure = null;
      await tester.tap(inCard(find.widgetWithText(AdminButton, '다시 받기')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('school-select')), findsOneWidget);
    });

    testWidgets('권한 없음 · 2단계 풀림(403): 관문이 다시 판정해 권한 없음 화면으로 간다', (tester) async {
      final auth = FakeAdminAuth(mfa: aal2);
      final server = three()..listFailure = 403;
      final image = await portraitTestImage(tester);
      await pumpAdminApp(
        tester,
        auth: auth,
        api: server.api(),
        initialPath: '/graduates',
        overrides: [proofImageProvider.overrideWithValue((url) => TestProofImage(url, image))],
      );
      // 관문 판정(/admin/me)을 다시 불렀다 — 가짜는 me 에 200 을 주므로 화면은 그대로 오류 상태
      expect(server.requests.where((r) => r.url.path == '/admin/me').length, greaterThanOrEqualTo(2));
    });

    testWidgets('/graduates/{id} 로 열면 그 건을 고른다 · 틀린 번호는 첫 건', (tester) async {
      await openA10(tester, path: '/graduates/g3');
      expect(materialOf(tester, row('g3')).color, AdminColors.primaryWash);
    });

    testWidgets('글자를 키워도(1.3배) 경고 3종 · 이력이 있어도 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = three()
        ..detailOverrides['g1'] = {
          'previous_school_email': 'hong.gildong.long.address@snu.ac.kr',
          'warnings': [
            graduateWarning('school_email_in_use', profileId: 'p-9'),
            graduateWarning('school_email_rejoin_blocked'),
            graduateWarning('document_seen', profileId: 'p-8'),
          ],
          'history': [graduateHistory('rejected', reason: 'unverifiable'), graduateHistory('cancelled')],
        };
      await openA10(tester, server: server);

      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('reject-select')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('카드가 화면보다 길면(경고 3종 + 사유 메뉴) 카드 안이 스크롤되고 넘침 오류가 없다', (tester) async {
      final server = three()
        ..detailOverrides['g1'] = {
          'previous_school_email': 'hong@snu.ac.kr',
          'warnings': [
            graduateWarning('school_email_in_use', profileId: 'p-9'),
            graduateWarning('school_email_rejoin_blocked'),
            graduateWarning('document_seen', profileId: 'p-8'),
          ],
        };
      await openA10(tester, server: server, size: const Size(1440, 700));

      await tester.tap(find.byKey(const ValueKey('reject-select')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
