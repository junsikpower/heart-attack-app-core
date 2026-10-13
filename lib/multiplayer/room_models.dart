// 멀티플레이 데이터 모델
// Firebase Realtime Database의 방(rooms/{code}) 데이터를 앱에서 쓰기 좋은 객체로 바꾼다.
//
// rooms/{code}
//   hostId, guestId, status(lobby|playing|finished|closed), createdAt
//   players/{uid}  : nickname, color, ready, online, rematch
//   live/{uid}     : bpm, ok           ← 1초마다 갱신되는 실시간 심박
//   baselines/{uid}: 기준 심박(숨 고르기 평균)
//   game           : phase, turn, endsAt(서버시각 ms), attackerId, choices("l1,t3,w2"), cardId, gameId
//   turns/t{n}     : attackerId, defenderId, cardId, points, peakRise, samples("3,5,8,…")
//
// ※ RTDB는 배열을 자동 변환하며 예기치 않은 형태로 돌려줄 수 있어, 목록은 쉼표 문자열로 저장한다.

import 'package:flutter/foundation.dart';
import '../core/rules.dart';

enum RoomStatus { lobby, playing, finished, closed }

enum GamePhase { calibrate, pick, attack, reveal, result }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, Object?>{};

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
double? _doubleOrNull(Object? v) => v is num ? v.toDouble() : null;
bool _bool(Object? v) => v == true;
List<String> _csv(Object? v) =>
    v is String && v.isNotEmpty ? v.split(',') : const <String>[];

@immutable
class RoomPlayer {
  final String uid;
  final String nickname;
  final int colorIndex;
  final bool ready;
  final bool online;
  final bool rematch;

  const RoomPlayer({
    required this.uid,
    required this.nickname,
    required this.colorIndex,
    this.ready = false,
    this.online = true,
    this.rematch = false,
  });

  factory RoomPlayer.fromMap(String uid, Map<String, Object?> m) => RoomPlayer(
    uid: uid,
    nickname: (m['nickname'] as String?) ?? '플레이어',
    colorIndex: _int(m['color']),
    ready: _bool(m['ready']),
    online: m['online'] != false,
    rematch: _bool(m['rematch']),
  );
}

@immutable
class LiveHeart {
  final int bpm;
  final bool ok;
  const LiveHeart({this.bpm = 0, this.ok = false});
}

@immutable
class GameState {
  final GamePhase phase;
  final int turn;
  final int endsAt; // 서버 시각(ms) 기준 이 페이즈가 끝나는 순간
  final String? attackerId;
  final List<String> choices;
  final String? cardId;
  final int gameId; // 판 식별자 (한 판 더 하기 구분용)

  const GameState({
    required this.phase,
    required this.turn,
    required this.endsAt,
    this.attackerId,
    this.choices = const [],
    this.cardId,
    this.gameId = 0,
  });

  factory GameState.fromMap(Map<String, Object?> m) => GameState(
    phase: _enumByName(GamePhase.values, m['phase'], GamePhase.calibrate),
    turn: _int(m['turn']),
    endsAt: _int(m['endsAt']),
    attackerId: m['attackerId'] as String?,
    choices: _csv(m['choices']),
    cardId: m['cardId'] as String?,
    gameId: _int(m['gameId']),
  );
}

@immutable
class TurnRecord {
  final int turn;
  final String attackerId;
  final String defenderId;
  final String? cardId;
  final int points; // 공격자가 이번 턴에 얻은 점수
  final int peakRise; // 방어자 최고 상승률(%)
  final List<int> samples; // 1초 단위 상승률(%) 기록 → 결과 화면 그래프

  const TurnRecord({
    required this.turn,
    required this.attackerId,
    required this.defenderId,
    this.cardId,
    this.points = 0,
    this.peakRise = 0,
    this.samples = const [],
  });

  factory TurnRecord.fromMap(int turn, Map<String, Object?> m) => TurnRecord(
    turn: turn,
    attackerId: (m['attackerId'] as String?) ?? '',
    defenderId: (m['defenderId'] as String?) ?? '',
    cardId: m['cardId'] as String?,
    points: _int(m['points']),
    peakRise: _int(m['peakRise']),
    samples: _csv(m['samples']).map((s) => int.tryParse(s) ?? 0).toList(),
  );

  Map<String, Object?> toMap() => {
    'attackerId': attackerId,
    'defenderId': defenderId,
    'cardId': cardId,
    'points': points,
    'peakRise': peakRise,
    'samples': samples.join(','),
  };
}

@immutable
class RoomSnapshot {
  final String code;
  final String hostId;
  final String? guestId;
  final RoomStatus status;
  final Map<String, RoomPlayer> players;
  final Map<String, LiveHeart> live;
  final Map<String, double> baselines;
  final GameState? game;
  final Map<int, TurnRecord> turns;

  const RoomSnapshot({
    required this.code,
    required this.hostId,
    this.guestId,
    this.status = RoomStatus.lobby,
    this.players = const {},
    this.live = const {},
    this.baselines = const {},
    this.game,
    this.turns = const {},
  });

  factory RoomSnapshot.fromMap(String code, Map<String, Object?> m) {
    final players = <String, RoomPlayer>{};
    _map(m['players']).forEach((uid, v) => players[uid] = RoomPlayer.fromMap(uid, _map(v)));

    final live = <String, LiveHeart>{};
    _map(m['live']).forEach((uid, v) {
      final lm = _map(v);
      live[uid] = LiveHeart(bpm: _int(lm['bpm']), ok: _bool(lm['ok']));
    });

    final baselines = <String, double>{};
    _map(m['baselines']).forEach((uid, v) {
      final b = _doubleOrNull(v);
      if (b != null && b > 0) baselines[uid] = b;
    });

    final turns = <int, TurnRecord>{};
    _map(m['turns']).forEach((key, v) {
      final n = int.tryParse(key.replaceFirst('t', ''));
      if (n != null) turns[n] = TurnRecord.fromMap(n, _map(v));
    });

    final gameMap = _map(m['game']);
    return RoomSnapshot(
      code: code,
      hostId: (m['hostId'] as String?) ?? '',
      guestId: m['guestId'] as String?,
      status: _enumByName(RoomStatus.values, m['status'], RoomStatus.lobby),
      players: players,
      live: live,
      baselines: baselines,
      game: gameMap.isEmpty ? null : GameState.fromMap(gameMap),
      turns: turns,
    );
  }

  bool isHost(String uid) => hostId == uid;

  String? opponentOf(String uid) => uid == hostId ? guestId : hostId;

  RoomPlayer? player(String? uid) => uid == null ? null : players[uid];

  bool get isFull => guestId != null && players.containsKey(guestId);

  /// n번째 턴의 공격자 / 방어자
  String? attackerOfTurn(int turn) => GameRules.isHostAttacker(turn) ? hostId : guestId;
  String? defenderOfTurn(int turn) => GameRules.isHostAttacker(turn) ? guestId : hostId;

  /// 지금 턴의 방어자 (게임 중일 때만)
  String? get currentDefender => game == null ? null : defenderOfTurn(game!.turn);

  /// 플레이어의 누적 점수 = 그 사람이 공격자였던 턴들의 점수 합
  int scoreOf(String? uid) => uid == null
      ? 0
      : turns.values.where((t) => t.attackerId == uid).fold(0, (sum, t) => sum + t.points);

  /// 이미 사용한 카드들 (다음 카드 뽑기에서 제외)
  Set<String> get usedCards => turns.values.map((t) => t.cardId).whereType<String>().toSet();
}
