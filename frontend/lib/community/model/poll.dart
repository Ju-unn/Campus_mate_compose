/// 선택지 기본 라벨. 둘 다 이 값이면 카드가 글자 대신 O·X 아이콘을 그린다(DESIGN §8.11).
const String defaultOptionA = '찬성';
const String defaultOptionB = '반대';

/// 서버 `QUESTION_MAX_LENGTH` · `OPTION_MAX_LENGTH`, DB check 와 같은 값이다.
const int pollQuestionMaxLength = 80;
const int pollOptionMaxLength = 6;

enum PollChoice { a, b }

/// 커뮤니티 질문 하나. **작성자가 누구인지는 모른다** — 서버가 [isMine] 만 준다.
class Poll {
  const Poll({
    required this.id,
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.createdAt,
    required this.aCount,
    required this.bCount,
    this.myChoice,
    this.isMine = false,
  });

  final String id;
  final String question;
  final String optionA;
  final String optionB;
  final DateTime createdAt;
  final int aCount;
  final int bCount;
  final PollChoice? myChoice;
  final bool isMine;

  int get total => aCount + bCount;

  /// 반올림한 A 쪽 %. B 쪽은 100 에서 빼서 두 수의 합이 늘 100 이다("찬성 62% · 반대 38%").
  int get aPercent => total == 0 ? 0 : (aCount * 100 / total).round();
  int get bPercent => total == 0 ? 0 : 100 - aPercent;

  bool get usesDefaultLabels => optionA == defaultOptionA && optionB == defaultOptionB;

  factory Poll.fromJson(Map<String, dynamic> json) {
    return Poll(
      id: json['id'] as String,
      question: json['question'] as String,
      optionA: json['option_a_label'] as String,
      optionB: json['option_b_label'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      aCount: json['a_count'] as int,
      bCount: json['b_count'] as int,
      myChoice: switch (json['my_choice']) {
        'a' => PollChoice.a,
        'b' => PollChoice.b,
        _ => null,
      },
      isMine: json['is_mine'] as bool,
    );
  }
}
