import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/http_billing_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 하트 구매(15e · 18d)가 쓰는 서버 창구. 테스트는 이 provider 를 가짜로 덮어쓴다.
final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return HttpBillingRepository(ref.read(apiClientProvider));
});
