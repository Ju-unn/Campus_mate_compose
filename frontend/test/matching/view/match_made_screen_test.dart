import 'package:campus_mate/matching/view/match_made_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('상대 닉네임을 넣은 두 줄 서브텍스트를 보여준다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
    );

    expect(find.text('매칭됐어요!'), findsOneWidget);
    expect(find.text('토끼 님도 수락했어요.\n대화를 시작해 보세요.'), findsOneWidget);
    expect(find.text('나중에 확인하기'), findsOneWidget);
  });
}
