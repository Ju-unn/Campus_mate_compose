import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_checkbox.dart';
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
import '../helpers/heart_task_fakes.dart' show TestProofImage, portraitTestImage, testNow;
import '../helpers/report_fakes.dart';

/// A4 신고 상세(pen gHMhM · 1440×900) · 대화상자(C4uUUH · yNu8b · n73XF) — 값표 ② ~ ⑥ + PNG A4_상세_* · A4_*_대화상자 측정.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  /// 메시지 신고 한 건 + 같은 사람의 다른 열린 신고 둘(pen gHMhM 예시)
  FakeReportServer messageReport({Map<String, Object?>? target}) {
    final server = FakeReportServer([reportRow('r1', target: target ?? targetProfile())]);
    server.others['p1'] = [
      otherReport('o1', createdAt: '2026-10-18T00:10:00+00:00'),
      otherReport('o2', reason: 'spam', createdAt: '2026-10-17T11:44:00+00:00'),
    ];
    return server;
  }

  Future<FakeReportServer> openDetail(
    WidgetTester tester, {
    FakeReportServer? server,
    String path = '/reports/r1',
    Size size = const Size(1440, 900),
    bool settle = true,
  }) async {
    final fake = server ?? messageReport();
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

  Future<void> letToastGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  Finder card(String name) => find.byKey(ValueKey('report-$name'));
  Finder inCard(String name, Finder f) => find.descendant(of: card(name), matching: f);
  Finder button(String label) => find.widgetWithText(AdminButton, label);
  Finder actionButton(String label) => inCard('actions', button(label));
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;
  AdminButton buttonOf(WidgetTester tester, Finder f) => tester.widget<AdminButton>(f);

  group('pen 배치(gHMhM)', () {
    testWidgets('TopBar "신고 상세", 머리줄 y96 · 높이 26: "← 신고 목록" 14/600 web-primary-text → 12 → 제목 16/700 → 상태 배지(오른쪽 끝)', (tester) async {
      await openDetail(tester);

      expect(find.text('신고 상세'), findsOneWidget);
      final head = tester.getRect(find.byKey(const ValueKey('report-head')));
      expect(head, const Rect.fromLTWH(272, 96, 1136, 26));
      final back = find.text('← 신고 목록');
      final title = find.text('메시지 신고 · 1명 신고');
      expect(tester.getRect(back).left, 272);
      expect(tester.getRect(title).left - tester.getRect(find.byKey(const ValueKey('report-back'))).right, 12);
      expect((styleOf(tester, back).fontSize, styleOf(tester, back).fontWeight, styleOf(tester, back).color), (14, FontWeight.w600, AdminColors.primaryText));
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (16, FontWeight.w700));
      final badge = find.descendant(of: find.byKey(const ValueKey('report-head')), matching: find.byType(StatusBadge));
      expect(tester.getRect(badge).right, 1408);
      expect(tester.widget<StatusBadge>(badge).label, '대기');
    });

    testWidgets('두 열 556 · 사이 24, 열 안 16: 왼쪽 사본 126(PNG 99 + 신고 사유 줄 27, 대장 지시 10-18) · 대상 요약 178, 오른쪽 다른 신고 124 · 조치 212', (tester) async {
      await openDetail(tester);

      expect(tester.getRect(card('copy')), const Rect.fromLTWH(272, 146, 556, 126));
      expect(tester.getRect(card('target')), const Rect.fromLTWH(272, 288, 556, 178));
      expect(tester.getRect(card('others')), const Rect.fromLTWH(852, 146, 556, 124));
      expect(tester.getRect(card('actions')), const Rect.fromLTWH(852, 286, 556, 212));
    });

    testWidgets('카드: web-surface · web-outline 1 · 모서리 14 · 안쪽 24 · 제목 16/700, 사본 글 14 web-body 줄 1.5', (tester) async {
      await openDetail(tester);

      final box = tester.widget<Container>(card('copy'));
      expect((box.decoration! as BoxDecoration).color, AdminColors.surface);
      expect((box.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(14));
      expect((box.foregroundDecoration! as BoxDecoration).border, Border.all(color: AdminColors.outline));
      expect(box.padding, const EdgeInsets.all(24));
      final title = inCard('copy', find.text('신고 당시 사본'));
      expect(tester.getRect(title).topLeft, const Offset(296, 170));
      final body = inCard('copy', find.text('신고된 메시지: "여기에 신고 당시 글자가 그대로 보여요."'));
      expect((styleOf(tester, body).fontSize, styleOf(tester, body).color, styleOf(tester, body).height), (14, AdminColors.body, 1.5));
      expect(tester.getRect(body).top, 227);
    });

    testWidgets('사본 카드 맨 위 "신고 사유" 줄 — 이름 88 14 web-muted · 사이 12 · 값 14/600 web-ink(대상 요약과 같은 규칙)', (tester) async {
      await openDetail(tester);

      final name = inCard('copy', find.text('신고 사유'));
      final value = inCard('copy', find.text('욕설·비방·혐오'));
      expect(tester.getRect(name).topLeft, const Offset(296, 200));
      expect(tester.getRect(value).left, 296 + 88 + 12);
      expect(styleOf(tester, name).color, AdminColors.muted);
      expect((styleOf(tester, value).fontSize, styleOf(tester, value).fontWeight, styleOf(tester, value).color), (14, FontWeight.w600, AdminColors.ink));
      // 메모가 없으면 메모 줄도 없다
      expect(inCard('copy', find.textContaining('메모: ')), findsNothing);
    });

    testWidgets('"기타" 메모(reason_note)가 있으면 사유 줄 아래 8 에 "메모: …" 14 web-body — 긴 글은 줄을 바꾼다', (tester) async {
      final note = '같은 말을 계속 보내요. ' * 8;
      await openDetail(tester, server: FakeReportServer([reportRow('r1', reason: 'other', reasonNote: note)]));

      expect(inCard('copy', find.text('기타')), findsOneWidget);
      final memo = inCard('copy', find.text('메모: $note'));
      expect(memo, findsOneWidget);
      expect((styleOf(tester, memo).fontSize, styleOf(tester, memo).fontWeight, styleOf(tester, memo).color), (14, FontWeight.w400, AdminColors.body));
      expect(tester.getRect(memo).top, tester.getRect(inCard('copy', find.text('신고 사유'))).bottom + 8);
      expect(tester.getRect(memo).height, greaterThan(21));
      expect(tester.widget<Text>(memo).maxLines, isNull);
    });

    testWidgets('대상 요약(QLdLH): 줄 4 — 이름 88 14 web-muted · 사이 12 · 값 14/600 web-ink, 줄 사이 8', (tester) async {
      await openDetail(tester);

      final rows = [('닉네임', '닉네임B'), ('학교', '연세대학교'), ('상태', '정상'), ('받은 신고', '1명')];
      for (final (i, (name, value)) in rows.indexed) {
        final key = inCard('target', find.text(name));
        final val = inCard('target', find.text(value));
        expect(tester.getRect(key).left, 296, reason: name);
        expect(tester.getRect(val).left, 296 + 88 + 12, reason: value);
        expect(tester.getRect(val).top, 288 + 24 + 22 + 8 + i * (19 + 8), reason: value);
        expect(styleOf(tester, key).color, AdminColors.muted);
        expect((styleOf(tester, val).fontWeight, styleOf(tester, val).color), (FontWeight.w600, AdminColors.ink));
      }
    });

    testWidgets('같은 대상 다른 신고(kZJtf): "사유 · 시각 · 상태" 14 web-body', (tester) async {
      await openDetail(tester);

      final first = inCard('others', find.text('욕설·비방·혐오 · 2026-10-18 09:10 · 열림'));
      expect(first, findsOneWidget);
      expect(inCard('others', find.text('광고·스팸 · 2026-10-17 20:44 · 열림')), findsOneWidget);
      expect((styleOf(tester, first).fontSize, styleOf(tester, first).color), (14, AdminColors.body));
    });

    testWidgets('조치 카드(eKM6S): 단추 44 · 사이 8, 줄 사이 12, 안내 12 web-muted 줄 1.5', (tester) async {
      await openDetail(tester);

      final suspend = tester.getRect(actionButton('정지'));
      final done = tester.getRect(actionButton('조치 완료'));
      expect(suspend.topLeft, const Offset(876, 286 + 24 + 22 + 12));
      expect(suspend.height, 44);
      expect(done.top - suspend.bottom, 12);
      expect(tester.getRect(actionButton('기각')).left - done.right, 8);
      expect(buttonOf(tester, actionButton('정지')).variant, AdminButtonVariant.danger);
      expect(buttonOf(tester, actionButton('조치 완료')).variant, AdminButtonVariant.primary);
      expect(buttonOf(tester, actionButton('기각')).variant, AdminButtonVariant.secondary);
      expect(buttonOf(tester, actionButton('채팅 앞뒤 보기')).variant, AdminButtonVariant.secondary);
      final guide = inCard('actions', find.text('정지·가림 해제는 사유 입력이 필요해요. 같은 대상의 열린 신고를 한꺼번에 닫을 수도 있어요.'));
      expect((styleOf(tester, guide).fontSize, styleOf(tester, guide).color, styleOf(tester, guide).height), (12, AdminColors.muted, 1.5));
    });
  });

  group('조치 단추 노출 규칙(⑥)', () {
    testWidgets('메시지 신고 · 정상 대상: [정지] [조치 완료] [기각] [채팅 앞뒤 보기] — 가림 해제 · 글 가림 없음', (tester) async {
      await openDetail(tester);

      for (final label in ['정지', '조치 완료', '기각', '채팅 앞뒤 보기']) {
        expect(actionButton(label), findsOneWidget, reason: label);
      }
      for (final label in ['정지 해제', '가림 해제', '글 가림', '글 가림 해제']) {
        expect(actionButton(label), findsNothing, reason: label);
      }
    });

    testWidgets('자동 가림 중이면 [가림 해제], 상태 "정상 · 자동 가림 중"', (tester) async {
      await openDetail(tester, server: messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00')));

      expect(actionButton('가림 해제'), findsOneWidget);
      expect(inCard('target', find.text('정상 · 자동 가림 중')), findsOneWidget);
    });

    testWidgets('대상이 정지 중이면 [정지] 대신 [정지 해제](보조), 상태 "정지 중"', (tester) async {
      await openDetail(tester, server: messageReport(target: targetProfile(status: 'suspended')));

      expect(actionButton('정지'), findsNothing);
      expect(buttonOf(tester, actionButton('정지 해제')).variant, AdminButtonVariant.secondary);
      expect(inCard('target', find.text('정지 중')), findsOneWidget);
    });

    testWidgets('투표 글 신고: [글 가림] · 채팅 없음, 대상 요약 "글 상태" 보임 배지(web-success)', (tester) async {
      await openDetail(tester, server: FakeReportServer([reportRow('r1', type: 'poll')]));

      expect(find.text('투표 글 신고 · 1명 신고'), findsOneWidget);
      expect(actionButton('글 가림'), findsOneWidget);
      expect(actionButton('채팅 앞뒤 보기'), findsNothing);
      final badge = tester.widget<StatusBadge>(inCard('target', find.byType(StatusBadge)));
      expect((badge.label, badge.tone), ('보임', StatusTone.success));
      expect(inCard('target', find.text('상태')), findsNothing);
      expect(inCard('copy', find.text('질문: 학식 어때요?')), findsOneWidget);
      expect(styleOf(tester, inCard('copy', find.text('질문: 학식 어때요?'))).fontWeight, FontWeight.w600);
      expect(inCard('copy', find.text('선택지 1 · 맛있어요')), findsOneWidget);
      expect(inCard('copy', find.text('선택지 2 · 별로예요')), findsOneWidget);
    });

    testWidgets('지인 리뷰 신고 · 가려진 글: [글 가림 해제], "작성자" · 가려짐 배지(web-danger), 태그 칩 · 한마디', (tester) async {
      final server = FakeReportServer([reportRow('r1', type: 'friend_review', targetId: 'rv1')])..contentStatus['rv1'] = 'blinded';
      await openDetail(tester, server: server);

      expect(find.text('지인 리뷰 신고 · 1명 신고'), findsOneWidget);
      expect(actionButton('글 가림 해제'), findsOneWidget);
      expect(actionButton('글 가림'), findsNothing);
      expect(inCard('target', find.text('작성자')), findsOneWidget);
      final badge = tester.widget<StatusBadge>(inCard('target', find.byType(StatusBadge)));
      expect((badge.label, badge.tone), ('가려짐', StatusTone.danger));
      expect(inCard('copy', find.text('신고 당시 사본 · 지인 리뷰')), findsOneWidget);
      final chip = tester.getRect(find.byKey(const ValueKey('review-tag-0')));
      expect(chip.height, 36);
      expect(tester.getRect(find.byKey(const ValueKey('review-tag-1'))).left - chip.right, 8);
      expect(inCard('copy', find.text('한마디: 이 자리에는 신고 당시 한마디가 그대로 보여요.')), findsOneWidget);
    });

    testWidgets('닫힌 신고: [조치 완료] · [기각] 대신 "처리됨 · 시각" 14 web-muted, 배지 조치', (tester) async {
      final server = FakeReportServer([
        reportRow('r1', status: 'actioned', resolvedAt: '2026-10-18T05:30:00+00:00', target: targetProfile(status: 'suspended')),
      ]);
      await openDetail(tester, server: server);

      expect(actionButton('조치 완료'), findsNothing);
      expect(actionButton('기각'), findsNothing);
      expect(actionButton('채팅 앞뒤 보기'), findsOneWidget);
      final done = inCard('actions', find.text('처리됨 · 2026-10-18 14:30'));
      expect((styleOf(tester, done).fontSize, styleOf(tester, done).color), (14, AdminColors.muted));
      expect(tester.widget<StatusBadge>(find.descendant(of: find.byKey(const ValueKey('report-head')), matching: find.byType(StatusBadge))).label, '조치');
      // 안내는 열린 신고와 같은 YZM0o 하나(대장 결정 10-18)
      expect(inCard('actions', find.text('정지·가림 해제는 사유 입력이 필요해요. 같은 대상의 열린 신고를 한꺼번에 닫을 수도 있어요.')), findsOneWidget);
      expect(inCard('actions', find.textContaining('닫힌 신고는')), findsNothing);
    });

    testWidgets('닫힌 신고는 단추를 한 줄(사이 8)에 — [정지 해제] [채팅 앞뒤 보기], 조치 카드 높이 187(PNG 286 → 473)', (tester) async {
      final server = FakeReportServer([
        reportRow('r1', status: 'actioned', resolvedAt: '2026-10-18T05:30:00+00:00', target: targetProfile(status: 'suspended')),
      ]);
      await openDetail(tester, server: server);

      final unsuspend = tester.getRect(actionButton('정지 해제'));
      final chat = tester.getRect(actionButton('채팅 앞뒤 보기'));
      expect(chat.top, unsuspend.top);
      expect(chat.left - unsuspend.right, 8);
      expect(tester.getRect(card('actions')).height, 187);
    });

    testWidgets('대상 계정이 지워졌으면(target_profile null) 사람 조치 단추가 없고 요약 값은 "—"', (tester) async {
      await openDetail(tester, server: FakeReportServer([reportRow('r1', target: null)]));

      expect(actionButton('정지'), findsNothing);
      expect(actionButton('조치 완료'), findsOneWidget);
      expect(inCard('target', find.text('—')), findsNWidgets(3));
      expect(inCard('target', find.text('0명')), findsOneWidget);
    });
  });

  group('프로필 사본(Web/Thumb vKr36 · No Photo Iy6MD)', () {
    FakeReportServer profileReport({bool avatar = true, int photos = 1}) {
      final server = FakeReportServer([reportRow('r1', type: 'profile')]);
      server.snapshots['r1'] = {
        'nickname': '닉네임B',
        'bio': '이 자리에는 신고 당시 소개 글이 그대로 보여요.',
        'avatar_url': avatar ? 'https://storage.test/object/public/avatars/p1/a.png' : null,
        'photo_urls': [for (var i = 0; i < photos; i++) 'https://storage.test/sign/p1/$i.jpg?token=t'],
      };
      return server;
    }

    testWidgets('닉네임 줄 · 소개 → 썸네일 72(web-surface-strong · web-outline 1 · 모서리 8) + 이름표 12 web-muted, 사이 16 → 안내', (tester) async {
      await openDetail(tester, server: profileReport());

      expect(inCard('copy', find.text('신고 당시 사본 · 프로필')), findsOneWidget);
      expect(inCard('copy', find.text('닉네임B')), findsOneWidget);
      expect(inCard('copy', find.text('소개: 이 자리에는 신고 당시 소개 글이 그대로 보여요.')), findsOneWidget);
      final avatar = tester.getRect(find.byKey(const ValueKey('report-thumb-avatar')));
      final photo = tester.getRect(find.byKey(const ValueKey('report-thumb-photo-0')));
      expect(avatar.size, const Size(72, 72));
      expect(avatar.topLeft, const Offset(296, 256 + 27));
      expect(photo.left - avatar.right, 16);
      expect(inCard('copy', find.text('공개 아바타')), findsOneWidget);
      expect(inCard('copy', find.text('실사진')), findsOneWidget);
      expect(tester.getRect(inCard('copy', find.text('공개 아바타'))).top, avatar.bottom + 6);
      expect(styleOf(tester, inCard('copy', find.text('실사진'))).color, AdminColors.muted);
      expect(inCard('copy', find.text('썸네일을 누르면 크게 보여요.')), findsOneWidget);
      // 카드 높이 252(PNG 측정 146 → 398) + 신고 사유 줄 27
      expect(tester.getRect(card('copy')).height, 252 + 27);
    });

    testWidgets('사진이 없으면 image-off 24 web-disabled + "사진 없음" 12 web-muted 썸네일(누를 수 없음)', (tester) async {
      await openDetail(tester, server: profileReport(avatar: false, photos: 0));

      final avatar = find.byKey(const ValueKey('report-thumb-avatar'));
      final icon = tester.widget<Icon>(find.descendant(of: avatar, matching: find.byIcon(LucideIcons.imageOff)));
      expect((icon.size, icon.color), (24, AdminColors.disabled));
      expect(find.descendant(of: avatar, matching: find.text('사진 없음')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('report-thumb-photo-0')), matching: find.text('사진 없음')), findsOneWidget);
      expect(inCard('copy', find.text('썸네일을 누르면 크게 보여요.')), findsNothing);
    });

    testWidgets('썸네일을 누르면 A3 와 같은 크게 보기(닫기 44 · 안내 알약), 닫으면 사라진다', (tester) async {
      await openDetail(tester, server: profileReport(photos: 2));

      await tester.tap(find.byKey(const ValueKey('report-thumb-photo-1')));
      await tester.pumpAndSettle();
      final zoom = find.byKey(const ValueKey('proof-zoom'));
      expect(zoom, findsOneWidget);
      final shown = tester.widget<Image>(find.descendant(of: zoom, matching: find.byType(Image)));
      expect((shown.image as TestProofImage).url, 'https://storage.test/sign/p1/1.jpg?token=t');
      expect(find.text('Esc 또는 바깥을 누르면 닫혀요'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('proof-zoom-close')));
      await tester.pumpAndSettle();
      expect(zoom, findsNothing);
    });
  });

  group('사유 대화상자(C4uUUH · Web/Dialog p8OOG)', () {
    Future<void> openSuspend(WidgetTester tester) async {
      await tester.tap(actionButton('정지'));
      await tester.pumpAndSettle();
    }

    Finder dialog() => find.byKey(const ValueKey('reason-dialog'));
    Finder confirm(String label) => find.descendant(of: dialog(), matching: button(label));

    testWidgets('정지: 480 · 안쪽 24 · 제목 20/700 · 설명 14 web-muted · 입력 96(web-outline-strong 1 · 모서리 8) · [취소] + [정지](위험)', (tester) async {
      await openDetail(tester);
      await openSuspend(tester);

      expect(tester.getSize(dialog()).width, 480);
      expect(find.descendant(of: dialog(), matching: find.text('사용자를 정지할까요?')), findsOneWidget);
      expect(find.descendant(of: dialog(), matching: find.text('닉네임B 를 정지해요. 작업 기록에 사유가 남고, 사유는 필수예요.')), findsOneWidget);
      final field = find.descendant(of: dialog(), matching: find.byType(TextField));
      expect(tester.getSize(field), const Size(480 - 48, 96));
      final decoration = tester.widget<TextField>(field).decoration!;
      expect(decoration.hintText, '사유 (필수)');
      // 열 때는 pen 처럼 쉬는 테두리(초점 테두리가 보이지 않는다)
      expect(tester.widget<TextField>(field).focusNode?.hasFocus ?? false, isFalse);
      expect(tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText))).focusNode.hasFocus, isFalse);
      expect((decoration.enabledBorder! as OutlineInputBorder).borderSide, const BorderSide(color: AdminColors.outlineStrong));
      expect((decoration.enabledBorder! as OutlineInputBorder).borderRadius, BorderRadius.circular(8));
      expect(buttonOf(tester, confirm('정지')).variant, AdminButtonVariant.danger);
      expect(buttonOf(tester, confirm('취소')).variant, AdminButtonVariant.secondary);
      expect(tester.getRect(confirm('정지')).left - tester.getRect(confirm('취소')).right, 8);
    });

    testWidgets('사유가 비거나 공백뿐이면 확인이 잠기고, 500자 넘게는 들어가지 않는다', (tester) async {
      await openDetail(tester);
      await openSuspend(tester);

      expect(buttonOf(tester, confirm('정지')).onPressed, isNull);
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '   ');
      await tester.pump();
      expect(buttonOf(tester, confirm('정지')).onPressed, isNull);
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '가' * 600);
      await tester.pump();
      expect(tester.widget<TextField>(find.descendant(of: dialog(), matching: find.byType(TextField))).controller!.text.length, 500);
      expect(buttonOf(tester, confirm('정지')).onPressed, isNotNull);
    });

    testWidgets('정지 → 사유(앞뒤 공백만 뗌)를 보내고 토스트 "처리했어요" · 상세를 새로 받아 [정지 해제]', (tester) async {
      final server = await openDetail(tester);
      await openSuspend(tester);

      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '  불쾌한 사진 3건  ');
      await tester.pump();
      await tester.tap(confirm('정지'));
      await tester.pumpAndSettle();

      expect(server.actions, ['/admin/profiles/p1/suspend {"reason":"불쾌한 사진 3건"}']);
      expect(dialog(), findsNothing);
      expect(find.widgetWithText(AdminToast, '처리했어요'), findsOneWidget);
      expect(server.detailFetches('r1'), 2);
      expect(actionButton('정지 해제'), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('처리 중: 확인에 도는 아이콘, 취소는 눌리지 않고 Esc · 바깥으로도 닫히지 않는다', (tester) async {
      final server = await openDetail(tester);
      await openSuspend(tester);
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '사유');
      await tester.pump();
      server.holdAction = Completer<void>();

      await tester.tap(confirm('정지'));
      await tester.pump();
      expect(buttonOf(tester, confirm('정지')).loading, isTrue);
      expect(buttonOf(tester, confirm('취소')).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dialog(), findsOneWidget);

      server.holdAction!.complete();
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('실패하면 대화상자 안 오류 줄(입력 아래 8), 대화상자 · 글자는 그대로', (tester) async {
      final server = await openDetail(tester);
      server.actionFailure = 500;
      await openSuspend(tester);
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '불쾌한 사진 3건');
      await tester.pump();

      await tester.tap(confirm('정지'));
      await tester.pumpAndSettle();

      final error = find.descendant(of: dialog(), matching: find.byType(ErrorRow));
      expect(error, findsOneWidget);
      expect(find.descendant(of: error, matching: find.text('처리하지 못했어요. 다시 시도해 주세요.')), findsOneWidget);
      expect(tester.getRect(error).top - tester.getRect(find.descendant(of: dialog(), matching: find.byType(TextField))).bottom, 8);
      expect(find.text('불쾌한 사진 3건'), findsOneWidget);
      expect(buttonOf(tester, confirm('정지')).onPressed, isNotNull);
    });

    testWidgets('409 → 대화상자를 닫고 "이미 처리된 항목이에요" → 확인하면 상세를 새로 받아 있다', (tester) async {
      final server = await openDetail(tester);
      server.takenElsewhere = true;
      await openSuspend(tester);
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '사유');
      await tester.pump();

      await tester.tap(confirm('정지'));
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(find.text('이미 처리된 항목이에요'), findsOneWidget);
      await tester.tap(button('확인'));
      await tester.pumpAndSettle();
      expect(find.text('이미 처리된 항목이에요'), findsNothing);
      expect(server.detailFetches('r1'), 2);
    });

    testWidgets('가림 해제 · 글 가림도 사유를 받아 각 경로로 보낸다', (tester) async {
      final server = FakeReportServer([
        reportRow('r1', type: 'poll', targetId: 'poll1', target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00')),
      ]);
      await openDetail(tester, server: server);

      await tester.tap(actionButton('글 가림'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '욕설');
      await tester.pump();
      await tester.tap(confirm('글 가림'));
      await tester.pumpAndSettle();
      await letToastGo(tester);
      await tester.tap(actionButton('가림 해제'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '오신고');
      await tester.pump();
      await tester.tap(confirm('가림 해제'));
      await tester.pumpAndSettle();

      expect(server.actions, ['/admin/content/polls/poll1/blind {"reason":"욕설"}', '/admin/profiles/p1/unhide {"reason":"오신고","seen_report_ids":["r1"]}']);
      expect(actionButton('글 가림 해제'), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('[가림 해제] 대화상자 본문은 "이 화면에서 본 열린 신고만 기각돼요(그 뒤 들어온 신고는 남아요)"', (tester) async {
      await openDetail(tester, server: messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00')));

      await tester.tap(actionButton('가림 해제'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: dialog(),
          matching: find.text('닉네임B 의 자동 가림을 풀고, 이 화면에서 본 열린 신고만 기각돼요(그 뒤 들어온 신고는 남아요). 작업 기록에 사유가 남고, 사유는 필수예요.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('[가림 해제] 단추는 이 신고(열려 있으면)와 같은 사람의 열린 신고들을 본 신고로 보낸다', (tester) async {
      final server = messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'));
      server.others['p1']!.add(otherReport('o0', status: 'actioned', createdAt: '2026-10-10T00:00:00+00:00'));
      await openDetail(tester, server: server);
      // 운영자가 상세를 연 뒤에 들어온 새 신고는 본 신고가 아니다
      server.others['p1']!.add(otherReport('o3', createdAt: '2026-10-18T05:00:00+00:00'));

      await tester.tap(actionButton('가림 해제'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '오신고');
      await tester.pump();
      await tester.tap(confirm('가림 해제'));
      await tester.pumpAndSettle();

      expect(server.lastBody('/unhide'), {'reason': '오신고', 'seen_report_ids': ['r1', 'o1', 'o2']});
      expect(server.others['p1']!.where((o) => o['status'] == 'open').map((o) => o['id']), ['o3']);
      await letToastGo(tester);
    });
  });

  group('조치 완료 · 기각 대화상자(체크 Web/Checkbox A2mVU · kwu5q)', () {
    Finder dialog() => find.byKey(const ValueKey('resolve-dialog'));
    Finder confirm(String label) => find.descendant(of: dialog(), matching: button(label));
    Finder check(String label) => find.descendant(of: dialog(), matching: find.widgetWithText(AdminCheckbox, label));

    testWidgets('조치 완료: 메모(선택) 44 · 체크 "같은 대상의 열린 신고 2건도 함께 닫기"(기본 켬) · 확인은 늘 열림', (tester) async {
      await openDetail(tester);
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();

      expect(find.descendant(of: dialog(), matching: find.text('조치를 완료할까요?')), findsOneWidget);
      expect(find.descendant(of: dialog(), matching: find.text('신고를 조치 완료로 닫아요. 메모는 작업 기록에 남아요.')), findsOneWidget);
      expect(find.descendant(of: dialog(), matching: find.text('메모 (선택)')), findsOneWidget);
      final field = find.descendant(of: dialog(), matching: find.byType(TextField));
      expect(tester.getSize(field).height, 44);
      expect(tester.widget<TextField>(field).decoration!.hintText, '처리 메모를 남길 수 있어요');
      expect(tester.widget<AdminCheckbox>(check('같은 대상의 열린 신고 2건도 함께 닫기')).value, isTrue);
      expect(check('가림도 함께 해제하기'), findsNothing);
      expect(buttonOf(tester, confirm('조치 완료')).variant, AdminButtonVariant.primary);
      expect(buttonOf(tester, confirm('조치 완료')).onPressed, isNotNull);
      // 입력 → 12 → 체크 줄 → 16 → 단추 (PNG 측정)
      expect(tester.getRect(check('같은 대상의 열린 신고 2건도 함께 닫기')).top - tester.getRect(field).bottom, 12);
    });

    testWidgets('조치 완료 → {outcome: actioned, note, same_target: true} · 토스트 · 닫힌 상세("처리됨 · 시각")', (tester) async {
      final server = await openDetail(tester);
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), ' 경고 ');
      await tester.tap(confirm('조치 완료'));
      await tester.pumpAndSettle();

      expect(server.lastBody('/resolve'), {'outcome': 'actioned', 'note': '경고', 'same_target': true, 'seen_report_ids': ['o1', 'o2']});
      expect(find.widgetWithText(AdminToast, '처리했어요'), findsOneWidget);
      expect(inCard('actions', find.text('처리됨 · 2026-10-18 14:30')), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('메모 칸에서 Enter 를 누르면 확인과 같다(키보드만으로 닫기)', (tester) async {
      final server = await openDetail(tester);
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '경고');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(server.lastBody('/resolve'), {'outcome': 'actioned', 'note': '경고', 'same_target': true, 'seen_report_ids': ['o1', 'o2']});
      expect(dialog(), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('체크를 끄면 same_target: false, 메모가 비면 note: null', (tester) async {
      final server = await openDetail(tester);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();
      await tester.tap(check('같은 대상의 열린 신고 2건도 함께 닫기'));
      await tester.pump();
      await tester.tap(confirm('기각'));
      await tester.pumpAndSettle();

      expect(server.lastBody('/resolve'), {'outcome': 'dismissed', 'note': null, 'same_target': false});
      await letToastGo(tester);
    });

    testWidgets('같은 대상의 다른 열린 신고가 없으면 체크도 없다', (tester) async {
      await openDetail(tester, server: FakeReportServer([reportRow('r1')]));
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();

      expect(find.descendant(of: dialog(), matching: find.byType(AdminCheckbox)), findsNothing);
    });

    testWidgets('기각 + 자동 가림 중: 체크 2개(기본 켬) → 기각 뒤 가림 해제를 같은 글로 이어 부른다', (tester) async {
      final server = messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'));
      await openDetail(tester, server: server);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();

      expect(find.descendant(of: dialog(), matching: find.text('신고를 기각할까요?')), findsOneWidget);
      expect(find.descendant(of: dialog(), matching: find.text('이 신고를 기각으로 닫아요. 대상이 자동 가림 중이라 가림 해제 선택이 함께 보여요.')), findsOneWidget);
      expect(tester.widget<AdminCheckbox>(check('가림도 함께 해제하기')).value, isTrue);
      final first = tester.getRect(check('같은 대상의 열린 신고 2건도 함께 닫기'));
      expect(tester.getRect(check('가림도 함께 해제하기')).top - first.bottom, 12);
      await tester.enterText(find.descendant(of: dialog(), matching: find.byType(TextField)), '오신고');
      await tester.tap(confirm('기각'));
      await tester.pumpAndSettle();

      expect(server.actions, [
        '/admin/reports/r1/resolve {"outcome":"dismissed","note":"오신고","same_target":true,"seen_report_ids":["o1","o2"]}',
        '/admin/profiles/p1/unhide {"reason":"오신고","seen_report_ids":["o1","o2"]}',
      ]);
      expect(find.widgetWithText(AdminToast, '처리했어요'), findsOneWidget);
      expect(actionButton('가림 해제'), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('메모 없이 가림도 해제하면 가림 해제 사유는 "신고 기각"(서버는 사유 필수)', (tester) async {
      final server = messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'));
      await openDetail(tester, server: server);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('기각'));
      await tester.pumpAndSettle();

      expect(server.lastBody('/unhide'), {'reason': '신고 기각', 'seen_report_ids': ['o1', 'o2']});
      await letToastGo(tester);
    });

    Future<FakeReportServer> openHiddenDismiss(WidgetTester tester) async {
      final server = messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'));
      await openDetail(tester, server: server);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();
      return server;
    }

    AdminCheckbox closeOthers(WidgetTester tester) => tester.widget<AdminCheckbox>(check('같은 대상의 열린 신고 2건도 함께 닫기'));

    testWidgets('가림 해제가 켜져 있으면 "함께 닫기"는 켜진 채로 잠기고(서버 가림 해제가 열린 신고를 모두 기각), 끄면 잠기기 전 값으로', (tester) async {
      await openHiddenDismiss(tester);

      expect(closeOthers(tester).value, isTrue);
      expect(closeOthers(tester).onChanged, isNull);

      // 가림 해제를 끄면 다시 바꿀 수 있다 → 끈 채로 두고 가림 해제를 켜면 켜짐으로 잠기고, 다시 끄면 끈 값으로 돌아온다
      await tester.tap(check('가림도 함께 해제하기'));
      await tester.pump();
      expect(closeOthers(tester).onChanged, isNotNull);
      await tester.tap(check('같은 대상의 열린 신고 2건도 함께 닫기'));
      await tester.pump();
      expect(closeOthers(tester).value, isFalse);
      await tester.tap(check('가림도 함께 해제하기'));
      await tester.pump();
      expect((closeOthers(tester).value, closeOthers(tester).onChanged), (true, null));
      await tester.tap(check('가림도 함께 해제하기'));
      await tester.pump();
      expect(closeOthers(tester).value, isFalse);
      expect(closeOthers(tester).onChanged, isNotNull);
    });

    testWidgets('"가림도 함께 해제하기" 바로 아래 안내 12 web-muted 줄 1.5 — 체크 글자 시작에 맞춤, 이 체크가 보일 때만', (tester) async {
      await openHiddenDismiss(tester);

      final hint = find.descendant(of: dialog(), matching: find.text('가림을 풀면 이 화면에서 본 열린 신고도 함께 기각돼요'));
      final style = styleOf(tester, hint);
      expect((style.fontSize, style.color, style.height), (12, AdminColors.muted, 1.5));
      final label = find.descendant(of: check('가림도 함께 해제하기'), matching: find.text('가림도 함께 해제하기'));
      expect(tester.getRect(hint).left, tester.getRect(label).left);
      // 체크 아랫선 ↔ 안내 윗선 12(pen A4_기각_대화상자)
      expect(tester.getRect(hint).top, tester.getRect(check('가림도 함께 해제하기')).bottom + 12);

      await tester.tap(find.descendant(of: dialog(), matching: button('취소')));
      await tester.pumpAndSettle();
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();
      expect(find.text('가림을 풀면 이 화면에서 본 열린 신고도 함께 기각돼요'), findsNothing);
    });

    testWidgets('요청 순서: 닫기(same_target true) → 가림 해제 → 상세 새로 받기', (tester) async {
      final server = await openHiddenDismiss(tester);
      final before = server.requests.length;

      await tester.tap(confirm('기각'));
      await tester.pumpAndSettle();

      expect(server.requests.skip(before).map((r) => '${r.method} ${r.url.path}'), [
        'POST /admin/reports/r1/resolve',
        'POST /admin/profiles/p1/unhide',
        'GET /admin/reports/r1',
      ]);
      expect(server.lastBody('/resolve')['same_target'], isTrue);
      await letToastGo(tester);
    });

    testWidgets('가림 해제 체크를 끄면 기각만 보낸다', (tester) async {
      final server = messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'));
      await openDetail(tester, server: server);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();
      await tester.tap(check('가림도 함께 해제하기'));
      await tester.pump();
      await tester.tap(confirm('기각'));
      await tester.pumpAndSettle();

      expect(server.actions.where((a) => a.contains('/unhide')), isEmpty);
      await letToastGo(tester);
    });

    testWidgets('기각은 됐는데 가림 해제가 실패하면 대화상자를 닫고 조치 카드에 그 사실을 오류 줄로', (tester) async {
      final server = messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'))..unhideFailure = 500;
      await openDetail(tester, server: server);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('기각'));
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      final error = inCard('actions', find.byType(ErrorRow));
      expect(find.descendant(of: error, matching: find.text('신고는 기각했지만 가림은 해제하지 못했어요. [가림 해제]로 다시 시도해 주세요.')), findsOneWidget);
      expect(actionButton('가림 해제'), findsOneWidget);
      expect(inCard('actions', find.textContaining('처리됨 · ')), findsOneWidget);
    });

    testWidgets('본 신고만 닫는다 — 보내는 id 는 대화상자의 "2건"과 같은 열린 신고들이고, 닫힌 신고 · 열고 난 뒤 들어온 새 신고는 없다', (tester) async {
      final server = messageReport();
      server.others['p1']!.add(otherReport('o0', status: 'dismissed', createdAt: '2026-10-10T00:00:00+00:00'));
      await openDetail(tester, server: server);
      // 운영자가 상세를 연 뒤에 들어온 새 신고
      server.others['p1']!.add(otherReport('o3', createdAt: '2026-10-18T05:00:00+00:00'));

      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();
      expect(check('같은 대상의 열린 신고 2건도 함께 닫기'), findsOneWidget);
      await tester.tap(confirm('조치 완료'));
      await tester.pumpAndSettle();

      expect(server.lastBody('/resolve')['seen_report_ids'], ['o1', 'o2']);
      expect(server.others['p1']!.where((o) => o['status'] == 'open').map((o) => o['id']), ['o3']);
      await letToastGo(tester);
    });

    testWidgets('함께 닫기를 끄면 본 신고 목록을 보내지 않는다 · 다른 열린 신고가 없어도 마찬가지', (tester) async {
      final server = await openDetail(tester);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();
      await tester.tap(check('같은 대상의 열린 신고 2건도 함께 닫기'));
      await tester.pump();
      await tester.tap(confirm('기각'));
      await tester.pumpAndSettle();

      expect(server.lastBody('/resolve').containsKey('seen_report_ids'), isFalse);
      await letToastGo(tester);
    });

    testWidgets('서버가 422 seen_reports_required 로 돌리면 일반 오류 줄 "처리하지 못했어요"', (tester) async {
      final server = await openDetail(tester);
      server.actionFailure = 422;
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('조치 완료'));
      await tester.pumpAndSettle();

      expect(dialog(), findsOneWidget);
      expect(find.descendant(of: dialog(), matching: find.text('처리하지 못했어요. 다시 시도해 주세요.')), findsOneWidget);
    });

    testWidgets('닫기 실패는 대화상자 안 오류 줄, 409 는 이미 처리됨', (tester) async {
      final server = await openDetail(tester);
      server.actionFailure = 0;
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('조치 완료'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: dialog(), matching: find.text('처리하지 못했어요. 다시 시도해 주세요.')), findsOneWidget);

      server
        ..actionFailure = null
        ..takenElsewhere = true;
      await tester.tap(confirm('조치 완료'));
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
      expect(find.text('이미 처리된 항목이에요'), findsOneWidget);
    });
  });

  group('체크박스(Web/Checkbox) 모양', () {
    testWidgets('상자 18 · 모서리 4 · 켬 web-primary 테두리 + 체크, 끔 web-outline-strong 테두리 · 체크 없음 · 글자 14 web-ink 사이 10', (tester) async {
      await openDetail(tester);
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();
      final checkbox = find.byType(AdminCheckbox);
      final box = find.descendant(of: checkbox, matching: find.byKey(const ValueKey('checkbox-box')));

      expect(tester.getSize(box), const Size(18, 18));
      BoxDecoration deco() => tester.widget<Container>(box).decoration! as BoxDecoration;
      expect(deco().border, Border.all(color: AdminColors.primary, width: 1.5));
      expect(deco().borderRadius, BorderRadius.circular(4));
      expect(find.descendant(of: box, matching: find.byIcon(LucideIcons.check)), findsOneWidget);
      final label = find.descendant(of: checkbox, matching: find.text('같은 대상의 열린 신고 2건도 함께 닫기'));
      expect(tester.getRect(label).left - tester.getRect(box).right, 10);
      expect((styleOf(tester, label).fontSize, styleOf(tester, label).color), (14, AdminColors.ink));

      await tester.tap(checkbox);
      await tester.pump();
      expect(deco().border, Border.all(color: AdminColors.outlineStrong, width: 1.5));
      expect(find.descendant(of: box, matching: find.byIcon(LucideIcons.check)), findsNothing);
    });

    testWidgets('잠긴 켬(Web/Checkbox · On · Disabled IovNE): 상자 · 체크 web-disabled, 글자 web-muted — 잠금이 풀리면 원래 색', (tester) async {
      final server = messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'));
      await openDetail(tester, server: server);
      await tester.tap(actionButton('기각'));
      await tester.pumpAndSettle();
      final others = find.widgetWithText(AdminCheckbox, '같은 대상의 열린 신고 2건도 함께 닫기');
      final box = find.descendant(of: others, matching: find.byKey(const ValueKey('checkbox-box')));
      BoxDecoration deco() => tester.widget<Container>(box).decoration! as BoxDecoration;
      Color? iconColor() => tester.widget<Icon>(find.descendant(of: box, matching: find.byIcon(LucideIcons.check))).color;
      Color? labelColor() => styleOf(tester, find.descendant(of: others, matching: find.text('같은 대상의 열린 신고 2건도 함께 닫기'))).color;

      expect(deco().border, Border.all(color: AdminColors.disabled, width: 1.5));
      expect(iconColor(), AdminColors.disabled);
      expect(labelColor(), AdminColors.muted);

      await tester.tap(find.widgetWithText(AdminCheckbox, '가림도 함께 해제하기'));
      await tester.pump();
      expect(deco().border, Border.all(color: AdminColors.primary, width: 1.5));
      expect(iconColor(), AdminColors.primary);
      expect(labelColor(), AdminColors.ink);
    });

    testWidgets('잠긴 끔은 지금 그대로(web-outline-strong 테두리 · 체크 없음 · 글자 web-ink)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(child: Center(child: AdminCheckbox(label: '잠긴 끔', value: false, onChanged: null))),
        ),
      );
      final box = find.byKey(const ValueKey('checkbox-box'));

      expect((tester.widget<Container>(box).decoration! as BoxDecoration).border, Border.all(color: AdminColors.outlineStrong, width: 1.5));
      expect(find.descendant(of: box, matching: find.byIcon(LucideIcons.check)), findsNothing);
      expect(styleOf(tester, find.text('잠긴 끔')).color, AdminColors.ink);
    });

    testWidgets('화면 읽기에 체크 상태로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await openDetail(tester);
      await tester.tap(actionButton('조치 완료'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(AdminCheckbox)),
        isSemantics(label: '같은 대상의 열린 신고 2건도 함께 닫기', hasCheckedState: true, isChecked: true, isButton: false, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('채팅 앞뒤 보기(n73XF · p2BSQ)', () {
    FakeReportServer withChat() {
      return messageReport()
        ..chat = [
          chatLine('m1', '안녕하세요'),
          chatLine('m2', '오늘 수업 끝났어요?', fromTarget: true),
          chatLine('m3', '(신고된 메시지) 여기에 신고된 글자가 보여요', fromTarget: true, reported: true),
          chatLine('m4', '그만 말씀해 주세요'),
        ];
    }

    Future<void> view(WidgetTester tester, {String reason = '신고 확인'}) async {
      await tester.tap(actionButton('채팅 앞뒤 보기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: find.byType(TextField)), reason);
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: button('보기')));
      await tester.pumpAndSettle();
    }

    Finder chat() => find.byKey(const ValueKey('chat-dialog'));

    testWidgets('사유 대화상자 "채팅 앞뒤를 볼까요?" · [보기](주) → POST chat-context {reason}', (tester) async {
      final server = await openDetail(tester, server: withChat());
      await tester.tap(actionButton('채팅 앞뒤 보기'));
      await tester.pumpAndSettle();

      expect(find.text('채팅 앞뒤를 볼까요?'), findsOneWidget);
      expect(find.text("신고된 줄 앞뒤 5개씩, 글자만 보여요. 저장되지 않고 작업 기록에 '열람'만 남아요. 사유는 필수예요."), findsOneWidget);
      expect(buttonOf(tester, find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: button('보기'))).variant, AdminButtonVariant.primary);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: find.byType(TextField)), ' 신고 확인 ');
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: button('보기')));
      await tester.pumpAndSettle();

      expect(jsonDecode(server.requests.last.body), {'reason': '신고 확인'});
      expect(find.byKey(const ValueKey('reason-dialog')), findsNothing);
      expect(chat(), findsOneWidget);
    });

    testWidgets('결과: 560 · 안쪽 24 · 제목 20/700 · 목록 web-canvas 모서리 8 안쪽 12 · 말풍선 위 이름표 12 web-muted("신고 대상" / "상대")', (tester) async {
      await openDetail(tester, server: withChat());
      await view(tester);

      expect(tester.getSize(chat()).width, 560);
      expect(find.descendant(of: chat(), matching: find.text('신고된 채팅 앞뒤 보기')), findsOneWidget);
      expect(find.descendant(of: chat(), matching: find.text("신고된 줄 앞뒤 5개씩, 글자만 보여요. 저장되지 않아요. 작업 기록에는 '열람'만 남아요.")), findsOneWidget);
      final list = tester.widget<Container>(find.byKey(const ValueKey('chat-list')));
      expect((list.decoration! as BoxDecoration).color, AdminColors.canvas);
      expect((list.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(8));
      expect(find.descendant(of: chat(), matching: find.text('상대')), findsNWidgets(2));
      expect(find.descendant(of: chat(), matching: find.text('신고 대상')), findsNWidgets(2));
      final label = find.descendant(of: find.byKey(const ValueKey('chat-line-m1')), matching: find.text('상대'));
      expect((styleOf(tester, label).fontSize, styleOf(tester, label).color), (12, AdminColors.muted));
      final bubble = tester.getRect(find.byKey(const ValueKey('chat-bubble-m1')));
      expect(bubble.top - tester.getRect(label).bottom, 4);
      expect(bubble.height, 41);
      expect(tester.getRect(find.byKey(const ValueKey('chat-line-m2'))).top - tester.getRect(find.byKey(const ValueKey('chat-line-m1'))).bottom, 8);
      final normal = tester.widget<Container>(find.byKey(const ValueKey('chat-bubble-m1')));
      expect((normal.decoration! as BoxDecoration).color, AdminColors.surfaceStrong);
      expect((normal.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(14));
      expect(normal.padding, const EdgeInsets.symmetric(horizontal: 14, vertical: 10));
    });

    testWidgets('신고된 줄: web-danger-wash 바탕 · web-danger 1 테두리 · 글자 700 web-danger', (tester) async {
      await openDetail(tester, server: withChat());
      await view(tester);

      final reported = tester.widget<Container>(find.byKey(const ValueKey('chat-bubble-m3')));
      final deco = reported.decoration! as BoxDecoration;
      expect(deco.color, AdminColors.dangerWash);
      expect(deco.border, Border.all(color: AdminColors.danger));
      final text = find.text('(신고된 메시지) 여기에 신고된 글자가 보여요');
      expect((styleOf(tester, text).fontWeight, styleOf(tester, text).color), (FontWeight.w700, AdminColors.danger));
    });

    testWidgets('신고된 줄은 색만이 아니라 화면 읽기에도 "신고된 줄" 로 알린다', (tester) async {
      final handle = tester.ensureSemantics();
      await openDetail(tester, server: withChat());
      await view(tester);

      expect(find.bySemanticsLabel(RegExp('^신고된 줄: ')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('목록이 길면 목록 칸만 스크롤(스크롤바 6 · 썸 web-outline-strong), 대화상자는 화면 90% 안 · [닫기] 오른쪽', (tester) async {
      final server = messageReport()..chat = [for (var i = 0; i < 11; i++) chatLine('m$i', '줄 $i', fromTarget: i.isOdd, reported: i == 5)];
      await openDetail(tester, server: server);
      await view(tester);

      expect(tester.getSize(chat()).height, lessThanOrEqualTo(900 * 0.9));
      final scrollbar = tester.widget<RawScrollbar>(find.descendant(of: chat(), matching: find.byType(RawScrollbar)));
      expect((scrollbar.thickness, scrollbar.thumbColor, scrollbar.trackColor), (6, AdminColors.outlineStrong, AdminColors.outline));
      final close = find.descendant(of: chat(), matching: button('닫기'));
      expect(tester.getRect(close).right, tester.getRect(chat()).right - 24);
      final title = tester.getRect(find.text('신고된 채팅 앞뒤 보기'));
      await tester.drag(find.byKey(const ValueKey('chat-line-m3')), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('신고된 채팅 앞뒤 보기')), title);
      expect(tester.takeException(), isNull);
    });

    testWidgets('사유 → 결과는 같은 대화상자 자리에서 200ms 에 바뀐다(막이 꺼졌다 켜지지 않는다), 동작 줄이기면 바로', (tester) async {
      await openDetail(tester, server: withChat());
      await tester.tap(actionButton('채팅 앞뒤 보기'));
      await tester.pumpAndSettle();
      final reasonRoute = ModalRoute.of(tester.element(find.byKey(const ValueKey('reason-dialog'))));
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: find.byType(TextField)), '확인');
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: button('보기')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(chat(), findsOneWidget);
      expect(ModalRoute.of(tester.element(chat())), same(reasonRoute));
      final switcher = tester.widget<AnimatedSwitcher>(find.byKey(const ValueKey('chat-flow')));
      expect(switcher.duration, const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reason-dialog')), findsNothing);
    });

    testWidgets('동작 줄이기: 사유 → 결과가 움직임 없이 바로 바뀐다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openDetail(tester, server: withChat());
      await view(tester);

      expect(tester.widget<AnimatedSwitcher>(find.byKey(const ValueKey('chat-flow'))).duration, Duration.zero);
      expect(chat(), findsOneWidget);
    });

    testWidgets('닫으면 버린다 — 다시 보려면 사유부터 다시(서버에 두 번 묻는다)', (tester) async {
      final server = await openDetail(tester, server: withChat());
      await view(tester);
      await tester.tap(find.descendant(of: chat(), matching: button('닫기')));
      await tester.pumpAndSettle();
      expect(chat(), findsNothing);

      await view(tester, reason: '다시 확인');
      expect(server.requests.where((r) => r.url.path.endsWith('/chat-context')), hasLength(2));
      expect(chat(), findsOneWidget);
    });

    testWidgets('대화가 지워졌으면 "대화가 지워져 볼 수 없어요" + [닫기]', (tester) async {
      await openDetail(tester, server: messageReport());
      await view(tester);

      expect(find.text('신고된 채팅 앞뒤 보기'), findsOneWidget);
      expect(find.text('대화가 지워져 볼 수 없어요'), findsOneWidget);
      await tester.tap(button('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('대화가 지워져 볼 수 없어요'), findsNothing);
    });

    testWidgets('채팅 보기 실패는 사유 대화상자 안 오류 줄', (tester) async {
      final server = await openDetail(tester, server: withChat());
      server.actionFailure = 500;
      await view(tester);

      expect(chat(), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: find.byType(ErrorRow)), findsOneWidget);
    });
  });

  group('시안에 없던 상태(⑥ · A4_상세_*)', () {
    testWidgets('목록에서 고른 건은 받는 중에도 머리줄(종류 · 배지) + 틀 없이 도는 아이콘 "신고 내용을 불러오고 있어요"', (tester) async {
      final server = messageReport();
      await pumpAdminApp(
        tester,
        auth: FakeAdminAuth(mfa: aal2),
        api: server.api(),
        initialPath: '/reports',
        overrides: [clockProvider.overrideWithValue(() => testNow)],
      );
      server.holdDetail = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('report-row-r1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('메시지 신고'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('report-head')), matching: find.byType(StatusBadge)), findsOneWidget);
      expect(tester.widget<AdminTableEmpty>(find.byType(AdminTableEmpty)).framed, isFalse);
      expect(find.descendant(of: find.byType(AdminTableEmpty), matching: find.byType(AdminLoader)), findsOneWidget);
      expect(find.text('신고 내용을 불러오고 있어요'), findsOneWidget);

      server.holdDetail!.complete();
      await tester.pumpAndSettle();
      expect(find.text('메시지 신고 · 1명 신고'), findsOneWidget);
    });

    testWidgets('못 받음: "신고를 불러오지 못했어요" + 다시 시도', (tester) async {
      final server = messageReport()..detailFailure = 0;
      await openDetail(tester, server: server);

      expect(find.text('신고를 불러오지 못했어요'), findsOneWidget);
      server.detailFailure = null;
      await tester.tap(button('다시 시도'));
      await tester.pumpAndSettle();
      expect(card('actions'), findsOneWidget);
    });

    testWidgets('없는 신고(404)는 "신고를 찾을 수 없어요" + [신고 목록]', (tester) async {
      await openDetail(tester, path: '/reports/nope');
      expect(find.text('신고를 찾을 수 없어요'), findsOneWidget);

      await tester.tap(button('신고 목록'));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/reports');
    });

    testWidgets('꼴이 틀린 번호(..%2Fme)는 보내지도 않고 "신고를 찾을 수 없어요" — 다른 관리자 API 를 부르지 못한다', (tester) async {
      final server = await openDetail(tester, path: '/reports/..%2Fme');

      expect(find.text('신고를 찾을 수 없어요'), findsOneWidget);
      expect(server.requests.map((r) => r.url.path), everyElement('/admin/me'));
    });

    testWidgets('"← 신고 목록" 을 누르면 목록(/reports)', (tester) async {
      await openDetail(tester);

      await tester.tap(find.byKey(const ValueKey('report-back')));
      await tester.pumpAndSettle();

      expect(locationOf(tester), '/reports');
      expect(find.byKey(const ValueKey('report-table')), findsOneWidget);
    });
  });

  group('크기', () {
    testWidgets('1280 폭에서도 넘치지 않는다 — 두 열이 같이 줄어든다', (tester) async {
      await openDetail(tester, server: messageReport(target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00')), size: const Size(1280, 800));

      expect(tester.takeException(), isNull);
      expect(tester.getRect(card('copy')).width, (1280 - 240 - 64 - 24) / 2);
    });

    testWidgets('글자를 키워도(1.3배) 넘치지 않는다 — 단추는 다음 줄로', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = FakeReportServer([reportRow('r1', type: 'poll', target: targetProfile(autoHiddenAt: '2026-10-18T03:00:00+00:00'))]);
      await openDetail(tester, server: server, size: const Size(1280, 800));

      expect(tester.takeException(), isNull);
      expect(actionButton('글 가림'), findsOneWidget);
    });

    testWidgets('동작 줄이기: 대화상자가 움직임 없이 열리고 닫힌다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openDetail(tester);

      await tester.tap(actionButton('정지'));
      await tester.pump();
      expect(ModalRoute.of(tester.element(find.byKey(const ValueKey('reason-dialog'))))!.animation!.value, 1);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('reason-dialog')), matching: button('취소')));
      await tester.pump();
      expect(find.byKey(const ValueKey('reason-dialog')), findsNothing);
    });
  });
}
