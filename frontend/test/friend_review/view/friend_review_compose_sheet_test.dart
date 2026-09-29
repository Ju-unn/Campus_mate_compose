import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/model/friend_review_tags.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_friend_review_repository.dart';

const _placeholder = '이 사람을 잘 보여주는 따뜻한 이야기를 적어주세요.';

/// 20b 리뷰 쓰기 시트(pen `NHcsP`, 판 `nIrPW`, 값표 B §1). 태그는 서버 12종 · 최대 3 · 한마디 100자(대장 결정).
void main() {
  late FakeFriendReviewRepository repository;
  bool? result;
  var closed = false;

  setUp(() {
    repository = FakeFriendReviewRepository()..target = Success(reviewTargetFixture(nickname: '햄스터'));
    result = null;
    closed = false;
  });

  /// 빈 화면 위에서 온보딩(PR 4)처럼 [showFriendReviewComposeSheet] 로 연다.
  Future<void> open(WidgetTester tester, {double scale = 1, bool settle = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showFriendReviewComposeSheet(context, 'p2');
                closed = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Finder sheet() => find.byType(FriendReviewComposeSheet);

  Finder chip(String tag) => find.descendant(of: sheet(), matching: find.widgetWithText(TextButton, tag));

  /// 칩의 보이는 모양(자기 Material). 누르는 영역(TextButton 크기)은 이보다 크다.
  Finder chipFace(String tag) => find.descendant(of: chip(tag), matching: find.byType(Material)).first;

  Finder submit() => find.byKey(friendReviewSubmitKey);

  Future<void> tapChip(WidgetTester tester, String tag) async {
    await tester.ensureVisible(chip(tag));
    await tester.tap(chip(tag));
    await tester.pump();
  }

  group('모양(pen NHcsP)', () {
    testWidgets('시트 664 · 위 모서리 24 · 딤 50% · 손잡이 36×4 r999, 제목 · 닫기 없음', (tester) async {
      await open(tester);

      final box = tester.getRect(sheet());
      expect(box, const Rect.fromLTWH(0, 780 - 664, 360, 664));
      final decoration = tester
          .widget<DecoratedBox>(find.descendant(of: sheet(), matching: find.byType(DecoratedBox)).first)
          .decoration as BoxDecoration;
      expect(decoration.color, AppColors.canvas);
      expect(decoration.borderRadius, const BorderRadius.vertical(top: Radius.circular(24)));
      final barrier = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last;
      expect(barrier.color, AppColors.scrim);
      final handle = tester.getRect(find.byKey(friendReviewComposeHandleKey));
      expect(handle.size, const Size(36, 4));
      expect(handle.top - box.top, 12);
      expect(handle.center.dx, 180);
      expect(find.descendant(of: sheet(), matching: find.byType(IconButton)), findsNothing);
    });

    testWidgets('머리(pen eRud0 y32 · 52) — 이니셜 44 primaryWash "햄" 16/700 ink, 이름 17/600, 관계 12/400 muted', (tester) async {
      await open(tester);

      final top = tester.getRect(sheet()).top;
      final initial = find.ancestor(of: find.text('햄'), matching: find.byType(FriendReviewInitial));
      final avatar = tester.getRect(initial);
      expect(avatar.size, const Size(44, 44));
      expect(avatar.topLeft, Offset(16, top + 32 + 4));
      final initialStyle = tester.widget<Text>(find.text('햄')).style!;
      expect((initialStyle.fontSize, initialStyle.fontWeight, initialStyle.color), (16, FontWeight.w700, AppColors.ink));
      final name = tester.getRect(find.text('햄스터'));
      expect(name.left - avatar.right, 10);
      expect(name.height, 26);
      final nameStyle = tester.widget<Text>(find.text('햄스터')).style!;
      expect((nameStyle.fontSize, nameStyle.fontWeight, nameStyle.color), (17, FontWeight.w600, AppColors.ink));
      final relation = find.descendant(of: sheet(), matching: find.text(friendReviewRelationLabel));
      expect(tester.getRect(relation).top - name.bottom, 2);
      final relationStyle = tester.widget<Text>(relation).style!;
      expect((relationStyle.fontSize, relationStyle.color), (12, AppColors.muted));
      expect(repository.targetRequests, ['p2']);
    });

    testWidgets('질문 두 줄 · 칩 12개(서버 순서, 2열 160×40) · 한마디 칸 · "0 / 100" · "리뷰 남기기" 가 pen 자리에 있다', (tester) async {
      await open(tester);

      final top = tester.getRect(sheet()).top;
      final question1 = tester.getRect(find.text('어떤 장점이 있나요?'));
      expect(question1.top - top, 100);
      expect(question1.height, 27);
      final labels = [
        for (final button in tester.widgetList<TextButton>(find.descendant(of: sheet(), matching: find.byType(TextButton))))
          ((button.child! as Text).data!),
      ];
      expect(labels, friendReviewTags);
      final first = tester.getRect(chipFace(friendReviewTags[0]));
      expect(first, Rect.fromLTWH(16, top + 143, 160, 40));
      expect(tester.getRect(chipFace(friendReviewTags[1])).left - first.right, 8);
      expect(tester.getRect(chipFace(friendReviewTags[2])).top - first.bottom, 8);
      await tester.ensureVisible(find.text(_placeholder));
      await tester.pumpAndSettle();
      final question2 = tester.getRect(find.text('한마디를 남겨주세요'));
      final lastChip = tester.getRect(chipFace(friendReviewTags.last));
      expect(question2.top - lastChip.bottom, 16);
      final box = tester.getRect(find.byKey(friendReviewCommentBoxKey));
      expect(box.top - question2.bottom, 16);
      expect(box.size, const Size(328, 104));
      expect(tester.getRect(find.text('0 / 100')).bottom, box.bottom - 12);
      expect(tester.getRect(find.text(_placeholder)).topLeft - box.topLeft, const Offset(12, 12));
      final button = tester.getRect(submit());
      expect(button, Rect.fromLTWH(16, 780 - 24 - 52, 328, 52));
      final label = tester.widget<Text>(find.text('리뷰 남기기')).style!;
      expect((label.fontSize, label.fontWeight), (18, FontWeight.w700));
    });

    testWidgets('한마디 칸(pen h3SkMd) — surfaceSoft r8 · outline 1, placeholder 14 muted, 카운터 12 muted', (tester) async {
      await open(tester);

      final box = tester.widget<Container>(find.byKey(friendReviewCommentBoxKey));
      expect((box.decoration! as BoxDecoration).color, AppColors.surfaceSoft);
      expect((box.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(8));
      expect(((box.foregroundDecoration! as BoxDecoration).border! as Border).top.color, AppColors.outline);
      final counter = tester.widget<Text>(find.text('0 / 100')).style!;
      expect((counter.fontSize, counter.color), (12, AppColors.muted));
    });
  });

  group('태그', () {
    testWidgets('안 고른 칩은 흰 바탕 · hairline · 14/600 body, 고르면 primaryWash · primary 테두리 · primaryText', (tester) async {
      await open(tester);
      const tag = '배려가 깊어요';

      ButtonStyle style() => tester.widget<TextButton>(chip(tag)).style!;
      Color? background() => style().backgroundColor!.resolve({});
      expect(background(), AppColors.canvas);
      expect(style().side!.resolve({})!.color, AppColors.hairline);
      expect(style().foregroundColor!.resolve({}), AppColors.body);
      final text = style().textStyle!.resolve({})!;
      expect((text.fontSize, text.fontWeight), (14, FontWeight.w600));

      await tapChip(tester, tag);

      expect(background(), AppColors.primaryWash);
      expect(style().side!.resolve({})!.color, AppColors.primary);
      expect(style().foregroundColor!.resolve({}), AppColors.primaryText);
    });

    testWidgets('보이는 칩은 40, 누르는 영역은 44 이상 · 눌림 효과는 칩 자신의 모양 안(§4-2)', (tester) async {
      await open(tester);

      for (final tag in [friendReviewTags.first, friendReviewTags.last]) {
        await tester.ensureVisible(chip(tag));
        expect(tester.getSize(chipFace(tag)), const Size(160, 40), reason: tag);
        expect(tester.getSize(chip(tag)).height, greaterThanOrEqualTo(44), reason: tag);
        final ink = find.descendant(of: chip(tag), matching: find.byType(InkWell));
        expect(tester.getSize(find.ancestor(of: ink, matching: find.byType(Material)).first), const Size(160, 40));
      }
    });

    testWidgets('태그 0개면 버튼이 꺼져 있고(primaryDisabled · disabled 글자), 하나 고르면 켜진다', (tester) async {
      await open(tester);

      Material face() => tester.widget<Material>(submit());
      expect(face().color, AppColors.primaryDisabled);
      expect(tester.widget<Text>(find.text('리뷰 남기기')).style!.color, AppColors.disabled);
      await tester.tap(submit());
      await tester.pump();
      expect(repository.creates, isEmpty);

      await tapChip(tester, '성실해요');

      expect(face().color, AppColors.primary);
      expect(tester.widget<Text>(find.text('리뷰 남기기')).style!.color, AppColors.onPrimary);
    });

    testWidgets('세 개까지 — 네 번째 칩은 눌러도 안 골라진다', (tester) async {
      await open(tester);

      for (final tag in friendReviewTags.take(4)) {
        await tapChip(tester, tag);
      }

      Color? background(String tag) => tester.widget<TextButton>(chip(tag)).style!.backgroundColor!.resolve({});
      expect([for (final tag in friendReviewTags.take(4)) background(tag)],
          [AppColors.primaryWash, AppColors.primaryWash, AppColors.primaryWash, AppColors.canvas]);
    });
  });

  group('한마디', () {
    testWidgets('100자 넘게 못 치고 카운터가 따라간다', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), '가' * 120);
      await tester.pump();

      expect(find.text('100 / 100'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '가' * 100);
    });
  });

  group('보내기', () {
    testWidgets('보내는 중에는 버튼 안에 도는 표시, 한 번 더 눌러도 한 번만 보낸다', (tester) async {
      repository.holdCreate = Completer<void>();
      await open(tester);
      await tapChip(tester, '성실해요');

      await tester.tap(submit());
      await tester.pump();

      expect(find.descendant(of: submit(), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text('리뷰 남기기'), findsNothing);
      await tester.tap(submit());
      await tester.pump();
      expect(repository.creates, hasLength(1));
      repository.holdCreate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('보내는 중에 닫고, 닫히는 동안 응답이 와도 밑 화면은 그대로다', (tester) async {
      repository.holdCreate = Completer<void>();
      await open(tester);
      await tapChip(tester, '성실해요');
      await tester.tap(submit());
      await tester.pump();

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      repository.holdCreate!.complete();
      await tester.pumpAndSettle();

      expect(sheet(), findsNothing);
      expect(find.text('열기'), findsOneWidget);
    });

    testWidgets('남기면 고른 순서 태그 · 한마디를 보내고 시트를 닫은 뒤 "리뷰를 남겼어요", 결과 true', (tester) async {
      await open(tester);
      await tapChip(tester, '유머 감각이 좋아요');
      await tapChip(tester, '약속을 잘 지켜요');
      await tester.enterText(find.byType(TextField), '같이 있으면 편해요');

      await tester.tap(submit());
      await tester.pumpAndSettle();

      final sent = repository.creates.single;
      expect(sent.revieweeId, 'p2');
      expect(sent.tags, ['유머 감각이 좋아요', '약속을 잘 지켜요']);
      expect(sent.comment, '같이 있으면 편해요');
      expect(sheet(), findsNothing);
      expect((closed, result), (true, true));
      expect(find.widgetWithText(AppToast, '리뷰를 남겼어요'), findsOneWidget);
    });

    testWidgets('보낼 때 409 면 시트 안에 "이미 리뷰를 남겼어요" 토스트, 시트는 그대로', (tester) async {
      repository.createResult = const FailureResult(ServerRejectedFailure('이미 리뷰를 남겼어요'));
      await open(tester);
      await tapChip(tester, '성실해요');

      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(sheet(), findsOneWidget);
      expect(closed, isFalse);
      // 시트가 화면 아래를 덮으니 시트 안에 띄워야 보인다.
      expect(find.descendant(of: sheet(), matching: find.widgetWithText(AppToast, '이미 리뷰를 남겼어요')), findsOneWidget);
      expect(find.widgetWithText(AppToast, '이미 리뷰를 남겼어요'), findsOneWidget);
    });

    testWidgets('그 밖의 실패도 시트 안 토스트 — 다시 누를 수 있다', (tester) async {
      repository.createResult = const FailureResult(NetworkFailure());
      await open(tester);
      await tapChip(tester, '성실해요');

      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.descendant(of: sheet(), matching: find.widgetWithText(AppToast, '네트워크 연결을 확인해 주세요')), findsOneWidget);
      expect(tester.widget<Material>(submit()).color, AppColors.primary);
    });
  });

  group('열 때', () {
    testWidgets('읽는 동안은 시트 가운데 도는 표시만', (tester) async {
      repository.holdTarget = Completer<void>();
      await open(tester, settle: false);

      expect(find.descendant(of: sheet(), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text('어떤 장점이 있나요?'), findsNothing);
      repository.holdTarget!.complete();
      await tester.pumpAndSettle();
      expect(find.text('어떤 장점이 있나요?'), findsOneWidget);
    });

    testWidgets('이미 썼으면(409) "이미 리뷰를 남겼어요" 토스트 뒤 닫힌다, 결과 null', (tester) async {
      repository.target = const FailureResult(ServerRejectedFailure('이미 리뷰를 남겼어요'));
      await open(tester);

      expect(sheet(), findsNothing);
      expect((closed, result), (true, null));
      expect(find.widgetWithText(AppToast, '이미 리뷰를 남겼어요'), findsOneWidget);
    });

    testWidgets('읽기에 실패하면 문구 토스트 뒤 닫힌다', (tester) async {
      repository.target = const FailureResult(NetworkFailure());
      await open(tester);

      expect(sheet(), findsNothing);
      expect(closed, isTrue);
      expect(find.widgetWithText(AppToast, '네트워크 연결을 확인해 주세요'), findsOneWidget);
    });
  });

  group('넘침', () {
    testWidgets('12종이 664 에 다 안 들어가도 넘치지 않고 가운데만 스크롤 — 버튼은 바닥 그대로', (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      final before = tester.getRect(submit());
      await tester.drag(find.text('어떤 장점이 있나요?'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getRect(submit()), before);
      expect(tester.getRect(find.byKey(friendReviewCommentBoxKey)).bottom, lessThanOrEqualTo(before.top - 16));
    });

    testWidgets('키보드가 올라와도 넘치지 않고 버튼은 키보드 위 24', (tester) async {
      await open(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);

      await tester.showKeyboard(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getRect(submit()).bottom, 780 - 300 - 24);
    });

    // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        await open(tester, scale: scale);

        // 띄어쓰기 없는 태그("긍정적이에요")는 좁으면 글자 단위로 줄을 바꾼다 — 폭 검사에서만 뺀다(높이는 본다).
        List<String> clipped() => [
              for (final element in find.descendant(of: sheet(), matching: find.byType(RichText)).evaluate())
                if (element.renderObject case final RenderParagraph p
                    when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                        (!friendReviewTags.contains(p.text.toPlainText()) &&
                            p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
                  p.text.toPlainText(),
            ];
        expect(tester.takeException(), isNull);
        final seen = clipped();
        await tester.ensureVisible(find.byKey(friendReviewCommentBoxKey));
        await tester.pumpAndSettle();
        seen.addAll(clipped());
        expect(seen.toSet(), isEmpty);
      });
    }
  });
}
