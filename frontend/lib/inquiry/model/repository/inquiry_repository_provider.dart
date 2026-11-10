import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/inquiry/model/repository/http_inquiry_repository.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 문의하기 화면이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final inquiryRepositoryProvider = Provider<InquiryRepository>((ref) {
  return HttpInquiryRepository(ref.read(apiClientProvider));
});
