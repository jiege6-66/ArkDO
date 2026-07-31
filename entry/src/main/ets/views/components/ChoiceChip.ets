import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';

/**
 * 单选胶囊(chip)。首页筛选抽屉的过滤器区、已选标签区,以及搜索高级筛选面板共用同一套规格,
 * 免得两处各写一遍慢慢漂移。
 *
 * 规格(标准档 / compact 档):
 *  · 字号 14 / 13,行高 32 / 30,左右内边距 14 / 12,圆角 = 高度一半(正圆胶囊)
 *  · 选中 brand + info_soft_bg + Medium;未选 text_body + surface_muted + Regular
 *  · 禁用 text_tertiary + surface_muted + 整体 opacity 0.6,且不响应点击
 *
 * 选中态 brand on info_soft_bg 的对比度亮/暗色分别是 4.54:1 与 4.52:1,刚好压在 WCAG AA(4.5:1)线上。
 * 14 号字是正文字号必须过 AA —— 后面若有人觉得选中色扎眼想调浅,会直接掉出合规区间,别改。
 */
@Component
export struct ChoiceChip {
  // 这几个一律 @Prop:普通成员变量只在组件创建时被父组件赋值一次,之后父组件再更新也不会同步进来
  // ——选中态、禁用态都是点一下就变的东西,写成普通变量的话 chip 会点了不变色。
  @Prop label: string = '';
  @Prop selected: boolean = false;
  // 命名避开 ArkUI 的通用属性 .enabled(),免得读起来像在设置组件可用性。
  @Prop chipDisabled: boolean = false;
  // 紧凑档:密集的次级筛选(搜索面板)用,比标准档小一号。
  @Prop compact: boolean = false;
  // 尾部带 ✕ 的可移除形态(已选标签)。视觉上恒为选中态。
  @Prop removable: boolean = false;
  // 可选的前导图标:传 FaIcon 名(空 = 不画)。标签 chip 靠它把自己的专属图标带上,
  // 与帖子卡片上的标签徽章保持同一套视觉。
  @Prop iconId: string = '';
  // 图标色(十六进制)。空 = 跟随文字色。
  @Prop iconColor: string = '';
  onTap: () => void = () => {};
  // 禁用态被点时的出口。置灰本身只说明「现在不能选」,说不出为什么;
  // 未登录和「多标签只支持最新」两种限制都需要当场给一句话,否则用户只会觉得点不动。
  onBlockedTap: () => void = () => {};

  // 按下反馈。chips 的热区比整行小,没有按下态手感会发虚。
  @State private pressed: boolean = false;

  build() {
    Row({ space: this.removable ? 4 : 0 }) {
      if (this.iconId.length > 0) {
        FaIconView({
          icon: this.leadingIcon(),
          color: this.leadingIconColor(),
          iconSize: this.compact ? 10 : 11
        })
          .margin({ right: 5 })
      }

      Text(this.label)
        .fontSize(this.compact ? 13 : 14)
        .fontColor(this.chipForeground())
        .fontWeight(this.isHighlighted() ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.removable) {
        Text('✕')
          .fontSize(this.compact ? 10 : 11)
          .fontColor(this.chipForeground())
      }
    }
    .height(this.compact ? 30 : 32)
    // 带 ✕ 时右侧内边距收一点:✕ 本身已经贡献了视觉留白,照常给会显得右边空一块。
    .padding({
      left: this.compact ? 12 : 14,
      right: this.removable ? (this.compact ? 9 : 10) : (this.compact ? 12 : 14)
    })
    .margin({ right: 8, bottom: 8 })
    .backgroundColor(this.chipBackground())
    .borderRadius(this.compact ? 15 : 16)
    .opacity(this.chipDisabled ? 0.6 : (this.pressed ? 0.7 : 1))
    .alignItems(VerticalAlign.Center)
    .onTouch((event: TouchEvent) => {
      if (this.chipDisabled) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.chipDisabled) {
        this.onBlockedTap();
        return;
      }
      this.onTap();
    })
  }

  // FaIcon 取不到时给个同名兜底(FaIconView 自己会处理缺资源,不会崩)。
  private leadingIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(this.iconId);
    return def !== undefined ? def : { id: this.iconId, rawfilePath: `fa_icons/${this.iconId}.svg` };
  }

  private leadingIconColor(): ResourceColor {
    return this.iconColor.length > 0 ? this.iconColor : this.chipForeground();
  }

  private isHighlighted(): boolean {
    return (this.selected || this.removable) && !this.chipDisabled;
  }

  private chipForeground(): Resource {
    if (this.chipDisabled) {
      return $r('app.color.text_tertiary');
    }
    return this.isHighlighted() ? $r('app.color.brand') : $r('app.color.text_body');
  }

  private chipBackground(): Resource {
    return this.isHighlighted() ? $r('app.color.info_soft_bg') : $r('app.color.surface_muted');
  }
}
