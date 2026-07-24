import { ActionBarStyle, BlurStrategy } from '@kit.UIDesignKit';
import { LengthMetrics } from '@ohos.arkui.node';
import { ButtonModifier } from '@ohos.arkui.modifier';

class ImmersiveFloatingActionButtonModifier extends ButtonModifier {
  private readonly blurRadius: number;

  constructor(blurRadius: number) {
    super();
    this.blurRadius = blurRadius;
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    // primaryButton 会铺满整个 ActionBar，外层 backgroundBlurStyle 无法在按钮中间形成
    // 可见的背板采样。这里沿用 ClashBox 悬浮按钮已验证的同节点方案：
    // backdropBlur(30) 直接模糊按钮后方内容，再叠加主题底色和细高光边缘。
    // 浅色使用 ClashBox 的 #B3 思路；暗色不能照搬 70% 黑色，否则会在 ArkDO 的深色页面上
    // 抹掉模糊后的色差，因此暗色资源改用更浅、透明度更低的中性材质色。
    // HdsActionBar 没有标题栏的 systemMaterialEffect 接口，只能通过其官方开放的
    // buttonModifier 在最上层补一条细高光；0.5vp 避免高密度屏上出现明显的粗描边。
    instance
      .backdropBlur(this.blurRadius)
      .borderWidth(0.5)
      .borderColor($r('app.color.hds_floating_action_highlight'));
  }
}

// HdsActionBar 不提供 HdsNavigation 的 systemMaterialEffect 参数。外层 ActionBar 保留自己的
// 交互与布局，真正可见的 primaryButton 则由上面的 modifier 直接执行 backdropBlur；
// 两处统一维护，避免首页和详情页逐渐出现视觉差异。
export const IMMERSIVE_ACTION_BAR_BLUR_STRATEGY: BlurStrategy = BlurStrategy.ENABLE;

export function buildImmersiveFloatingActionButtonModifier(blurRadius: number = 30): ButtonModifier {
  return new ImmersiveFloatingActionButtonModifier(blurRadius);
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
