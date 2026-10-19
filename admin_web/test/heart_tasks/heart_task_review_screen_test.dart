import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_review_screen.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/enter_motion.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/heart_task_fakes.dart';

/// A3 인증샷 검수(pen GX3T8 · 1440×900). 노드 값은 campus-pen 재조회(10-18) + pencil 직접 조회.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  // 시험 기본 글꼴은 글자마다 정사각형이라 폭이 실제보다 넓다("2026-10-18 14:08" 16자 × 14 = 224 > 값 칸 180).
  // 이 파일은 실제 Pretendard 를 실어 pen 과 같은 폭으로 잰다(글자 상자 높이는 줄 높이 토큰이 정한다).
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  FakeHeartTaskServer fiveWaiting() {
    return FakeHeartTaskServer([
      taskRow('e1'),
      taskRow('k1', task: 'kakao_share', nickname: '닉네임B', createdAt: '2026-10-18T04:59:00+00:00'),
      taskRow('e2', nickname: '닉네임C', createdAt: '2026-10-18T03:20:00+00:00'),
      taskRow('k2', task: 'kakao_share', nickname: '닉네임D', createdAt: '2026-10-15T05:20:00+00:00'),
      taskRow('e3', nickname: '닉네임E'),
    ]);
  }

  Future<FakeHeartTaskServer> openA3(
    WidgetTester tester, {
    FakeHeartTaskServer? server,
    String path = '/heart-tasks',
    Size size = const Size(1440, 900),
    bool settle = true,
  }) async {
    final fake = server ?? fiveWaiting();
    final image = await portraitTestImage(tester);
    await pumpAdminApp(
      tester,
      auth: FakeAdminAuth(mfa: aal2),
      api: fake.api(),
      initialPath: path,
      size: size,
      settle: settle,
      overrides: [
        clockProvider.overrideWithValue(() => testNow),
        proofImageProvider.overrideWithValue((url) => TestProofImage(url, image)),
      ],
    );
    return fake;
  }

  /// 토스트(2초) 시계가 남지 않게 다 흘려보낸다.
  Future<void> letToastGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  Finder row(String id) => find.byKey(ValueKey('heart-task-row-$id'));
  Finder inCard(Finder f) => find.descendant(of: find.byKey(const ValueKey('submit-info')), matching: f);
  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);
  Material materialOf(WidgetTester tester, Finder f) =>
      tester.widget<Material>(find.descendant(of: f, matching: find.byType(Material)).first);
  RoundedRectangleBorder shapeOf(WidgetTester tester, Finder f) => materialOf(tester, f).shape! as RoundedRectangleBorder;
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;
  String? photoUrlShown(WidgetTester tester) {
    final images = find.descendant(of: find.byKey(const ValueKey('proof-photo')), matching: find.byType(Image));
    if (images.evaluate().isEmpty) return null;
    return (tester.widget<Image>(images).image as TestProofImage).url;
  }

  group('pen 배치(GX3T8)', () {
    testWidgets('내용 32 안쪽: 칩 줄 y96 · 목록 칸 320(줄 80, 사이 12) · 사진 440×380(머리줄 아래) · 정보 카드 328×372(사진 행 포함)', (tester) async {
      await openA3(tester);

      expect(rectOf(tester, find.widgetWithText(AdminChip, '전체')).topLeft, const Offset(272, 96));
      expect(rectOf(tester, row('e1')), const Rect.fromLTWH(272, 144, 320, 80));
      expect(rectOf(tester, row('k1')), const Rect.fromLTWH(272, 236, 320, 80));
      expect(rectOf(tester, find.byKey(const ValueKey('proof-photo'))), const Rect.fromLTWH(616, 132, 440, 380));
      expect(rectOf(tester, find.byKey(const ValueKey('submit-info'))), const Rect.fromLTWH(1080, 96, 328, 372));
    });

    testWidgets('칩 3개(xL1CC · wEkG9): 높이 36 · 사이 8 · 좌우 14 · 14/600 · 켜짐 web-ink 바탕, 꺼짐 web-surface + web-outline 1', (tester) async {
      await openA3(tester);

      final all = find.widgetWithText(AdminChip, '전체');
      final everytime = find.widgetWithText(AdminChip, '에브리타임');
      final kakao = find.widgetWithText(AdminChip, '단톡방');
      expect(find.byType(AdminChip), findsNWidgets(3));
      expect(rectOf(tester, all).height, 36);
      expect(rectOf(tester, everytime).left - rectOf(tester, all).right, 8);
      expect(rectOf(tester, kakao).left - rectOf(tester, everytime).right, 8);
      expect(rectOf(tester, find.descendant(of: everytime, matching: find.text('에브리타임'))).left - rectOf(tester, everytime).left, 14);

      expect(materialOf(tester, all).color, AdminColors.ink);
      expect(shapeOf(tester, all).side, BorderSide.none);
      expect(styleOf(tester, find.descendant(of: all, matching: find.text('전체'))).color, AdminColors.onPrimary);
      expect(materialOf(tester, everytime).color, AdminColors.surface);
      expect(shapeOf(tester, everytime).side, const BorderSide(color: AdminColors.outline));
      final off = styleOf(tester, find.descendant(of: everytime, matching: find.text('에브리타임')));
      expect((off.fontSize, off.fontWeight, off.color), (14, FontWeight.w600, AdminColors.body));
    });

    testWidgets('목록 줄: 닉네임 14/700 · "{항목} · {학교} · {n분 전}" 12 web-muted · 대기 배지, 안쪽 16 · 사이 6', (tester) async {
      await openA3(tester);

      final nick = find.descendant(of: row('k1'), matching: find.text('닉네임B'));
      final meta = find.descendant(of: row('k1'), matching: find.text('단톡방 · 서울대학교 · 21분 전'));
      final badge = find.descendant(of: row('k1'), matching: find.byType(StatusBadge));
      final box = rectOf(tester, row('k1'));
      expect(rectOf(tester, nick).left - box.left, 16);
      expect(rectOf(tester, nick).center.dy - box.top, 16 + 13, reason: '위 줄 26 의 가운데'); // pen 은 y 4(3.5 반올림)
      expect(rectOf(tester, meta).topLeft - box.topLeft, const Offset(16, 48));
      expect(rectOf(tester, meta).height, 16);
      expect(rectOf(tester, badge).right, box.right - 16);
      expect(rectOf(tester, badge).top - box.top, 16);
      expect(styleOf(tester, nick).fontWeight, FontWeight.w700);
      expect((styleOf(tester, meta).fontSize, styleOf(tester, meta).color), (12, AdminColors.muted));
      // 시각: 1시간 넘으면 시간, 하루 넘으면 일
      expect(find.text('에브리타임 · 서울대학교 · 2시간 전'), findsOneWidget);
      expect(find.text('단톡방 · 서울대학교 · 3일 전'), findsOneWidget);
    });

    testWidgets('고른 줄 web-primary-wash + web-primary 2, 나머지 web-surface + web-outline 1, 모서리 8', (tester) async {
      await openA3(tester);

      expect(materialOf(tester, row('e1')).color, AdminColors.primaryWash);
      expect(shapeOf(tester, row('e1')).side, const BorderSide(color: AdminColors.primary, width: 2));
      expect(shapeOf(tester, row('e1')).borderRadius, BorderRadius.circular(8));
      expect(materialOf(tester, row('k1')).color, AdminColors.surface);
      expect(shapeOf(tester, row('k1')).side, const BorderSide(color: AdminColors.outline));
      // 눌림 효과는 줄의 Material 에 그린다(COMMON §4-2) — 목록이 스크롤돼도 같이 움직인다
      final ink = find.descendant(of: row('k1'), matching: find.byType(InkWell));
      expect(tester.getSize(find.ancestor(of: ink, matching: find.byType(Material)).first), tester.getSize(ink));
    });

    testWidgets('대기 배지(DZhY4): 높이 26 · 좌우 10 · 점 8 + 6 + 12/700 web-warning, web-warning-wash 바탕', (tester) async {
      await openA3(tester);

      final badge = find.descendant(of: row('e1'), matching: find.byType(StatusBadge));
      final dot = find.descendant(of: badge, matching: find.byKey(const ValueKey('status-badge-dot')));
      final label = find.descendant(of: badge, matching: find.text('대기'));
      expect(rectOf(tester, badge).height, 26);
      expect(rectOf(tester, dot).size, const Size(8, 8));
      expect(rectOf(tester, dot).left - rectOf(tester, badge).left, 10);
      expect(rectOf(tester, label).left - rectOf(tester, dot).right, 6);
      expect(rectOf(tester, badge).right - rectOf(tester, label).right, 10);
      final style = styleOf(tester, label);
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w700, AdminColors.warning));
      final box = tester.widget<Container>(find.descendant(of: badge, matching: find.byType(Container)).first);
      expect((box.decoration! as BoxDecoration).color, AdminColors.warningWash);
    });

    testWidgets('정보 카드(SuzHP): 제목 16/700 → 16 → 6줄(제출자·학교·항목·사진·제출 시각·보상, 이름 88 · 사이 12 · 줄 19 · 사이 16) → 단추 44 → 단축키 줄', (tester) async {
      await openA3(tester);

      final card = rectOf(tester, find.byKey(const ValueKey('submit-info')));
      final title = inCard(find.text('제출 정보'));
      expect(rectOf(tester, title).topLeft - card.topLeft, const Offset(24, 24));
      expect(rectOf(tester, title).height, 22);
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (16, FontWeight.w700));

      const rows = {
        '제출자': '닉네임A',
        '학교': '서울대학교',
        '항목': '에브리타임 홍보',
        '사진': '1장',
        '제출 시각': '2026-10-18 14:08',
        '보상': '하트 40개',
      };
      var top = 62.0;
      for (final MapEntry(:key, :value) in rows.entries) {
        final name = rectOf(tester, inCard(find.text(key)));
        final shown = rectOf(tester, inCard(find.text(value)));
        expect(name.topLeft - card.topLeft, Offset(24, top), reason: key);
        expect(name.height, 19, reason: key);
        expect(shown.left - name.left, 100, reason: '$key 값은 이름 칸 88 + 12');
        expect(styleOf(tester, inCard(find.text(value))).fontWeight, FontWeight.w600);
        expect(styleOf(tester, inCard(find.text(key))).color, AdminColors.muted);
        top += 35;
      }

      final approve = rectOf(tester, find.widgetWithText(AdminButton, '승인'));
      final select = rectOf(tester, find.byKey(const ValueKey('reject-select')));
      expect(approve.top - card.top, 272);
      expect(approve.height, 44);
      expect(select.left - approve.right, 12);
      expect(select.size, const Size(200, 44));
      final hint = inCard(find.text('단축키: 승인 A · 반려 R'));
      expect(rectOf(tester, hint).top - card.top, 332);
      expect((styleOf(tester, hint).fontSize, styleOf(tester, hint).color), (12, AdminColors.muted));
    });

    testWidgets('반려 Select(EHrY2): 200×44 · 모서리 8 · web-outline-strong 1 · "반려" 14 + chevron 18 web-muted(대장 결정 10-18: ▾ 글자 뺌)', (tester) async {
      await openA3(tester);

      final select = find.byKey(const ValueKey('reject-select'));
      expect(shapeOf(tester, select).side, const BorderSide(color: AdminColors.outlineStrong));
      expect(shapeOf(tester, select).borderRadius, BorderRadius.circular(8));
      expect(materialOf(tester, select).color, AdminColors.surface);
      final label = find.descendant(of: select, matching: find.text('반려'));
      expect(find.textContaining('▾'), findsNothing);
      expect(rectOf(tester, label).left - rectOf(tester, select).left, 12);
      expect((styleOf(tester, label).fontWeight, styleOf(tester, label).color), (FontWeight.w400, AdminColors.ink));
      final chevron = find.descendant(of: select, matching: find.byIcon(LucideIcons.chevronDown));
      expect(rectOf(tester, chevron).size, const Size(18, 18));
      expect(rectOf(tester, select).right - rectOf(tester, chevron).right, 12);
      expect(tester.widget<Icon>(chevron).color, AdminColors.muted);
    });

    testWidgets('사진 칸(D4KeG): 큰 사진 web-surface-strong · 모서리 14 · contain, 썸네일 줄 아래 구분선 · "지난 제출 (사진 1장씩)" + 썸네일 64(사이 12)', (tester) async {
      final server = fiveWaiting()
        ..photoCounts['e1'] = 3
        ..previous['e1'] = [previousPhoto('o1'), previousPhoto('o2'), previousPhoto('o3')];
      await openA3(tester, server: server);

      final photo = find.byKey(const ValueKey('proof-photo'));
      expect(materialOf(tester, photo).color, AdminColors.surfaceStrong);
      expect(shapeOf(tester, photo).borderRadius, BorderRadius.circular(14));
      expect(shapeOf(tester, photo).side, const BorderSide(color: AdminColors.outline));
      expect(tester.widget<Image>(find.descendant(of: photo, matching: find.byType(Image))).fit, BoxFit.contain);
      expect(photoUrlShown(tester), contains('e1.jpg'));

      // pen eStrb: 세로 gap 8, 캡션(16) 아래에 썸네일 줄(가로 gap 12). 썸네일이 캡션 옆이 아니라 아래다.
      final caption = rectOf(tester, find.text('지난 제출 (사진 1장씩)'));
      final first = rectOf(tester, find.byKey(const ValueKey('proof-thumb-o1')));
      final second = rectOf(tester, find.byKey(const ValueKey('proof-thumb-o2')));
      expect(caption, Rect.fromLTWH(616, 647, caption.width, 16));
      expect(first, const Rect.fromLTWH(616, 647 + 16 + 8, 64, 64));
      expect(second.left - first.right, 12);
      expect(shapeOf(tester, find.byKey(const ValueKey('proof-thumb-o1'))).borderRadius, BorderRadius.circular(8));
    });
  });

  group('반려 펼침(Rrwiu)', () {
    testWidgets('반려를 누르면 카드 안 16 아래에 사유 3개(280×132, 44씩)가 펼쳐지고 단축키 줄이 아래로 내려간다', (tester) async {
      await openA3(tester);
      await tester.tap(find.byKey(const ValueKey('reject-select')));
      await tester.pumpAndSettle();

      final card = rectOf(tester, find.byKey(const ValueKey('submit-info')));
      final menu = rectOf(tester, find.byKey(const ValueKey('reject-menu')));
      expect(menu, Rect.fromLTWH(card.left + 24, card.top + 332, 280, 132));
      const reasons = ['날짜가 안 보여요', '게시글·공유가 확인되지 않아요', '이미 쓴 캡처예요'];
      for (final (i, reason) in reasons.indexed) {
        final option = rectOf(tester, find.byKey(ValueKey('reject-option-$i')));
        expect(option, Rect.fromLTWH(menu.left, menu.top + 44.0 * i, 280, 44), reason: reason);
        expect(rectOf(tester, find.text(reason)).left - option.left, 16, reason: reason);
      }
      expect(rectOf(tester, inCard(find.text('단축키: 승인 A · 반려 R'))).top - card.top, 480);
      expect(card.height, 520);
      final box = find.byKey(const ValueKey('reject-menu'));
      expect(shapeOf(tester, box).side, const BorderSide(color: AdminColors.outlineStrong));
      expect(materialOf(tester, box).color, AdminColors.surface);
    });

    testWidgets('사유를 고르면 바로 반려 요청 → 토스트 "처리했어요" · 같은 자리의 다음 건', (tester) async {
      final server = await openA3(tester);
      await tester.tap(find.byKey(const ValueKey('reject-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이미 쓴 캡처예요'));
      await tester.pump();
      await tester.pump();

      expect(server.reviews, ['reject:e1:reused']);
      expect(find.text('처리했어요'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(row('e1'), findsNothing);
      expect(find.byKey(const ValueKey('reject-menu')), findsNothing);
      expect(materialOf(tester, row('k1')).color, AdminColors.primaryWash);
      expect(inCard(find.text('닉네임B')), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('바깥을 누르거나 Esc 면 접힌다', (tester) async {
      await openA3(tester);
      final select = find.byKey(const ValueKey('reject-select'));
      final menu = find.byKey(const ValueKey('reject-menu'));

      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(800, 700));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);

      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
    });
  });

  group('처리', () {
    testWidgets('승인 → 토스트 "처리했어요"(아래 가운데 32) · 다음 건, 마지막이면 빈 목록(t36bfq)', (tester) async {
      final server = await openA3(tester, server: FakeHeartTaskServer([taskRow('e1'), taskRow('k1', task: 'kakao_share')]));

      await tester.tap(find.widgetWithText(AdminButton, '승인'));
      await tester.pumpAndSettle();
      expect(server.reviews, ['approve:e1']);
      expect(find.text('처리했어요'), findsOneWidget);
      expect(rectOf(tester, find.byType(AdminToast)).bottom, 900 - 32);
      expect(rectOf(tester, find.byType(AdminToast)).center.dx, 720);

      await tester.tap(find.widgetWithText(AdminButton, '승인'));
      await tester.pumpAndSettle();
      expect(server.reviews, ['approve:e1', 'approve:k1']);

      final empty = find.byType(AdminTableEmpty);
      expect(rectOf(tester, empty), const Rect.fromLTWH(272, 156, 1136, 240));
      expect(find.text('검수할 인증샷이 없어요'), findsOneWidget);
      expect(find.text('새 제출이 들어오면 여기에 보여요'), findsOneWidget);
      expect(tester.widget<Icon>(find.descendant(of: empty, matching: find.byType(Icon))).icon, LucideIcons.inbox);
      expect(rectOf(tester, find.descendant(of: empty, matching: find.byType(Icon))).size, const Size(32, 32));
      expect(find.byType(AdminChip), findsNWidgets(3), reason: '빈 목록에도 칩 줄은 남는다');
      expect(find.byKey(const ValueKey('submit-info')), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('필터를 걸면 그 항목만, 처리 뒤에도 같은 필터 안의 다음 건', (tester) async {
      final server = await openA3(tester);
      await tester.tap(find.widgetWithText(AdminChip, '단톡방'));
      await tester.pumpAndSettle();

      expect(server.requests.any((r) => r.url.queryParameters['task'] == 'kakao_share'), isTrue);
      expect(row('e1'), findsNothing);
      expect(materialOf(tester, find.widgetWithText(AdminChip, '단톡방')).color, AdminColors.ink);

      await tester.tap(find.widgetWithText(AdminButton, '승인'));
      await tester.pumpAndSettle();
      expect(materialOf(tester, row('k2')).color, AdminColors.primaryWash);
      await letToastGo(tester);
    });

    testWidgets('409 → "이미 처리된 항목이에요"(Z3Xg7O: 480 · 안쪽 24 · 확인 오른쪽) → 확인하면 닫히고 목록은 새로 받아 있다', (tester) async {
      final server = fiveWaiting()..takenElsewhere.add('e1');
      await openA3(tester, server: server);

      await tester.tap(find.widgetWithText(AdminButton, '승인'));
      await tester.pumpAndSettle();

      final title = find.text('이미 처리된 항목이에요');
      final body = find.text('다른 관리자가 먼저 처리했어요. 목록을 새로 불러올게요.');
      expect(title, findsOneWidget);
      final dialog = rectOf(tester, find.byKey(const ValueKey('admin-dialog')));
      expect(dialog.width, 480);
      expect(dialog.center, const Offset(720, 450));
      expect(rectOf(tester, title).topLeft - dialog.topLeft, const Offset(24, 24));
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (20, FontWeight.w700));
      expect(styleOf(tester, body).color, AdminColors.muted);
      final ok = rectOf(tester, find.widgetWithText(AdminButton, '확인'));
      expect(ok.right, dialog.right - 24);
      expect(ok.bottom, dialog.bottom - 24);
      expect(server.listFetches, 2);

      await tester.tap(find.widgetWithText(AdminButton, '확인'));
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      expect(row('e1'), findsNothing);
      expect(materialOf(tester, row('k1')).color, AdminColors.primaryWash);
    });

    testWidgets('처리 중: 누른 단추에 도는 아이콘(승인 · 반려 Select), 다른 쪽은 눌리지 않는다', (tester) async {
      final server = await openA3(tester);
      server.holdReview = Completer<void>();
      final select = find.byKey(const ValueKey('reject-select'));

      await tester.tap(find.widgetWithText(AdminButton, '승인'));
      await tester.pump();
      expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '승인')).loading, isTrue);
      await tester.tap(select);
      await tester.pump();
      expect(find.byKey(const ValueKey('reject-menu')), findsNothing);
      server.holdReview!.complete();
      await tester.pumpAndSettle();

      server.holdReview = Completer<void>();
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('날짜가 안 보여요'));
      await tester.pump();
      expect(find.descendant(of: select, matching: find.byType(AdminLoader)), findsOneWidget);
      expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '승인')).onPressed, isNull);
      server.holdReview!.complete();
      await tester.pumpAndSettle();
      expect(server.reviews, ['approve:e1', 'reject:k1:date_missing']);
      await letToastGo(tester);
    });

    testWidgets('처리 요청이 실패하면 카드 안 오류 줄, 목록은 그대로', (tester) async {
      final server = fiveWaiting()..reviewFailure = 500;
      await openA3(tester, server: server);

      await tester.tap(find.widgetWithText(AdminButton, '승인'));
      await tester.pumpAndSettle();

      expect(inCard(find.text('처리하지 못했어요. 다시 시도해 주세요.')), findsOneWidget);
      expect(row('e1'), findsOneWidget);
      expect(find.text('처리했어요'), findsNothing);
    });
  });

  group('단축키', () {
    testWidgets('A 는 승인, R 은 반려 사유를 펼치고 첫 사유에 초점 — Enter 로 고른다', (tester) async {
      final server = await openA3(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(server.reviews, ['approve:e1']);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reject-menu')), findsOneWidget);
      expect(Focus.of(tester.element(find.text('날짜가 안 보여요'))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(server.reviews, ['approve:e1', 'reject:k1:not_verified']);
      await letToastGo(tester);
    });

    testWidgets('Ctrl · Cmd 조합(Ctrl+R 새로고침 등)은 건드리지 않는다', (tester) async {
      final server = await openA3(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('reject-menu')), findsNothing);
      expect(server.reviews, isEmpty);
    });

    testWidgets('대화상자(사진 크게 보기)에 초점이 있으면 무시', (tester) async {
      final server = await openA3(tester);
      await tester.tap(find.byKey(const ValueKey('proof-photo')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();

      expect(server.reviews, isEmpty);
    });

    testWidgets('입력 칸에 초점이 있으면 무시', (tester) async {
      final server = fiveWaiting();
      final image = await portraitTestImage(tester);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminApiProvider.overrideWithValue(server.api()),
            clockProvider.overrideWithValue(() => testNow),
            proofImageProvider.overrideWithValue((url) => TestProofImage(url, image)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(children: [TextField(), Expanded(child: HeartTaskReviewScreen())]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();

      expect(server.reviews, isEmpty);
      expect(find.byKey(const ValueKey('reject-menu')), findsNothing);
    });

    testWidgets('사진 · 지난 제출을 받는 중에는 승인 단추가 잠기고 A 도 보내지 않는다', (tester) async {
      final server = fiveWaiting();
      await openA3(tester, server: server);
      server.holdDetail = Completer<void>();
      await tester.tap(row('k1'));
      await tester.pump();
      await tester.pump();

      expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '승인')).onPressed, isNull);
      expect(find.descendant(of: find.byKey(const ValueKey('proof-photo')), matching: find.byType(AdminLoader)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(server.reviews, isEmpty);

      server.holdDetail!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '승인')).onPressed, isNotNull);
    });
  });

  group('사진', () {
    testWidgets('사진 없음(RmiFS): 큰 칸 image-off 40 + "사진 없음" 14/600 web-muted, 사진 없는 썸네일 image-off 20', (tester) async {
      final server = fiveWaiting()
        ..noPhoto.add('e1')
        ..previous['e1'] = [previousPhoto('o1', photo: false)];
      await openA3(tester, server: server);

      final photo = find.byKey(const ValueKey('proof-photo'));
      final icon = find.descendant(of: photo, matching: find.byIcon(LucideIcons.imageOff));
      expect(rectOf(tester, icon).size, const Size(40, 40));
      expect(tester.widget<Icon>(icon).color, AdminColors.disabled);
      final label = find.descendant(of: photo, matching: find.text('사진 없음'));
      expect(rectOf(tester, label).top - rectOf(tester, icon).bottom, 8);
      expect((styleOf(tester, label).fontWeight, styleOf(tester, label).color), (FontWeight.w600, AdminColors.muted));
      final thumbIcon = find.descendant(of: find.byKey(const ValueKey('proof-thumb-o1')), matching: find.byIcon(LucideIcons.imageOff));
      expect(rectOf(tester, thumbIcon).size, const Size(20, 20));
      // 사진이 없어도 승인 · 반려는 할 수 있다(pen RmiFS)
      expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '승인')).onPressed, isNotNull);
    });

    testWidgets('photo error refetches the item — 서명이 만료된 사진은 그 건만 다시 받아 새 주소로 그린다', (tester) async {
      final server = fiveWaiting()..brokenOnce.add('e1');
      await openA3(tester, server: server);

      expect(server.detailFetches('e1'), 2);
      expect(server.listFetches, 1);
      expect(photoUrlShown(tester), 'https://storage.test/e1.jpg?v=2');
      expect(find.text('사진 없음'), findsNothing);
    });

    testWidgets('다시 받은 주소도 깨지면 더 받지 않고 "사진 없음"(무한 반복 막기)', (tester) async {
      final server = fiveWaiting()..alwaysBroken.add('e1');
      await openA3(tester, server: server);

      expect(server.detailFetches('e1'), 2);
      expect(find.descendant(of: find.byKey(const ValueKey('proof-photo')), matching: find.text('사진 없음')), findsOneWidget);
    });

    testWidgets('사진을 누르면 크게 보기(gpMkm): 화면 90% 안 contain · 닫기 44(오른쪽 위 16) · 안내 알약 · 다운로드 없음', (tester) async {
      await openA3(tester);
      await tester.tap(find.byKey(const ValueKey('proof-photo')));
      await tester.pumpAndSettle();

      final zoom = find.byKey(const ValueKey('proof-zoom'));
      final image = find.descendant(of: zoom, matching: find.byType(Image));
      expect(tester.widget<Image>(image).fit, BoxFit.contain);
      expect((tester.widget<Image>(image).image as TestProofImage).url, contains('e1.jpg'));
      final shown = rectOf(tester, image);
      expect(shown.height, closeTo(810, 0.5), reason: '세로 캡처는 화면 높이 90%');
      expect(shown.center, const Offset(720, 450));
      final close = find.byKey(const ValueKey('proof-zoom-close'));
      expect(rectOf(tester, close), const Rect.fromLTWH(1380, 16, 44, 44));
      final x = find.descendant(of: close, matching: find.byIcon(LucideIcons.x));
      expect(rectOf(tester, x).size, const Size(24, 24));
      expect(tester.widget<Icon>(x).color, AdminColors.onPrimary);
      final hint = find.text('Esc 또는 바깥을 누르면 닫혀요');
      expect((styleOf(tester, hint).fontSize, styleOf(tester, hint).color), (12, AdminColors.onPrimary));
      expect(find.byIcon(LucideIcons.download), findsNothing);

      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(zoom, findsNothing);

      await tester.tap(find.byKey(const ValueKey('proof-photo')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(zoom, findsNothing);

      await tester.tap(find.byKey(const ValueKey('proof-photo')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(60, 450));
      await tester.pumpAndSettle();
      expect(zoom, findsNothing);
    });

    testWidgets('지난 제출 최대 5개는 캡션 아래 한 줄(폭 368)에 모두 놓이고, 누르면 그 사진을 크게 본다', (tester) async {
      final server = fiveWaiting()..previous['e1'] = [for (var i = 1; i <= 5; i++) previousPhoto('o$i')];
      await openA3(tester, server: server);

      final photo = rectOf(tester, find.byKey(const ValueKey('proof-photo')));
      final caption = rectOf(tester, find.text('지난 제출 (사진 1장씩)'));
      final first = rectOf(tester, find.byKey(const ValueKey('proof-thumb-o1')));
      final last = rectOf(tester, find.byKey(const ValueKey('proof-thumb-o5')));
      expect(last.size, const Size(64, 64));
      expect(last.left - first.left, 4 * (64 + 12));
      expect(last.right - first.left, 368);
      expect(last.right, lessThanOrEqualTo(photo.right));
      expect(first.top, greaterThanOrEqualTo(caption.bottom + 8));
      expect(tester.takeException(), isNull);
      for (var i = 1; i <= 5; i++) {
        expect(find.byKey(ValueKey('proof-thumb-o$i')).hitTestable(), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('proof-thumb-o2')));
      await tester.pumpAndSettle();

      final image = find.descendant(of: find.byKey(const ValueKey('proof-zoom')), matching: find.byType(Image));
      expect((tester.widget<Image>(image).image as TestProofImage).url, contains('o2.jpg'));
    });

    testWidgets('지난 제출의 첫 장 서명이 실패해도 다른 장이 있으면 그 장이 보이고, 누르면 그 장을 크게 본다', (tester) async {
      final server = fiveWaiting()
        ..previous['e1'] = [
          {...previousPhoto('o1'), 'photo_urls': [null, 'https://storage.test/o1b.jpg?token=t']},
        ];
      await openA3(tester, server: server);

      final thumb = find.byKey(const ValueKey('proof-thumb-o1'));
      expect(find.descendant(of: thumb, matching: find.byIcon(LucideIcons.imageOff)), findsNothing);
      await tester.tap(thumb);
      await tester.pumpAndSettle();

      final image = find.descendant(of: find.byKey(const ValueKey('proof-zoom')), matching: find.byType(Image));
      expect((tester.widget<Image>(image).image as TestProofImage).url, contains('o1b.jpg'));
    });

    testWidgets('지난 제출이 없으면 "지난 제출 (사진 1장씩)" 옆에 "없어요"', (tester) async {
      await openA3(tester);

      expect(find.text('없어요'), findsOneWidget);
    });
  });

  group('사진 여러 장(pen A3 D4KeG · s1xG8)', () {
    FakeHeartTaskServer threePhotos() => fiveWaiting()
      ..photoCounts['e1'] = 3
      ..previous['e1'] = [for (var i = 1; i <= 5; i++) previousPhoto('o$i')];
    Finder thumb(int i) => find.byKey(ValueKey('proof-photo-thumb-$i'));

    testWidgets('사진 3장: 머리줄 "이 제출의 인증샷" 16/700 + "3장" 알약, 큰 사진 380, 썸네일 줄(캡션 + 64 셋, 사이 12), 구분선, "같은 사람의 지난 제출" 16/700, 지난 제출 줄', (tester) async {
      await openA3(tester, server: threePhotos());

      final title = find.text('이 제출의 인증샷');
      expect(rectOf(tester, title).left, 616);
      expect(rectOf(tester, title).top, 96 + 1, reason: '머리줄 24 안 가운데: (24 - 22) / 2');
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight, styleOf(tester, title).color), (16, FontWeight.w700, AdminColors.ink));
      final pill = find.byKey(const ValueKey('photo-count'));
      expect(rectOf(tester, pill), Rect.fromLTRB(1056 - rectOf(tester, pill).width, 96, 1056, 120));
      final pillBox = tester.widget<Container>(pill).decoration! as BoxDecoration;
      expect((pillBox.color, pillBox.borderRadius), (AdminColors.surfaceStrong, BorderRadius.circular(9999)));
      final count = find.descendant(of: pill, matching: find.text('3장'));
      expect((styleOf(tester, count).fontSize, styleOf(tester, count).fontWeight, styleOf(tester, count).color), (12, FontWeight.w600, AdminColors.muted));
      expect(rectOf(tester, count).left - rectOf(tester, pill).left, 10);

      expect(rectOf(tester, find.byKey(const ValueKey('proof-photo'))), const Rect.fromLTWH(616, 132, 440, 380));
      final caption = find.text('1/3 선택됨');
      expect((styleOf(tester, caption).fontSize, styleOf(tester, caption).fontWeight, styleOf(tester, caption).color), (12, FontWeight.w600, AdminColors.muted));
      final first = rectOf(tester, thumb(0));
      expect(first, Rect.fromLTWH(rectOf(tester, caption).right + 12, 524, 64, 64));
      expect(rectOf(tester, thumb(1)).left - first.right, 12);
      expect(rectOf(tester, thumb(2)).left - rectOf(tester, thumb(1)).right, 12);
      expect(rectOf(tester, caption).left, 616);

      expect(rectOf(tester, find.byKey(const ValueKey('proof-divider'))), const Rect.fromLTWH(616, 600, 440, 1));
      final past = find.text('같은 사람의 지난 제출');
      expect(rectOf(tester, past).top, 613);
      expect((styleOf(tester, past).fontSize, styleOf(tester, past).fontWeight), (16, FontWeight.w700));
      expect(rectOf(tester, find.text('지난 제출 (사진 1장씩)')).top, 647, reason: '지난 제출 캡션, 썸네일은 그 아래 16 + 8');
      expect(rectOf(tester, find.byKey(const ValueKey('proof-thumb-o1'))).top, 671);
    });

    testWidgets('썸네일: 고른 장은 web-primary 2 테두리 + web-primary-wash, 나머지는 web-surface-strong + web-outline 1 · 모서리 8', (tester) async {
      await openA3(tester, server: threePhotos());

      expect(materialOf(tester, thumb(0)).color, AdminColors.primaryWash);
      expect(shapeOf(tester, thumb(0)).side, const BorderSide(color: AdminColors.primary, width: 2));
      expect(shapeOf(tester, thumb(0)).borderRadius, BorderRadius.circular(8));
      for (final i in [1, 2]) {
        expect(materialOf(tester, thumb(i)).color, AdminColors.surfaceStrong);
        expect(shapeOf(tester, thumb(i)).side, const BorderSide(color: AdminColors.outline));
      }
    });

    testWidgets('tapping a thumbnail changes the big view; 캡션 · 테두리도 따라간다', (tester) async {
      await openA3(tester, server: threePhotos());
      expect(photoUrlShown(tester), contains('e1.jpg'));

      await tester.tap(thumb(1));
      await tester.pumpAndSettle();
      expect(photoUrlShown(tester), contains('e1-1.jpg'));
      expect(find.text('2/3 선택됨'), findsOneWidget);
      expect(shapeOf(tester, thumb(1)).side, const BorderSide(color: AdminColors.primary, width: 2));
      expect(shapeOf(tester, thumb(0)).side, const BorderSide(color: AdminColors.outline));

      await tester.tap(thumb(2));
      await tester.pumpAndSettle();
      expect(photoUrlShown(tester), contains('e1-2.jpg'));
      expect(find.text('3/3 선택됨'), findsOneWidget);
    });

    testWidgets('다른 건을 고르면 첫 장으로 돌아간다', (tester) async {
      final server = threePhotos()..photoCounts['k1'] = 2;
      await openA3(tester, server: server);
      await tester.tap(thumb(2));
      await tester.pumpAndSettle();

      await tester.tap(row('k1'));
      await tester.pumpAndSettle();

      expect(photoUrlShown(tester), contains('k1.jpg'));
      expect(find.text('1/2 선택됨'), findsOneWidget);
    });

    testWidgets('zoom opens the selected photo of the selected submission', (tester) async {
      await openA3(tester, server: threePhotos());
      await tester.tap(thumb(2));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('proof-photo')));
      await tester.pumpAndSettle();

      final image = find.descendant(of: find.byKey(const ValueKey('proof-zoom')), matching: find.byType(Image));
      expect((tester.widget<Image>(image).image as TestProofImage).url, contains('e1-2.jpg'));
    });

    testWidgets('지난 제출 썸네일은 첫 장을 크게 본다(고른 장과 상관없이)', (tester) async {
      await openA3(tester, server: threePhotos());
      await tester.tap(thumb(2));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('proof-thumb-o3')));
      await tester.pumpAndSettle();

      final image = find.descendant(of: find.byKey(const ValueKey('proof-zoom')), matching: find.byType(Image));
      expect((tester.widget<Image>(image).image as TestProofImage).url, contains('o3.jpg'));
    });

    testWidgets('with one photo no strip is shown: "1장" 알약만, 구분선은 큰 사진 아래 12', (tester) async {
      await openA3(tester);

      expect(find.descendant(of: find.byKey(const ValueKey('photo-count')), matching: find.text('1장')), findsOneWidget);
      expect(thumb(0), findsNothing);
      expect(find.textContaining('선택됨'), findsNothing);
      expect(rectOf(tester, find.byKey(const ValueKey('proof-divider'))).top, 524);
    });

    testWidgets('옛 서버 모양(photo_urls 없음)이면 1장으로 보인다 — 웹이 서버보다 먼저 나가도 죽지 않는다', (tester) async {
      final server = fiveWaiting()
        ..legacyShape.add('e1')
        ..previous['e1'] = [previousPhoto('o1', legacy: true)];
      await openA3(tester, server: server);

      expect(tester.takeException(), isNull);
      expect(photoUrlShown(tester), contains('e1.jpg'));
      expect(thumb(0), findsNothing);
      expect(find.byKey(const ValueKey('proof-thumb-o1')), findsOneWidget);
      expect(inCard(find.text('1장')), findsOneWidget);
    });

    testWidgets('서명에 실패한 장(null): 썸네일은 image-off 20, 고르면 큰 칸이 기존 "사진 없음" 모양이고 크게 보기는 열리지 않는다', (tester) async {
      final server = threePhotos()..unsigned['e1'] = {1};
      await openA3(tester, server: server);

      final icon = find.descendant(of: thumb(1), matching: find.byIcon(LucideIcons.imageOff));
      expect(rectOf(tester, icon).size, const Size(20, 20));
      await tester.tap(thumb(1));
      await tester.pumpAndSettle();

      final photo = find.byKey(const ValueKey('proof-photo'));
      expect(find.descendant(of: photo, matching: find.text('사진 없음')), findsOneWidget);
      expect(find.descendant(of: photo, matching: find.byIcon(LucideIcons.imageOff)), findsOneWidget);
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proof-zoom')), findsNothing);
      // 다른 장은 그대로 본다
      await tester.tap(thumb(2));
      await tester.pumpAndSettle();
      expect(photoUrlShown(tester), contains('e1-2.jpg'));
    });

    testWidgets('사진이 한 장도 없으면(정리됨) 알약 · 썸네일 줄 없이 "사진 없음", 정보 카드는 "없음"', (tester) async {
      final server = fiveWaiting()..noPhoto.add('e1');
      await openA3(tester, server: server);

      expect(find.byKey(const ValueKey('photo-count')), findsNothing);
      expect(thumb(0), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('proof-photo')), matching: find.text('사진 없음')), findsOneWidget);
      expect(inCard(find.text('없음')), findsOneWidget);
    });

    testWidgets('사진 오류로 다시 받아도 고른 장이 유지된다', (tester) async {
      final server = threePhotos()..brokenOnce.add('e1');
      await openA3(tester, server: server);
      expect(server.detailFetches('e1'), 2);

      await tester.tap(thumb(1));
      await tester.pumpAndSettle();
      expect(photoUrlShown(tester), 'https://storage.test/e1-1.jpg?v=2');
    });

    testWidgets('제출 정보 카드에 "사진 / 3장" 행: 이름 88 14 web-muted + 값 14/600 web-ink, 항목 다음 · 제출 시각 앞', (tester) async {
      await openA3(tester, server: threePhotos());

      final name = inCard(find.text('사진'));
      final value = inCard(find.text('3장'));
      expect(rectOf(tester, value).left - rectOf(tester, name).left, 88 + 12);
      expect((styleOf(tester, name).fontSize, styleOf(tester, name).color), (14, AdminColors.muted));
      expect((styleOf(tester, value).fontWeight, styleOf(tester, value).color), (FontWeight.w600, AdminColors.ink));
      final kind = rectOf(tester, inCard(find.text('에브리타임 홍보')));
      final time = rectOf(tester, inCard(find.text('2026-10-18 14:08')));
      expect(rectOf(tester, name).top, kind.bottom + 16);
      expect(time.top, rectOf(tester, name).bottom + 16);
    });

    testWidgets('사진을 받는 동안 정보 카드의 사진 행은 "—", 카드 높이는 그대로(단추가 밀리지 않는다)', (tester) async {
      final server = threePhotos()..holdDetail = Completer<void>();
      await openA3(tester, server: server, settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(inCard(find.text('—')), findsOneWidget);
      final loadingCard = rectOf(tester, find.byKey(const ValueKey('submit-info')));
      server.holdDetail!.complete();
      await tester.pumpAndSettle();
      expect(rectOf(tester, find.byKey(const ValueKey('submit-info'))), loadingCard);
    });

    testWidgets('승인하면 다음 건으로 자동 이동하고 첫 장부터 보인다(동작은 그대로)', (tester) async {
      final server = threePhotos()..photoCounts['k1'] = 2;
      await openA3(tester, server: server);
      await tester.tap(thumb(2));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AdminButton, '승인'));
      await tester.pumpAndSettle();
      await letToastGo(tester);

      expect(server.reviews, ['approve:e1']);
      expect(photoUrlShown(tester), contains('k1.jpg'));
      expect(find.text('1/2 선택됨'), findsOneWidget);
    });

    testWidgets('1280 폭(최소 창)에서도, 글자 1.3배여도 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openA3(tester, server: threePhotos(), size: const Size(1280, 800));

      expect(tester.takeException(), isNull);
      expect(rectOf(tester, find.byKey(const ValueKey('proof-photo'))).width, 280);
    });

    testWidgets('화면 읽기: 썸네일은 "인증샷 n번 사진 보기" 단추, 고른 장은 selected', (tester) async {
      final handle = tester.ensureSemantics();
      await openA3(tester, server: threePhotos());

      expect(tester.getSemantics(thumb(0)), isSemantics(label: '인증샷 1번 사진 보기', isButton: true, isSelected: true));
      expect(tester.getSemantics(thumb(1)), isSemantics(label: '인증샷 2번 사진 보기', isButton: true, isSelected: false));
      handle.dispose();
    });
  });

  group('주소 · 목록', () {
    testWidgets('디스코드 링크 /heart-tasks/{id} 로 열면 그 건이 골라져 있다', (tester) async {
      await openA3(tester, path: '/heart-tasks/e2');

      expect(locationOf(tester), '/heart-tasks/e2');
      expect(materialOf(tester, row('e2')).color, AdminColors.primaryWash);
      expect(inCard(find.text('닉네임C')), findsOneWidget);
      // 메뉴 · TopBar 제목은 인증샷 검수
      expect(find.text('인증샷 검수'), findsNWidgets(2));
    });

    testWidgets('목록이 길면 목록 칸만 스크롤(zMTVl): 칩 줄은 제자리, 스크롤바 6 · 썸 web-outline-strong', (tester) async {
      await openA3(tester, server: FakeHeartTaskServer([for (var i = 0; i < 12; i++) taskRow('r$i', nickname: '닉네임$i')]));

      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(scrollbar.thickness, 6);
      expect(scrollbar.thumbColor, AdminColors.outlineStrong);
      expect(scrollbar.trackColor, AdminColors.outline);
      await tester.drag(row('r3'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(rectOf(tester, find.widgetWithText(AdminChip, '전체')).top, 96);
      expect(rectOf(tester, row('r0')).top, lessThan(144));
      expect(rectOf(tester, find.byKey(const ValueKey('submit-info'))).top, 96);
    });

    testWidgets('목록을 받는 중: 칩 줄 아래 같은 틀에 도는 아이콘 + 글', (tester) async {
      final server = fiveWaiting()..holdList = Completer<void>();
      await openA3(tester, server: server, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final frame = find.byType(AdminTableEmpty);
      expect(find.descendant(of: frame, matching: find.byType(AdminLoader)), findsOneWidget);
      expect(find.text('인증샷 목록을 불러오고 있어요'), findsOneWidget);

      server.holdList!.complete();
      await tester.pumpAndSettle();
      expect(row('e1'), findsOneWidget);
    });

    testWidgets('목록을 못 받으면 오류 틀 + 다시 시도', (tester) async {
      final server = fiveWaiting()..listFailure = 0;
      await openA3(tester, server: server);

      expect(find.text('목록을 불러오지 못했어요'), findsOneWidget);
      server.listFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();
      expect(row('e1'), findsOneWidget);
    });

    testWidgets('1280 폭(최소 창)에서도 넘치지 않는다 — 사진 칸만 줄어든다', (tester) async {
      await openA3(tester, size: const Size(1280, 800));

      expect(tester.takeException(), isNull);
      expect(rectOf(tester, row('e1')).width, 320);
      expect(rectOf(tester, find.byKey(const ValueKey('submit-info'))).width, 328);
      expect(rectOf(tester, find.byKey(const ValueKey('submit-info'))).right, 1280 - 32);
      expect(rectOf(tester, find.byKey(const ValueKey('proof-photo'))).width, 280);
    });

    testWidgets('글자를 키워도(1.3배) 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = fiveWaiting()..previous['e1'] = [previousPhoto('o1')];
      await openA3(tester, server: server);

      expect(tester.takeException(), isNull);
      expect(find.text('닉네임A'), findsWidgets);
    });
  });

  group('움직임', () {
    testWidgets('빈 목록은 관문 카드와 같은 등장(투명 · 8 아래 → 200ms), 동작 줄이기면 바로', (tester) async {
      await openA3(tester, server: FakeHeartTaskServer(const []));
      expect(find.descendant(of: find.byType(AdminTableEmpty), matching: find.byType(EnterMotion)), findsOneWidget);
    });

    // 대화상자 자신의 나타남(route animation)만 본다 — 누른 칸의 눌림 덧칠(색 변화)은 움직임이 아니다.
    double zoomShown(WidgetTester tester) =>
        ModalRoute.of(tester.element(find.byKey(const ValueKey('proof-zoom'))))!.animation!.value;

    testWidgets('동작 줄이기: 크게 보기 대화상자가 움직임 없이 바로 열리고 닫힌다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openA3(tester);

      await tester.tap(find.byKey(const ValueKey('proof-photo')));
      await tester.pump();
      await tester.pump();
      expect(zoomShown(tester), 1);

      await tester.tap(find.byKey(const ValueKey('proof-zoom-close')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('proof-zoom')), findsNothing);
    });

    testWidgets('크게 보기는 200ms 에 나타나고 200ms 에 사라진다(관문 카드와 같은 토큰 — DialogRoute 는 시간이 하나)', (tester) async {
      await openA3(tester);

      await tester.tap(find.byKey(const ValueKey('proof-photo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(zoomShown(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(zoomShown(tester), 1);

      await tester.tap(find.byKey(const ValueKey('proof-zoom-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(zoomShown(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 101));
      await tester.pump();
      expect(find.byKey(const ValueKey('proof-zoom')), findsNothing);
    });
  });

  group('접근성', () {
    testWidgets('목록 줄 · 칩은 고른 상태를, 사진은 "크게 보기"를 읽어 준다', (tester) async {
      final handle = tester.ensureSemantics();
      await openA3(tester);

      expect(tester.getSemantics(row('e1')), isSemantics(isSelected: true, isButton: true));
      expect(tester.getSemantics(row('k1')), isSemantics(isSelected: false, isButton: true));
      expect(tester.getSemantics(find.widgetWithText(AdminChip, '전체')), isSemantics(isSelected: true, isButton: true));
      expect(
        tester.getSemantics(find.byKey(const ValueKey('proof-photo'))),
        isSemantics(label: '인증샷 크게 보기', isButton: true),
      );
      expect(tester.getSemantics(inCard(find.text('제출 정보'))), isSemantics(isHeader: true));
      handle.dispose();
    });

    testWidgets('목록을 못 받았다는 제목은 화면 읽기가 바로 알린다(live region)', (tester) async {
      final handle = tester.ensureSemantics();
      await openA3(tester, server: fiveWaiting()..listFailure = 0);

      expect(tester.getSemantics(find.text('목록을 불러오지 못했어요')), isSemantics(isLiveRegion: true, isHeader: true));
      handle.dispose();
    });
  });
}
