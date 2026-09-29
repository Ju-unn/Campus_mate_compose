import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 15-4 가 읽는 "남이 보는 내 카드". autoDispose — 열 때마다 새로 읽어 15-5 에서 고친 값이 바로 보인다.
/// 실패도 [Result] 그대로 돌려준다([myProfileProvider] 와 같은 이유 — 던지면 Riverpod 3 가 재시도 타이머를 건다).
final myCardPreviewProvider = FutureProvider.autoDispose<Result<CardDetail>>((ref) {
  return ref.watch(meRepositoryProvider).fetchCardPreview();
});
