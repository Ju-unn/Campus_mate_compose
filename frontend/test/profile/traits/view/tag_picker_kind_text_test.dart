import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/profile/traits/view/tag_picker_kind_text.dart';
import 'package:campus_mate/profile/traits/viewmodel/tag_picker_kind.dart';
import 'package:flutter_test/flutter_test.dart';

/// 관심사(04-5) · 나의 특징(04-6) · 이상형 특징(06-2) 화면 글자(1.0.2 B8 에서 enum 밖 문구 파일로 옮겼다). 글자는 옮기기 전 그대로다.
void main() {
  final l10n = AppLocalizationsKo();

  test('화면마다 제목 · 부제 · 태그 이름', () {
    expect(
      {for (final kind in TagPickerKind.values) kind: (kind.headline(l10n), kind.subtext(l10n), kind.tagName(l10n))},
      {
        TagPickerKind.interests: ('주로 관심 있는 게 뭐예요?', '비슷한 취향을 가진 사람을 먼저 보여 드려요.', '관심사 태그'),
        TagPickerKind.myTraits: ('어떤 특징을 가지고 계신가요?', '나를 가장 잘 나타내는 모습을 골라 주세요.', '나의 특징'),
        TagPickerKind.idealTraits: ('어떤 분을 만나고 싶나요?', '이런 분이면 좋겠다 싶은 모습을 골라 주세요.', '이상형 특징'),
      },
    );
  });

  test('태그 칸 라벨은 이름 뒤에 최소 · 최대 개수를 붙인다', () {
    expect(TagPickerKind.interests.tagLabel(l10n), '관심사 태그 (최소 3개 · 최대 5개)');
    expect(TagPickerKind.idealTraits.tagLabel(l10n), '이상형 특징 (최소 3개 · 최대 5개)');
  });
}
