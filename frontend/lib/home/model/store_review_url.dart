import 'package:campus_mate/core/env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 홈 "리뷰 남기기" 가 열 스토어 리뷰 주소. 시험이 다른 값을 끼울 수 있게 provider 로 둔다 — 빌드 값은 [Env.storeReviewUrl].
final storeReviewUrlProvider = Provider<String>((ref) => Env.storeReviewUrl);
