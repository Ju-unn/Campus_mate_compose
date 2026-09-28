import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/referral/model/http_referral_repository.dart';
import 'package:campus_mate/referral/model/referral_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return HttpReferralRepository(ref.read(apiClientProvider));
});
