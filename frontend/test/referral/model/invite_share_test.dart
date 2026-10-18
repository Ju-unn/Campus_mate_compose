import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카카오 SDK 대신 불린 값을 모은다.
class _FakeKakaoShareClient implements KakaoShareClient {
  _FakeKakaoShareClient({this.configured = true, this.available = true, this.error});

  final bool configured;
  final bool available;
  final Object? error;
  final templateIds = <int>[];
  final templateArgs = <Map<String, String>>[];
  int availabilityChecks = 0;

  @override
  bool isConfigured() => configured;

  @override
  Future<bool> isKakaoTalkSharingAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<void> shareCustom({required int templateId, required Map<String, String> templateArgs}) async {
    if (error case final error?) throw error;
    templateIds.add(templateId);
    this.templateArgs.add(templateArgs);
  }
}

void main() {
  const deviceText = 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.';

  test('공유 글은 19 결정 5 문구다', () {
    expect(inviteShareText('K7QMX2'), deviceText);
  });

  group('카카오톡 공유 카드 먼저, 못 보내면 기기 공유 창(계획서 3-6)', () {
    late List<String> shared;
    late Future<void> Function(String) share;

    setUp(() {
      shared = [];
      share = (text) async => shared.add(text);
    });

    Future<void> shareWith(_FakeKakaoShareClient kakao, {int? templateId = 123}) async {
      final container = ProviderContainer(
        overrides: [
          kakaoShareClientProvider.overrideWithValue(kakao),
          kakaoInviteTemplateIdProvider.overrideWithValue(templateId),
          shareTextProvider.overrideWithValue((text) => share(text)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(shareInviteProvider)('K7QMX2');
    }

    test('번호가 있고 카카오톡이 있으면 그 번호와 {code: 코드} 로 카드를 보내고 기기 공유 창은 띄우지 않는다', () async {
      final kakao = _FakeKakaoShareClient();
      await shareWith(kakao);
      expect(kakao.templateIds, [123]);
      expect(kakao.templateArgs, [
        {'code': 'K7QMX2'},
      ]);
      expect(shared, isEmpty);
    });

    test('카카오톡이 없으면 지금 글 그대로 기기 공유 창', () async {
      final kakao = _FakeKakaoShareClient(available: false);
      await shareWith(kakao);
      expect(kakao.templateIds, isEmpty);
      expect(shared, [deviceText]);
    });

    test('카카오 쪽 오류(템플릿 삭제 · 키 막힘 · 인터넷 · 하루 한도)면 기기 공유 창', () async {
      final kakao = _FakeKakaoShareClient(error: Exception('template not found'));
      await shareWith(kakao);
      expect(shared, [deviceText]);
    });

    test('템플릿 번호가 없으면 카카오를 부르지 않고 기기 공유 창', () async {
      final kakao = _FakeKakaoShareClient();
      await shareWith(kakao, templateId: null);
      expect(kakao.availabilityChecks, 0);
      expect(kakao.templateIds, isEmpty);
      expect(shared, [deviceText]);
    });

    test('카카오 키 없는 빌드(KakaoSdk.init 을 건너뜀)면 카카오를 부르지 않고 기기 공유 창', () async {
      final kakao = _FakeKakaoShareClient(configured: false);
      await shareWith(kakao);
      expect(kakao.availabilityChecks, 0);
      expect(kakao.templateIds, isEmpty);
      expect(shared, [deviceText]);
    });

    test('기기 공유 창도 못 열면 오류를 부른 화면으로 올린다(화면이 안내 토스트를 띄운다)', () async {
      share = (_) async => throw Exception('공유 창 없음');
      await expectLater(shareWith(_FakeKakaoShareClient(available: false)), throwsException);
    });
  });

  group('기본값', () {
    test('템플릿 번호는 이 파일의 상수를 쓴다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(kakaoInviteTemplateIdProvider), kakaoInviteTemplateId);
    });

    test('실제 SDK 층은 네이티브 앱 키가 있어야 카카오를 부른다 — 시험 빌드는 키가 없다', () {
      expect(const SdkKakaoShareClient('').isConfigured(), isFalse);
      expect(const SdkKakaoShareClient('  ').isConfigured(), isFalse);
      expect(const SdkKakaoShareClient('abc').isConfigured(), isTrue);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(kakaoShareClientProvider).isConfigured(), isFalse);
    });
  });
}
