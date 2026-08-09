import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { Topic, TopicCategory } from '../../models/Topic';
import { User } from '../../models/User';
import { TopicListItem } from '../components/TopicListItem';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';
import {
  AVATAR_SIZE_MAX,
  AVATAR_SIZE_MIN,
  LINE_HEIGHT_RATIO_MAX,
  LINE_HEIGHT_RATIO_MIN,
  LINE_HEIGHT_RATIO_STEP,
  ROW_PADDING_MAX,
  ROW_PADDING_MIN,
  TITLE_FONT_SIZE_MAX,
  TITLE_FONT_SIZE_MIN,
  TITLE_FONT_WEIGHT_MEDIUM,
  TITLE_FONT_WEIGHT_REGULAR,
  TITLE_FONT_WEIGHT_SEMI_BOLD,
  TopicListStyle,
  TopicListStylePrefs
} from '../../common/theme/TopicListStylePrefs';

// 预览容器高度的初始估计值。首帧过后由两行实测高度取代,只用来避免第一帧塌成 0 高度闪一下。
const PREVIEW_FALLBACK_HEIGHT: number = 200;

// 字重档位:字体里真实存在的就这三档,故用分段按钮而非滑块。
interface FontWeightOption {
  label: string;
  value: number;
}

const FONT_WEIGHT_OPTIONS: FontWeightOption[] = [
  { label: '常规', value: TITLE_FONT_WEIGHT_REGULAR },
  { label: '中等', value: TITLE_FONT_WEIGHT_MEDIUM },
  { label: '加粗', value: TITLE_FONT_WEIGHT_SEMI_BOLD }
];

// 滑块行的入参。必须打成一个对象、且在调用点直接写成对象字面量:@Builder 只有「单参数 +
// 对象字面量」这一种形态是按引用传递,其余(含多参数)都按值传递,参数变了不会刷新 Builder 内部——
// 那样拖动时右上角的数值会僵在原地,点「恢复默认」滑块也不会归位。
interface SliderCellParams {
  label: string;
  valueLabel: string;
  value: number;
  min: number;
  max: number;
  step: number;
  // done=true 表示这次是松手或点击定位,而非拖动途中的连续回调,只有它为真才落盘。
  onSliderChange: (value: number, done: boolean) => void;
}

/**
 * 帖子列表样式设置页:调标题字号 / 字重 / 行高 / 行间距 / 头像大小,顶部固定预览区实时反映。
 *
 * 三处帖子列表(首页、搜索结果、已读列表)共用 TopicListItem,故这套设置对三处同时生效。
 *
 * 预览用的就是 TopicListItem 本体而不是另画一份仿制品:所见即所得,且日后改列表样式不会
 * 出现「预览和真实列表长得不一样」这种最难发现的偏差。
 *
 * 写盘时机:滑块 onChange 每帧都来,拖动中只更新 AppStorage(预览与真实列表即时跟手),
 * 松手(End/Click)才落盘,避免每帧 store.flush()。
 */
