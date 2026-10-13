// 멀티플레이 입구 — 빠른 매칭 / 방 만들기 / 코드로 입장

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/session_provider.dart';
import '../nav.dart';
import '../permissions.dart';
import '../widgets/common.dart';
import '../widgets/heart_buddy.dart';
import '../widgets/pulse_heart.dart';
import 'room_screen.dart';

class MultiEntryScreen extends ConsumerStatefulWidget {
  const MultiEntryScreen({super.key});

  @override
  ConsumerState<MultiEntryScreen> createState() => _MultiEntryScreenState();
}

enum _Busy { none, quick, create, join }

class _MultiEntryScreenState extends ConsumerState<MultiEntryScreen> {
  final _code = TextEditingController();
  _Busy _busy = _Busy.none;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  SessionController get _session => ref.read(sessionProvider.notifier);

  Future<void> _run(_Busy kind, Future<bool> Function() action) async {
    if (_busy != _Busy.none) return;
    if (!await ensureGamePermissions(context)) return;
    setState(() => _busy = kind);
    try {
      final entered = await action();
      if (entered && mounted) {
        await Navigator.of(context).push(fadeRoute(const RoomScreen()));
      }
    } catch (e) {
      if (mounted) showToast(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  void _quick() => _run(_Busy.quick, _session.quickMatch);

  void _create() => _run(_Busy.create, () async {
    await _session.createRoom();
    return true;
  });

  void _join() {
    final code = _code.text.trim();
    if (code.length != 5) {
      showToast(context, '방 코드 5자리를 입력해 주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    _run(_Busy.join, () async {
      await _session.joinRoom(code);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searching = _busy == _Busy.quick;
    return PopScope(
      canPop: !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && searching) _session.cancelQuickMatch();
      },
      child: Scaffold(
        body: AppBackdrop(
          tint: AppColors.coral,
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Row(
                    children: [
                      RoundIconButton(
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 12),
                      Text('1:1 두근 배틀', style: AppText.display(26)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HeartBuddy(colorIndex: 0, size: 70, flush: 0.15),
                      SizedBox(width: 6),
                      PulseHeart(bpm: 84, size: 40),
                      SizedBox(width: 6),
                      HeartBuddy(colorIndex: 4, size: 70, flush: 0.7),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _Promise(icon: Icons.videocam_off_rounded, text: '영상 없이 목소리만 주고받아요'),
                  const _Promise(icon: Icons.face_retouching_off_rounded, text: '사진 대신 하트 버디로 만나요'),
                  const _Promise(icon: Icons.style_rounded, text: '카드가 대화를 이끌어서 어색하지 않아요'),
                  const SizedBox(height: 22),
                  BigButton(
                    label: '빠른 매칭',
                    icon: Icons.bolt_rounded,
                    busy: _busy == _Busy.quick,
                    onPressed: _quick,
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: '친구랑 하기 · 방 만들기',
                    icon: Icons.add_home_rounded,
                    secondary: true,
                    busy: _busy == _Busy.create,
                    onPressed: _create,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.line)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('초대 코드가 있다면', style: AppText.body(12.5, color: AppColors.inkFaint)),
                      ),
                      const Expanded(child: Divider(color: AppColors.line)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          maxLength: 5,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                            TextInputFormatter.withFunction(
                              (o, n) => n.copyWith(text: n.text.toUpperCase()),
                            ),
                          ],
                          onSubmitted: (_) => _join(),
                          style: AppText.display(22).copyWith(letterSpacing: 6),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'ABCDE',
                            hintStyle: AppText.display(22, color: AppColors.line).copyWith(letterSpacing: 6),
                            filled: true,
                            fillColor: AppColors.paper,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: AppColors.line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: AppColors.line),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: AppColors.coral, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 96,
                        child: BigButton(
                          label: '입장',
                          secondary: true,
                          busy: _busy == _Busy.join,
                          onPressed: _join,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (searching) _SearchingOverlay(onCancel: _session.cancelQuickMatch),
            ],
          ),
        ),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Promise({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: AppColors.mint),
        const SizedBox(width: 8),
        Text(text, style: AppText.body(14, color: AppColors.inkSoft, weight: FontWeight.w600)),
      ],
    ),
  );
}

class _SearchingOverlay extends StatelessWidget {
  final VoidCallback onCancel;
  const _SearchingOverlay({required this.onCancel});

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Container(
      color: AppColors.cream.withValues(alpha: 0.94),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PulseHeart(bpm: 96, size: 110),
          const SizedBox(height: 24),
          Text('두근거릴 상대를 찾는 중…', style: AppText.display(24)),
          const SizedBox(height: 8),
          Text('누군가 빠른 매칭을 누르면 바로 연결돼요', style: AppText.body(14, color: AppColors.inkSoft)),
          const SizedBox(height: 28),
          SizedBox(
            width: 180,
            child: BigButton(label: '그만 찾기', secondary: true, onPressed: onCancel),
          ),
        ],
      ),
    ),
  );
}
