import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// 휴대폰 공유 창(19 계획서 결정 5). 테스트는 받은 글을 모은다. 19 대기 화면과 16i 친구 초대 시트가 같이 쓴다.
final shareTextProvider = Provider<Future<void> Function(String)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// 공유 글(19 결정 5). 하트 숫자 · 스토어 링크는 넣지 않는다.
String inviteShareText(String code) => 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 $code 를 넣어 줘.';
