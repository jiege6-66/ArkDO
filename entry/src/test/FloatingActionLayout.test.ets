import { describe, it, expect } from '@ohos/hypium';
import { floatingActionBottomMargin } from '../main/ets/common/ui/FloatingActionLayout';

export default function floatingActionLayoutTest() {
  describe('floatingActionLayoutTest', () => {
    it('keepsDefaultMarginWithoutBottomInset', 0, () => {
      expect(floatingActionBottomMargin(0)).assertEqual(16);
    });

    it('addsBottomInsetToDefaultMargin', 0, () => {
      expect(floatingActionBottomMargin(24)).assertEqual(40);
    });

    it('ignoresInvalidBottomInset', 0, () => {
      expect(floatingActionBottomMargin(-8)).assertEqual(16);
    });
  });
}
