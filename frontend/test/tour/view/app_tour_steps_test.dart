import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/coach_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/store/view/pretendard.dart';

void main() {
  final l10n = AppLocalizationsKo();

  // 줄 수는 실제 글꼴로 잰다 — 시험 기본 글꼴(Ahem)은 글자마다 1em 네모라 한글 폭이 실제와 다르다.
  setUpAll(loadPretendard);

  test('6단계 — 화면 · 문구는 사용자 확정본 그대로(pen 섹션 24 vfrto)', () {
    expect([for (final step in appTourSteps) (step.location, step.copy.title(l10n), step.copy.body(l10n))], [
      // 1단계 설명은 사용자 지시(10-16 "우리 학교 소식 없잖아")로 바꿨다 — pen `O6FER/YoOxK`.
      (AppRoutes.home, '여기가 캠퍼스메이트의 시작이에요', '오늘의 카드와 소중한 인연을 만나봐요.'),
      (AppRoutes.home, '프로필부터 채워 보세요', '사진, 소개, 이상형을 채우면 더 잘 맞아요.'),
      (AppRoutes.community, '사람들과 이야기해요', '전체, 인기, 내 질문, 내 투표로 골라 볼 수 있어요.'),
      // 4단계 제목 · 설명은 요일을 못 박지 않는다(1.0.2 A1) — 서버가 다음 지급 시각을 주면 제목에 그 요일이 들어간다(아래 그룹).
      (AppRoutes.today, '카드는 정해진 요일 오전 7시에 열려요', '그때 새로운 한 명이 도착해요.'),
      (AppRoutes.today, '하트로 여는 카드는 더 정밀해요', '서로의 성향, 관심사, 이상형을 함께 비교해 골라 드려요.'),
      (AppRoutes.heartStore, '하트는 무료로도 모아요', '무료로 모으기에서 미션을 인증하면 받아요.'),
    ]);
  });

  test('단계마다 서로 다른 문구 묶음을 가리키고, 묶음마다 제목 · 설명이 비어 있지 않다', () {
    expect([for (final step in appTourSteps) step.copy], TourCopy.values);
    for (final copy in TourCopy.values) {
      expect(copy.title(l10n), isNotEmpty, reason: copy.name);
      expect(copy.body(l10n), isNotEmpty, reason: copy.name);
    }
  });

  group('4단계 제목 — 서버가 준 다음 지급 시각의 서울 요일 · 시각으로 만든다(1.0.2 A1, 사용자 확정 문구)', () {
    final step = appTourSteps[3];

    // 서울 시각을 UTC 로 만든다 — 기기 시간대에 기대지 않는다. 2026-11-09 가 월요일.
    DateTime seoul(int day, int hour) => DateTime.utc(2026, 11, day, hour).subtract(const Duration(hours: 9));

    test('다음 지급 시각이 있으면 그 요일 · 시각을 말한다', () {
      expect(step.titleFor(l10n, seoul(9, 7)), '다음 카드는 월요일 오전 7시에 열려요');
      expect(step.titleFor(l10n, seoul(12, 7)), '다음 카드는 목요일 오전 7시에 열려요');
    });

    test('서버 값은 UTC 로 오지만 요일 · 시각은 서울 기준이다 — 일요일 22시(UTC)는 월요일 오전 7시', () {
      expect(step.titleFor(l10n, DateTime.utc(2026, 11, 8, 22)), '다음 카드는 월요일 오전 7시에 열려요');
    });

    test('7시가 아니면 그 시각을 그대로 쓴다', () {
      expect(step.titleFor(l10n, seoul(9, 8)), '다음 카드는 월요일 오전 8시에 열려요');
      expect(step.titleFor(l10n, seoul(13, 19)), '다음 카드는 금요일 오후 7시에 열려요');
    });

    test('시각을 모르면(null) 요일을 못 박지 않는 문구다 — 기본 제목 그대로', () {
      expect(step.titleFor(l10n, null), '카드는 정해진 요일 오전 7시에 열려요');
      expect(step.titleFor(l10n, null), step.copy.title(l10n));
    });

    test('값으로 만드는 단계는 4단계 하나뿐이고 나머지는 늘 같은 제목이다', () {
      expect([for (final s in appTourSteps) s.titleAt != null], [false, false, false, true, false, false]);
      for (final other in appTourSteps.where((s) => s.titleAt == null)) {
        expect(other.titleFor(l10n, seoul(9, 7)), other.copy.title(l10n));
      }
    });

    testWidgets('제목은 어느 요일 · 시각이어도 말풍선 글자 칸(280)에서 실제 글꼴 16/700 한 줄이다 — pen 제목 상자 280×22', (tester) async {
      final titles = [
        step.titleFor(l10n, null),
        for (var day = 9; day <= 15; day++)
          for (final hour in [7, 10, 12, 22]) step.titleFor(l10n, seoul(day, hour)),
      ];
      for (final title in titles) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 312,
                child: CoachBubble(
                  number: 4,
                  total: appTourSteps.length,
                  title: title,
                  body: step.copy.body(l10n),
                  isLast: false,
                  onNext: () {},
                  onSkip: () {},
                ),
              ),
            ),
          ),
        );

        expect(tester.getSize(find.text(title)).height, 22, reason: title);
      }
    });
  });

  testWidgets('1단계 설명은 말풍선(폭 312, 글자 칸 280)에서 실제 글꼴 14/400 한 줄이다 — pen `O6FER/YoOxK`', (tester) async {
    final body = appTourSteps.first.copy.body(l10n);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 312,
            child: CoachBubble(
              number: 1,
              total: appTourSteps.length,
              title: appTourSteps.first.copy.title(l10n),
              body: body,
              isLast: false,
              onNext: () {},
              onSkip: () {},
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text(body));
    expect(paragraph.constraints.maxWidth, 280);
    final painter = TextPainter(text: paragraph.text, textDirection: TextDirection.ltr)
      ..layout(maxWidth: paragraph.constraints.maxWidth);
    expect(painter.computeLineMetrics().length, 1);
    painter.dispose();
  });

  test('가리키는 대상과 구멍 반경 — 히어로 34 · 완성도 26 · 탭 줄 16 · 도착 시각 16 · 무료로 모으기 16, 5단계는 구멍 없음', () {
    expect([for (final step in appTourSteps) step.targets], [
      [TourTargetId.homeHero],
      [TourTargetId.homeProfileNudge],
      [TourTargetId.communityTabs],
      // 도착 시각 안내가 없는 상태(카드 목록 등)면 앱바 제목(상단 영역)을 가리킨다.
      [TourTargetId.todayArrival, TourTargetId.todayHeader],
      <TourTargetId>[],
      [TourTargetId.heartStoreFree],
    ]);
    expect([for (final step in appTourSteps.where((s) => s.targets.isNotEmpty)) step.holeRadius], [34, 26, 16, 16, 16]);
    expect(appTourSteps[4].detail, isNotNull);
  });

  test('구멍 띄움 · 선 길이(pen 값 — campus-pen 확인) — 카드 사방 2 · 탭 줄 좌우 8 위 4 아래 6 · 글자 위아래 7 좌우 38 · 섹션 사방 4, 선 52(5단계 32)', () {
    expect([for (final step in appTourSteps) step.holePadding], const [
      EdgeInsets.all(2),
      EdgeInsets.all(2),
      EdgeInsets.fromLTRB(8, 4, 8, 6),
      EdgeInsets.symmetric(vertical: 7, horizontal: 38),
      EdgeInsets.zero,
      EdgeInsets.all(4),
    ]);
    expect([for (final step in appTourSteps) step.lineLength], [52, 52, 52, 52, 32, 52]);
  });

  test('6단계만 대상 위쪽을 앱바 바로 아래 12 로 밀어 올린다(pen campus-pen 10-16) — 나머지는 가운데로', () {
    expect([for (final step in appTourSteps) step.alignTop], [null, null, null, null, null, 12]);
  });

  test('하트 스토어는 오늘 탭 위에 올려(push) 열고, 무료로 모으기가 목록 끝이라 스크롤해 찾는다', () {
    expect([for (final step in appTourSteps) step.push], [false, false, false, false, false, true]);
    expect(appTourSteps[5].scrollAnchor, TourTargetId.heartStoreTop);
    expect(appTourSteps[1].scrollAnchor, TourTargetId.homeHero);
  });

  test('가격 · 비율 · 확률 · 보상 숫자 · "가장 잘 맞는" · "상위 20%" 는 어느 단계에도 없다', () {
    final banned = RegExp(r'가장 잘 맞는|상위|%|확률|\d+\s*(원|하트|개)');
    for (final step in appTourSteps) {
      expect(banned.hasMatch(step.copy.title(l10n) + step.copy.body(l10n)), isFalse, reason: step.copy.title(l10n));
    }
  });
}
