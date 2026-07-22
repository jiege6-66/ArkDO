import { describe, it, expect } from '@ohos/hypium';
import {
  adaptiveSystemMaterialEffect,
  canUseBitmapFallback,
  canUseOfficialHds,
  customSystemMaterialEffect,
  HDS_MATERIAL_LEVEL_ADAPTIVE,
  HDS_MATERIAL_LEVEL_GENTLE,
  HDS_MATERIAL_LEVEL_SMOOTH,
  HDS_MATERIAL_TYPE_ADAPTIVE,
  ImmersiveLightArea,
  ImmersiveLightMode
} from '../main/ets/common/ui/ImmersiveLightMaterial';

export default function immersiveLightMaterialTest() {
  describe('immersiveLightMaterialTest', () => {
    it('neverUsesBitmapFallback', 0, () => {
      expect(canUseBitmapFallback()).assertFalse();
    });

    it('marksOfficialHdsAreas', 0, () => {
      expect(canUseOfficialHds(ImmersiveLightArea.TITLE_BAR)).assertTrue();
      expect(canUseOfficialHds(ImmersiveLightArea.BOTTOM_TABS)).assertTrue();
      expect(canUseOfficialHds(ImmersiveLightArea.FLOATING_ACTION)).assertTrue();
      expect(canUseOfficialHds(ImmersiveLightArea.PANEL)).assertFalse();
      expect(ImmersiveLightMode.ADAPTIVE).assertEqual('adaptive');
    });

    it('usesSystemAdaptiveMaterialByDefault', 0, () => {
      const effect = adaptiveSystemMaterialEffect();

      expect(effect.materialType).assertEqual(HDS_MATERIAL_TYPE_ADAPTIVE);
      expect(effect.materialLevel).assertEqual(HDS_MATERIAL_LEVEL_ADAPTIVE);
    });

    it('selectsCustomMaterialLevelFromSupportFlag', 0, () => {
      expect(customSystemMaterialEffect(true).materialLevel).assertEqual(HDS_MATERIAL_LEVEL_GENTLE);
      expect(customSystemMaterialEffect(false).materialLevel).assertEqual(HDS_MATERIAL_LEVEL_SMOOTH);
    });
  });
}
