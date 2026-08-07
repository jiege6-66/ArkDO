import { describe, it, expect } from '@ohos/hypium';
import {
  BreakpointManager,
  SPLIT_NAV_BAR_MAX_WIDTH,
  SPLIT_NAV_BAR_MIN_WIDTH,
  SPLIT_NAV_BAR_RATIO,
  UNFOLDED_SQUARE_RATIO_MAX,
  UNFOLDED_WIDE_THRESHOLD_VP,
  WIDE_THRESHOLD_VP
} from '../main/ets/common/utils/BreakpointManager';

export default function breakpointManagerTest() {
  describe('breakpointManagerTest', () => {
    // 尺寸取自华为官方各机型实测 vp(阔折叠一组见「阔折叠应用开发」最佳实践),
    // 改阈值时这一组就是回归护栏:每台机器每种形态该单栏还是双栏,都钉在这里。

    it('phoneStaysSingleColumn', 0, () => {
      // 手机竖屏 / 横屏都够不着 840,非折叠屏也走不到第二条。
      expect(BreakpointManager.isWideLayout(360, 780, false)).assertFalse();
      expect(BreakpointManager.isWideLayout(780, 360, false)).assertFalse();
    });

    it('tabletSplitsOnlyInLandscape', 0, () => {
      // 大屏平板竖屏宽度就有 965vp:光看阈值会误判,长宽比这一刀把它按回单栏。
      expect(BreakpointManager.isWideLayout(1138, 800, false)).assertTrue();
      expect(BreakpointManager.isWideLayout(965, 1300, false)).assertFalse();
    });

    it('foldableInnerScreenSplitsInBothOrientations', 0, () => {
      // 竖折叠(Mate X 系)内屏近方形 741×832,比值 1.12,横竖都双栏。
      expect(BreakpointManager.isWideLayout(741, 832, true)).assertTrue();
      expect(BreakpointManager.isWideLayout(832, 741, true)).assertTrue();
      // 折叠态外屏 ≈360:低于 600 兜底阈值,不会被误判。
      expect(BreakpointManager.isWideLayout(360, 780, true)).assertFalse();
    });

    it('wideFoldSplitsOnlyWhenUnfoldedLandscape', 0, () => {
      // Pura X Max:展开横持 939×664 走第一条(939 ≥ 840 且横着)→ 双栏。
      expect(BreakpointManager.isWideLayout(939, 664, true)).assertTrue();
      // 同一块内屏竖持 664×939,比值 1.41 已接近平板竖屏形状 → 单栏。
      // 若不看长宽比,这里会因 664 ≥ 600 被兜底判成双栏,与上面平板竖屏那条自相矛盾。
      expect(BreakpointManager.isWideLayout(664, 939, true)).assertFalse();
      // 折叠态外屏 459×672,两条都不成立。
      expect(BreakpointManager.isWideLayout(459, 672, true)).assertFalse();
      // Pura X 展开态 440×707:宽度不到 600,兜底那条本就够不着。
      expect(BreakpointManager.isWideLayout(440, 707, true)).assertFalse();
      expect(BreakpointManager.isWideLayout(326, 326, true)).assertFalse();
    });

    it('splitScreenFallsBackToSingleColumn', 0, () => {
      // 展开态再左右分屏,应用窗口只剩半宽:低于 600 直接落回单栏。
      expect(BreakpointManager.isWideLayout(470, 664, true)).assertFalse();
      // 平板横屏分屏同理,半宽够不着 840。
      expect(BreakpointManager.isWideLayout(569, 800, false)).assertFalse();
    });

    it('rejectsDegenerateSizes', 0, () => {
      // 首帧之前 / 异常回调可能喂进 0,不能除零也不能判成宽屏。
      expect(BreakpointManager.isWideLayout(0, 0, true)).assertFalse();
      expect(BreakpointManager.isWideLayout(700, 0, true)).assertFalse();
    });

    it('thresholdsMatchDocumentedValues', 0, () => {
      expect(WIDE_THRESHOLD_VP).assertEqual(840);
      expect(UNFOLDED_WIDE_THRESHOLD_VP).assertEqual(600);
      expect(UNFOLDED_SQUARE_RATIO_MAX).assertEqual(1.2);
      expect(SPLIT_NAV_BAR_RATIO).assertEqual(0.5);
      expect(SPLIT_NAV_BAR_MIN_WIDTH).assertEqual(320);
      expect(SPLIT_NAV_BAR_MAX_WIDTH).assertEqual(420);
    });

    it('splitNavBarCapsWidthOnNonFoldables', 0, () => {
      // 平板横屏对半是 569 / 720,都封顶 420(与改造前写死的值一致)。
      expect(BreakpointManager.splitNavBarWidth(1138, false)).assertEqual(420);
      expect(BreakpointManager.splitNavBarWidth(1440, false)).assertEqual(420);
      // 窄窗口对半不足 320 时抬到下限,保证分区抽屉(288)滑出不溢进右栏。
      expect(BreakpointManager.splitNavBarWidth(600, false)).assertEqual(320);
    });

    it('splitNavBarAlignsToCreaseWhenUnfolded', 0, () => {
      // 双折叠内屏 741 对半是 370:本来就没触顶,豁免上限前后一致(回归护栏)。
      expect(BreakpointManager.splitNavBarWidth(741, true)).assertEqual(370);
      // Pura X Max 展开横持 939 对半是 470:改前被 420 夹住、分割线偏离折痕约 50vp,
      // 展开态豁免上限后取满一半,压在折痕上,右栏 469。
      expect(BreakpointManager.splitNavBarWidth(939, true)).assertEqual(470);
      // 上限只对非折叠设备生效——同一个宽度在直板/平板上仍然封顶。
      expect(BreakpointManager.splitNavBarWidth(939, false)).assertEqual(420);
      // 下限对展开态同样生效。
      expect(BreakpointManager.splitNavBarWidth(600, true)).assertEqual(320);
    });
  });
}
