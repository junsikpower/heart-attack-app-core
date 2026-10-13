// 방/매칭 저장소 (Room Repository)
// 게임 로직은 RoomRepository 인터페이스에만 의존한다.
// 나중에 자체 서버로 옮길 때는 이 인터페이스를 구현한 새 클래스만 만들면 된다.

import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../providers/profile_provider.dart';
import 'room_models.dart';

class RoomException implements Exception {
  final String message;
  const RoomException(this.message);
  @override
  String toString() => message;
}

/// 빠른 매칭 결과: 어떤 방에, 호스트로 들어가는지 게스트로 들어가는지
@immutable
class MatchFound {
  final String code;
  final bool asHost;
  const MatchFound(this.code, {required this.asHost});
}

abstract class RoomRepository {
  /// 서버 시각 - 내 기기 시각 (ms). 두 폰의 타이머를 똑같이 맞추는 데 사용.
  Stream<int> serverTimeOffset();

  Future<String> createRoom(Profile me);
  Future<void> joinRoom(String code, Profile me);
  Stream<RoomSnapshot?> watchRoom(String code);

  Future<void> markOnline(String code, String uid);
  Future<void> updatePlayer(String code, String uid, Map<String, Object?> fields);
  Future<void> pushLive(String code, String uid, {required int bpm, required bool ok});
  Future<void> setBaseline(String code, String uid, double baseline);
  Future<void> writeTurn(String code, TurnRecord record);
  Future<void> pickCard(String code, String cardId);

  /// 여러 경로를 한 번에 갱신 (호스트의 페이즈 진행용)
  Future<void> updateRoom(String code, Map<String, Object?> updates);

  Future<void> leaveRoom(String code, String uid, {required bool isHost, required RoomStatus status});

  /// 빠른 매칭: 상대를 찾을 때까지 기다린다. [cancelQuickMatch] 호출 시 null 반환.
  Future<MatchFound?> quickMatch(Profile me);
  Future<void> cancelQuickMatch();
}

class FirebaseRoomRepository implements RoomRepository {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  DatabaseReference _room(String code) => _db.ref('rooms/$code');

  @override
  Stream<int> serverTimeOffset() => _db
      .ref('.info/serverTimeOffset')
      .onValue
      .map((e) => (e.snapshot.value as num?)?.toInt() ?? 0);

  // ── 방 만들기 ──
  @override
  Future<String> createRoom(Profile me) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final code = _randomCode();
      // hostId 자리를 '선점'하는 트랜잭션: 같은 코드의 방이 이미 있으면 다른 코드로 재시도
      final result = await _room(code).child('hostId').runTransaction((value) {
        if (value == null) return Transaction.success(me.uid);
        return Transaction.abort();
      });
      if (!result.committed || result.snapshot.value != me.uid) continue;

