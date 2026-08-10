import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { MdAction, MdActionKind } from '../../utils/markdownInsert';

/** 工具栏上的「非格式」动作。这些不改文本语法,而是拉起选择器再由页面插入结果。 */
export enum ToolbarSpecial {
  Image = 'image',
  Attachment = 'attachment',
  Media = 'media'
}

// 工具栏单个按钮:图标 id + 语义。action 有值走格式插入;special 有值走对应的上传回调。
interface ToolbarButton {
  iconId: string;
  action?: MdAction;
  special?: ToolbarSpecial;
}

// 工具栏按钮清单(顺序即展示顺序)。上传类按钮带 special 标记,其余携带 MdAction 由父级统一 apply。
const TOOLBAR_BUTTONS: ToolbarButton[] = [
  { iconId: 'image', special: ToolbarSpecial.Image },
  { iconId: 'video', special: ToolbarSpecial.Media },
  { iconId: 'file-arrow-up', special: ToolbarSpecial.Attachment },
  { iconId: 'bold', action: { kind: MdActionKind.Wrap, before: '**', after: '**', placeholder: '粗体' } },
  { iconId: 'italic', action: { kind: MdActionKind.Wrap, before: '_', after: '_', placeholder: '斜体' } },
  { iconId: 'quote-left', action: { kind: MdActionKind.LinePrefix, prefix: '> ' } },
  { iconId: 'code', action: { kind: MdActionKind.Wrap, before: '`', after: '`', placeholder: '代码' } },
  { iconId: 'file-code', action: { kind: MdActionKind.InsertCursor, snippet: '```\n\n```', cursorOffset: 4, selectLength: 0 } },
  { iconId: 'list-ul', action: { kind: MdActionKind.LinePrefix, prefix: '- ' } },
  { iconId: 'list-ol', action: { kind: MdActionKind.LinePrefix, ordered: true } },
  { iconId: 'hashtag', action: { kind: MdActionKind.LinePrefix, prefix: '# ' } },
  { iconId: 'link', action: { kind: MdActionKind.Wrap, before: '[', after: '](url)', placeholder: '链接文字' } }
];

// Markdown 快捷工具栏:一排图标,点击插入对应语法。横向可滚,轻量态与全屏态复用同一组件。
// 与文本无关——只发出「要做什么」(onAction / onUpload),文本改写由持有 TextAreaController 的页面完成。
@Component
export struct MarkdownToolbar {
  // 图标颜色(默认次要文字色);随主题走。
  tintColor: ResourceColor = $r('app.color.text_secondary');
  // 下面三个必须是 @Prop 而不是普通属性:自定义组件的普通属性只在**创建时**从父级取一次,
  // 父级后续重渲染不会同步(本项目在 ComposerPage 的分类图标上踩过同一个坑)。
  // showAttachment 尤其致命——它开局是 false,等站点设置拉回来才翻真,不同步就永远不出现。
  //
  // 上传是否进行中:置灰全部上传按钮避免重复触发。
  @Prop disabled: boolean = false;
  /**
   * 附件按钮是否显示。站点一个非图片扩展名都不允许(Discourse 默认白名单就是纯图片)时藏掉 ——
   * 留着只会让用户点开选择器发现没有任何文件类型可选。
   */
  @Prop showAttachment: boolean = true;
  /** 音视频按钮是否显示。由 SiteCapabilities.mediaUpload 决定,只在 linux.do 露出。 */
  @Prop showMedia: boolean = false;
  onAction: (action: MdAction) => void = (action: MdAction) => {};
  onUpload: (kind: ToolbarSpecial) => void = (kind: ToolbarSpecial) => {};

  private iconOf(id: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(id);
    return def ? def : { id: id, rawfilePath: `fa_icons/${id}.svg` };
  }

  // 当前该展示哪些按钮。按站点能力过滤,顺序不变。
  private visibleButtons(): ToolbarButton[] {
    const result: ToolbarButton[] = [];
    for (let index: number = 0; index < TOOLBAR_BUTTONS.length; index++) {
      const button: ToolbarButton = TOOLBAR_BUTTONS[index];
      if (button.special === ToolbarSpecial.Attachment && !this.showAttachment) {
        continue;
      }
      if (button.special === ToolbarSpecial.Media && !this.showMedia) {
        continue;
      }
      result.push(button);
    }
    return result;
  }

  private handleTap(button: ToolbarButton): void {
    const special: ToolbarSpecial | undefined = button.special;
    if (special !== undefined) {
      if (!this.disabled) {
        this.onUpload(special);
      }
      return;
    }
    if (button.action) {
      this.onAction(button.action);
    }
  }

  build() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(this.visibleButtons(), (button: ToolbarButton) => {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            FaIconView({
              icon: this.iconOf(button.iconId),
              color: this.tintColor,
              iconSize: 18
            })
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .opacity(button.special !== undefined && this.disabled ? 0.4 : 1)
          .onClick(() => {
            this.handleTap(button);
          })
        }, (button: ToolbarButton) => button.iconId)
      }
      .padding({ left: 8, right: 8 })
      .height(48)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(48)
    .align(Alignment.Start)
  }
}
