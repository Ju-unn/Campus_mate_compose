import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('6단계 — 화면 · 문구는 사용자 확정본 그대로(pen 섹션 24 vfrto)', () {
    expect([for (final step in appTourSteps) (step.location, step.title, step.body)], [
      (AppRoutes.home, '여기가 캠퍼스메이트의 시작이에요', '오늘의 카드와 학교 소식을 홈에서 한눈에 봐요.'),
      (AppRoutes.home, '프로필부터 채워 보세요', '사진, 소개, 이상형을 채우면 더 잘 맞아요.'),
      (AppRoutes.community, '사람들과 이야기해요', '전체, 인기, 내 질문, 내 투표로 골라 볼 수 있어요.'),
      (AppRoutes.today, '매주 월요일 오전 7시에 열려요', '월요일 아침 7시에 새로운 한 명이 도착해요.'),
      (AppRoutes.today, '하트로 여는 카드는 더 정밀해요', '성향, 관심사, 글, 조건을 비교해 골라 드려요.'),
      (AppRoutes.heartStore, '하트는 무료로도 모아요', '무료로 모으기에서 미션을 인증하면 받아요.'),
    ]);
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

  test('하트 스토어는 오늘 탭 위에 올려(push) 열고, 무료로 모으기가 목록 끝이라 스크롤해 찾는다', () {
    expect([for (final step in appTourSteps) step.push], [false, false, false, false, false, true]);
    expect(appTourSteps[5].scrollAnchor, TourTargetId.heartStoreTop);
    expect(appTourSteps[1].scrollAnchor, TourTargetId.homeHero);
  });

  test('가격 · 비율 · 확률 · 보상 숫자 · "가장 잘 맞는" · "상위 20%" 는 어느 단계에도 없다', () {
    final banned = RegExp(r'가장 잘 맞는|상위|%|확률|\d+\s*(원|하트|개)');
    for (final step in appTourSteps) {
      expect(banned.hasMatch(step.title + step.body), isFalse, reason: step.title);
    }
  });
}