@Component
export struct TopicListStyleSettingsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  // 五个可调值的页内镜像:滑块要双向绑定,故各存一份 @State,变更后同步进 prefs。
  @State private titleFontSize: number = 17;
  @State private titleFontWeight: number = TITLE_FONT_WEIGHT_MEDIUM;
  @State private lineHeightRatio: number = 1.35;
  @State private rowPadding: number = 8;
  @State private avatarSize: number = 48;
  // 预览用的假数据:两条覆盖了列表上会出现的全部元素(内联图标、未读药丸、蓝点、
  // 多行标题、分类标签、时间),调任一项都能立刻看出影响面。
  @State private previewTopics: Topic[] = [];
  @State private previewHeight: number = PREVIEW_FALLBACK_HEIGHT;
  // 两行各自的实测高度。存成普通字段而非 @State:它只是 previewHeight 的中间量,
  // 自身变更不必触发重渲染(否则每次测量都白刷一帧)。
  private previewItemHeights: number[] = [0, 0];
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const style: TopicListStyle = TopicListStylePrefs.current();
    this.titleFontSize = style.titleFontSize;
    this.titleFontWeight = style.titleFontWeight;
    this.lineHeightRatio = style.lineHeightRatio;
    this.rowPadding = style.rowPadding;
    this.avatarSize = style.avatarSize;
    this.previewTopics = this.buildPreviewTopics();
  }

  // 卡片分组容器:无描边,靠灰底衬托。
  @Styles
  cardStyle() {
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Blank()
          .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))

        // 预览区固定在顶部不随控件滚走:调滑块时眼睛不必在页面上下找效果。
        this.PreviewCard()

        this.ControlsScroll()
      }
      .width('100%')
      .height('100%')
      .padding({ left: PAGE_MARGIN, right: PAGE_MARGIN })
      .alignItems(HorizontalAlign.Start)

      this.TitleBarOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg_gray'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // 宿主 Context 收口。getContext(this) 已废弃,统一从 UIContext 取,免得每个调用点各写一遍 cast。
  private hostContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  // ==================== Builder:预览 ====================

  @Builder
  private PreviewCard() {
    Column() {
      // TopicListItem 的根节点是 ListItem,只能挂在 List 下,故预览也得包一层 List。
      // 高度由两行回传的实测值相加得出——行高随设置项变,估不准。
      List() {
        ForEach(this.previewTopics, (topic: Topic, index: number) => {
          TopicListItem({
            topic: topic,
            category: index === 0 ? this.previewCategory() : undefined,
            contentHorizontalPadding: CARD_PADDING,
            onMeasured: (height: number) => {
              this.handlePreviewMeasured(index, height);
            }
          })
        }, (topic: Topic) => `${topic.id}`)
      }
      .width('100%')
      .height(this.previewHeight)
      .scrollBar(BarState.Off)
      // 预览不是可操作的列表:滑动手势要留给下面的控件区,别让人以为这里能翻。
      .enableScrollInteraction(false)
    }
    .cardStyle()
    // 行末的分割线正好压在卡片圆角上,不裁会溢出圆角。
    .clip(true)
    .margin({ top: 0 })
  }

  // ==================== Builder:控件 ====================

  @Builder
  private ControlsScroll() {
    Scroll(this.scroller) {
      Column() {
        Column() {
          this.SliderCell({
            label: '标题字号',
            valueLabel: `${this.titleFontSize}`,
            value: this.titleFontSize,
            min: TITLE_FONT_SIZE_MIN,
            max: TITLE_FONT_SIZE_MAX,
            step: 1,
            onSliderChange: (value: number, done: boolean) => {
              this.titleFontSize = TopicListStylePrefs.setTitleFontSize(value);
              this.persistIfDone(done);
            }
          })
          this.HairlineInset()
          this.FontWeightCell()
          this.HairlineInset()
          this.SliderCell({
            label: '行高',
            valueLabel: this.lineHeightRatio.toFixed(2),
            value: this.lineHeightRatio,
            min: LINE_HEIGHT_RATIO_MIN,
            max: LINE_HEIGHT_RATIO_MAX,
            step: LINE_HEIGHT_RATIO_STEP,
            onSliderChange: (value: number, done: boolean) => {
              this.lineHeightRatio = TopicListStylePrefs.setLineHeightRatio(value);
              this.persistIfDone(done);
            }
          })
          this.HairlineInset()
          this.SliderCell({
            label: '行间距',
            valueLabel: `${this.rowPadding}`,
            value: this.rowPadding,
            min: ROW_PADDING_MIN,
            max: ROW_PADDING_MAX,
            step: 1,
            onSliderChange: (value: number, done: boolean) => {
              this.rowPadding = TopicListStylePrefs.setRowPadding(value);
              this.persistIfDone(done);
            }
          })
          this.HairlineInset()
          this.SliderCell({
            label: '头像大小',
            valueLabel: `${this.avatarSize}`,
            value: this.avatarSize,
            min: AVATAR_SIZE_MIN,
            max: AVATAR_SIZE_MAX,
            step: 1,
            onSliderChange: (value: number, done: boolean) => {
              this.avatarSize = TopicListStylePrefs.setAvatarSize(value);
              this.persistIfDone(done);
            }
          })
        }
        .cardStyle()

        Text('设置对首页、搜索结果和已读列表同时生效。')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 10 })

        this.ResetButton()

        Row()
          .width('100%')
          .height(40)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  // 滑块行:标题 + 当前值在上,滑块与两端极值在下。两端标出极值,让人一眼知道还能调多少。
  // 入参见 SliderCellParams 上的注释——必须是单参数对象字面量,否则拖动时数值不刷新。
  @Builder
  private SliderCell(params: SliderCellParams) {
    Column() {
      Row() {
        Text(params.label)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(params.valueLabel)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
      }
      .width('100%')

      Row() {
        Text(`${params.min}`)
          .fontSize(11)
          .fontColor($r('app.color.text_faint'))
        Slider({
          value: params.value,
          min: params.min,
          max: params.max,
          step: params.step,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .selectedColor($r('app.color.ld_accent'))
          .trackThickness(4)
          .onChange((sliderValue: number, mode: SliderChangeMode) => {
            params.onSliderChange(sliderValue,
              mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        Text(`${params.max}`)
          .fontSize(11)
          .fontColor($r('app.color.text_faint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private FontWeightCell() {
    Column() {
      Text('标题字重')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row() {
        ForEach(FONT_WEIGHT_OPTIONS, (option: FontWeightOption) => {
          Text(option.label)
            .fontSize(14)
            .fontWeight(option.value)
            .fontColor(this.titleFontWeight === option.value
              ? $r('app.color.ld_accent') : $r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .backgroundColor(this.titleFontWeight === option.value
              ? $r('app.color.surface_muted') : Color.Transparent)
            .onClick(() => {
              this.titleFontWeight = TopicListStylePrefs.setTitleFontWeight(option.value);
              // 档位切换是离散动作,没有「拖动中」一说,当场落盘。
              TopicListStylePrefs.flush(this.hostContext());
            })
        }, (option: FontWeightOption) => `${option.value}`)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ResetButton() {
    Button('恢复默认')
      .fontSize(15)
      .fontColor($r('app.color.text_primary'))
      .backgroundColor($r('app.color.surface_card'))
      .width('100%')
      .height(48)
      .borderRadius(CARD_RADIUS)
      .margin({ top: CARD_GAP })
      .onClick(() => {
        const style: TopicListStyle = TopicListStylePrefs.resetDefaults(this.hostContext());
        this.titleFontSize = style.titleFontSize;
        this.titleFontWeight = style.titleFontWeight;
        this.lineHeightRatio = style.lineHeightRatio;
        this.rowPadding = style.rowPadding;
        this.avatarSize = style.avatarSize;
      })
  }

  @Builder
  private HairlineInset() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.border'))
      .margin({ left: CARD_PADDING, right: CARD_PADDING })
  }

  @Builder
  private TitleBarOverlay() {
    HdsNavigation() {
      Column()
        .width('100%')
        .height('100%')
    }
    .titleBar({
      avoidLayoutSafeArea: requiresHdsLayoutSafeAreaAvoidance(ImmersiveLightArea.TITLE_BAR),
      enableComponentSafeArea: requiresHdsComponentSafeArea(ImmersiveLightArea.TITLE_BAR),
      style: buildImmersiveTitleBarStyle(),
      content: {
        title: {
          mainTitle: '帖子列表样式'
        },
        backIcon: {
          icon: $r('sys.symbol.chevron_left'),
          label: '返回',
          action: () => {
            this.onBack();
          }
        }
      }
    })
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    // 只当标题栏容器用,不参与分栏(分栏由 RootTabPage 根 Navigation 负责)。默认 Auto 会在
    // 宽度 ≥600vp 时自切 Split——平板横屏右详情栏就会多出一条可拖的分割线,菜单也被挤到线左边。
    .mode(NavigationMode.Stack)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // ==================== 逻辑 ====================

  private persistIfDone(done: boolean): void {
    if (done) {
      TopicListStylePrefs.flush(this.hostContext());
    }
  }

  // 两行各自上报高度,累加即预览容器应有的高度。行高不依赖容器高度,故一轮测量即收敛。
  private handlePreviewMeasured(index: number, height: number): void {
    if (index < 0 || index >= this.previewItemHeights.length || height <= 0) {
      return;
    }
    if (Math.abs(this.previewItemHeights[index] - height) < 0.5) {
      return;
    }
    this.previewItemHeights[index] = height;
    const total: number = this.previewItemHeights[0] + this.previewItemHeights[1];
    if (total > 0) {
      this.previewHeight = Math.ceil(total);
    }
  }

  private previewCategory(): TopicCategory {
    return {
      id: 1,
      name: '资源分享',
      color: '0088CC',
      textColor: 'FFFFFF'
    };
  }

  // 预览作者不给 avatarTemplate:UserAvatar 找不到候选就回退首字母头像,预览页因此不发任何网络请求。
  private previewAuthor(username: string, displayName: string): User {
    return {
      id: 10000,
      username: username,
      displayName: displayName
    };
  }

  private buildPreviewTopics(): Topic[] {
    // 第一条:长标题(必然折行,行高才看得出来)+ 未读药丸 + 分类标签 + 时间。
    const withUnread: Topic = new Topic();
    withUnread.id = -1;
    withUnread.title = '这是一条用来预览的帖子标题，它足够长，好让你看清标题折行之后的行高与整体密度';
    withUnread.author = this.previewAuthor('demo_user', '示例用户');
    withUnread.tags = [{ name: '教程' }, { name: '实用工具' }];
    withUnread.categoryId = 1;
    withUnread.unreadPosts = 12;
    withUnread.lastPostedAt = new Date(Date.now() - 15 * 60 * 1000).toISOString();

    // 第二条:短标题 + 书签与已解决内联图标 + 蓝点,验证图标随字号缩放后是否还与文字对齐。
    const withMarks: Topic = new Topic();
    withMarks.id = -2;
    withMarks.title = '一条较短的帖子标题';
    withMarks.author = this.previewAuthor('arkdo', 'ArkDO');
    withMarks.bookmarked = true;
    withMarks.hasAcceptedAnswer = true;
    withMarks.unseen = true;
    withMarks.lastPostedAt = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString();

    return [withUnread, withMarks];
  }
}
