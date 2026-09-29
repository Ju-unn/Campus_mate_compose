import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_referral_repository.dart';

void main() {
  late FakeReferralRepository repository;
  late List<String> shared;
  late Future<void> Function(String) share;
  late List<String> copied;

  Future<void> pump(WidgetTester tester) async {
    // pen 판 360×780(`eoJOg`).
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          referralRepositoryProvider.overrideWithValue(repository),
          shareTextProvider.overrideWithValue((text) => share(text)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showInviteFriendsSheet(context), child: const Text('열기')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    repository = FakeReferralRepository();
    shared = [];
    copied = [];
    share = (text) async => shared.add(text);
  });

  testWidgets('내 코드와 설명을 보여 준다', (tester) async {
    await pump(tester);
    expect(find.text('K7QMX2'), findsOneWidget);
    expect(find.text('친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.'), findsOneWidget);
  });

  testWidgets('복사하면 코드가 클립보드에 들어가고 안내가 3초 뜬다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('복사'));
    await tester.pump();
    expect(copied, ['K7QMX2']);
    expect(find.text('코드를 복사했어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('코드를 복사했어요'), findsNothing);
  });

  testWidgets('공유하기는 19 와 같은 공유 글을 보낸다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    expect(shared, ['CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.']);
  });

  testWidgets('공유하기를 두 번 눌러도 한 번만 공유한다', (tester) async {
    final gate = Completer<void>();
    share = (text) async {
      shared.add(text);
      await gate.future;
    };
    await pump(tester);
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    expect(shared, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('공유 창을 못 열면 안내하고 시트는 남는다', (tester) async {
    share = (text) async => throw PlatformException(code: 'share');
    await pump(tester);
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
    expect(find.byType(InviteFriendsSheet), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('못 읽으면 문구와 다시 시도, 누르면 코드가 뜬다', (tester) async {
    repository.nextMyCode = const FailureResult(NetworkFailure());
    await pump(tester);
    expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
    expect(find.text('복사'), findsNothing);
    expect(find.text('공유하기'), findsNothing);

    repository.nextMyCode = const Success('K7QMX2');
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('K7QMX2'), findsOneWidget);
    expect(repository.myCodeCalls, 2);
  });

  testWidgets('닫기를 누르면 시트가 닫힌다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteFriendsSheet), findsNothing);
  });

  testWidgets('안내가 떠 있을 때 닫아도 타이머가 남지 않는다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('복사'));
    await tester.pump();
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteFriendsSheet), findsNothing);
    // 끝날 때 도는 타이머가 남아 있으면 flutter_test 가 실패로 잡는다.
  });

  testWidgets('글자 2배에서도 넘치지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('K7QMX2'), findsOneWidget);
  });

  group('pen 값(16i eoJOg · AlertSheet D0TvG 인스턴스 vBZjk)', () {
    Rect rect(WidgetTester tester, Finder finder) => tester.getRect(finder);
    TextStyle styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;
    Finder codeBox() => find.ancestor(of: find.text('K7QMX2'), matching: find.byType(Container)).first;

    testWidgets('시트 틀: 흰 채움 · 위 모서리 24 · 그림자 #00000026 (0,-2) blur 16', (tester) async {
      await pump(tester);
      final surface = tester.widget<Container>(
        find.ancestor(of: find.byType(SheetHandle), matching: find.byType(Container)).first,
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.canvas);
      expect(decoration.borderRadius, const BorderRadius.vertical(top: Radius.circular(24)));
      expect(decoration.boxShadow, const [BoxShadow(color: Color(0x26000000), offset: Offset(0, -2), blurRadius: 16)]);
    });

    testWidgets('세로 자리: 손잡이 위아래 12 · 내용 위 8 · 간격 16 · 버튼 간격 8 · 아래 32', (tester) async {
      await pump(tester);
      final handle = rect(tester, find.byType(SheetHandle));
      final title = rect(tester, find.text('친구 초대'));
      final description = rect(tester, find.text('친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.'));
      final box = rect(tester, codeBox());
      final shareButton = rect(tester, find.widgetWithText(AppButton, '공유하기'));
      final close = rect(tester, find.widgetWithText(AppButton, '닫기'));

      expect(title.top - handle.bottom, 12 + 8);
      expect(description.top - title.bottom, 16);
      expect(box.top - description.bottom, 16);
      expect(shareButton.top - box.bottom, 16);
      expect(close.top - shareButton.bottom, 8);
      expect(780 - close.bottom, 32);
      // 좌우 여백 16 → 폭 328.
      expect(box.left, 16);
      expect(box.width, 328);
    });

    testWidgets('제목 20/700 렌더 29 · 설명 14/400 lh1.55 #6A6A6A', (tester) async {
      await pump(tester);
      final title = styleOf(tester, '친구 초대');
      expect((title.fontSize, title.fontWeight, title.color), (20, FontWeight.w700, AppColors.ink));
      expect(tester.getSize(find.text('친구 초대')).height, 29);
      final description = styleOf(tester, '친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.');
      expect(
        (description.fontSize, description.fontWeight, description.height, description.color),
        (14, FontWeight.w400, 1.55, AppColors.muted),
      );
    });

    testWidgets('코드 상자 e3n2P: surface-soft · 모서리 14 · 여백 [12,12,12,16] · 높이 68', (tester) async {
      await pump(tester);
      final box = tester.widget<Container>(codeBox());
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.surfaceSoft);
      expect(decoration.borderRadius, BorderRadius.circular(14));
      expect(box.padding, const EdgeInsets.fromLTRB(16, 12, 12, 12));
      expect(tester.getSize(codeBox()).height, 68);
    });

    testWidgets('코드 Kf6Wi: display 32/700/1.3/-0.96 #222222, 상자 왼쪽 16', (tester) async {
      await pump(tester);
      final code = styleOf(tester, 'K7QMX2');
      expect(
        (code.fontSize, code.fontWeight, code.height, code.letterSpacing, code.color),
        (32, FontWeight.w700, 1.3, -0.96, AppColors.ink),
      );
      expect(rect(tester, find.text('K7QMX2')).left - rect(tester, codeBox()).left, 16);
    });

    testWidgets('복사 yAaQX: 높이 44 · 모서리 12 · #E5E5E5 · copy 16 · 14/600 렌더 20 · 상자 오른쪽 12', (tester) async {
      await pump(tester);
      final button = find.ancestor(of: find.text('복사'), matching: find.byType(Material)).first;
      final material = tester.widget<Material>(button);
      expect(material.color, AppColors.primaryDisabled);
      expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(12));
      expect(tester.getSize(button).height, 44);
      expect(rect(tester, codeBox()).right - rect(tester, button).right, 12);

      final icon = tester.widget<Icon>(find.descendant(of: button, matching: find.byType(Icon)));
      expect((icon.icon, icon.size, icon.color), (AppIcons.copy, 16, AppColors.ink));
      // 아이콘과 글자 사이 6, 좌우 여백 14.
      expect(rect(tester, find.text('복사')).left - rect(tester, find.byIcon(AppIcons.copy)).right, 6);
      expect(rect(tester, find.byIcon(AppIcons.copy)).left - rect(tester, button).left, 14);
      expect(rect(tester, button).right - rect(tester, find.text('복사')).right, 14);

      final label = styleOf(tester, '복사');
      expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w600, AppColors.ink));
      expect(tester.getSize(find.text('복사')).height, 20);
    });

    testWidgets('공유하기는 기본 주 버튼(56), 닫기는 글자 버튼(48)', (tester) async {
      await pump(tester);
      expect(tester.widget<AppButton>(find.widgetWithText(AppButton, '공유하기')).variant, AppButtonVariant.primary);
      expect(tester.getSize(find.widgetWithText(AppButton, '공유하기')).height, 56);
      expect(tester.widget<AppButton>(find.widgetWithText(AppButton, '닫기')).variant, AppButtonVariant.text);
      expect(tester.getSize(find.widgetWithText(AppButton, '닫기')).height, 48);
    });

    testWidgets('복사 토스트 CuNVR: check 16 흰색, 시트 윗변 16 위 · 가운데', (tester) async {
      await pump(tester);
      await tester.tap(find.text('복사'));
      await tester.pump();

      final toast = find.byType(AppToast);
      final icon = tester.widget<Icon>(find.descendant(of: toast, matching: find.byType(Icon)));
      expect((icon.icon, icon.size, icon.color), (AppIcons.check, 16, AppColors.onInk));
      // 시트 윗변 = 손잡이 위 12.
      expect(rect(tester, find.byType(SheetHandle)).top - 12 - rect(tester, toast).bottom, 16);
      expect(rect(tester, toast).center.dx, 180);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('공유 창 실패 안내에는 체크 아이콘을 달지 않는다', (tester) async {
      share = (text) async => throw PlatformException(code: 'share');
      await pump(tester);
      await tester.tap(find.text('공유하기'));
      await tester.pump();
      expect(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
