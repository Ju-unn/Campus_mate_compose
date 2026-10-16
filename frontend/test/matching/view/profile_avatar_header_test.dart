import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/matching/view/profile_avatar_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카드 맨 위 아바타(pen 부품 PhotoSlide · Avatar `xLjFQ`): 288×260 · clip · 모서리 16 · 안쪽 1px hairline · cover · 점 줄 없음,
/// 아래 13(pen `Dtu4T` · `JERLm`). 아바타가 없으면 회색 면 + 사람 아이콘.
void main() {
  Future<void> pump(WidgetTester tester, String? url) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              // 카드 안쪽 폭(360 화면 · 본문 여백 16 · 카드 테두리 1 · 여백 20 → 286).
              child: SizedBox(
                width: 286,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [ProfileAvatarHeader(url: url), const SizedBox(key: Key('next'), height: 10)],
                ),
              ),
            ),
          ),
        ),
      );

  /// 그림 칸 = 테두리를 앞에 덧그린 Container.
  Finder frame() => find.descendant(
        of: find.byType(ProfileAvatarHeader),
        matching: find.byWidgetPredicate((widget) => widget is Container && widget.foregroundDecoration != null),
      );

  testWidgets('아바타가 있으면 칸 폭 전체 × 260 에 cover 로 깔고, 모서리 16 으로 자르고 안쪽 1px hairline 을 덧그린다', (tester) async {
    await pump(tester, 'https://img.test/avatar.png');

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl, 'https://img.test/avatar.png');
    expect(image.fit, BoxFit.cover);
    expect(tester.getSize(frame()), const Size(286, 260));
    final container = tester.widget<Container>(frame());
    expect(container.clipBehavior, Clip.antiAlias);
    expect((container.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(AppRadius.card));
    final border = container.foregroundDecoration! as BoxDecoration;
    expect(border.border, Border.all(color: AppColors.hairline));
    expect(border.borderRadius, BorderRadius.circular(AppRadius.card));
    // 그림이 칸을 다 채운다.
    expect(tester.getSize(find.byType(CachedNetworkImage)), const Size(286, 260));
  });

  testWidgets('아바타가 없으면 그림 대신 회색 면 + 사람 아이콘이다', (tester) async {
    await pump(tester, null);

    expect(find.byType(CachedNetworkImage), findsNothing);
    final container = tester.widget<Container>(frame());
    expect((container.decoration! as BoxDecoration).color, AppColors.surfaceStrong);
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.userRound));
    expect(icon.color, AppColors.disabled);
    expect(tester.getSize(frame()), const Size(286, 260));
  });

  testWidgets('그림 아래 13 뒤에 다음 줄이 온다 · 점 줄이 없다', (tester) async {
    await pump(tester, 'https://img.test/avatar.png');

    expect(tester.getTopLeft(find.byKey(const Key('next'))).dy - tester.getBottomLeft(frame()).dy, 13);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('낭독기에는 "아바타" 그림으로 읽힌다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, null);

    expect(find.bySemanticsLabel('아바타'), findsOneWidget);
    semantics.dispose();
  });
}
