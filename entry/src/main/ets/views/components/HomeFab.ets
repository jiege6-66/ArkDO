import { ActionBarButton, ActionBarStyle, HdsActionBar } from '@kit.UIDesignKit';
import { ColorMetrics, LengthMetrics } from '@ohos.arkui.node';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import {
  buildImmersiveFloatingActionButtonModifier,
  buildImmersiveFloatingActionStyle,
  IMMERSIVE_ACTION_BAR_BLUR_STRATEGY
} from '../../common/ui/ImmersiveActionBarStyle';

const HOME_FAB_BLUR_RADIUS: number = 20;

@Component
export struct HomeFab {
  // 由父页滚动位置驱动:true=回顶态,false=发帖态。
  @Prop showBackToTop: boolean = false;
  onCompose: () => void = () => {};
  onBackToTop: () => void = () => {};

  build() {
    HdsActionBar({
      primaryButton: this.fabButton(),
      actionBarStyle: this.fabStyle(),
      blurStrategy: IMMERSIVE_ACTION_BAR_BLUR_STRATEGY
    })
    .width(52)
    .height(52)
  }

  private fabButton(): ActionBarButton {
    return new ActionBarButton({
      width: LengthMetrics.vp(52),
      // 背景色必须落在按钮层：若只加到 ActionBar 外层，会被 HDS 模糊材质再次合成，
      // 首页采用稍浅的背景模糊：正文仍不可辨认，但滚动时材质变化更轻。
      // 不会像单纯透明背景一样仍能辨认；外层 ActionBar 保留官方交互与阴影能力。
      backgroundColor: ColorMetrics.resourceColor($r('app.color.hds_floating_action_bg')),
      buttonModifier: buildImmersiveFloatingActionButtonModifier(HOME_FAB_BLUR_RADIUS),
      iconSize: LengthMetrics.vp(22),
      // 发帖/回复仍使用品牌蓝图标表达主操作，回顶态则沿用中性色降低视觉权重。
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
    const style: ActionBarStyle = buildImmersiveFloatingActionStyle();
    style.isPrimaryIconChanged = this.showBackToTop;
    return style;
  }

  private symbolModifier(icon: Resource, color: ResourceColor): SymbolGlyphModifier {
    const modifier: SymbolGlyphModifier = new SymbolGlyphModifier(icon);
    modifier.fontSize(22);
    modifier.fontColor([color]);
    return modifier;
  }
}
