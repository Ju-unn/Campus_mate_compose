/// MBTI 극 규칙 — 축마다 하나만 고른다. 04-1 "내 MBTI"(온보딩)와 15-6 "내 MBTI"(수정)가 같이 쓴다.
abstract final class MbtiPoles {
  /// 네 축(E/I · N/S · T/F · J/P). 이 순서가 네 글자 코드의 순서다.
  static const List<List<String>> axes = [
    ['E', 'I'],
    ['N', 'S'],
    ['T', 'F'],
    ['J', 'P'],
  ];

  /// [pole] 을 누른 결과. 같은 축의 다른 극은 꺼지고, 이미 켜진 극을 다시 누르면 그 축이 빈다.
  static Set<String> toggle(Set<String> poles, String pole) {
    final axis = axes.firstWhere((axis) => axis.contains(pole));
    final next = {...poles}..removeAll(axis);
    if (!poles.contains(pole)) {
      next.add(pole);
    }
    return next;
  }

  static bool isComplete(Set<String> poles) => axes.every((axis) => axis.any(poles.contains));

  /// 네 축을 모두 골랐을 때만 네 글자 코드(서버 `[EI][NS][TF][JP]`), 아니면 null.
  static String? code(Set<String> poles) {
    if (!isComplete(poles)) {
      return null;
    }
    return [for (final axis in axes) axis.firstWhere(poles.contains)].join();
  }

  /// 서버 코드를 극 집합으로 푼다. null(선택 안 함)은 빈 집합.
  static Set<String> fromCode(String? code) => {...?code?.split('')};
}
