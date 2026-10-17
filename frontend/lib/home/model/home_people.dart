import 'dart:convert';
import 'dart:typed_data';

/// mosaic-rail 사람 칸 그림(`GET /home/people`). 서버가 실제 가입자 아바타를 줄이기만 해(224×280 JPEG, 블러 없음 10-17) base64 로
/// 준다 — 누구인지 알 만한 값(id · 닉네임 · 학교)은 오지 않는다. 여기서 한 번만 풀고, 화면은 흐리지 않고 그대로 그린다.
/// 후보가 모자라면 서버가 빈 목록을 주고, 그때 레일은 기본 그림 칸으로 대신한다.
class HomePeople {
  const HomePeople._(this._images);

  /// 사람이 없다(빈 목록 · 못 받음 · 받는 중).
  static const HomePeople none = HomePeople._([]);

  final List<Uint8List> _images;

  /// 잘못된 항목은 그 항목만 건너뛴다. 같은 그림은 한 번만 둔다 — 한 벌에 같은 얼굴을 되풀이하지 않는다.
  factory HomePeople.fromJson(Object body) {
    final people = (body as Map<String, dynamic>)['people'] as List<dynamic>;
    return HomePeople._([
      for (final encoded in people.toSet()) ?_decode(encoded),
    ]);
  }

  /// base64 글자가 아니거나 비었으면 null.
  static Uint8List? _decode(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  bool get isEmpty => _images.isEmpty;

  /// 사람 칸마다 [toTile] 로 바꾼다(받은 순서).
  List<T> map<T>(T Function(Uint8List image) toTile) => _images.map(toTile).toList();
}
