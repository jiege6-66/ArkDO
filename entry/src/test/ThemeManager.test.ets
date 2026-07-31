import { describe, it, expect } from '@ohos/hypium';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeManager, ThemeMode } from '../main/ets/common/theme/ThemeManager';

export default function themeManagerTest() {
  describe('themeManagerTest', () => {
    it('mapsThemeModeToSystemColorMode', 0, () => {
      expect(ThemeManager.toColorMode(ThemeMode.SYSTEM))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      expect(ThemeManager.toColorMode(ThemeMode.LIGHT))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      expect(ThemeManager.toColorMode(ThemeMode.DARK))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    });

    it('parsesStoredThemeModeString', 0, () => {
      expect(ThemeManager.parseMode('system')).assertEqual(ThemeMode.SYSTEM);
      expect(ThemeManager.parseMode('light')).assertEqual(ThemeMode.LIGHT);
      expect(ThemeManager.parseMode('dark')).assertEqual(ThemeMode.DARK);
    });

    it('fallsBackToSystemForUnknownMode', 0, () => {
      expect(ThemeManager.parseMode('')).assertEqual(ThemeMode.SYSTEM);
      expect(ThemeManager.parseMode('unknown')).assertEqual(ThemeMode.SYSTEM);
    });

    // 强制主题不看生效模式;跟随系统才透传。透传这一条是深色高亮 BUG 的回归点:
    // 生效模式为深色时 appIsDark 必须为 true,否则非资源染色会错用浅色。
    it('resolvesForcedModeRegardlessOfEffectiveColorMode', 0, () => {
      expect(ThemeManager.resolveIsDark(ThemeMode.DARK, false)).assertTrue();
      expect(ThemeManager.resolveIsDark(ThemeMode.DARK, true)).assertTrue();
      expect(ThemeManager.resolveIsDark(ThemeMode.LIGHT, true)).assertFalse();
      expect(ThemeManager.resolveIsDark(ThemeMode.LIGHT, false)).assertFalse();
    });

    it('followsEffectiveColorModeInSystemMode', 0, () => {
      expect(ThemeManager.resolveIsDark(ThemeMode.SYSTEM, true)).assertTrue();
      expect(ThemeManager.resolveIsDark(ThemeMode.SYSTEM, false)).assertFalse();
    });
  });
}
