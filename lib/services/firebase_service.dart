import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'repositories/i_multiplayer_repository.dart';

// ── Firebase RTDB 기반 멀티플레이 구현체 ──
// 나중에 자체 소켓 서버로 교체 시, IMultiplayerRepository를 구현하는
// 새 클래스만 만들면 UI 코드 수정 불필요.
class FirebaseMultiplayerServiceImpl implements IMultiplayerRepository {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  String? _currentRoomId;
  String? _myUserId;

  // 상대방 BPM 실시간 스트림 컨트롤러
  final StreamController<int> _opponentBpmController =
      StreamController<int>.broadcast();

  StreamSubscription? _opponentBpmSubscription;

  @override
  String? get currentRoomId => _currentRoomId;

  @override
  Stream<int> get opponentBpmStream => _opponentBpmController.stream;

  // ── 방 생성 (호스트) ──
  @override
  Future<String> createRoom(String myUserId) async {
    _myUserId = myUserId;

    // 6자리 랜덤 방 코드 생성
    final roomCode = (100000 + Random().nextInt(900000)).toString();
    _currentRoomId = roomCode;

    final roomRef = _db.ref('rooms/$roomCode');
    await roomRef.set({
      'host': myUserId,
      'guest': null,
      'status': 'waiting', // waiting | playing | ended
      'createdAt': ServerValue.timestamp,
      'bpm': {
        myUserId: 0,
      }
    });

    // 방에 상대방이 들어오면 상대방 BPM 감지 시작
    _listenForOpponent(roomCode, myUserId);

    return roomCode;
  }

  // ── 방 참가 (게스트) ──
  @override
  Future<void> joinRoom(String roomCode, String myUserId) async {
    final roomRef = _db.ref('rooms/$roomCode');
    final snapshot = await roomRef.get();

    if (!snapshot.exists) {
      throw Exception('존재하지 않는 방입니다.');
    }

    final roomData = snapshot.value as Map<dynamic, dynamic>;
    final currentGuest = roomData['guest'];
    final status = roomData['status'];

    // 이미 게스트가 있거나 게임이 진행 중인 경우 차단
    if (currentGuest != null || status == 'playing') {
      throw Exception('이미 인원이 가득 찬 방입니다. (최대 2인)');
    }

    _myUserId = myUserId;
    _currentRoomId = roomCode;

    await roomRef.update({
      'guest': myUserId,
      'status': 'playing',
      'bpm/$myUserId': 0,
    });

    _listenForOpponent(roomCode, myUserId);
  }

  // ── 상대방 BPM 실시간 Listen ──
  void _listenForOpponent(String roomCode, String myUserId) {
    final roomRef = _db.ref('rooms/$roomCode/bpm');
    _opponentBpmSubscription = roomRef.onValue.listen((event) {
      final bpmMap = event.snapshot.value as Map<dynamic, dynamic>?;
      if (bpmMap == null) return;

      // 내 ID가 아닌 상대방의 BPM만 스트림으로 전달
      bpmMap.forEach((userId, bpm) {
        if (userId != myUserId && bpm is int) {
          _opponentBpmController.add(bpm);
        }
      });
    });
  }

  // ── 내 BPM Push ──
  @override
  Future<void> pushMyBpm(int bpm) async {
    if (_currentRoomId == null || _myUserId == null) return;
    await _db.ref('rooms/$_currentRoomId/bpm/$_myUserId').set(bpm);
  }

  // ── 방 퇴장 ──
  @override
  Future<void> leaveRoom() async {
    if (_currentRoomId == null) return;

    await _opponentBpmSubscription?.cancel();
    await _db.ref('rooms/$_currentRoomId/status').set('ended');

    _currentRoomId = null;
    _myUserId = null;
  }

  void dispose() {
    _opponentBpmSubscription?.cancel();
    _opponentBpmController.close();
  }
}
