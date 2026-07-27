import { ActionBarStyle, BlurStrategy } from '@kit.UIDesignKit';
import { LengthMetrics } from '@ohos.arkui.node';
import { ButtonModifier } from '@ohos.arkui.modifier';

class ImmersiveFloatingActionButtonModifier extends ButtonModifier {
  private readonly blurEnabled: boolean;

  constructor(blurEnabled: boolean) {
    super();
    this.blurEnabled = blurEnabled;
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    // 内容自适应的光边:描边用统一的半透明白。因为半透明,这圈边会透出它正后方的内容——
    // 顶边压着按钮上方组件、底边压着下方组件,于是上下自然呈现不同颜色,近似原生材质那种
    // 随环境变化的光边,而不是写死一圈白线。两态都画:关闭开关后按钮在暗色下仍保留边线。
    instance
      .borderWidth(0.5)
      .borderColor($r('app.color.hds_floating_action_highlight'));
    if (this.blurEnabled) {
      // 玻璃态:用 backgroundEffect 而非 COMPONENT_* 组件材质——后者模糊强度与不透明度绑死,越糊越白越不透,
      // 做不到「强磨砂 + 通透」。backgroundEffect 把两者拆开:radius 控制磨砂强度、color 的 alpha 控制透不透,
      // 于是可以「大半径出强磨砂 + 低 alpha 底色保持看得穿」。adaptiveColor AVERAGE 让遮罩色随背后内容走,
      // 边线与磨砂都会带上环境色。半径 28 偏强;想更/更不磨砂改这个数,想更/更不透明改 hds_floating_action_bg 的 alpha。
      const glassEffect: BackgroundEffectOptions = {
        radius: 28,
        color: $r('app.color.hds_floating_action_bg'),
        adaptiveColor: AdaptiveColor.AVERAGE
      };
      instance.backgroundEffect(glassEffect);
    } else {
      // 关态:去掉磨砂底(半径归零),仅保留上面的半透明描边。显式复位,避免 modifier 属性残留导致半玻璃错态。
      const resetEffect: BackgroundEffectOptions = { radius: 0 };
      instance.backgroundEffect(resetEffect);
      instance.backdropBlur(0);
    }
  }
}

// HdsActionBar 不提供 HdsNavigation 的 systemMaterialEffect 参数。外层 ActionBar 保留自己的
// 交互与布局，真正可见的 primaryButton 则由上面的 modifier 直接执行 backdropBlur；
// 两处统一维护，避免首页和详情页逐渐出现视觉差异。
export const IMMERSIVE_ACTION_BAR_BLUR_STRATEGY: BlurStrategy = BlurStrategy.ENABLE;

// 玻璃效果关闭时用:显式关掉 ActionBar 的材质模糊(配合按钮层的透明背景),
// 让开/关两态共用同一个 HdsActionBar 调用点,仅切 blurStrategy,避免 if/else 双实例导致的重复 id。
export const IMMERSIVE_ACTION_BAR_BLUR_DISABLED: BlurStrategy = BlurStrategy.DISABLE;

export function buildImmersiveFloatingActionButtonModifier(enabled: boolean): ButtonModifier {
  return new ImmersiveFloatingActionButtonModifier(enabled);
}

export function buildImmersiveFloatingActionStyle(size: number = 52): ActionBarStyle {
  return new ActionBarStyle({
    height: LengthMetrics.vp(size),
    backgroundBlurStyle: BlurStyle.COMPONENT_REGULAR,
    innerSpace: LengthMetrics.vp(0),
    startSpace: LengthMetrics.vp(0),
    endSpace: LengthMetrics.vp(0),
    isHorizontal: true
  });
}
