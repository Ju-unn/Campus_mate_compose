/// `1.0.10` 처럼 숫자.숫자.숫자 로 된 앱 버전. 글자로 견주면 `1.0.9 > 1.0.10` 이 되므로 숫자 세 칸으로 견준다.
///
/// 빌드 번호(`+19`)나 `-beta` 같은 꼬리는 받지 않는다 — 모양이 다르면 [tryParse] 가 null 이고,
/// 부르는 쪽은 null 을 "견줄 수 없음 = 막지 않음" 으로 다룬다(강제 업데이트가 잘못된 값 하나로 앱을 잠그지 않게).
final class AppVersion {
  const AppVersion._(this._parts);

  /// major · minor · patch 순서의 세 숫자.
  final List<int> _parts;

  static final RegExp _format = RegExp(r'^\d+\.\d+\.\d+$');

  /// [text] 가 숫자.숫자.숫자 가 아니거나 숫자가 너무 커서 읽을 수 없으면 null.
  static AppVersion? tryParse(String text) {
    if (!_format.hasMatch(text)) return null;
    final parts = text.split('.').map(int.tryParse).toList();
    return parts.contains(null) ? null : AppVersion._(parts.cast<int>());
  }

  /// 내가 [other] 보다 낮은 버전이면 true. 같으면 false.
  bool isOlderThan(AppVersion other) => _compareTo(other) < 0;

  /// 앞자리부터 처음 다른 칸의 크기 차이(음수 = 내가 낮음, 0 = 같음).
  int _compareTo(AppVersion other) => Iterable<int>.generate(_parts.length)
      .map((index) => _parts[index].compareTo(other._parts[index]))
      .firstWhere((difference) => difference != 0, orElse: () => 0);

  @override
  bool operator ==(Object other) => other is AppVersion && _compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(_parts);

  @override
  String toString() => _parts.join('.');
}
