import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/model/mock_home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 API 가 생기기 전까지 provider 는 목 저장소를 준다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(homeRepositoryProvider), isA<MockHomeRepository>());
  });

  test('목 저장소는 성공으로 요약 한 벌을 준다', () async {
    final result = await const MockHomeRepository().fetchSummary();

    final summary = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null);
    expect(summary, isNotNull);
    expect(summary!.campuses, isNotEmpty);
    expect(summary.profileCompletionPercent, inInclusiveRange(0, 100));
  });

  test('mosaic-rail 사람 칸은 pen 과 같은 그림 두 장이다(`b9Rask` · `Ch4h6`)', () async {
    final result = await const MockHomeRepository().fetchSummary();

    final images = result.when(onSuccess: (s) => s.presentPeopleImages, onFailure: (_) => <String>[]);
    expect(images, ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png']);
  });

  test('공개 저장소라 목 대학 이름에 실제 학교를 쓰지 않는다', () async {
    // pen 시안(`zOaUW`)의 실제 학교 이름이 그대로 들어오는 걸 막는다.
    const realNames = ['서울대', '연세대', '고려대', '성균관대'];
    final result = await const MockHomeRepository().fetchSummary();

    final campuses = result.when(onSuccess: (s) => s.campuses, onFailure: (_) => <String>[]);
    expect(campuses.where(realNames.contains), isEmpty);
  });
}
