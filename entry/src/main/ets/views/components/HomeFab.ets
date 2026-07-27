import { ActionBarButton, ActionBarStyle, HdsActionBar } from '@kit.UIDesignKit';
import { ColorMetrics, LengthMetrics } from '@ohos.arkui.node';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import {
  buildImmersiveFloatingActionButtonModifier,
  IMMERSIVE_ACTION_BAR_BLUR_DISABLED
} from '../../common/ui/ImmersiveActionBarStyle';
import { FAB_GLASS_ENABLED_STORAGE_KEY } from '../../common/ui/FabGlassPrefs';

@Component
export struct HomeFab {
  // 由父页滚动位置驱动:true=回顶态,false=发帖态。
  @Prop showBackToTop: boolean = false;
  // 「悬浮按钮玻璃效果」开关(设置页-外观):开⇒模糊材质背板;关⇒当前透明样式。默认关。
  @StorageProp(FAB_GLASS_ENABLED_STORAGE_KEY) private glassEnabled: boolean = false;
  onCompose: () => void = () => {};
  onBackToTop: () => void = () => {};

  build() {
    // 玻璃材质与光边都做在 primaryButton 上(见 buttonModifier),外层 ActionBar 只承载位置/阴影/交互,
    // 故其背景模糊始终 DISABLE,避免与按钮材质叠成双层磨砂。
    HdsActionBar({
      primaryButton: this.fabButton(),
      actionBarStyle: this.fabStyle(),
      blurStrategy: IMMERSIVE_ACTION_BAR_BLUR_DISABLED
    })
      .width(52)
      .height(52)
  }

  private fabButton(): ActionBarButton {
    return new ActionBarButton({
      width: LengthMetrics.vp(52),
      // 背景恒透明:玻璃态的磨砂底由 buttonModifier 里的 backgroundBlurStyle 组件材质提供,不再叠主题底色。
      backgroundColor: ColorMetrics.resourceColor(Color.Transparent),
      // 始终挂载 modifier(内部按开关施加/复位),避免关闭时材质/描边残留。
      buttonModifier: buildImmersiveFloatingActionButtonModifier(this.glassEnabled),
      iconSize: LengthMetrics.vp(22),
      iconFillColor: ColorMetrics.resourceColor(this.showBackToTop ? $r('app.color.fab_top_fg') : $r('app.color.fab_compose_bg')),
      baseIconSymbolGlyphModifier: this.symbolModifier($r('sys.symbol.square_and_pencil'), $r('app.color.fab_compose_bg')),
      altIconSymbolGlyphModifier: this.symbolModifier($r('sys.symbol.arrow_up_to_line'), $r('app.color.fab_top_fg')),
      accessibilityText: this.showBackToTop ? '回到顶部' : '发帖',
      onClick: () => {
        if (this.showBackToTop) {
          this.onBackToTop();
        } else {
          this.onCompose();
        }
      }
    });
  }

  private fabStyle(): ActionBarStyle {
    // 外层容器恒透明、不加背景模糊(磨砂交给按钮层的组件材质),只保留同位 morph 的图标切换标志。
    return new ActionBarStyle({
      height: LengthMetrics.vp(52),
      backgroundBlurStyle: BlurStyle.NONE,
      backgroundColor: ColorMetrics.resourceColor(Color.Transparent),
      innerSpace: LengthMetrics.vp(0),
      startSpace: LengthMetrics.vp(0),
      endSpace: LengthMetrics.vp(0),
      isHorizontal: true,
      isPrimaryIconChanged: this.showBackToTop
    });
  }

  private symbolModifier(icon: Resource, color: ResourceColor): SymbolGlyphModifier {
    const modifier: SymbolGlyphModifier = new SymbolGlyphModifier(icon);
    modifier.fontSize(22);
    modifier.fontColor([color]);
    return modifier;
  }
}
