// PPG 디스플레이 광원 바 (Display-Illuminated PPG Light Bar)
// [아키텍처 피벗] 후면 플래시를 전면 폐기한 뒤, OLED 디스플레이의 초록색 화소를
//   '소프트웨어 조명'으로 활용하여 전면 카메라 PPG를 수행하는 광원 UI 컴포넌트.
// [설계 원칙] DRY(Don't Repeat Yourself) - 3개의 화면(PreCheckModal, GameScreen,
//   MultiplayerGameScreen)에서 동일한 광원 UI를 재사용하기 위해 독립된 위젯으로 캡슐화.
// [3단계 확장 예정] 향후 시스템 밝기 제어(screen_brightness) 로직을
//   이 위젯의 생명주기(initState/dispose)에 결합하여 일원 관리할 예정.

import 'package:flutter/material.dart';

/// 전면 카메라 렌즈 주변에 초록색 빛을 뿜어내는 PPG 전용 광원 바.
/// 혈액 속 헤모글로빈이 초록색 파장(약 530nm)에 가장 강하게 반응하므로,
/// 순수 초록색(#00FF00) 화소를 최대 밝기로 발광시켜 약한 디스플레이 빛으로도
/// 피부를 투과하여 혈류 신호를 수집할 수 있게 합니다.
class PpgLightBar extends StatelessWidget {
  const PpgLightBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      // ── 광원 영역 크기 ──
      // 전면 카메라 렌즈(노치/펀치홀)를 완전히 덮을 수 있는 충분한 높이.
      // SafeArea 상단 패딩(상태바 높이)을 포함하여 렌즈 주변 전체를 초록빛으로 감쌈.
      width: double.infinity,
      height: MediaQuery.of(context).padding.top + 90,
      // ── 순백색 (Pure White) ──
      // flutter_ppg 라이브러리가 '빨간색 채널'만을 읽어들이도록 하드코딩되어 있으므로,
      // 순백색(RGB 모두 최대치)을 뿜어내어 손가락을 투과한 붉은빛을 카메라에 제공합니다.
      color: Colors.white,
      // ── 사용자 안내 문구 ──
      child: Padding(
        // 상태바 영역을 피해서 텍스트를 배치 (상태바 아래부터 안내 시작)
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: const Center(
          child: Text(
            '이곳에 검지손가락을 밀착해 주세요',
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
