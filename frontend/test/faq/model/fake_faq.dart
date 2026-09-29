import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';

class FakeFaqRepository implements FaqRepository {
  FakeFaqRepository(this.result, {this.gate});

  Result<List<FaqItem>> result;

  /// 주면 이 Future 가 끝날 때까지 답을 미룬다 — "받는 중" 모습을 볼 때 쓴다.
  final Future<void>? gate;
  int calls = 0;

  @override
  Future<Result<List<FaqItem>>> fetchAll() async {
    calls++;
    await gate;
    return result;
  }
}

class FakeFaqCache implements FaqCache {
  FakeFaqCache({this.stored = const [], this.failSave = false});

  final List<FaqItem> stored;
  final bool failSave;
  List<FaqItem>? saved;

  @override
  Future<List<FaqItem>> load() async => stored;

  @override
  Future<void> save(List<FaqItem> items) async {
    if (failSave) throw Exception('disk full');
    saved = items;
  }
}

/// 묶음마다 1~2개. 카드·매칭은 sort_order 를 거꾸로 넣어 정렬을 본다. 510 은 가장 긴 질문.
const faqFixture = <FaqItem>[
  FaqItem(
    id: 'c2',
    category: FaqCategory.cardMatching,
    question: '왜 한 번에 한 장만 오나요?',
    answer: '사진은 점수에 들어가지 않아요.',
    sortOrder: 20,
  ),
  FaqItem(
    id: 'c1',
    category: FaqCategory.cardMatching,
    question: '카드는 언제 오나요?',
    answer: '지급일 아침 7시에 와요.',
    sortOrder: 10,
  ),
  FaqItem(
    id: 'h1',
    category: FaqCategory.heartPayment,
    question: '하트는 어디에 쓰나요?',
    answer: '아바타를 다시 만들 때 써요.',
    sortOrder: 110,
  ),
  FaqItem(
    id: 'p1',
    category: FaqCategory.photoProfile,
    question: '실명은 왜 받나요?',
    answer: '학생증 이름과 맞춰 봐요.',
    sortOrder: 250,
  ),
  FaqItem(
    id: 'f1',
    category: FaqCategory.friendReview,
    question: '리뷰가 부적절하면 어떻게 하나요?',
    answer: '신고할 수 있어요.',
    sortOrder: 340,
  ),
  FaqItem(
    id: 's1',
    category: FaqCategory.safety,
    question: '신고하면 어떻게 되나요?',
    answer: '그 사람은 자동으로 차단돼요.',
    sortOrder: 410,
  ),
  FaqItem(
    id: 'a1',
    category: FaqCategory.account,
    question: '누가 가입할 수 있나요? 재학생이 아니어도 되나요?',
    answer: '졸업 여부는 따로 확인하지 않아요.',
    sortOrder: 510,
  ),
  FaqItem(
    id: 'a2',
    category: FaqCategory.account,
    question: '잠시 쉬고 싶어요.',
    answer: '매칭 활성화를 끄면 돼요.',
    sortOrder: 550,
  ),
];
