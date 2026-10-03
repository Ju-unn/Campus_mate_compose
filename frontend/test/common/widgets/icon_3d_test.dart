import 'dart:io';

import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppIcon3d 표와 assets/icons/ 의 WebP 가 하나도 빠짐 · 남음 없이 맞는다', () {
    final files = Directory('assets/icons').listSync().map((f) => f.uri.pathSegments.last).toSet();
    final table = AppIcon3d.values.map((i) => i.asset.split('/').last).toSet();

    expect(table, hasLength(AppIcon3d.values.length));
    expect(files, table);
  });

  testWidgets('크기만 받아 그 크기로 그리고, 화소 배율만큼 줄여 풀고, 낭독기에는 읽히지 않는다', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 3),
        child: Center(child: Icon3d(AppIcon3d.siren, size: 22)),
      ),
    );

    expect(tester.getSize(find.byType(Icon3d)), const Size(22, 22));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>().having((r) => r.width, 'width', 66));
    expect(image.excludeFromSemantics, isTrue);
  });
}
