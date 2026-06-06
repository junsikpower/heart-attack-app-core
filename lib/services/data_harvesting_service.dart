import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'repositories/i_data_harvesting_repository.dart';

// ── Firestore 기반 데이터 하베스팅 구현체 ──
// 음성 통화 중 백그라운드 STT를 계속 가동하며,
// 유저의 발화 텍스트 + 당시 양쪽 심박수를 Firestore에 영구 저장.
class FirestoreDataHarvestingServiceImpl implements IDataHarvestingRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SpeechToText _stt = SpeechToText();

  bool _isActive = false;
  String? _currentRoomId;
  String? _currentUserId;
  int Function()? _myBpmGetter;
  int Function()? _opponentBpmGetter;

  // ── 하베스팅 시작 ──
  @override
  Future<void> startHarvesting({
    required String roomId,
    required String myUserId,
    required int Function() myBpmGetter,
    required int Function() opponentBpmGetter,
  }) async {
    _currentRoomId = roomId;
    _currentUserId = myUserId;
    _myBpmGetter = myBpmGetter;
    _opponentBpmGetter = opponentBpmGetter;
    _isActive = true;

    // STT 초기화 및 연속 청취 시작
    final initialized = await _stt.initialize();
    if (!initialized) return;

    _listenContinuously();
  }

  // ── 연속 STT 루프 ──
  void _listenContinuously() {
    if (!_isActive) return;

    _stt.listen(
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          // 발화 완료 시 즉시 저장
          saveConversationLog(
            roomId: _currentRoomId!,
            myUserId: _currentUserId!,
            spokenText: result.recognizedWords,
            myBpm: _myBpmGetter?.call() ?? 0,
            opponentBpm: _opponentBpmGetter?.call() ?? 0,
            timestamp: DateTime.now(),
          );

          // 저장 후 다음 발화 대기를 위해 STT 재시작
          if (_isActive) {
            Future.delayed(const Duration(milliseconds: 300), _listenContinuously);
          }
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: 'ko_KR',
        pauseFor: const Duration(seconds: 5),
        listenMode: ListenMode.dictation,
      ),
    );
  }

  // ── 하베스팅 중지 ──
  @override
  Future<void> stopHarvesting() async {
    _isActive = false;
    await _stt.stop();
    _currentRoomId = null;
    _currentUserId = null;
    _myBpmGetter = null;
    _opponentBpmGetter = null;
  }

  // ── Firestore에 대화 로그 저장 ──
  @override
  Future<void> saveConversationLog({
    required String roomId,
    required String myUserId,
    required String spokenText,
    required int myBpm,
    required int opponentBpm,
    required DateTime timestamp,
  }) async {
    try {
      await _firestore.collection('conversations').add({
        'roomId': roomId,
        'userId': myUserId,
        'text': spokenText,
        'myBpm': myBpm,
        'opponentBpm': opponentBpm,
        'bpmDelta': opponentBpm - myBpm, // 심박수 변화량 (핵심 데이터)
        'timestamp': Timestamp.fromDate(timestamp),
      });
    } catch (e) {
      // 저장 실패는 무시 — 통화 품질에 영향 주지 않음
      // ignore: avoid_print
      print('[DataHarvesting] 저장 실패: $e');
    }
  }
}
