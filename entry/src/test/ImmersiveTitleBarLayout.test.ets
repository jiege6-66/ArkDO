import { describe, it, expect } from '@ohos/hypium';
import { immersiveTitleBarContentTopSpacer } from '../main/ets/common/ui/ImmersiveTitleBarLayout';

export default function immersiveTitleBarLayoutTest() {
  describe('immersiveTitleBarLayoutTest', () => {
    it('keepsContentReadableBelowHostTitleBar', 0, () => {
      expect(immersiveTitleBarContentTopSpacer(24)).assertEqual(88);
    });

    it('usesTitleBarHeightWhenStatusInsetIsUnavailable', 0, () => {
      expect(immersiveTitleBarContentTopSpacer(0)).assertEqual(64);
    });

    it('ignoresInvalidStatusInset', 0, () => {
      expect(immersiveTitleBarContentTopSpacer(-12)).assertEqual(64);
    });

  });
}
