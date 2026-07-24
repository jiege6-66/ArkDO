export interface ImmersiveLightSystemMaterialEffect {
  materialType: number;
  materialLevel: number;
}

// API 23 hdsMaterial enum values. Keeping them local avoids loading HDS runtime modules in local unit tests.
export const HDS_MATERIAL_TYPE_ADAPTIVE: number = 100;
export const HDS_MATERIAL_TYPE_IMMERSIVE: number = 101;
export const HDS_MATERIAL_LEVEL_GENTLE: number = 1;
export const HDS_MATERIAL_LEVEL_SMOOTH: number = 2;
export const HDS_MATERIAL_LEVEL_ADAPTIVE: number = 10;
export const HDS_SCROLL_EFFECT_TYPE_GRADIENT_BLUR: number = 2;
export const HDS_TITLE_BAR_BLUR_RADIUS: number = 24;
export const HDS_TITLE_BAR_MASK_EXTRA_HEIGHT: number = 16;
// 普通 ArkUI 浮层没有 HDS 的 systemMaterialEffect 接口，需要直接使用 backdropBlur。
// 输入栏、搜索栏等面板统一从这里取半径，后续调整时不会出现不同页面各写一套数值。
export const IMMERSIVE_PANEL_BLUR_RADIUS: number = 30;

export enum ImmersiveLightArea {
  TITLE_BAR = 'titleBar',
  BOTTOM_TABS = 'bottomTabs',
  FLOATING_ACTION = 'floatingAction',
  PANEL = 'panel',
  SEARCH = 'search',
  INPUT_BAR = 'inputBar'
}

export enum ImmersiveLightMode {
  ADAPTIVE = 'adaptive',
  CUSTOM = 'custom'
}

export function adaptiveSystemMaterialEffect(): ImmersiveLightSystemMaterialEffect {
  return {
    materialType: HDS_MATERIAL_TYPE_ADAPTIVE,
    materialLevel: HDS_MATERIAL_LEVEL_ADAPTIVE
  };
}

export function customSystemMaterialEffect(supportsImmersive: boolean = true): ImmersiveLightSystemMaterialEffect {
  return {
    materialType: supportsImmersive
      ? HDS_MATERIAL_TYPE_IMMERSIVE
      : HDS_MATERIAL_TYPE_ADAPTIVE,
    materialLevel: supportsImmersive
      ? HDS_MATERIAL_LEVEL_GENTLE
      : HDS_MATERIAL_LEVEL_SMOOTH
  };
}

export function preferredTitleBarScrollEffectType(): number {
  return HDS_SCROLL_EFFECT_TYPE_GRADIENT_BLUR;
}

export function canUseBitmapFallback(): boolean {
  return false;
}

export function canUseOfficialHds(area: ImmersiveLightArea): boolean {
  return area === ImmersiveLightArea.TITLE_BAR
    || area === ImmersiveLightArea.BOTTOM_TABS
    || area === ImmersiveLightArea.FLOATING_ACTION;
}

export function requiresHdsScrollableBinding(area: ImmersiveLightArea): boolean {
  return area === ImmersiveLightArea.TITLE_BAR;
}

export function requiresHdsComponentSafeArea(area: ImmersiveLightArea): boolean {
  return area === ImmersiveLightArea.TITLE_BAR;
}

export function requiresHdsLayoutSafeAreaAvoidance(area: ImmersiveLightArea): boolean {
  return area === ImmersiveLightArea.TITLE_BAR;
}
