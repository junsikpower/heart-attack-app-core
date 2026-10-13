// 토크 카드 덱 (Talk Cards)
// 공격자는 매 턴 '서로 다른 종류' 카드 3장 중 1장을 골라 그대로 말한다.
// 카드의 역할:
//   1) 처음 만난 사이에도 "무슨 말을 하지?" 고민 없이 바로 놀 수 있게 소재를 준다.
//   2) 대화를 '작업 멘트'가 아닌 '놀이'로 만든다. → 웃음/반전/뭉클/설렘/미션 5가지 결로 심장을 흔든다.
// 작성 원칙: 개인정보(사는 곳, 연락처, 외모 평가)를 묻지 않는다. 처음 본 사람과 해도 편한 수위.

import 'dart:math' as math;
import 'package:flutter/material.dart';

enum CardKind { laugh, twist, warm, flutter, mission }

extension CardKindStyle on CardKind {
  String get label => switch (this) {
    CardKind.laugh => '웃음',
    CardKind.twist => '반전',
    CardKind.warm => '뭉클',
    CardKind.flutter => '설렘',
    CardKind.mission => '미션',
  };

  String get verb => switch (this) {
    CardKind.laugh => '웃겨라',
    CardKind.twist => '놀래켜라',
    CardKind.warm => '뭉클하게',
    CardKind.flutter => '설레게',
    CardKind.mission => '해내라',
  };

  IconData get icon => switch (this) {
    CardKind.laugh => Icons.sentiment_very_satisfied_rounded,
    CardKind.twist => Icons.bolt_rounded,
    CardKind.warm => Icons.local_florist_rounded,
    CardKind.flutter => Icons.auto_awesome_rounded,
    CardKind.mission => Icons.flag_rounded,
  };

  Color get color => switch (this) {
    CardKind.laugh => const Color(0xFFFFA42B),
    CardKind.twist => const Color(0xFF7B6CF6),
    CardKind.warm => const Color(0xFF22B07D),
    CardKind.flutter => const Color(0xFFFF4F6D),
    CardKind.mission => const Color(0xFF3D9BE9),
  };
}

@immutable
class TalkCard {
  final String id;
  final CardKind kind;
  final String title;
  final String prompt;

  const TalkCard(this.id, this.kind, this.title, this.prompt);
}

class CardDeck {
  CardDeck._();

