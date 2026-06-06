import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ── 1. 상태 모델 (State) ──
class AIVoiceState {
  final int aiBpm;
  final String lastUserText;
  final String lastAiReply;
  final bool isListening;
  final bool isThinking;
  final String errorMessage;

  AIVoiceState({
    this.aiBpm = 75,
    this.lastUserText = '',
    this.lastAiReply = '안녕? 들어올 때부터 계속 지켜봤어.',
    this.isListening = false,
    this.isThinking = false,
    this.errorMessage = '',
  });

  AIVoiceState copyWith({
    int? aiBpm,
    String? lastUserText,
    String? lastAiReply,
    bool? isListening,
    bool? isThinking,
    String? errorMessage,
  }) {
    return AIVoiceState(
      aiBpm: aiBpm ?? this.aiBpm,
      lastUserText: lastUserText ?? this.lastUserText,
      lastAiReply: lastAiReply ?? this.lastAiReply,
      isListening: isListening ?? this.isListening,
      isThinking: isThinking ?? this.isThinking,
      errorMessage: errorMessage ?? '',
    );
  }
}

// ── 2. 프로바이더 (Provider) ──
final aiVoiceServiceProvider =
    StateNotifierProvider<AIVoiceService, AIVoiceState>((ref) {
  return AIVoiceService();
});

// ── 3. 서비스 로직 (Service) ──
class AIVoiceService extends StateNotifier<AIVoiceState> {
  GenerativeModel? _model;
  ChatSession? _chat;

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isSttInitialized = false;

  AIVoiceService() : super(AIVoiceState()) {
    _initAI();
    _initTts();
    _initStt();
  }

  // 🧠 [기능 1] Gemini 2.5 Flash AI 초기화
  void _initAI() {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      state = state.copyWith(errorMessage: 'GEMINI_API_KEY가 없습니다.');
      return;
    }

    const systemInstruction = '''
너는 지금 20대 사용자와 '소개팅'을 하고 있는 매력적인 상대방이다.
혼자만 말하거나 반응만 하지 말고, 반드시 자연스럽게 상대방에게 질문을 던지며 '티키타카(대화의 핑퐁)'를 이어가라.
대답은 무조건 1~2문장으로 아주 짧고 간결하게 해라.
너의 기본 심박수는 75 BPM이며, 사용자의 멘트에 따라 감정이 변하고 심박수가 요동친다.

[감정-심박수 변동 루브릭]
1. 차가움/지루함: 무례, 지루, 대화 끊김 -> 변동: -2 ~ -5 BPM (최하 60 방어)
2. 일상/평온: 스몰토크 (취미, 날씨 등) -> 변동: +1 ~ +3 BPM
3. 기분 좋은 칭찬/호감: 공감, 다정한 멘트 -> 변동: +5 ~ +10 BPM
4. 강력한 플러팅/심쿵: 훅 들어오는 고백, 도발 -> 변동: +12 ~ +20 BPM

[승리 규칙]
사용자가 너의 누적 심박수를 115 BPM 이상으로 만들면 너는 완전히 설렌 상태(패배)가 된다.
115 BPM 이상이 되면 대화 내용에 반드시 "내가 졌어, 완전 심쿵했네..." 같은 항복의 의미를 담아라.

[응답 포맷]
반드시 아래의 순수 JSON 포맷으로만 응답하라. 마크다운 백틱(```json)을 절대 포함하지 마라.
{"reply": "너의 대답 (1~2문장으로 짧게, 질문 포함)", "bpm": 현재너의누적BPM숫자}
''';

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(systemInstruction),
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    _chat = _model?.startChat();
  }

  // 👄 [기능 2] TTS 초기화
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.1);
  }

  // 👂 [기능 3] STT 초기화 (최신 API 규격 적용)
  Future<void> _initStt() async {
    _isSttInitialized = await _speechToText.initialize(
      onError: (error) => state = state.copyWith(
        isListening: false,
        errorMessage: error.errorMsg,
      ),
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          state = state.copyWith(isListening: false);
        }
      },
    );
  }

  // 🎤 [기능 4] 듣기 시작 (PTT 버튼 누를 때)
  Future<void> startListening() async {
    if (!_isSttInitialized) return;
    state = state.copyWith(isListening: true, errorMessage: '');

    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          state = state.copyWith(lastUserText: result.recognizedWords);
          _sendMessageToAI(result.recognizedWords);
        }
      },
      // 최신 SpeechListenOptions 규격으로 통합
      listenOptions: SpeechListenOptions(
        localeId: 'ko_KR',
        pauseFor: const Duration(seconds: 30),
        listenMode: ListenMode.dictation,
      ),
    );
  }

  // 🛑 [기능 5] 듣기 중지 (PTT 버튼 뗄 때)
  Future<void> stopListening() async {
    await _speechToText.stop();
    state = state.copyWith(isListening: false);
  }

  // 🚀 [기능 6] Gemini에게 메시지 보내고 답변 받기
  Future<void> _sendMessageToAI(String message) async {
    if (_chat == null || message.trim().isEmpty) return;

    state = state.copyWith(isThinking: true);

    try {
      final prompt = "현재 너의 누적 BPM: ${state.aiBpm}\n사용자의 멘트: $message";

      final response = await _chat!.sendMessage(Content.text(prompt));
      final jsonString = response.text ?? '{}';

      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final aiReply = decoded['reply'] as String? ?? '응? 뭐라고?';
      final newBpm = decoded['bpm'] as int? ?? state.aiBpm;

      state = state.copyWith(
        isThinking: false,
        lastAiReply: aiReply,
        aiBpm: newBpm,
      );

      await _flutterTts.speak(aiReply);
    } catch (e) {
      state = state.copyWith(
        isThinking: false,
        errorMessage: 'AI 통신 오류: $e',
      );
    }
  }
}
