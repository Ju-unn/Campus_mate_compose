import 'dart:convert';

import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/http_billing_repository.dart';
import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

final String _token = 'a' * 64;

const String _appleToken = '3f2b8c1e-6a4d-4b7e-9c0a-1d2e3f4a5b6c';

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpBillingRepository build(http.Client client) => HttpBillingRepository(ApiClient('https://api.test', client, auth));

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  T? valueOf<T>(Result<T> result) => result.when(onSuccess: (value) => value, onFailure: (_) => null);
  Failure? failureOf<T>(Result<T> result) => result.when(onSuccess: (_) => null, onFailure: (failure) => failure);

  group('GET /billing/status', () {
    test('첫 구매 전 — 계정 표시 64자와 보너스(50 · 100하트 이상)', () async {
      final client = MockClient((request) async {
        expect((request.method, request.url.toString()), ('GET', 'https://api.test/billing/status'));
        expect(request.headers['Authorization'], 'Bearer token-abc');
        return json({
          'account_token': _token,
          'first_purchase_bonus': {'hearts': 50, 'min_product_hearts': 100},
        });
      });

      final status = valueOf(await build(client).fetchStatus())!;

      expect(status.accountToken, _token);
      expect((status.bonus!.hearts, status.bonus!.appliesTo(100), status.bonus!.appliesTo(50)), (50, true, false));
    });

    test('애플 계정 표시(UUID)도 읽는다 — 스토어마다 제 칸을 구매 창에 싣는다', () async {
      final client = MockClient(
        (request) async => json({'account_token': _token, 'apple_account_token': _appleToken, 'first_purchase_bonus': null}),
      );

      final status = valueOf(await build(client).fetchStatus())!;

      expect(
        (status.accountTokenFor(PaymentStore.googlePlay), status.accountTokenFor(PaymentStore.appStore)),
        (_token, _appleToken),
      );
    });

    test('애플 칸이 없는 서버(배포 전)여도 구글 구매는 그대로 — 애플 계정 표시만 null', () async {
      final client = MockClient((request) async => json({'account_token': _token, 'first_purchase_bonus': null}));

      final status = valueOf(await build(client).fetchStatus())!;

      expect((status.accountTokenFor(PaymentStore.googlePlay), status.accountTokenFor(PaymentStore.appStore)), (_token, null));
    });

    test('이미 산 사람 — 보너스 null', () async {
      final client = MockClient((request) async => json({'account_token': _token, 'first_purchase_bonus': null}));

      final status = valueOf(await build(client).fetchStatus())!;

      expect(status.bonus, isNull);
    });

    test('모양이 다르면 알 수 없는 오류다(예외가 Result 밖으로 튀지 않는다)', () async {
      final client = MockClient((request) async => json({'first_purchase_bonus': null}));

      expect(failureOf(await build(client).fetchStatus()), isA<UnknownFailure>());
    });
  });

  group('POST /billing/google/verify', () {
    Future<Result<PurchaseOutcome>> verify(http.Response Function(http.Request) answer) async {
      final client = MockClient((request) async => answer(request));
      return build(client).verifyGoogle('heart_100', 'opaque-token.AbC_123-xyz');
    }

    test('본문은 product_id · purchase_token 둘만 보낸다', () async {
      late Map<String, dynamic> sent;
      await verify((request) {
        expect((request.method, request.url.toString()), ('POST', 'https://api.test/billing/google/verify'));
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'result': 'granted', 'hearts': 100, 'bonus_hearts': 50, 'heart_balance': 150});
      });

      expect(sent, {'product_id': 'heart_100', 'purchase_token': 'opaque-token.AbC_123-xyz'});
    });

    test('200 granted → 새로 받음(보너스 숫자는 서버 값)', () async {
      final result = await verify((_) => json({'result': 'granted', 'hearts': 100, 'bonus_hearts': 50, 'heart_balance': 150}));

      final granted = valueOf(result)! as PurchaseGranted;
      expect((granted.hearts, granted.bonusHearts, granted.isNew), (100, 50, true));
    });

    test('200 already_granted → 이미 받은 결제(isNew false)', () async {
      final result = await verify(
        (_) => json({'result': 'already_granted', 'hearts': 100, 'bonus_hearts': 0, 'heart_balance': 320}),
      );

      expect((valueOf(result)! as PurchaseGranted).isNew, isFalse);
    });

    test('202 pending → 스토어 대기', () async {
      final result = await verify((_) => json({'result': 'pending'}, 202));

      expect(valueOf(result), isA<PurchasePendingAtStore>());
    });

    for (final (status, code) in [
      (409, 'purchase_other_account'),
      (409, 'purchase_token_used'),
      (422, 'purchase_invalid'),
    ]) {
      test('$status $code → ServerRejectedFailure.hasCode', () async {
        final result = await verify((_) => json({'detail': '서버 문구', 'code': code}, status));

        final failure = failureOf(result);
        expect(failure, isA<ServerRejectedFailure>());
        expect((failure! as ServerRejectedFailure).hasCode(code), isTrue);
      });
    }

    test('503 billing_unavailable → ServerUnavailableFailure(다시 보낼 수 있다)', () async {
      final result = await verify((_) => json({'detail': '하트 지급이 늦어지고 있어요', 'code': 'billing_unavailable'}, 503));

      expect(failureOf(result), isA<ServerUnavailableFailure>());
    });

    test('200 인데 result 가 계약 밖이면 알 수 없는 오류(지급으로 보지 않는다)', () async {
      final result = await verify((_) => json({'result': 'token_used'}));

      expect(failureOf(result), isA<UnknownFailure>());
    });
  });

  group('POST /billing/apple/verify', () {
    Future<Result<PurchaseOutcome>> verify(http.Response Function(http.Request) answer) async {
      final client = MockClient((request) async => answer(request));
      return build(client).verifyApple('heart_200', '2000000123456789');
    }

    test('본문은 product_id · transaction_id(StoreKit 거래 번호) 둘만 보낸다', () async {
      late Map<String, dynamic> sent;
      await verify((request) {
        expect((request.method, request.url.toString()), ('POST', 'https://api.test/billing/apple/verify'));
        expect(request.headers['Authorization'], 'Bearer token-abc');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'result': 'granted', 'hearts': 200, 'bonus_hearts': 50, 'heart_balance': 250});
      });

      expect(sent, {'product_id': 'heart_200', 'transaction_id': '2000000123456789'});
    });

    test('200 granted · already_granted — 구글과 같은 모양으로 읽는다', () async {
      final granted = valueOf(
        await verify((_) => json({'result': 'granted', 'hearts': 200, 'bonus_hearts': 50, 'heart_balance': 250})),
      )! as PurchaseGranted;
      final again = valueOf(
        await verify((_) => json({'result': 'already_granted', 'hearts': 200, 'bonus_hearts': 0, 'heart_balance': 250})),
      )! as PurchaseGranted;

      expect((granted.hearts, granted.bonusHearts, granted.isNew, again.isNew), (200, 50, true, false));
    });

    for (final (status, code) in [
      (409, 'purchase_other_account'),
      (409, 'purchase_token_used'),
      (422, 'purchase_invalid'),
      // 애플만 — 환불된 거래.
      (422, 'purchase_revoked'),
    ]) {
      test('$status $code → ServerRejectedFailure.hasCode(구글과 같은 코드)', () async {
        final result = await verify((_) => json({'detail': '서버 문구', 'code': code}, status));

        expect((failureOf(result)! as ServerRejectedFailure).hasCode(code), isTrue);
      });
    }

    for (final code in ['billing_unavailable', 'apple_not_configured']) {
      test('503 $code → ServerUnavailableFailure(지급 지연 — 거래를 끝내지 않고 다시 보낸다)', () async {
        final result = await verify((_) => json({'detail': '하트 지급이 늦어지고 있어요', 'code': code}, 503));

        expect(failureOf(result), isA<ServerUnavailableFailure>());
      });
    }

    test('200 인데 result 가 계약 밖이면 알 수 없는 오류(지급으로 보지 않는다)', () async {
      expect(failureOf(await verify((_) => json({'result': 'pending?'}))), isA<UnknownFailure>());
    });
  });
}
