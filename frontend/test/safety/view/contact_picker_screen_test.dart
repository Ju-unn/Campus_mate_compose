import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/contact_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_contact_blocks.dart';

/// 8d 차단할 연락처 선택(pen `bWKuJ` — 검색 `ARlR7`, 목록 `rpkaB`, 하단 `bzBZZ`, 버튼 `k4MqlT`).
void main() {
  late FakeDeviceContactSource source;
  late FakeContactBlockRepository repository;
  late FakeContactNameStore nameStore;
  bool? popped;

  setUp(() {
    source = FakeDeviceContactSource(granted: true, contacts: const [momContact, siblingContact]);
    repository = FakeContactBlockRepository();
    nameStore = FakeContactNameStore();
    popped = null;
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
      contactNameStoreProvider.overrideWithValue(nameStore),
    ]);
    addTearDown(container.dispose);
    // 8d 는 push 로 열리고 결과(true = 차단함)를 돌려준다 — 여는 쪽을 두고 그 결과를 받는다.
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () async => popped = await context.push<bool>(AppRoutes.contactPicker),
            child: const Text('열기'),
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
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Finder cta() => find.byType(AppButton);

  testWidgets('app bar title and search placeholder (pen E5UH9 · WFqyo)', (tester) async {
    await pump(tester);

    expect(find.text('차단할 연락처 선택'), findsOneWidget);
    expect(find.text('이름 검색'), findsOneWidget);
    expect(find.byIcon(AppIcons.search), findsOneWidget);
  });

  testWidgets('rows show name and the first number masked', (tester) async {
    await pump(tester);

    expect(find.text('엄마'), findsOneWidget);
    // 번호는 하이픈 뒤마다 조각으로 나눠 그린다(ContactRow) — 읽어 주는 이름으로 찾는다.
    expect(maskedNumber('010-****-2841'), findsOneWidget);
    expect(find.text('동생'), findsOneWidget);
    expect(maskedNumber('010-****-7710'), findsOneWidget);
    expect(find.byType(ContactRow), findsNWidgets(2));
  });

  testWidgets('8d CTA reads 선택 완료 (N명) and is disabled at 0', (tester) async {
    await pump(tester);

    expect(find.text('선택 완료 (0명)'), findsOneWidget);
    expect(tester.widget<AppButton>(cta()).onPressed, isNull);

    await tester.tap(find.text('엄마'));
    await tester.pump();
    await tester.tap(find.text('동생'));
    await tester.pump();

    expect(find.text('선택 완료 (2명)'), findsOneWidget);
    expect(tester.widget<AppButton>(cta()).onPressed, isNotNull);
  });

  testWidgets('8d shows the fixed encryption line at the bottom', (tester) async {
    await pump(tester);

    final notice = tester.getRect(find.text('번호는 암호화해 대조에만 쓰고 원본은 저장하지 않아요.'));
    final button = tester.getRect(cta());
    // pen bzBZZ 여백 [16,24,28,24], 간격 8 — 안내 → 8 → 버튼 → 28 → 화면 끝.
    expect(button.top - notice.bottom, 8);
    expect(780 - button.bottom, 28);
    expect(button.height, 52); // HE8FZ 2026-10-01 개편
    expect(button.left, 24);
    expect(button.width, 312);
    final noticeText = tester.widget<Text>(find.text('번호는 암호화해 대조에만 쓰고 원본은 저장하지 않아요.'));
    expect(noticeText.style?.fontSize, 12);
    expect(noticeText.style?.color, AppColors.muted);
  });

  testWidgets('search narrows the list by name and keeps selection', (tester) async {
    await pump(tester);
    await tester.tap(find.text('엄마'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '동');
    await tester.pump();

    expect(find.text('엄마'), findsNothing);
    expect(find.text('동생'), findsOneWidget);
    expect(find.text('선택 완료 (1명)'), findsOneWidget);
  });

  testWidgets('search field is 44 high under the app bar, list starts 12 below (pen ARlR7 · rpkaB)', (tester) async {
    await pump(tester);

    final field = tester.getRect(find.byType(TextField));
    expect(field.top, 56);
    expect(field.height, 44);
    expect(field.left, 24);
    expect(field.width, 312);
    // pen 여백 [0,12] · 간격 8 — 돋보기는 왼쪽 12, 돋보기 오른쪽 끝에서 글자까지 8.
    final icon = tester.getRect(find.byIcon(AppIcons.search));
    expect(icon.left - field.left, 12);
    expect(tester.getRect(find.text('이름 검색')).left - icon.right, 8);
    final firstRow = tester.getRect(find.byType(ContactRow).first);
    expect(firstRow.top - field.bottom, 12);
    expect(firstRow.left, 24);
    expect(firstRow.width, 312);
  });

  testWidgets('submit closes 8d with true', (tester) async {
    await pump(tester);
    await tester.tap(find.text('동생'));
    await tester.pump();

    await tester.tap(find.text('선택 완료 (1명)'));
    await tester.pumpAndSettle();

    expect(find.byType(ContactPickerScreen), findsNothing);
    expect(popped, isTrue);
    expect(nameStore.labels.values.single.name, '동생');
  });

  testWidgets('submit failure stays with a red line (pen 에 없는 상태)', (tester) async {
    repository.addResult = const FailureResult(NetworkFailure());
    await pump(tester);
    await tester.tap(find.text('동생'));
    await tester.pump();

    await tester.tap(find.text('선택 완료 (1명)'));
    await tester.pumpAndSettle();

    expect(find.byType(ContactPickerScreen), findsOneWidget);
    final message = tester.widget<Text>(find.text('네트워크 연결을 확인해 주세요'));
    expect(message.style?.color, AppColors.error);
  });

  testWidgets('only landline numbers shows the mobile-only message', (tester) async {
    repository.addResult = const Success([null]);
    source.contacts = const [DeviceContact(id: 'c-office', name: '사무실', numbers: ['02-123-4567'])];
    await pump(tester);
    await tester.tap(find.text('사무실'));
    await tester.pump();

    await tester.tap(find.text('선택 완료 (1명)'));
    await tester.pumpAndSettle();

    expect(find.text('휴대전화 번호가 있는 연락처만 차단할 수 있어요'), findsOneWidget);
    expect(find.byType(ContactPickerScreen), findsOneWidget);
  });

  testWidgets('rows ink stays inside the list when scrolled (COMMON §4-2)', (tester) async {
    source.contacts = [
      for (var i = 0; i < 20; i++) DeviceContact(id: 'c$i', name: '친구$i', numbers: ['010-0000-00${i.toString().padLeft(2, '0')}']),
    ];
    await pump(tester);

    final rows = find.byType(ContactRow);
    for (var i = 0; i < 3; i++) {
      final ink = find.descendant(of: rows.at(i), matching: find.byType(InkWell));
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(rows.at(i)));
    }
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      await pump(tester, scale: scale);
      await tester.tap(find.text('엄마'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // 하단 버튼은 공용 AppButton(높이 52 고정, 2026-10-01 개편)이라 이 PR 이 고치지 않는다. 테스트 글꼴은 모든 글자가 한 칸(1em)이라
      // "선택 완료 (1명)" 이 2.0 에서 360 으로 재져 두 줄이 된다 — 보고서 걱정 항목에 적었다.
      final clipped = [
        for (final element in find
            .byType(RichText)
            .evaluate()
            .where((element) => find.descendant(of: find.byType(AppButton), matching: find.byWidget(element.widget)).evaluate().isEmpty))
          if (element.renderObject case final RenderParagraph p
              when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                  p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
            p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
    });
  }
}
