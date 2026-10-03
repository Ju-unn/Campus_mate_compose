import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_heart_task_repository.dart';

void main() {
  late FakeHeartTaskRepository repository;
  // 없는 파일이어도 된다 — 위젯 테스트의 가짜 시계에서는 파일을 실제로 읽지 않는다.
  final photo = File('proof.jpg');

  setUp(() => repository = FakeHeartTaskRepository());

  /// 18a 에서 들어온 것처럼 push 한다. 18c 는 글자만 있는 자리 화면.
  Future<GoRouter> pump(
    WidgetTester tester, {
    HeartTaskKind kind = HeartTaskKind.kakaoShare,
    HeartTaskRejectReason? reason,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.heartTasks,
      routes: [
        GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const Text('18a')),
        GoRoute(
          path: '${AppRoutes.heartTaskSubmit}/:task',
          builder: (context, state) => HeartTaskSubmitScreen(kind: kind, rejectReason: reason),
        ),
        GoRoute(path: AppRoutes.heartTaskPending, builder: (context, state) => const Text('18c')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          heartTaskRepositoryProvider.overrideWithValue(repository),
          imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push(heartTaskSubmitLocation(kind, reason)));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(HeartTaskSubmitScreen)))
        .read(heartTaskSubmitViewModelProvider.notifier)
        .pickFromGallery = () async => photo;
    return router;
  }

  testWidgets('18b — 안내 · 업로더 · 꺼진 "제출하기", 반려 알림 · 에브리타임 줄은 없다', (tester) async {
    await pump(tester);

    expect(find.text('인증샷 제출'), findsOneWidget);
    expect(find.text('스크린샷을 첨부하면 확인 후 하트를 드려요'), findsOneWidget);
    expect(find.text('스크린샷 첨부하기'), findsOneWidget);
    expect(find.text('날짜가 보이게 찍어 주세요'), findsNothing);
    expect(find.textContaining('반려 사유'), findsNothing);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(find.text('제출하기'), findsOneWidget);
  });

  testWidgets('에브리타임만 "날짜가 보이게 찍어 주세요" 한 줄이 붙는다(편차 6)', (tester) async {
    await pump(tester, kind: HeartTaskKind.everytimePost);

    expect(find.text('날짜가 보이게 찍어 주세요'), findsOneWidget);
  });

  testWidgets('18b-2 — 사유 알림과 "다시 제출하기", pen 배치 16 · 99 · 138 · 374', (tester) async {
    await pump(tester, reason: HeartTaskRejectReason.dateMissing);
    // 세로 좌표만 본다. 테스트 글꼴은 한글이 Pretendard 보다 넓어 안내(pen `qLG9R` 한 줄 264)가 360 폭에서 두 줄로
    // 접힌다 — 접히지 않게 화면만 넓힌다(home_screen_test 와 같다). 위젯에 말줄임을 달지 않는다(글자 확대 때 잘린다).
    tester.view.physicalSize = const Size(420, 780);
    await tester.pumpAndSettle();

    expect(find.text('반려 사유: 날짜가 안 보여요'), findsOneWidget);
    expect(find.text('다시 찍어 올려 주세요'), findsOneWidget);
    expect(find.text('다시 제출하기'), findsOneWidget);
    // 본문은 앱바(56) 아래에서 시작한다.
    const body = 56.0;
    final alert = find.ancestor(
      of: find.text('반려 사유: 날짜가 안 보여요'),
      matching: find.byWidgetPredicate((widget) => widget is Container && widget.color == AppColors.errorWash),
    );
    expect(tester.getRect(alert).top - body, 16);
    expect(tester.getRect(alert).height, 67);
    expect(tester.getRect(find.text('스크린샷을 첨부하면 확인 후 하트를 드려요')).top - body, 99);
    expect(tester.getRect(find.byKey(heartTaskUploaderKey)).top - body, 138);
    expect(tester.getRect(find.byKey(heartTaskUploaderKey)).height, 220);
    expect(tester.getRect(find.byType(ElevatedButton)).top - body, 374);
  });

  testWidgets('사진을 고르면 버튼이 켜지고, 제출하면 18c 로 바뀌며 뒤로 가면 18a 다', (tester) async {
    final router = await pump(tester);

    await tester.tap(find.byKey(heartTaskUploaderKey));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    await tester.tap(find.text('제출하기'));
    await tester.pumpAndSettle();

    expect(find.text('18c'), findsOneWidget);
    expect(repository.submitted, [(HeartTaskKind.kakaoShare, photo.path)]);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('18a'), findsOneWidget);
  });

  testWidgets('실패하면 버튼 위에 토스트로 알리고 화면에 남는다', (tester) async {
    repository.submitResult = const FailureResult(RateLimitedFailure());
    await pump(tester);

    await tester.tap(find.byKey(heartTaskUploaderKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제출하기'));
    // 토스트 타이머는 프레임을 걸지 않아 pumpAndSettle 이 기다리지 않는다.
    await tester.pumpAndSettle();

    expect(find.text(heartTaskMonthlyLimitMessage), findsOneWidget);
    expect(find.text('18c'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(heartTaskMonthlyLimitMessage), findsNothing);
  });

  testWidgets('업로더 328×220, 안은 3D 업로드 70(y61) · 간격 8 · 글자 렌더 20 muted(pen u7vbr · C1BBE · WmkOO)', (tester) async {
    await pump(tester);

    final uploader = tester.getRect(find.byKey(heartTaskUploaderKey));
    final icon = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.upload);
    final label = find.text('스크린샷 첨부하기');
    expect(uploader.size, const Size(328, 220));
    expect(tester.getSize(icon), const Size(70, 70));
    expect(tester.getRect(icon).top - uploader.top, 61);
    expect(tester.getRect(label).top - tester.getRect(icon).bottom, 8);
    expect(tester.getSize(label).height, 20);
    expect(tester.widget<Text>(label).style?.color, AppColors.muted);
  });

  testWidgets('업로더 잉크는 업로더 자신의 Material 에 그린다(COMMON §4-2)', (tester) async {
    await pump(tester);

    final label = find.text('스크린샷 첨부하기');
    final tile = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    final painter = find.ancestor(of: label, matching: find.byType(Material)).first;
    expect(tester.getSize(painter), tester.getSize(tile));
  });

  testWidgets('글자 2배에서도 넘침 예외가 없고 말줄임으로 잘린 글자도 없다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, kind: HeartTaskKind.everytimePost, reason: HeartTaskRejectReason.notVerified);

    expect(tester.takeException(), isNull);
    // 넘침 예외가 없어도 maxLines 로 조용히 잘릴 수 있다(DESIGN §11.2) — 화면 글자를 전부 본다.
    for (final paragraph in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
      expect(paragraph.didExceedMaxLines, isFalse, reason: paragraph.text.toPlainText());
    }
  });
}
