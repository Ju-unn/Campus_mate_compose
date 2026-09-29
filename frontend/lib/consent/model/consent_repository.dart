import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/consent_item.dart';

abstract interface class ConsentRepository {
  /// 켠 줄을 보낸다. 필수 항목은 이번 판으로 쌓이고, 마케팅을 켰으면 수신 동의가 켜진다.
  /// 판(version)과 시각은 서버가 정한다.
  Future<Result<void>> submit({required Set<ConsentItem> agreed});
}
