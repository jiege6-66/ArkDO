import { TopicCategory, TopicTag } from '../../models/Topic';
import { TopicMetadataBadges } from './TopicBadges';

// 详情页 HDS 标题栏的自定义中间内容。返回键与右侧菜单由 HdsNavigation 原生区域绘制；
// 本组件只负责双层标题及其左右占位。两种标题内容始终挂载、叠层显示,
// 靠 opacity+translate 随 summaryVisible 做淡入+竖向上滑切换:
// 摘要(标题/分类/标签)仍在视口内时显示静态标题「帖子详情」,滑出后切换为帖子标题与分类标签行。
@Component
export struct TopicDetailHeader {
  @Prop summaryVisible: boolean = true;
  // 标题与分类/标签随详情、站点元数据异步到达而变化 → 用 @Prop 保持与父组件同步刷新。
  @Prop title: string = '';
  @Prop showBadges: boolean = false;
  @Prop category: TopicCategory | undefined = undefined;
  @Prop parentCategory: TopicCategory | undefined = undefined;
  @Prop tags: TopicTag[] = [];
  // 已解决(有采纳答案):滚动后的帖子标题(图层 B)行首内联绿色 far-square-check 标记,与顶部摘要卡一致。
  @Prop solved: boolean = false;
  // 已收藏:图层 B 帖子标题最前内联灰色书签标记,排在已解决勾选框之前。
  @Prop bookmarked: boolean = false;
  // 点顶栏帖子标题回一楼。只在图层 B(帖子标题)显示时可点——摘要仍在视口内时一楼就在眼前,
  // 且那时显示的是「帖子详情」静态标题,点它没有意义(图层 B 的 hitTestBehavior 已天然做到这点)。
  onTitleClick: () => void = () => {};
  // 右侧原生过盾菜单出现时，为自定义标题预留同宽空间，避免标题伸到菜单按钮下面。
  @Prop showChallengeShortcut: boolean = false;

  build() {
    Row({ space: 8 }) {
      // stackBuilder 覆盖整条标题栏，需为 HDS 原生返回按钮留出不可点击的布局空间。
      Blank()
        .width(40)
        .height(40)

      Stack({ alignContent: Alignment.Start }) {
        // 图层 A:摘要在视口内时显示的静态标题「帖子详情」。
        Text('帖子详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.summaryVisible ? 1 : 0)
          .translate({ y: this.summaryVisible ? 0 : -8 })
          .hitTestBehavior(this.summaryVisible ? HitTestMode.Default : HitTestMode.None)
          .animation({ duration: 250, curve: Curve.EaseInOut })

        // 图层 B:摘要滑出后显示的帖子标题 + 分类/标签行。
        Column({ space: 2 }) {
          // 已解决时行首内联绿色勾选框标记(同摘要卡:烘 #090 的专用 SVG,ImageSpan 内联随文字排)。
          Text() {
            // 书签排在已解决之前:烘 #919191 专用 SVG,ImageSpan 内联随文字排。
            if (this.bookmarked) {
              ImageSpan($rawfile('fa_icons/bookmark-gray.svg'))
                .width(15)
                .height(15)
                .margin({ right: 5 })
                .verticalAlign(ImageSpanAlignment.CENTER)
            }
            if (this.solved) {
              ImageSpan($rawfile('fa_icons/far-square-check-green.svg'))
                .width(15)
                .height(15)
                .margin({ right: 5 })
                .verticalAlign(ImageSpanAlignment.CENTER)
            }
            Span(this.title)
          }
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.showBadges) {
            TopicMetadataBadges({
              category: this.category,
              parentCategory: this.parentCategory,
              tags: this.tags
            })
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .opacity(this.summaryVisible ? 0 : 1)
        .translate({ y: this.summaryVisible ? 8 : 0 })
        .hitTestBehavior(this.summaryVisible ? HitTestMode.None : HitTestMode.Default)
        .animation({ duration: 250, curve: Curve.EaseInOut })
        // 整行(标题 + 徽章)都是回一楼的热区。摘要可见时 hitTestBehavior 为 None,点不到,无需再判。
        .onClick(() => {
          this.onTitleClick();
        })
      }
      .layoutWeight(1)
      .alignContent(Alignment.Start)

      // 右侧按钮由 HdsNavigation.menu 绘制，这里仅做对称占位，不参与点击。
      if (this.showChallengeShortcut) {
        Blank()
          .width(40)
          .height(40)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .height(56)
    .padding({ left: 16, right: 16 })
  }
}