  static const all = <TalkCard>[
    // ── 웃음: 상대를 웃겨서 심장을 흔든다 ──
    TalkCard('l1', CardKind.laugh, '흑역사 공개', '지금 생각해도 이불킥하는 순간을 30초 안에 털어놓기'),
    TalkCard('l2', CardKind.laugh, '성대모사 퀴즈', '아무나 성대모사! 누구인지 상대가 맞혀보게 하기'),
    TalkCard('l3', CardKind.laugh, '쓸모없는 재능', '쓸데없지만 자신 있는 재능을 말로 시연하기'),
    TalkCard('l4', CardKind.laugh, '9시 뉴스', '오늘 내 하루를 뉴스 앵커처럼 진지하게 보도하기'),
    TalkCard('l5', CardKind.laugh, '아재개그 3연타', '준비한 아재개그를 쉬지 않고 3연속 발사'),
    TalkCard('l6', CardKind.laugh, '홈쇼핑 쇼호스트', '지금 눈앞에 있는 물건 하나를 홈쇼핑처럼 팔아보기'),
    TalkCard('l7', CardKind.laugh, '동물 빙의', '좋아하는 동물이 되어 그 동물 말투로 상대에게 말 걸기'),

    // ── 반전: 예상 못 한 이야기로 놀래킨다 ──
    TalkCard('t1', CardKind.twist, '두 개의 진실, 하나의 거짓', '나에 대한 이야기 3개 중 거짓 하나를 숨겨서 말하기'),
    TalkCard('t2', CardKind.twist, '기습 퀴즈', '상대에게 기습 상식 퀴즈 3문제 내기'),
    TalkCard('t3', CardKind.twist, '첫인상 반전', '사람들이 보는 나와 실제 내가 다른 점 고백하기'),
    TalkCard('t4', CardKind.twist, '미스터리 썰', '실제로 겪은 가장 이상하고 신기한 일 들려주기'),
    TalkCard('t5', CardKind.twist, '10초 침묵', '10초 동안 아무 말 없이 있다가 깜짝 한마디로 놀래키기'),
    TalkCard('t6', CardKind.twist, '미래에서 온 나', '10년 뒤의 내가 되어 지금 상대에게 비밀 조언하기'),
    TalkCard('t7', CardKind.twist, '작은 비밀', '친한 친구도 잘 모르는 나의 귀여운 비밀 하나 공개'),

    // ── 뭉클: 진심으로 마음을 움직인다 ──
    TalkCard('w1', CardKind.warm, '고마운 사람', '요즘 가장 고마운 사람과 그 이유 이야기하기'),
    TalkCard('w2', CardKind.warm, '어릴 적 꿈', '어릴 때 꿈과, 그 꿈이 지금의 나에게 남긴 것'),
    TalkCard('w3', CardKind.warm, '완벽한 하루', '살면서 가장 완벽했던 하루를 장면처럼 묘사하기'),
    TalkCard('w4', CardKind.warm, '오늘의 응원', '처음 만난 상대에게 오늘 꼭 필요할 것 같은 응원 건네기'),
    TalkCard('w5', CardKind.warm, '인생 노래', '내 인생 노래와 그 노래에 얽힌 기억 들려주기'),
    TalkCard('w6', CardKind.warm, '몰래 뿌듯', '아무도 모르게 혼자 뿌듯했던 순간 자랑하기'),
    TalkCard('w7', CardKind.warm, '1년 전의 나에게', '1년 전의 나에게 쓰는 짧은 편지를 소리 내어 읽기'),

    // ── 설렘: 기분 좋게 두근거리게 한다 (가볍고 다정하게) ──
    TalkCard('f1', CardKind.flutter, '목소리 칭찬', '지금까지 들은 상대 목소리의 좋은 점 3가지 칭찬하기'),
    TalkCard('f2', CardKind.flutter, '한 소절 선물', '상대에게 어울릴 것 같은 노래를 한 소절 불러주기'),
    TalkCard('f3', CardKind.flutter, '영화 같은 첫 만남', '우리가 영화 속에서 처음 만났다면 어떤 장면일지 묘사하기'),
    TalkCard('f4', CardKind.flutter, '닉네임 삼행시', '상대 닉네임 앞 세 글자로 칭찬 삼행시 짓기'),
    TalkCard('f5', CardKind.flutter, '심야 라디오 DJ', '심야 라디오 DJ처럼 상대에게 사연과 노래를 소개하기'),
    TalkCard('f6', CardKind.flutter, '진지한 칭찬', '세상에서 가장 진지한 목소리로 상대 칭찬하기'),
    TalkCard('f7', CardKind.flutter, '함께라면 주말', '상대와 함께라면 재밌을 것 같은 주말 계획 짜주기'),

    // ── 미션: 순발력 챌린지 ──
    TalkCard('m1', CardKind.mission, '무표정 개그', '최대한 무미건조한 목소리로 웃긴 이야기 하기'),
    TalkCard('m2', CardKind.mission, '즉석 랩', '상대 닉네임을 넣어 8마디 즉석 랩 하기'),
    TalkCard('m3', CardKind.mission, '1인 라디오극', '효과음까지 혼자 내면서 짧은 라디오극 하기'),
    TalkCard('m4', CardKind.mission, '칭찬 속사포', '30초 동안 상대 칭찬을 최대한 많이 쏟아내기'),
    TalkCard('m5', CardKind.mission, '공통점 사냥', '질문 공세로 상대와 나의 공통점 3개 찾아내기'),
    TalkCard('m6', CardKind.mission, '내일 예언', '용한 점쟁이가 되어 상대의 내일을 예언해주기'),
    TalkCard('m7', CardKind.mission, '끝말잇기 속공', '상대와 빠른 끝말잇기! 3초 이상 머뭇거리면 지는 걸로'),
  ];

  static final Map<String, TalkCard> _byId = {for (final c in all) c.id: c};

  static TalkCard? byId(String? id) => id == null ? null : _byId[id];

  /// 서로 다른 종류 3장을 뽑는다. [exclude]에 든 카드(이미 쓴 카드)는 가능한 한 피한다.
  static List<TalkCard> drawChoices({Set<String> exclude = const {}, math.Random? random}) {
    final rnd = random ?? math.Random();
    final kinds = CardKind.values.toList()..shuffle(rnd);
    final picks = <TalkCard>[];
    for (final kind in kinds.take(3)) {
      var pool = all.where((c) => c.kind == kind && !exclude.contains(c.id)).toList();
      if (pool.isEmpty) pool = all.where((c) => c.kind == kind).toList();
      picks.add(pool[rnd.nextInt(pool.length)]);
    }
    return picks;
  }
}
