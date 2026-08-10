import { describe, it, expect } from '@ohos/hypium';
import {
  clampFabGlassRadius,
  FAB_GLASS_RADIUS_DEFAULT,
  FAB_GLASS_RADIUS_MAX,
  FAB_GLASS_RADIUS_MIN
} from '../main/ets/common/ui/FabGlassPrefs';

export default function fabGlassTest() {
  describe('fabGlassTest', () => {
    // 回归护栏:默认半径必须等于改造前 ImmersiveActionBarStyle 里的硬编码 28,
    // 否则不动设置的老用户升级后会发现 FAB "自己变了样"。
    it('defaultRadiusReproducesLegacyHardcodedValue', 0, () => {
      expect(FAB_GLASS_RADIUS_DEFAULT).assertEqual(28);
    });

    it('clampsRadiusToRange', 0, () => {
      expect(clampFabGlassRadius(0)).assertEqual(FAB_GLASS_RADIUS_MIN);
      expect(clampFabGlassRadius(-10)).assertEqual(FAB_GLASS_RADIUS_MIN);
      expect(clampFabGlassRadius(999)).assertEqual(FAB_GLASS_RADIUS_MAX);
      expect(clampFabGlassRadius(28)).assertEqual(28);
    });

    it('roundsFractionalRadius', 0, () => {
      expect(clampFabGlassRadius(27.4)).assertEqual(27);
      expect(clampFabGlassRadius(27.6)).assertEqual(28);
    });

    // 读盘拿到脏值(旧版本写进去的非数字、NaN)时回默认,而不是把 NaN 传进 backgroundEffect。
    it('fallsBackToDefaultOnNonFinite', 0, () => {
      expect(clampFabGlassRadius(Number.NaN)).assertEqual(FAB_GLASS_RADIUS_DEFAULT);
      expect(clampFabGlassRadius(Number.POSITIVE_INFINITY)).assertEqual(FAB_GLASS_RADIUS_DEFAULT);
    });
  });
}
