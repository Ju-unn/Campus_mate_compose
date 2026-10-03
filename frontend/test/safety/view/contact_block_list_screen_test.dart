import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/view/contact_block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/contact_row.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_contact_blocks.dart';

/// 16b 연락처 차단 관리(pen `fkjEh` — 추가 `z9dxy`, 줄 `GC2LV` · `J2OCDM`, 해제 시트 `AA8T7`, 빈 상태 `Gp5my`).
void main() {
  late FakeDeviceContactSource source;
  late FakeContactBlockRepository repository;
  late FakeContactNameStore nameStore;

  setUp(() {
    source = FakeDeviceContactSource(granted: true, contacts: const [momContact, siblingContact]);
    repository = FakeContactBlockRepository()..blocks = Success([contactBlockFixture('b1'), contactBlockFixture('b2')]);
    nameStore = FakeContactNameStore({'b1': const ContactLabel(name: '김지은', maskedNumber: '010-****-2841')});
  });

  Future<void> pump(WidgetTester tester, {double scale = 1, Widget page = const ContactBlockListScreen()}) async {
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
    final router = GoRouter(initialLocation: AppRoutes.contactBlocks, routes: [
      GoRoute(path: AppRoutes.contactBlocks, builder: (context, state) => page),
      GoRoute(path: AppRoutes.contactPicker, builder: (context, state) => const ContactPickerScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Finder row(String text) => find.ancestor(of: find.text(text), matching: find.byType(ContactRow));
  Finder trash(String text) => find.descendant(of: row(text), matching: find.byType(IconButton));

  testWidgets('title, add button, known row shows name and masked number with trash', (tester) async {
    await pump(tester);

    expect(find.text('연락처 차단'), findsOneWidget);
    expect(find.text('추가'), findsOneWidget);
    expect(find.text('김지은'), findsOneWidget);
    expect(maskedNumber('010-****-2841'), findsOneWidget);
    expect(find.descendant(of: row('김지은'), matching: find.byIcon(AppIcons.trash2)), findsOneWidget);
  });

  testWidgets('16b unknown row shows 이전에 차단한 연락처 / 이 기기에서 이름을 찾을 수 없어요', (tester) async {
    await pump(tester);

    expect(find.text('이전에 차단한 연락처'), findsOneWidget);
    expect(find.text('이 기기에서 이름을 찾을 수 없어요'), findsOneWidget);
    expect(trash('이전에 차단한 연락처'), findsOneWidget);
  });

  testWidgets('add button 312x44 at (24, 64), list 16 below (pen z9dxy · ZwbzQ)', (tester) async {
    await pump(tester);

    final add = tester.getRect(find.byKey(contactBlockAddKey));
    expect(add, const Rect.fromLTWH(24, 64, 312, 44));
    final icon = tester.getRect(find.descendant(of: find.byKey(contactBlockAddKey), matching: find.byIcon(AppIcons.plus)));
    expect(icon.size, const Size(16, 16));
    expect(tester.getRect(find.text('추가')).left - icon.right, 6);
    expect(tester.getRect(row('김지은')).top, 124);
  });

  testWidgets('trash is 20 visible, 48 to press, at the row right edge', (tester) async {
    await pump(tester);

    final button = tester.getRect(trash('김지은'));
    expect(button.size, const Size(48, 48));
    final icon = tester.getRect(find.descendant(of: row('김지은'), matching: find.byIcon(AppIcons.trash2)));
    expect(icon.size, const Size(20, 20));
    expect(icon.right, tester.getRect(row('김지은')).right);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.trash2).first).color, AppColors.disabled);
  });

  testWidgets('16b trash → confirm sheet → remove', (tester) async {
    await pump(tester);

    await tester.tap(trash('김지은'));
    await tester.pumpAndSettle();

    expect(find.byType(SafetyConfirmSheet), findsOneWidget);
    expect(find.text('차단을 해제할까요?'), findsOneWidget);
    expect(find.text('이 연락처가 다시 카드에 나타날 수 있어요.'), findsOneWidget);

    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();

    expect(repository.removed, ['b1']);
    expect(nameStore.labels, isEmpty);
    expect(find.text('김지은'), findsNothing);
    expect(find.byType(ContactRow), findsOneWidget);
  });

  testWidgets('cancel on the confirm sheet sends nothing', (tester) async {
    await pump(tester);

    await tester.tap(trash('김지은'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(repository.removed, isEmpty);
    expect(find.text('김지은'), findsOneWidget);
  });

  testWidgets('remove failure keeps the row and shows a red line (pen 에 없는 상태)', (tester) async {
    repository.removeResult = const FailureResult(ServerUnavailableFailure());
    await pump(tester);

    await tester.tap(trash('김지은'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();

    expect(find.text('김지은'), findsOneWidget);
    expect(tester.widget<Text>(find.text('잠시 뒤 다시 시도해 주세요')).style?.color, AppColors.error);
  });

  testWidgets('16b empty state', (tester) async {
    repository.blocks = const Success([]);
    await pump(tester);

    expect(find.byType(ContactRow), findsNothing);
    expect(find.text('추가'), findsOneWidget);
    expect(find.text('아직 차단한 연락처가 없어요'), findsOneWidget);
    expect(find.text('추가한 연락처 속 지인과는 서로의 카드에 나타나지 않아요.'), findsOneWidget);
    final mascot = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is AssetImage && (widget.image as AssetImage).assetName == 'assets/images/mascot-female.png',
    );
    expect(tester.getSize(mascot), const Size(120, 120));
    final title = tester.getRect(find.text('아직 차단한 연락처가 없어요'));
    expect(title.top - tester.getRect(mascot).bottom, 16);
    expect(tester.getRect(find.text('추가한 연락처 속 지인과는 서로의 카드에 나타나지 않아요.')).top - title.bottom, 8);
  });

  testWidgets('load failure shows message and retry reads again', (tester) async {
    repository.blocks = const FailureResult(NetworkFailure());
    await pump(tester);

    expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
    repository.blocks = Success([contactBlockFixture('b1')]);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('김지은'), findsOneWidget);
    expect(repository.fetchCount, 2);
  });

  testWidgets('추가 → 8d → 차단 → back on 16b with the list read again', (tester) async {
    await pump(tester);
    repository.blocks = Success([contactBlockFixture('b1'), contactBlockFixture('b2'), contactBlockFixture('b3')]);

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(find.byType(ContactPickerScreen), findsOneWidget);

    await tester.tap(find.text('동생'));
    await tester.pump();
    await tester.tap(find.text('선택 완료 (1명)'));
    await tester.pumpAndSettle();

    expect(find.byType(ContactPickerScreen), findsNothing);
    expect(repository.fetchCount, 2);
    expect(find.byType(ContactRow), findsNWidgets(3));
  });

  testWidgets('rows ink stays inside the list when scrolled (COMMON §4-2)', (tester) async {
    await pump(tester);

    // 16b 줄 자체는 누르지 않는다 — 누르는 것은 휴지통뿐이고, 그 효과는 버튼 자신의 Material 에 그린다.
    expect(find.descendant(of: find.byType(ContactRow), matching: find.byType(InkWell)), findsNWidgets(2));
    final ink = find.descendant(of: trash('김지은'), matching: find.byType(InkWell));
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(material), const Size(48, 48));
    final add = find.descendant(of: find.byKey(contactBlockAddKey), matching: find.byType(InkWell));
    expect(tester.getSize(find.ancestor(of: add, matching: find.byType(Material)).first), const Size(312, 44));
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    for (final empty in [false, true]) {
      testWidgets('글자 배율 $scale${empty ? ' 빈 상태' : ''} 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        if (empty) repository.blocks = const Success([]);
        await pump(tester, scale: scale);

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

  group('ContactBlockListBody — 16b 밖 다른 틀에서 쓰는 본문(가입 마지막 06-4, 결정 8 ①)', () {
    // 틀(앱바 · 제목 · 건너뛰기)은 쓰는 쪽 몫이다. 본문은 높이가 정해진 자리에 둔다(안에서 목록이 남은 높이를 채운다).
    const framed = Scaffold(body: SafeArea(child: ContactBlockListBody()));

    testWidgets('앱바 없이 추가 버튼 · 목록을 그린다', (tester) async {
      await pump(tester, page: framed);

      expect(find.text('연락처 차단'), findsNothing);
      expect(find.byKey(contactBlockAddKey), findsOneWidget);
      expect(find.text('김지은'), findsOneWidget);
      expect(find.text('이전에 차단한 연락처'), findsOneWidget);
    });

    testWidgets('빈 상태도 본문이 그린다', (tester) async {
      repository.blocks = const Success([]);
      await pump(tester, page: framed);

      expect(find.text('아직 차단한 연락처가 없어요'), findsOneWidget);
    });

    testWidgets('읽기 실패면 다시 시도', (tester) async {
      repository.blocks = const FailureResult(NetworkFailure());
      await pump(tester, page: framed);

      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });
  });
}
