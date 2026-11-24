import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/viewmodel/community_composer_view_model.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/analytics/fake_analytics_service.dart';
import '../model/repository/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;
  late FakeAnalyticsService analytics;

  ProviderContainer start() {
    final container = ProviderContainer(overrides: [
      communityRepositoryProvider.overrideWithValue(repository),
      analyticsServiceProvider.overrideWithValue(analytics),
    ]);
    addTearDown(container.dispose);
    container.listen(communityComposerViewModelProvider, (_, _) {});
    return container;
  }

  CommunityComposerViewModel viewModel(ProviderContainer c) => c.read(communityComposerViewModelProvider.notifier);
  CommunityComposerUiState stateOf(ProviderContainer c) => c.read(communityComposerViewModelProvider);

  setUp(() {
    repository = FakeCommunityRepository();
    analytics = FakeAnalyticsService();
  });

  test('처음은 투표 · O/X · 카테고리 안 고름이고, 보낼 수 없다', () {
    final container = start();

    final state = stateOf(container);
    expect(state.kind, CommunityKind.poll);
    expect(state.usesDefaultOptions, isTrue);
    expect(state.category, isNull);
    expect(state.canSubmit, isFalse);
  });

  group('보낼 수 있는지 — 앱은 미리 보여 주기만, 기준은 서버', () {
    test('카테고리를 안 고르면 글이 있어도 못 보낸다(필수)', () {
      final container = start();
      viewModel(container)
        ..selectKind(CommunityKind.post)
        ..updateText('면접 팁 있나요');

      expect(stateOf(container).canSubmit, isFalse);
      viewModel(container).selectCategory(CommunityCategory.career);
      expect(stateOf(container).canSubmit, isTrue);
    });

    test('빈 글 · 공백뿐 · 0폭 문자뿐이면 못 보낸다', () {
      final container = start();
      viewModel(container)
        ..selectKind(CommunityKind.post)
        ..selectCategory(CommunityCategory.free);

      for (final blank in ['', '   \n', '​﻿']) {
        viewModel(container).updateText(blank);
        expect(stateOf(container).canSubmit, isFalse, reason: blank.runes.toString());
      }
    });

    test('게시물은 500자까지, 투표 질문은 80자까지(코드 포인트)', () {
      final container = start();
      viewModel(container)
        ..selectCategory(CommunityCategory.free)
        ..selectKind(CommunityKind.post)
        ..updateText('가' * 500);
      expect(stateOf(container).canSubmit, isTrue);

      viewModel(container).updateText('가' * 501);
      expect(stateOf(container).canSubmit, isFalse);

      viewModel(container)
        ..selectKind(CommunityKind.poll)
        ..updateText('가' * 81);
      expect(stateOf(container).canSubmit, isFalse);
      viewModel(container).updateText('가' * 80);
      expect(stateOf(container).canSubmit, isTrue);
    });

    test('직접 적기 투표는 두 보기가 있고(6자 이하) 서로 달라야 한다 — 서버 PollRequest 와 같다', () {
      final container = start();
      viewModel(container)
        ..selectCategory(CommunityCategory.love)
        ..updateText('짜장 vs 짬뽕')
        ..useDefaultOptions(false);
      expect(stateOf(container).canSubmit, isFalse, reason: '보기가 비었다');

      viewModel(container)
        ..updateOptionA('짜장')
        ..updateOptionB('짜장');
      expect(stateOf(container).canSubmit, isFalse, reason: '두 보기가 같다');

      viewModel(container).updateOptionB('일곱글자보기다');
      expect(stateOf(container).canSubmit, isFalse, reason: '6자를 넘었다');

      viewModel(container).updateOptionB(' 짬뽕 ');
      expect(stateOf(container).canSubmit, isTrue);
    });
  });

  group('보내기', () {
    test('게시물은 고른 카테고리와 앞뒤 공백을 뗀 본문을 보내고, 피드를 전체 탭으로 새로 받는다', () async {
      final container = start();
      container.read(communityFeedViewModelProvider);
      viewModel(container)
        ..selectKind(CommunityKind.post)
        ..selectCategory(CommunityCategory.career)
        ..updateText('  면접 팁 있나요\n');

      expect(await viewModel(container).submit(), isTrue);

      expect(repository.createdPosts.single, (category: CommunityCategory.career, body: '면접 팁 있나요'));
      expect(repository.created, isEmpty);
      await pumpEventQueue();
      expect(repository.pageRequests.last.tab, CommunityFeedTab.all);
    });

    test('O/X 투표는 기본 보기(찬성 · 반대)와 카테고리를 POST /community/polls 로 보내고 poll_create 를 남긴다', () async {
      final container = start();
      viewModel(container)
        ..selectCategory(CommunityCategory.love)
        ..updateText(' 깻잎 논쟁 ');

      expect(await viewModel(container).submit(), isTrue);

      expect(repository.created.single,
          (category: CommunityCategory.love, question: '깻잎 논쟁', optionA: '찬성', optionB: '반대'));
      expect(analytics.calls, ['poll_create']);
    });

    test('직접 적기 투표는 앞뒤 공백을 뗀 두 보기를 보낸다', () async {
      final container = start();
      viewModel(container)
        ..selectCategory(CommunityCategory.free)
        ..updateText('뭐 먹지')
        ..useDefaultOptions(false)
        ..updateOptionA(' 짜장 ')
        ..updateOptionB('짬뽕');

      await viewModel(container).submit();

      expect(repository.created.single,
          (category: CommunityCategory.free, question: '뭐 먹지', optionA: '짜장', optionB: '짬뽕'));
    });

    test('게시물은 poll_create 를 남기지 않는다(게시물 이벤트는 표에 없다)', () async {
      final container = start();
      viewModel(container)
        ..selectKind(CommunityKind.post)
        ..selectCategory(CommunityCategory.free)
        ..updateText('안녕');

      await viewModel(container).submit();

      expect(analytics.calls, isEmpty);
    });

    test('보낼 수 없는 상태면 요청하지 않는다', () async {
      final container = start();
      viewModel(container).updateText('카테고리 없음');

      expect(await viewModel(container).submit(), isFalse);

      expect(repository.created, isEmpty);
      expect(repository.createdPosts, isEmpty);
    });

    test('보내는 중에는 다시 눌러도 요청이 한 번이고, 보내는 중 표시가 켜진다', () async {
      final container = start();
      viewModel(container)
        ..selectKind(CommunityKind.post)
        ..selectCategory(CommunityCategory.free)
        ..updateText('안녕');
      final hold = repository.holdCreate = Completer<void>();

      final first = viewModel(container).submit();
      expect(stateOf(container).isSubmitting, isTrue);
      expect(stateOf(container).canSubmit, isFalse);
      expect(await viewModel(container).submit(), isFalse);
      hold.complete();
      await first;

      expect(repository.createdPosts, hasLength(1));
    });

    test('하루 한도(429)면 서버가 준 문구를 그대로 담고 글은 남긴다', () async {
      repository.createResult = const FailureResult(RateLimitedFailure('오늘은 글을 더 올릴 수 없어요'));
      final container = start();
      viewModel(container)
        ..selectKind(CommunityKind.post)
        ..selectCategory(CommunityCategory.free)
        ..updateText('열한 번째 글');

      expect(await viewModel(container).submit(), isFalse);

      final state = stateOf(container);
      expect(state.error, isA<RateLimitedFailure>().having((f) => f.serverMessage, 'serverMessage', '오늘은 글을 더 올릴 수 없어요'));
      expect(state.isSubmitting, isFalse);
      expect(state.text, '열한 번째 글');
    });

    test('다시 고치면 지난 오류는 지운다', () async {
      repository.createResult = const FailureResult(NetworkFailure());
      final container = start();
      viewModel(container)
        ..selectKind(CommunityKind.post)
        ..selectCategory(CommunityCategory.free)
        ..updateText('안녕');
      await viewModel(container).submit();
      expect(stateOf(container).error, isA<NetworkFailure>());

      viewModel(container).updateText('안녕하세요');

      expect(stateOf(container).error, isNull);
    });

    test('보내는 도중 화면이 닫혀 버려져도 늦은 응답이 던지지 않는다', () async {
      final local = ProviderContainer(overrides: [
        communityRepositoryProvider.overrideWithValue(repository),
        analyticsServiceProvider.overrideWithValue(analytics),
      ]);
      final sub = local.listen(communityComposerViewModelProvider, (_, _) {});
      local.read(communityComposerViewModelProvider.notifier)
        ..selectKind(CommunityKind.post)
        ..selectCategory(CommunityCategory.free)
        ..updateText('안녕');
      final hold = repository.holdCreate = Completer<void>();
      final sending = local.read(communityComposerViewModelProvider.notifier).submit();

      sub.close();
      local.dispose();
      hold.complete();

      await expectLater(sending, completion(isTrue)); // 서버는 받았다 — 알릴 화면만 없다
    });
  });
}
