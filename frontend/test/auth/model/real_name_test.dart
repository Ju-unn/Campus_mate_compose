import 'package:campus_mate/auth/model/real_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 문자열이면 null', () {
    expect(RealName.tryParse('   '), isNull);
  });

  test('앞뒤 공백을 잘라낸다', () {
    expect(RealName.tryParse(' 김가나 ')!.toRequestValue(), '김가나');
  });

  test('30자를 넘으면 null', () {
    expect(RealName.tryParse('가' * 31), isNull);
  });

  test('1자면 null', () {
    expect(RealName.tryParse('김'), isNull);
  });

  test('2자면 통과', () {
    expect(RealName.tryParse('김가')!.toRequestValue(), '김가');
  });

  test('한글 완성형·영문·띄어쓰기는 통과한다', () {
    // 외국인 이름은 "Jun seok" 처럼 띄어 쓴다(2026-09-24 사용자 결정).
    for (final name in ['홍길동', 'Jun seok', '김 민수']) {
      expect(RealName.tryParse(name)?.toRequestValue(), name, reason: name);
    }
  });

  test('숫자·기호·자모는 막는다', () {
    // 학생증에 적힌 이름과 대조하는 값이라, 이름에 없는 글자가 섞이면 대조가 어긋난다.
    for (final name in ['11', '!!', 'Mary-Jane', "O'Brien", 'ㄱㄴ', '홍길동1']) {
      expect(RealName.tryParse(name), isNull, reason: name);
    }
  });

  test('글자 규칙만 보는 검사는 길이가 모자란 입력을 잘못됐다고 하지 않는다', () {
    // 두 글자를 채우기 전에 "이름은 한글이나 영문으로만" 안내가 뜨면 입력 중에 계속 깜빡인다.
    expect(RealName.hasDisallowedCharacter('김'), isFalse);
    expect(RealName.hasDisallowedCharacter(''), isFalse);
    expect(RealName.hasDisallowedCharacter('김1'), isTrue);
  });
}
