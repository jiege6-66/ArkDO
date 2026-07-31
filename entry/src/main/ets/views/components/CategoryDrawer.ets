import { Log } from '../../services/logging/Log';
import { TopicCategory, TopicTag } from '../../models/Topic';
import { FeedDef, FeedKey, FeedPrefs } from '../../services/site/FeedPrefs';
import { SiteDef } from '../../services/site/SitePrefs';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { TagSuggestion, TopicService } from '../../services/topic/TopicService';
import {
  cloneTopicListQuery,
  createDefaultTopicListQuery,
  describeTopicListQuery,
  filterRequiresLogin,
  isDefaultTopicListQuery,
  sameTopicListQuery,
  TopicListQuery
} from '../../services/topic/TopicListQuery';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { ChoiceChip } from './ChoiceChip';
import {
  getCategoryColor,
  getCategoryIcon,
  getCategoryLogo,
  getTagColor,
  getTagIcon,
  resolveBadgeAssetUrl
} from './TopicBadgeUtils';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { SYS_BOTTOM_INSET_KEY, SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';

const LOG_TAG: string = '[ArkDO][Drawer]';
const ROW_HEIGHT: number = 48;
// 标签联想防抖:与搜索面板同一量级,避免每次击键都打 /tags/filter/search。
const TAG_DEBOUNCE_MS: number = 300;
// 两个 Tab 的下划线指示器:横向长出来的那一下。
const TAB_INDICATOR_MS: number = 180;
const TAB_CATEGORY: number = 0;
const TAB_TAG: number = 1;

// @Builder 收单个对象参数(ArkTS/Rollup 对多参数 @Builder 会报 Argument name clash)。
interface CategoryRowParams {
  category: TopicCategory;
  isChild: boolean;
  // 图标兜底用的父版块;顶级版块传自身。
  parent: TopicCategory;
}

interface TabParams {
  index: number;
  label: string;
  // >0 时在标签名后挂一个计数角标(当前只有「标签」页用得上)。
  badge: number;
}

/**
 * 首页筛选抽屉。
 *
 * 三块正交的条件:**过滤器**(最新/热门/排行榜/未读/新主题)× **版块** × **标签**
 * —— 对应 Discourse 的 filter × category × tag 三个维度,拼装规则见 TopicListQuery。
 * 抽屉里改的是一份草稿,点底部「查看结果」才回吐给首页去发请求;这样连点几个条件只打一次网络。
 *
 * 版块树和标签列表都很长(标签有几百个),所以用 Tab 切换让两者各占满滚动区,
 * 而不是上下堆叠——堆叠的话想选标签得先滚过整棵版块树。
 *
 * 「我的站点」不是筛选维度而是跳转入口,故单拎到滚动区之外、确认条正上方常驻:
 * 位置上与三块条件隔开,「点了立刻就走」的语义才不会和「暂存待确认」混在一起。
 */
@Component
export struct CategoryDrawer {
  // 窗口常驻全屏布局:抽屉高度铺满物理屏,内容自行避让状态栏/导航条。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  @StorageProp(SYS_BOTTOM_INSET_KEY) private sysBottomInset: number = 0;
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  isArkWebReady: boolean = false;
  // 分类异步加载,@Prop 才能在父组件更新后同步进抽屉(普通成员变量只在创建时赋值一次)。
  @Prop categories: TopicCategory[] = [];
  @Prop isLoggedIn: boolean = false;
  // 「我的站点」区是否显示(设置页开关);关掉后整区不渲染。
  @Prop sitesEntryEnabled: boolean = true;
  // 要展示的站点(已按 showInDrawer 过滤且有序);为空时只留标题行,点进管理页添加。
  @Prop sites: SiteDef[] = [];
  // 草稿条件:抽屉里的每一次勾选都改它。受控——状态由宿主(首页)持有,
  // 因为抽屉内容随开合挂载/卸载,草稿留在组件内部会被一起丢掉(与 expandedIds 同理)。
  @Prop @Watch('onDraftUpdated') draft: TopicListQuery = createDefaultTopicListQuery();
  // 当前真正生效的条件。用来判断草稿有没有实质改动:没改动就不该再打一次请求。
  @Prop applied: TopicListQuery = createDefaultTopicListQuery();
  onDraftChange: (next: TopicListQuery) => void = () => {};
  // 点「查看结果」:提交草稿并关抽屉。
  onApply: () => void = () => {};
  onClose: () => void = () => {};
  // 点了受限版块/需登录入口:交给宿主拉起登录。
  onRequireLogin: () => void = () => {};
  // 一句话提示(禁用项被点时解释原因)。
  onNotice: (message: string) => void = () => {};
  // 打开站点管理页。
  onOpenSites: () => void = () => {};
  // 打开某个站点(走通用 WebView 页,与帖子外链同一条链路)。siteId 用于缓存该站 favicon。
  onOpenSite: (url: string, title: string, siteId: string) => void = () => {};
  // 已展开的顶级版块 id。受控,理由同 draft。
  @Prop expandedIds: number[] = [];
  // 点展开箭头:只上报,由宿主增删。
  onToggleExpand: (categoryId: number) => void = () => {};

  @State private activeTab: number = TAB_CATEGORY;
  @State private tagQuery: string = '';
  @State private tagResults: TagSuggestion[] = [];
  @State private tagLoading: boolean = false;
  private tagDebounceTimer: number = -1;
  // 标签联想请求序号:丢弃过期响应。
  private tagSeq: number = 0;
  // 候选列表是否已经成功取过一次。标签联想不在 aboutToAppear 里预取——多数人开抽屉只是换个版块,
  // 每次开都白打一次 /tags/filter/search 不划算;推迟到真正切到标签页再取。失败时保持 false,下次切回来重试。
  private tagResultsLoaded: boolean = false;
  // 版块变了但当前不在标签页:候选的上下文已经过期,记个标记,切回标签页时再重取。
  private tagScopeDirty: boolean = false;

  aboutToDisappear(): void {
    this.clearTagDebounce();
  }

  build() {
    Column() {
      this.DrawerHeader()
      this.FilterSection()

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))
        .margin({ left: 16, right: 16 })

      this.ScopeTabBar()

      Scroll() {
        Column() {
          if (this.activeTab === TAB_CATEGORY) {
            this.CategoryTab()
          } else {
            this.TagTab()
          }
          Row().width('100%').height(12)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)

      // 「我的站点」:立即跳转,不受确认约束,故与三块条件之间用分割线隔开。
      if (this.sitesEntryEnabled) {
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.border'))
        this.SitesSection()
      }

      this.ConfirmBar()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.sysTopInset })
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ==================== 头部 ====================

  @Builder
  private DrawerHeader() {
    Row() {
      Text('筛选')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      // 「重置」只在草稿非默认时出现:全默认时它是个永远点不出效果的死按钮,不如不占位。
      if (!isDefaultTopicListQuery(this.draft)) {
        Text('重置')
          .fontSize(13)
          .fontColor($r('app.color.brand'))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.onDraftChange(createDefaultTopicListQuery());
          })
      }

      Row() {
        FaIconView({ icon: this.iconOf('xmark'), color: $r('app.color.text_secondary'), iconSize: 15 })
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onClose();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 14, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  // ==================== ① 过滤器 ====================

  @Builder
  private FilterSection() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.allFeeds(), (feed: FeedDef) => {
          ChoiceChip({
            label: feed.label,
            selected: this.draft.filter === feed.key,
            chipDisabled: this.isFilterBlocked(feed.key),
            onTap: () => {
              this.setFilter(feed.key);
            },
            onBlockedTap: () => {
              this.onNotice('登录后可查看该入口');
            }
          })
        }, (feed: FeedDef) => `f${feed.key}`)
      }
      .width('100%')
    }
    .width('100%')
    // chips 自带 bottom margin 8,底部这里就不再补,否则与下面的分割线之间会空一大截。
    .padding({ left: 16, right: 16, top: 2 })
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== ②③ Tab ====================

  @Builder
  private ScopeTabBar() {
    Row() {
      this.ScopeTab({ index: TAB_CATEGORY, label: '版块', badge: this.draft.category !== undefined ? -1 : 0 })
      this.ScopeTab({ index: TAB_TAG, label: '标签', badge: this.draft.tag !== undefined ? -1 : 0 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  // 指示器不做左右滑动而是「原地横向长出来」:滑动需要写死 Tab 宽度,抽屉宽度一变就错位;
  // scaleX 由各自的单元格自己插值,与布局宽度无关。
  @Builder
  private ScopeTab(p: TabParams) {
    Column() {
      Row() {
        Text(p.label)
          .fontSize(14)
          .fontWeight(this.activeTab === p.index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.activeTab === p.index ? $r('app.color.brand') : $r('app.color.text_secondary'))

        // badge > 0 显数字;= -1 表示「已选但没有计数」(版块只能选一个),显一个小圆点。
        if (p.badge > 0) {
          Text(`${p.badge}`)
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.brand'))
            .borderRadius(7)
            .constraintSize({ minWidth: 14 })
            .height(14)
            .textAlign(TextAlign.Center)
            .padding({ left: 4, right: 4 })
            .margin({ left: 5 })
        } else if (p.badge < 0) {
          Circle()
            .width(6)
            .height(6)
            .fill($r('app.color.brand'))
            .margin({ left: 5 })
        }
      }
      .height(38)
      .alignItems(VerticalAlign.Center)

      Row()
        .width(24)
        .height(2)
        .borderRadius(1)
        .backgroundColor($r('app.color.brand'))
        .opacity(this.activeTab === p.index ? 1 : 0)
        .scale({ x: this.activeTab === p.index ? 1 : 0.2 })
        .animation({ duration: TAB_INDICATOR_MS, curve: Curve.EaseOut })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.switchTab(p.index);
    })
  }

  private switchTab(index: number): void {
    this.activeTab = index;
    if (index !== TAB_TAG || (this.tagResultsLoaded && !this.tagScopeDirty)) {
      return;
    }
    this.tagScopeDirty = false;
    this.clearTagDebounce();
    // q 为空即「取热门标签前 limit 个」,一切过来就有候选可点,不用先猜着打字。
    this.loadTagSuggestions(this.tagQuery.trim());
  }

  // ==================== ② 版块 ====================

  @Builder
  private CategoryTab() {
    Column() {
      this.AllCategoriesRow()

      // 版块树的筛选统一走 CategoryIndex,与发帖分类选择器共用同一套(避免两处规则漂移)。
      ForEach(this.topLevelCategories(), (topCat: TopicCategory) => {
        // 顶级版块自身作图标兜底(getCategoryIcon 先看自身、再看父,自作父为无副作用空操作)。
        this.CategoryRow({ category: topCat, isChild: false, parent: topCat })
        if (this.isExpanded(topCat.id)) {
          ForEach(this.childrenOf(topCat.id), (child: TopicCategory) => {
            this.CategoryRow({ category: child, isChild: true, parent: topCat })
          }, (child: TopicCategory) => `c${child.id}`)
        }
      }, (topCat: TopicCategory) => `p${topCat.id}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 「全部版块」= 取消版块限定。确认制下必须有这么一项,否则选错了版块没法退回全站。
  @Builder
  private AllCategoriesRow() {
    Row() {
      Row() {
        FaIconView({
          icon: this.iconOf('layer-group'),
          color: this.draft.category === undefined ? $r('app.color.brand') : $r('app.color.text_secondary'),
          iconSize: 14
        })
      }
      .width(18)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })

      Text('全部版块')
        .fontSize(15)
        .fontWeight(this.draft.category === undefined ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.draft.category === undefined ? $r('app.color.brand') : $r('app.color.text_primary'))
        .layoutWeight(1)

      if (this.draft.category === undefined) {
        FaIconView({ icon: this.iconOf('check'), color: $r('app.color.brand'), iconSize: 13 })
      }
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 12, right: 16 })
    .backgroundColor(this.draft.category === undefined ? $r('app.color.surface_muted') : Color.Transparent)
    .onClick(() => {
      this.setCategory(undefined);
    })
  }

  @Builder
  private CategoryRow(p: CategoryRowParams) {
    Row() {
      // 前导图标:与帖子列表分类徽章同款——图标 → 上传 logo → 兜底色点(子版块回退父版块)。
      Row() {
        if (getCategoryIcon(p.category, p.parent)) {
          FaIconView({
            icon: getCategoryIcon(p.category, p.parent) as FaIconDefinition,
            color: getCategoryColor(p.category),
            iconSize: 15
          })
        } else if (getCategoryLogo(p.category, p.parent).length > 0) {
          Image(resolveBadgeAssetUrl(getCategoryLogo(p.category, p.parent)))
            .width(15)
            .height(15)
            .objectFit(ImageFit.Contain)
        } else {
          Circle()
            .width(11)
            .height(11)
            .fill(getCategoryColor(p.category))
        }
      }
      .width(18)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })

      Text(p.category.name)
        .fontSize(p.isChild ? 14 : 15)
        .fontWeight(this.isCategorySelected(p.category.id) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.isCategorySelected(p.category.id) ? $r('app.color.brand') : $r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.isRestricted(p.category)) {
        FaIconView({ icon: this.iconOf('lock'), color: $r('app.color.text_faint'), iconSize: 12 })
          .margin({ left: 6, right: 4 })
      } else if (this.isCategorySelected(p.category.id)) {
        FaIconView({ icon: this.iconOf('check'), color: $r('app.color.brand'), iconSize: 13 })
          .margin({ left: 6 })
      }

      if (!p.isChild && this.hasChildren(p.category.id)) {
        // 箭头单独热区:点它只折叠/展开子版块,不选中该版块(行其余部分才是「选它」)。
        // 热区做宽(整行高 × 56)且右移贴边,减少与「选中版块」的误触。
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.text_faint')])
            .rotate({ angle: this.isExpanded(p.category.id) ? 90 : 0 })
        }
        .height('100%')
        .width(56)
        .margin({ right: -16 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onToggleExpand(p.category.id);
        })
      }
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: p.isChild ? 28 : 12, right: 16 })
    .opacity(this.isRestricted(p.category) ? 0.45 : 1)
    .backgroundColor(this.isCategorySelected(p.category.id) ? $r('app.color.surface_muted') : Color.Transparent)
    .onClick(() => {
      this.handleCategoryTap(p.category);
    })
  }

  // ==================== ③ 标签 ====================

  @Builder
  private TagTab() {
    Column({ space: 10 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(14)
          .fontColor([$r('app.color.text_tertiary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .margin({ right: 8 })
        TextInput({ text: $$this.tagQuery, placeholder: '搜索标签' })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({ left: 0, right: 0, top: 8, bottom: 8 })
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .onChange((value: string) => {
            this.handleTagQueryChanged(value);
          })
        if (this.tagLoading) {
          LoadingProgress().width(16).height(16).color($r('app.color.brand'))
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(10)
      .alignItems(VerticalAlign.Center)

      // 标签是单选(linux.do 的标签过滤不支持多选),所以「已选」这里最多一个 chip,点 ✕ 即取消。
      if (this.draft.tag !== undefined) {
        Row() {
          Text('已选')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Flex({ wrap: FlexWrap.Wrap }) {
          ChoiceChip({
            label: (this.draft.tag as TopicTag).name,
            removable: true,
            iconId: this.tagIconId((this.draft.tag as TopicTag).name),
            iconColor: this.tagIconColor((this.draft.tag as TopicTag).name),
            onTap: () => {
              this.setTag(undefined);
            }
          })
        }
        .width('100%')
      }

      if (this.tagResults.length === 0 && !this.tagLoading) {
        Text(this.tagQuery.trim().length > 0 ? '没有匹配的标签' : '暂无可选标签')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
      } else if (this.tagResults.length > 0) {
        Column() {
          ForEach(this.tagResults, (tag: TagSuggestion) => {
            Row() {
              // 标签自己的专属图标(与帖子卡片上的标签徽章同一套);没登记过图标的标签退回通用小标签图标,
              // 图标位始终占着,候选列表的文字才是齐的。
              FaIconView({
                icon: this.iconOf(this.tagIconId(tag.name)),
                color: getTagColor(tag.name),
                iconSize: 12
              })
                .margin({ right: 8 })
              Text(tag.name)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`×${tag.count}`)
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .height(40)
            .padding({ left: 12, right: 12 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.pickTag(tag);
            })
          }, (tag: TagSuggestion) => `tr${tag.id}`)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(10)
        .clip(true)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 站点入口 / 确认条 ====================

  /**
   * 「我的站点」:标题行进管理页,下挂一条横滑的站点快捷条,点一个直达。
   *
   * 快捷条带站名而不是只放 favicon —— 不少站点根本抓不到 favicon,只放图标的话它们会全部退化成
   * 同一个通用链接图标,彼此认不出来。横滑也避免了站点多时把抽屉底部越撑越高。
   */
  @Builder
  private SitesSection() {
    Column() {
      // 前导图标撑出与版块行相同的 18+10 图标位,标题因此与版块名竖直对齐;
      // 右侧 chevron 表明点进去是另一个页面。
      Row() {
        Row() {
          FaIconView({ icon: this.iconOf('earth-americas'), color: $r('app.color.text_secondary'), iconSize: 15 })
        }
        .width(18)
        .justifyContent(FlexAlign.Center)
        .margin({ right: 10 })

        Text('我的站点')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.text_faint')])
      }
      .width('100%')
      .height(this.sites.length > 0 ? 38 : 44)
      .padding({ left: 12, right: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onOpenSites();
      })

      if (this.sites.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            // key 并入 iconUri:favicon 是站点打开后才落盘的,id 不变会复用旧行、图标刷不上屏。
            ForEach(this.sites, (site: SiteDef) => {
              this.SiteChip(site)
            }, (site: SiteDef) => `s${site.id}_${site.iconUri}`)
          }
          .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Start)
        .margin({ bottom: 8 })
      }
    }
    .width('100%')
  }

  @Builder
  private SiteChip(site: SiteDef) {
    Row({ space: 6 }) {
      if (site.iconUri.length > 0) {
        // 抓到的 favicon 原样显示,不套 Template 染色——站点 logo 多是彩色的,染了就废了。
        Image(site.iconUri)
          .width(14)
          .height(14)
          .objectFit(ImageFit.Contain)
          .borderRadius(3)
      } else {
        FaIconView({ icon: this.iconOf('link'), color: $r('app.color.text_faint'), iconSize: 12 })
      }
      Text(site.name)
        .fontSize(12)
        .fontColor($r('app.color.text_body'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(28)
    .constraintSize({ maxWidth: 140 })
    .padding({ left: 9, right: 11 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(14)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onOpenSite(site.url, site.name, site.id);
    })
  }

  @Builder
  private ConfirmBar() {
    Column({ space: 8 }) {
      Text(describeTopicListQuery(this.draft))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 草稿与生效中的一致时没有请求可发,按钮改成「关闭」——比置灰一个死按钮更有用。
      Button(this.isDirty() ? '查看结果' : '关闭')
        .width('100%')
        .height(42)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDirty() ? Color.White : $r('app.color.text_secondary'))
        .backgroundColor(this.isDirty() ? $r('app.color.brand') : $r('app.color.surface_muted'))
        .borderRadius(12)
        .onClick(() => {
          if (this.isDirty()) {
            this.onApply();
            return;
          }
          this.onClose();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 + this.sysBottomInset })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.page_bg'))
    .border({ width: { top: 0.5 }, color: $r('app.color.border') })
  }

  // ==================== 交互 ====================

  private setFilter(key: string): void {
    const next: TopicListQuery = cloneTopicListQuery(this.draft);
    next.filter = key;
    this.onDraftChange(next);
  }

  private setCategory(category: TopicCategory | undefined): void {
    const next: TopicListQuery = cloneTopicListQuery(this.draft);
    next.category = category;
    this.onDraftChange(next);
    // 版块变了,标签候选的上下文跟着变(/tags/filter/search 带 categoryId 后只回该版块下的标签)。
    // 但选版块是抽屉里最高频的动作,不能每点一下就打一次联想请求——不在标签页时只记脏,切过去再取。
    if (this.activeTab !== TAB_TAG) {
      this.tagScopeDirty = true;
      return;
    }
    this.clearTagDebounce();
    this.loadTagSuggestions(this.tagQuery.trim(), category);
  }

  private setTag(tag?: TopicTag): void {
    const next: TopicListQuery = cloneTopicListQuery(this.draft);
    next.tag = tag;
    this.onDraftChange(next);
  }

  // 标签单选:点候选即替换掉当前选中的那个(不是追加)。
  private pickTag(suggestion: TagSuggestion): void {
    this.setTag({ id: suggestion.id, name: suggestion.name });
    this.tagQuery = '';
    this.clearTagDebounce();
    this.loadTagSuggestions('');
  }

  private handleCategoryTap(category: TopicCategory): void {
    // 受限版块:拉起登录;否则选中它(顶级版块本身也可选,展开靠右侧箭头独立热区)。
    if (this.isRestricted(category)) {
      this.onRequireLogin();
      return;
    }
    this.setCategory(category);
  }

  // 草稿从外部换掉后(重置、宿主同步),候选列表里已选中的那些要重新剔除。
  // 每次改条件(包括只点了个过滤器)都会走到这里,所以先看有没有真要剔的,没有就别重建数组白刷一次。
  private onDraftUpdated(): void {
    const kept: TagSuggestion[] =
      this.tagResults.filter((tag: TagSuggestion) => !this.isTagSelected(tag.name));
    if (kept.length !== this.tagResults.length) {
      this.tagResults = kept;
    }
  }

  private handleTagQueryChanged(value: string): void {
    this.tagQuery = value;
    this.clearTagDebounce();
    // 清空输入不是「没有候选」,而是回到默认的热门标签列表。
    this.tagDebounceTimer = setTimeout(() => {
      this.tagDebounceTimer = -1;
      this.loadTagSuggestions(value.trim());
    }, TAG_DEBOUNCE_MS);
  }

  // category 显式传入而不读 this.draft:setCategory 里调用时 draft 还没被宿主回传更新。
  private async loadTagSuggestions(query: string, category?: TopicCategory): Promise<void> {
    if (!this.isArkWebReady) {
      return;
    }
    const scope: TopicCategory | undefined = category !== undefined ? category : this.draft.category;
    const seq: number = this.tagSeq + 1;
    this.tagSeq = seq;
    this.tagLoading = true;

    const service: TopicService = new TopicService(this.bridge);
    // 选了版块就带 categoryId:几百个标签里只留该版块下的那些,标签区才谈得上可用。
    const result: NetworkResult<TagSuggestion[]> = scope !== undefined
      ? await service.searchTags(scope.id, query, [])
      : await service.searchTagsSiteWide(query, []);

    if (seq !== this.tagSeq) {
      return;
    }
    this.tagLoading = false;
    if (result.success && result.data) {
      // 已选中的标签不再出现在候选里。
      this.tagResults = result.data.filter((tag: TagSuggestion) => !this.isTagSelected(tag.name));
      this.tagResultsLoaded = true;
      return;
    }
    this.tagResults = [];
    Log.i(`${LOG_TAG} tag suggest failed status=${result.statusCode}`);
  }

  private clearTagDebounce(): void {
    if (this.tagDebounceTimer >= 0) {
      clearTimeout(this.tagDebounceTimer);
      this.tagDebounceTimer = -1;
    }
  }

  // ==================== 数据 ====================

  private isTagSelected(name: string): boolean {
    return this.draft.tag !== undefined && this.draft.tag.name === name;
  }

  // 标签徽章的图标 id:登记过专属图标就用它,没有则退回通用小标签图标(图标位不留空)。
  private tagIconId(name: string): string {
    const icon: FaIconDefinition | undefined = getTagIcon(name);
    return icon !== undefined ? icon.id : 'tag';
  }

  // 没有专属图标时回空串,让通用小标签图标跟着 chip 的文字色走——固定的灰色配在选中态的蓝字旁边会脏。
  private tagIconColor(name: string): string {
    return getTagIcon(name) !== undefined ? getTagColor(name) : '';
  }

  // 五个入口全显、不再由设置页勾选:改成 chips 之后它们只占两行,没有裁剪的必要,
  // 而原先那份配置的默认值是空数组,反倒让新用户只看得到一枚「最新」。
  //
  // 未登录的入口也是「置灰可点」而非隐藏:一排 chips 里凭空少两个,用户分不清是没这功能还是没登录。
  private allFeeds(): FeedDef[] {
    return [FeedPrefs.latestFeed()].concat(FeedPrefs.optionalFeeds());
  }

  // 目前唯一的禁用理由是未登录。置灰而非隐藏,再配上点击时的这句提示,用户才分得清
  // 「没有这个功能」和「没登录」。
  private isFilterBlocked(key: string): boolean {
    return filterRequiresLogin(key) && !this.isLoggedIn;
  }

  private isDirty(): boolean {
    return !sameTopicListQuery(this.draft, this.applied);
  }

  private topLevelCategories(): TopicCategory[] {
    return CategoryIndex.topLevelCategories(this.categories);
  }

  private childrenOf(parentId: number): TopicCategory[] {
    return CategoryIndex.childrenOf(this.categories, parentId);
  }

  private hasChildren(parentId: number): boolean {
    return CategoryIndex.hasChildren(this.categories, parentId);
  }

  private isExpanded(id: number): boolean {
    return this.expandedIds.indexOf(id) >= 0;
  }

  private isRestricted(category: TopicCategory): boolean {
    return category.readRestricted === true && !this.isLoggedIn;
  }

  private isCategorySelected(id: number): boolean {
    return this.draft.category !== undefined && this.draft.category.id === id;
  }

  // FaIcon 取不到时给个同名兜底,免得每处都写 undefined 判断(FaIconView 自己会处理缺资源)。
  private iconOf(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def !== undefined ? def : { id: name, rawfilePath: `fa_icons/${name}.svg` };
  }
}
