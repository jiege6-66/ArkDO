import { ActionBarButton, ActionBarStyle, HdsActionBar } from '@kit.UIDesignKit';
import { ColorMetrics, LengthMetrics } from '@ohos.arkui.node';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';

@Component
export struct HomeFab {
  // 由父页滚动位置驱动:true=回顶态,false=发帖态。
  @Prop showBackToTop: boolean = false;
  onCompose: () => void = () => {};
  onBackToTop: () => void = () => {};

  build() {
    // 位置、阴影、点击态均由 HdsActionBar 官方按钮承载;之前额外叠的 Circle 会在按钮上方
    // 露出一圈方框(形状阴影按矩形包围盒投射)+ 圆形描边,这里不再自绘背板。
    HdsActionBar({
      primaryButton: this.fabButton(),
      actionBarStyle: this.fabStyle()
    })
    .width(52)
    .height(52)
  }

  private fabButton(): ActionBarButton {
    return new ActionBarButton({
      width: LengthMetrics.vp(52),
      backgroundColor: ColorMetrics.resourceColor(Color.Transparent),
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
