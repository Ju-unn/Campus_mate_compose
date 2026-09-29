import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('공유 글은 19 결정 5 문구다', () {
    expect(inviteShareText('K7QMX2'), 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.');
  });
}
