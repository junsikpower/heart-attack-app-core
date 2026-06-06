// 방 코드 입력 화면 (Room Screen)
// 역할: 멀티플레이 모드에서 방을 만들거나 참가하는 화면.
// '방 만들기'를 누르면 6자리 코드를 생성하고, '참가하기'를 누르면 코드를 입력하고 입장.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/multiplayer_provider.dart';
import 'multiplayer_game_screen.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _createdRoomCode; // 내가 만든 방 코드 (화면에 표시용)

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── 방 만들기 (호스트) ──
  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    try {
      final roomId = await ref.read(multiplayerProvider.notifier).createRoom(
        userId: 'user_${DateTime.now().millisecondsSinceEpoch}',
        myBpmGetter: () => 0, // 게임 화면 진입 후 실제 BPM으로 교체됨
      );
      setState(() {
        _createdRoomCode = roomId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('방 생성 실패: $e')),
        );
      }
    }
  }

  // ── 방 참가 (게스트) ──
  Future<void> _joinRoom() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('6자리 방 코드를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(multiplayerProvider.notifier).joinRoom(
        roomCode: code,
        userId: 'user_${DateTime.now().millisecondsSinceEpoch}',
        myBpmGetter: () => 0,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MultiplayerGameScreen()),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('방 참가 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text(
          '멀티플레이',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF2D55)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),

                    // ── 아이콘 ──
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1C1C1E),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF2D55).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Color(0xFFFF2D55),
                        size: 40,
                      ),
                    ),

                    const SizedBox(height: 32),

                    Text(
                      '상대방과 연결하기',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '방을 만들고 코드를 공유하거나\n상대방의 코드를 입력해 참가하세요',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.45),
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 48),

                    // ────────────────────────────
                    // 섹션 1: 방 만들기
                    // ────────────────────────────
                    _buildSectionCard(
                      title: '방 만들기',
                      subtitle: '코드를 상대방에게 공유하세요',
                      child: Column(
                        children: [
                          // 생성된 방 코드 표시
                          if (_createdRoomCode != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A0A0A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFF2D55).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _createdRoomCode!,
                                    style: GoogleFonts.outfit(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 6,
                                    ),
                                  ),
                                  // 클립보드 복사 버튼
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(
                                          text: _createdRoomCode!));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('방 코드가 복사되었습니다!')),
                                      );
                                    },
                                    child: const Icon(
                                      Icons.copy_rounded,
                                      color: Color(0xFFFF2D55),
                                      size: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '상대방이 입장하면 자동으로 시작됩니다',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // 방 코드를 공유하고 직접 게임 화면으로 이동
                            _buildButton(
                              label: '게임 시작',
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                      builder: (_) => const MultiplayerGameScreen()),
                                );
                              },
                              isPrimary: true,
                            ),
                          ] else ...[
                            _buildButton(
                              label: '방 만들기',
                              onTap: _createRoom,
                              isPrimary: true,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── OR 구분선 ──
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.3),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ────────────────────────────
                    // 섹션 2: 방 참가하기
                    // ────────────────────────────
                    _buildSectionCard(
                      title: '방 참가하기',
                      subtitle: '상대방에게 받은 6자리 코드를 입력하세요',
                      child: Column(
                        children: [
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 8,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '000000',
                              hintStyle: GoogleFonts.outfit(
                                fontSize: 24,
                                color: Colors.white.withValues(alpha: 0.15),
                                letterSpacing: 8,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0A0A0A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFFF2D55),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildButton(
                            label: '참가하기',
                            onTap: _joinRoom,
                            isPrimary: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── 섹션 카드 위젯 ──
  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ── 버튼 위젯 ──
  Widget _buildButton({
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [Color(0xFFFF2D55), Color(0xFFFF6B8A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isPrimary ? null : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF2D55).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