      await _room(code).update({
        'status': RoomStatus.lobby.name,
        'createdAt': ServerValue.timestamp,
        'players/${me.uid}': _playerMap(me),
      });
      return code;
    }
    throw const RoomException('방을 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
  }

  // ── 방 참가 ──
  @override
  Future<void> joinRoom(String code, Profile me) async {
    final snap = await _room(code).get();
    if (!snap.exists) throw const RoomException('방을 찾을 수 없어요. 코드를 확인해 주세요.');
    final room = RoomSnapshot.fromMap(code, Map<String, Object?>.from(snap.value as Map));
    if (room.status == RoomStatus.closed) throw const RoomException('이미 닫힌 방이에요.');
    if (room.hostId == me.uid) throw const RoomException('내가 만든 방이에요.');
    if (room.status != RoomStatus.lobby && room.guestId != me.uid) {
      throw const RoomException('이미 게임이 진행 중인 방이에요.');
    }

    // guestId 자리를 선점: 비어 있거나 이미 나라면 성공
    final result = await _room(code).child('guestId').runTransaction((value) {
      if (value == null || value == me.uid) return Transaction.success(me.uid);
      return Transaction.abort();
    });
    if (!result.committed || result.snapshot.value != me.uid) {
      throw const RoomException('방이 이미 꽉 찼어요. (1:1 게임)');
    }
    await _room(code).child('players/${me.uid}').set(_playerMap(me));
  }

  @override
  Stream<RoomSnapshot?> watchRoom(String code) => _room(code).onValue.map((e) {
    final v = e.snapshot.value;
    if (v is! Map) return null;
    return RoomSnapshot.fromMap(code, Map<String, Object?>.from(v));
  });

  // ── 접속 상태: 앱이 꺼지거나 네트워크가 끊기면 서버가 자동으로 online=false 처리 ──
  @override
  Future<void> markOnline(String code, String uid) async {
    final ref = _room(code).child('players/$uid/online');
    await ref.onDisconnect().set(false);
    await ref.set(true);
  }

  @override
  Future<void> updatePlayer(String code, String uid, Map<String, Object?> fields) =>
      _room(code).child('players/$uid').update(fields);

  @override
  Future<void> pushLive(String code, String uid, {required int bpm, required bool ok}) =>
      _room(code).child('live/$uid').set({'bpm': bpm, 'ok': ok});

  @override
  Future<void> setBaseline(String code, String uid, double baseline) =>
      _room(code).child('baselines/$uid').set(double.parse(baseline.toStringAsFixed(2)));

  @override
  Future<void> writeTurn(String code, TurnRecord record) =>
      _room(code).child('turns/t${record.turn}').set(record.toMap());

  @override
  Future<void> pickCard(String code, String cardId) =>
      _room(code).child('game/cardId').set(cardId);

  @override
  Future<void> updateRoom(String code, Map<String, Object?> updates) =>
      _room(code).update(updates);

  @override
  Future<void> leaveRoom(String code, String uid, {required bool isHost, required RoomStatus status}) async {
    final room = _room(code);
    await room.child('players/$uid/online').onDisconnect().cancel();
    if (status == RoomStatus.lobby) {
      if (isHost) {
        await room.update({'status': RoomStatus.closed.name});
      } else {
        // 대기실에서 게스트가 나가면 자리를 비워 다른 사람이 들어올 수 있게 한다
        await room.update({'guestId': null, 'players/$uid': null, 'live/$uid': null});
      }
    } else {
      await room.update({'players/$uid/online': false, 'players/$uid/left': true});
    }
  }

  // ─────────────────────────────────────────────────────────
  // 빠른 매칭 (queue/{uid})
  //   1) 이미 기다리는 사람이 있으면 → 내가 방을 만들고 그 사람의 대기표에 방 코드를 적는다(트랜잭션)
  //   2) 없으면 → 내 대기표를 올리고, 누군가 방 코드를 적어줄 때까지 기다린다
  //   3) 기다리는 동안에도 4초마다 다시 찾아본다. 단, '나보다 ID가 작은 사람'만 잡는다
  //      → 두 사람이 동시에 서로를 잡는 경합을 막는 간단한 규칙
  // ─────────────────────────────────────────────────────────
  Completer<MatchFound?>? _matchCompleter;

  @override
  Future<MatchFound?> quickMatch(Profile me) async {
    await cancelQuickMatch();
    final completer = Completer<MatchFound?>();
    _matchCompleter = completer;

    final myTicket = _db.ref('queue/${me.uid}');
    StreamSubscription<DatabaseEvent>? sub;
    Timer? retry;
    var busy = false;

    try {
      // 1) 먼저 기다리는 사람을 찾아본다
      final direct = await _tryClaimSomeone(me, lowerUidOnly: false);
      if (direct != null) return direct;
      if (completer.isCompleted) return completer.future;

      // 2) 대기표 등록
      await myTicket.onDisconnect().remove();
      await myTicket.set(_ticketMap(me));
      sub = myTicket.child('roomId').onValue.listen((e) {
        final code = e.snapshot.value;
        if (code is String && !completer.isCompleted) {
          completer.complete(MatchFound(code, asHost: false));
        }
      });

      // 3) 주기적 재탐색
      retry = Timer.periodic(const Duration(seconds: 4), (_) async {
        if (busy || completer.isCompleted) return;
        busy = true;
        try {
          final candidates = await _candidates(me, lowerUidOnly: true);
          if (candidates.isEmpty) return;
          // 내 대기표를 먼저 회수한다 (그 사이 누가 나를 잡았다면 회수 실패 → 그 방으로 감)
          final withdraw = await myTicket.runTransaction((value) {
            if (value is Map && value['roomId'] != null) return Transaction.abort();
            return Transaction.success(null);
          });
          if (!withdraw.committed || completer.isCompleted) return;
          final found = await _tryClaimSomeone(me, lowerUidOnly: true);
          if (found != null) {
            if (!completer.isCompleted) completer.complete(found);
          } else if (!completer.isCompleted) {
            await myTicket.set(_ticketMap(me)); // 실패했으면 다시 줄 선다
          }
        } catch (e) {
          debugPrint('[QuickMatch] 재탐색 오류: $e');
        } finally {
          busy = false;
        }
      });

      return await completer.future;
    } finally {
      retry?.cancel();
      await sub?.cancel();
      await myTicket.onDisconnect().cancel();
      await myTicket.remove();
      if (identical(_matchCompleter, completer)) _matchCompleter = null;
    }
  }

  @override
  Future<void> cancelQuickMatch() async {
    final c = _matchCompleter;
    if (c != null && !c.isCompleted) c.complete(null);
  }

  Future<List<String>> _candidates(Profile me, {required bool lowerUidOnly}) async {
    final snap = await _db.ref('queue').orderByChild('ts').limitToFirst(20).get();
    final v = snap.value;
    if (v is! Map) return const [];
    final out = <String>[];
    v.forEach((uid, ticket) {
      if (uid == me.uid || ticket is! Map || ticket['roomId'] != null) return;
      if (lowerUidOnly && uid.toString().compareTo(me.uid) >= 0) return;
      out.add(uid.toString());
    });
    return out;
  }

  Future<MatchFound?> _tryClaimSomeone(Profile me, {required bool lowerUidOnly}) async {
    final candidates = await _candidates(me, lowerUidOnly: lowerUidOnly);
    if (candidates.isEmpty) return null;

    final code = await createRoom(me);
    for (final uid in candidates) {
      final result = await _db.ref('queue/$uid').runTransaction((value) {
        // 로컬 캐시가 비어 있으면(null) 일단 null로 시도 → 서버 값이 다르면 서버 값으로 재실행됨
        if (value == null) return Transaction.success(null);
        if (value is Map && value['roomId'] == null) {
          return Transaction.success({...value, 'roomId': code});
        }
        return Transaction.abort();
      });
      final after = result.snapshot.value;
      if (result.committed && after is Map && after['roomId'] == code) {
        return MatchFound(code, asHost: true);
      }
    }
    await _room(code).remove(); // 아무도 못 잡았으면 만든 방 정리
    return null;
  }

  Map<String, Object?> _playerMap(Profile me) => {
    'nickname': me.nickname,
    'color': me.colorIndex,
    'ready': false,
    'online': true,
    'rematch': false,
  };

  Map<String, Object?> _ticketMap(Profile me) => {
    'nickname': me.nickname,
    'ts': ServerValue.timestamp,
  };

  /// 헷갈리는 글자(0/O, 1/I/L)를 뺀 5자리 방 코드
  static String _randomCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = math.Random.secure();
    return List.generate(5, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
