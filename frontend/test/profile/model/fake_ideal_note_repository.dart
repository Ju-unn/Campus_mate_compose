import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/ideal_note_repository.dart';

class FakeIdealNoteRepository implements IdealNoteRepository {
  Result<void> nextResult = const Success(null);
  String? submittedNote;

  @override
  Future<Result<void>> submit(String note) async {
    submittedNote = note;
    return nextResult;
  }
}
