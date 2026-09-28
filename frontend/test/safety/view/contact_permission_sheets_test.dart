import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/view/contact_block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_permission_sheets.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_contact_blocks.dart';

/// 16 "연락처 차단" → 8a(pen `KgX8O`) → OS 권한 → 8d(`bWKuJ`) / 거부 → 8a-2(`M9ovbi`) → 16b(`fkjEh`).
void main() {
  late FakeDeviceContactSource source;
  late FakeContactBlockRepository repository;

  setUp(() {
    source = FakeDeviceContactSource(contacts: const [momContact, siblingContact]);
    repository = FakeContactBlockRepository()..blocks = Success([contactBlockFixture('b1')]);
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
              onPressed: () => openContactBlocks(context, ref),
              child: const Text('연락처 차단 열기'),
            ),
          ),
        ),
      ),
      GoRoute(path: AppRoutes.contactBlocks, builder: (context, state) => const ContactBlockListScreen()),
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
    await tester.tap(find.text('연락처 차단 열기'));
    await tester.pumpAndSettle();
  }

  const title8a = '연락처 접근을 허용해 주세요';
  const title8a2 = '연락처 권한이 꺼져 있어요';

  testWidgets('settings row opens 16b directly when permission is already granted', (tester) async {
    source.granted = true;
    await pump(tester);

    await open(tester);

    expect(find.byType(ContactBlockListScreen), findsOneWidget);
    expect(find.text(title8a), findsNothing);
    expect(source.requestCount, 0);
  });

  testWidgets('first entry shows 8a with pen copy', (tester) async {
    await pump(tester);

    await open(tester);

    expect(find.text(title8a), findsOneWidget);
    expect(
      find.text('내 연락처에 있는 지인이 카드에 뜨지 않게 하려면 연락처를 읽어야 해요. 전화번호는 암호화해 대조에만 쓰고 원본은 저장하지 않아요.'),
      findsOneWidget,
    );
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
    expect(find.byType(ContactBlockListScreen), findsNothing);
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
    expect(find.text('연락처 차단 열기'), findsOneWidget);
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

  testWidgets('finishing 8d from settings lands on 16b', (tester) async {
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
    expect(find.byType(ContactBlockListScreen), findsOneWidget);
  });

  testWidgets('leaving 8d with back does not open 16b', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('허용하고 계속'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(ContactBlockListScreen), findsNothing);
    expect(find.text('연락처 차단 열기'), findsOneWidget);
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
