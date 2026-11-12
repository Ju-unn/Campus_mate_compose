import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/chat/view/partner_message_row.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_chat_repository.dart';

/// 상대 말풍선 줄(pen `H9vQHd` Message · Theirs · 프로필 / `C5V6P` Message · Theirs · 이어짐).
void main() {
  const body = '안녕하세요';
  final message = messageFixture(senderId: partnerId, body: body, createdAt: DateTime(2026, 11, 12, 14, 15));
  final bubble = MessageBubble(message: message, isMine: false);

  Future<void> pump(WidgetTester tester, Widget row, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(textScale)),
          // 채팅 목록 본문 여백 16 과 같다.
          child: Scaffold(body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: row)),
        ),
      ),
    );
  }

  Finder face() => find.byType(PartnerFace);
  Finder bubbleBox() => find.ancestor(of: find.text(body), matching: find.byType(Container)).first;

  group('묶음 첫 줄(pen H9vQHd)', () {
    testWidgets('왼쪽에 원형 사진 36(CxCs7), 사이 8, 오른쪽 위 닉네임(LpIpn) → 4 → 말풍선, 위 정렬', (tester) async {
      await pump(tester, PartnerMessageRow.first(nickname: '여우비', photoUrl: null, onOpenProfile: () {}, bubble: bubble));

      final photo = tester.getRect(face());
      expect(photo.size, const Size(36, 36));
      expect(photo.left, 16);
      final name = tester.getRect(find.text('여우비'));
      expect(name.left - photo.right, 8);
      expect(name.top, photo.top);
      expect(tester.getRect(bubbleBox()).top - name.bottom, 4);
      expect(tester.getRect(bubbleBox()).left, name.left);
    });

    testWidgets('닉네임은 12 / 600 / 줄높이 1.4 / ink #222222', (tester) async {
      await pump(tester, PartnerMessageRow.first(nickname: '여우비', photoUrl: null, onOpenProfile: () {}, bubble: bubble));

      final style = tester.widget<Text>(find.text('여우비')).style!;
      expect((style.fontSize, style.fontWeight, style.height, style.color), (12, FontWeight.w600, 1.4, AppColors.ink));
    });

    testWidgets('사진은 원형으로 잘라 cover 로 깐다', (tester) async {
      await pump(
        tester,
        PartnerMessageRow.first(nickname: '여우비', photoUrl: 'https://x/1.jpg', onOpenProfile: () {}, bubble: bubble),
      );

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect((image.imageUrl, image.fit), ('https://x/1.jpg', BoxFit.cover));
      final circle = tester.widget<Container>(
        find.descendant(of: face(), matching: find.byType(Container)).first,
      );
      expect((circle.decoration! as BoxDecoration).shape, BoxShape.circle);
      expect(circle.clipBehavior, Clip.antiAlias);
    });

    testWidgets('사진이 없으면 회색 면 + 사람 아이콘(제목 아바타와 같은 대체)', (tester) async {
      await pump(tester, PartnerMessageRow.first(nickname: '여우비', photoUrl: null, onOpenProfile: () {}, bubble: bubble));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.descendant(of: face(), matching: find.byIcon(AppIcons.userRound)), findsOneWidget);
    });

    testWidgets('사진을 누르면 상대 소개를 연다 — 낭독기는 "여우비 님 프로필 보기" 버튼으로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      var opened = 0;
      await pump(
        tester,
        PartnerMessageRow.first(nickname: '여우비', photoUrl: null, onOpenProfile: () => opened++, bubble: bubble),
      );

      await tester.tap(face());
      expect(opened, 1);
      expect(
        tester.getSemantics(find.bySemanticsLabel('여우비 님 프로필 보기')),
        isSemantics(label: '여우비 님 프로필 보기', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('누를 곳이 없으면(나간 방) 사진은 그림일 뿐 버튼이 아니다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, PartnerMessageRow.first(nickname: '여우비', photoUrl: null, onOpenProfile: null, bubble: bubble));

      await tester.tap(face());
      expect(find.bySemanticsLabel('여우비 님 프로필 보기'), findsNothing);
      handle.dispose();
    });
  });

  testWidgets('이어지는 줄(pen C5V6P)은 사진 · 닉네임 없이 왼쪽 44 를 비운다', (tester) async {
    await pump(tester, PartnerMessageRow.continued(bubble: bubble));

    expect(face(), findsNothing);
    expect(find.text('여우비'), findsNothing);
    expect(tester.getRect(bubbleBox()).left, 16 + 44);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('글자 배율 $scale 에서 긴 글도 남은 폭 안에서 접혀 넘치지 않는다', (tester) async {
      final long = MessageBubble(message: messageFixture(senderId: partnerId, body: '가' * 80), isMine: false);
      await pump(tester, PartnerMessageRow.first(nickname: '여우비', photoUrl: null, onOpenProfile: () {}, bubble: long),
          textScale: scale);

      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.ancestor(of: find.text('가' * 80), matching: find.byType(Container)).first);
      expect(box.right, lessThanOrEqualTo(360 - 16));
      // 말풍선 최대 폭 78% 규칙은 그대로다.
      expect(box.width, lessThanOrEqualTo(360 * 0.78));
    });
  }
}
