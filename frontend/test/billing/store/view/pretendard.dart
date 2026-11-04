import 'dart:io';

import 'package:flutter/services.dart';

/// 시험 기본 글꼴(Ahem)은 글자마다 폭이 같은 네모라 글자 폭이 실제와 전혀 다르다 — 실제 글꼴 Pretendard 를 불러 pen 치수로 잰다.
Future<void> loadPretendard() async {
  final loader = FontLoader('Pretendard');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File('assets/fonts/Pretendard-$weight.otf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}
