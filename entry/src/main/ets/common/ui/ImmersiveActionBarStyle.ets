import { ActionBarStyle, BlurStrategy } from '@kit.UIDesignKit';
import { LengthMetrics } from '@ohos.arkui.node';
import { ButtonModifier } from '@ohos.arkui.modifier';
import { clampFabGlassRadius, FAB_GLASS_RADIUS_DEFAULT } from './FabGlassPrefs';

class ImmersiveFloatingActionButtonModifier extends ButtonModifier {
  private readonly blurEnabled: boolean;
  private readonly blurRadius: number;

  constructor(blurEnabled: boolean, blurRadius: number) {
    super();
    this.blurEnabled = blurEnabled;
    this.blurRadius = clampFabGlassRadius(blurRadius);
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    // 内容自适应的光边:描边用统一的半透明白。因为半透明,这圈边会透出它正后方的内容——
    // 顶边压着按钮上方组件、底边压着下方组件,于是上下自然呈现不同颜色,近似原生材质那种
    // 随环境变化的光边,而不是写死一圈白线。两态都画:关闭开关后按钮在暗色下仍保留边线。
    instance
      .borderWidth(0.5)
      .borderColor($r('app.color.hds_floating_action_highlight'));
    if (this.blurEnabled) {
      // 用 backgroundEffect 而非 COMPONENT_* 组件材质:后者模糊强度与不透明度绑死,越糊越白越不透,
      // 做不到「强磨砂 + 通透」。backgroundEffect 把两者拆开:radius 控制磨砂强度、color 的 alpha 控制
      // 透不透,于是可以「大半径出强磨砂 + 低 alpha 底色保持看得穿」。radius 由设置页滑块给
      // (FabGlassPrefs,默认 28,即改造前的硬编码值);想更/更不透明改 hds_floating_action_bg 的
      // alpha。saturation 略提饱和,让透出来的底色不发灰。
      //
      // 蒙版色用静态 color,不用 adaptiveColor: AdaptiveColor.AVERAGE。AVERAGE 会让蒙版色跟着背后
      // 内容走(观感更"活"),代价是每帧都要额外采样背景算一次均色。这个 FAB 在首页与详情页常驻可见,
      // 转场期间背景每帧都在变、结果无法复用,曾是掉帧的来源之一。观感差异在 52vp 的小按钮上很有限,
      // 不值得为它付这笔每帧开销。
      const glassEffect: BackgroundEffectOptions = {
        radius: this.blurRadius,
        color: $r('app.color.hds_floating_action_bg'),
        saturation: 1.2
      };
      instance.backgroundEffect(glassEffect);
    } else {
      // 关态:磨砂半径归零,仅保留上面的半透明描边。显式复位而不是"不设置"——
      // modifier 每次 build 都是新实例,不显式写回 0 有可能残留上一次的磨砂,出现半玻璃错态。
      const resetEffect: BackgroundEffectOptions = { radius: 0 };
      instance.backgroundEffect(resetEffect);
    }
  }
}

// HdsActionBar 不提供 HdsNavigation 的 systemMaterialEffect 参数。外层 ActionBar 只承载位置/阴影/交互,
// 真正可见的磨砂做在 primaryButton 的 modifier 上,两处统一维护,避免首页与详情页逐渐出现视觉差异。
export const IMMERSIVE_ACTION_BAR_BLUR_STRATEGY: BlurStrategy = BlurStrategy.ENABLE;

// FAB 用这个:外层恒不加背景模糊(磨砂交给按钮层的 modifier),避免与按钮材质叠成双层。
// 开/关两态共用同一个 HdsActionBar 调用点、只切 blurStrategy,而不是写 if/else 两个实例——
// 后者会产生重复 id。
export const IMMERSIVE_ACTION_BAR_BLUR_DISABLED: BlurStrategy = BlurStrategy.DISABLE;

// radius 缺省仍是 28:调用点只有两个 FAB,都会显式传设置页的值,这个默认只兜住漏传的情况。
export function buildImmersiveFloatingActionButtonModifier(
  enabled: boolean,
  radius: number = FAB_GLASS_RADIUS_DEFAULT
): ButtonModifier {
  return new ImmersiveFloatingActionButtonModifier(enabled, radius);
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
