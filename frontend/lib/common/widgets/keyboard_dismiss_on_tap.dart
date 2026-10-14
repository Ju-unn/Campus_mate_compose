import 'package:flutter/widgets.dart';

/// 입력칸 밖 빈 곳을 누르면 키보드를 내린다(2026-10-14 사용자 피드백 9). `MaterialApp.builder` 에서 앱 전체를 한 번 감싼다.
///
/// 휴대폰의 Flutter 기본은 바깥을 눌러도 포커스를 놓지 않는다(`EditableText` 의 바깥 탭 동작은 데스크톱 · 웹만).
/// 여러 줄 칸(자기소개 · 신고 메모 · 채팅 등)은 '완료' 키 자리가 줄 바꿈이고, 아이폰 숫자 키보드(출생연도 · 키 · 인증 코드)는
/// '완료' 키가 아예 없어 내릴 길이 없었다. 한 줄 칸의 '완료' 는 원래 키보드를 내린다(Flutter 기본, `onEditingComplete` 미사용).
///
/// [GestureDetector] 라서 탭 경합에서 안쪽이 이긴다 — 버튼 · 다른 입력칸 · 목록 줄을 누르면 그쪽만 눌리고 키보드는 그대로다
/// (채팅 "보내기" 뒤에도 이어서 친다, 칸을 옮겨도 키보드가 깜빡이지 않는다). 아무도 안 받는 빈 곳의 탭만 여기로 온다.
/// ponytail: 끌어서 내리기(`keyboardDismissBehavior.onDrag`)는 앱 전체에 걸지 않았다 — 여러 줄 칸 안을 끌어 글을 올려도
/// 바깥 목록이 그 끌기를 받아 키보드를 내린다. 필요한 화면만 따로 켠다(04-1 기본 정보처럼).
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // 화면 읽기에 "앱 전체를 누르는 버튼" 이 생기면 안 된다.
      excludeFromSemantics: true,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
