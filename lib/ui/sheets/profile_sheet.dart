// 프로필 설정 시트 — 닉네임 + 하트 버디 색만 정한다 (사진/나이/성별 없음)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/profile_provider.dart';
import '../widgets/common.dart';
import '../widgets/heart_buddy.dart';

Future<bool> showProfileSheet(BuildContext context, {bool force = false}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !force,
    enableDrag: !force,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProfileSheet(),
  );
  return saved ?? false;
}

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet();

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  late final TextEditingController _nick;
  late int _color;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _nick = TextEditingController(text: p?.nickname ?? suggestNickname());
    _color = p?.colorIndex ?? 0;
  }

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  bool get _valid => _nick.text.trim().length >= 2 && _nick.text.trim().length <= 10;

  Future<void> _save() async {
    if (!_valid) return;
    await ref.read(profileProvider.notifier).save(nickname: _nick.text, colorIndex: _color);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + bottom + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(9)),
          ),
          const SizedBox(height: 18),
          Text('나의 하트 버디', style: AppText.display(26)),
          const SizedBox(height: 4),
          Text('사진 대신 이 친구가 나를 대신해요.\n두근거리면 표정이 바뀌니 조심!',
              textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.inkSoft)),
          const SizedBox(height: 16),
          HeartBuddy(colorIndex: _color, size: 96),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: List.generate(AppColors.buddies.length, (i) {
              final on = i == _color;
              return GestureDetector(
                onTap: () => setState(() => _color = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.buddies[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? AppColors.ink : Colors.white, width: on ? 3 : 2),
                    boxShadow: AppShadows.soft,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nick,
            maxLength: 10,
            onChanged: (_) => setState(() {}),
            textAlign: TextAlign.center,
            style: AppText.display(22),
            decoration: InputDecoration(
              counterText: '',
              hintText: '닉네임 (2~10자)',
              filled: true,
              fillColor: AppColors.paper,
              suffixIcon: IconButton(
                tooltip: '랜덤 닉네임',
                icon: const Icon(Icons.casino_rounded, color: AppColors.inkSoft),
                onPressed: () => setState(() => _nick.text = suggestNickname()),
              ),
              prefixIcon: const SizedBox(width: 48),
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
          const SizedBox(height: 16),
          BigButton(label: '이걸로 할래요', onPressed: _valid ? _save : null),
        ],
      ),
    );
  }
}
