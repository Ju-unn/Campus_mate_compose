import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/view/contact_permission_sheets.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_contact_blocks.dart';

/// 16b "추가" · 06-4 버튼 → 8a(pen `KgX8O`) → OS 권한 → 8d(`bWKuJ`) / 거부 → 8a-2(`M9ovbi`).
void main() {
  late FakeDeviceContactSource source;
  late FakeContactBlockRepository repository;
  bool? picked;

  setUp(() {
    source = FakeDeviceContactSource(contacts: const [momContact, siblingContact]);
    repository = FakeContactBlockRepository()..blocks = Success([contactBlockFixture('b1')]);
    picked = null;
  });

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [
      deviceContactSourceProvider.overrideWithValue(source),
      contactBlockRepositoryProvider.overrideWithValue(repository),
      contactNameStoreProvider.overrideWithValue(FakeContactNameStore()),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async => picked = await openContactPicker(context, ref),
              child: const Text('연락처 고르기'),
            ),
          ),
        ),
      ),
      GoRoute(path: AppRoutes.contactPicker, builder: (context, state) => const ContactPickerScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('연락처 고르기'));
    await tester.pumpAndSettle();
  }

  const title8a = '연락처 접근을 허용해 주세요';
  const title8a2 = '연락처 권한이 꺼져 있어요';

  testWidgets('permission already granted goes straight to 8d without 8a', (tester) async {
    source.granted = true;
    await pump(tester);

    await open(tester);

    expect(find.byType(ContactPickerScreen), findsOneWidget);
    expect(find.text(title8a), findsNothing);
    expect(source.requestCount, 0);
  });

  // 설명은 코드 사실 문장이다(2026-10-14 사용자 결정 "연락처 안내 문구 정정"): 서버로는 고른 사람 번호만 가고 해시로만 남는다.
  // '암호화' 는 풀 수 있는 변환이라 쓰지 않는다. pen YPJbz 옛 문구와 다르다(pen 후속).
  testWidgets('first entry shows 8a with the factual privacy copy', (tester) async {
    await pump(tester);

    await open(tester);

    expect(find.text(title8a), findsOneWidget);
    expect(
      find.text(
        '내 연락처에 있는 지인이 카드에 뜨지 않게 하려면 연락처를 읽어야 해요. '
        '고른 분의 전화번호만 원래 번호로 되돌릴 수 없는 형태로 바꿔 서버에 저장해요. '
        '이름과 연락처 목록은 서버로 보내지 않아요.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('암호화'), findsNothing);
    expect(find.widgetWithText(SafetySheetButton, '허용하고 계속'), findsOneWidget);
    expect(find.widgetWithText(SafetySheetButton, '나중에 할게요'), findsOneWidget);
    expect(source.requestCount, 0);
  });

  testWidgets('first entry shows 8a, allow → granted → 8d', (tester) async {
    await pump(tester);
    await open(tester);

    await tester.tap(find.text('허용하고 계속'));
    await tester.pumpAndSettle();

    expect(source.requestCount, 1);
    expect(find.text(title8a), findsNothing);
    expect(find.byType(ContactPickerScreen), findsOneWidget);
  });

  testWidgets('denied permission opens 8a-2 and its button calls openSettings', (tester) async {
    // "다시 묻지 않음" 상태 — OS 창 없이 곧바로 거부가 온다.
    source.grantOnRequest = false;
    await pump(tester);
    await open(tester);

    await tester.tap(find.text('허용하고 계속'));
    await tester.pumpAndSettle();

    expect(find.text(title8a2), findsOneWidget);
    expect(find.text('기기 설정 > CampusMate > 연락처를 켜면 지인 차단을 쓸 수 있어요.'), findsOneWidget);
    expect(find.byType(ContactPickerScreen), findsNothing);

    await tester.tap(find.text('기기 설정 열기'));
    await tester.pumpAndSettle();

    expect(source.openSettingsCount, 1);
    expect(find.text(title8a2), findsNothing);
    expect(picked, isFalse);
  });

  testWidgets('나중에 할게요 opens 8a-2 without asking the OS (DESIGN §9 8a-2)', (tester) async {
    await pump(tester);
    await open(tester);

    await tester.tap(find.text('나중에 할게요'));
    await tester.pumpAndSettle();

    expect(source.requestCount, 0);
    expect(find.text(title8a2), findsOneWidget);
  });

  testWidgets('8a-2 닫기 closes without opening settings', (tester) async {
    source.grantOnRequest = false;
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('허용하고 계속'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(source.openSettingsCount, 0);
    expect(find.text(title8a2), findsNothing);
    expect(find.text('연락처 고르기'), findsOneWidget);
  });

  testWidgets('swiping 8a away asks nothing and opens nothing', (tester) async {
    await pump(tester);
    await open(tester);

    await tester.tapAt(const Offset(180, 40));
    await tester.pumpAndSettle();

    expect(source.requestCount, 0);
    expect(find.text(title8a), findsNothing);
    expect(find.text(title8a2), findsNothing);
  });

  testWidgets('finishing 8d returns true', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('허용하고 계속'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('엄마'));
    await tester.pump();
    await tester.tap(find.text('선택 완료 (1명)'));
    await tester.pumpAndSettle();

    expect(repository.added.single, ['010-1111-2841', '02-123-4567']);
    expect(find.byType(ContactPickerScreen), findsNothing);
    expect(picked, isTrue);
  });

  testWidgets('leaving 8d with back returns false', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('허용하고 계속'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(picked, isFalse);
    expect(find.text('연락처 고르기'), findsOneWidget);
  });

  testWidgets('8a buttons are 52 high, 36 below the description (pen dWBi1 · Lh8kT)', (tester) async {
    await pump(tester);
    await open(tester);

    final description = tester.getRect(find.textContaining('내 연락처에 있는 지인이'));
    final allow = tester.getRect(find.widgetWithText(SafetySheetButton, '허용하고 계속'));
    final later = tester.getRect(find.widgetWithText(SafetySheetButton, '나중에 할게요'));
    expect(allow.height, 52);
    expect(allow.top - description.bottom, 36);
    expect(later.top - allow.bottom, 16);
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    for (final denied in [false, true]) {
      testWidgets('글자 배율 $scale ${denied ? '8a-2' : '8a'} 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        source.grantOnRequest = false;
        await pump(tester, scale: scale);
        await open(tester);
        if (denied) {
          await tester.tap(find.text('허용하고 계속'));
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        final clipped = [
          for (final element in find.byType(RichText).evaluate())
            if (element.renderObject case final RenderParagraph p
                when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
              p.text.toPlainText(),
        ];
        expect(clipped, isEmpty);
      });
    }
  }
}
