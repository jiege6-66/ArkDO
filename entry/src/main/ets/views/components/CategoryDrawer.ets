import { SiteCapabilities } from '../../services/site/SiteCapabilities';
import { Log } from '../../services/logging/Log';
import { TopicCategory, TopicTag } from '../../models/Topic';
import { SidebarTag } from '../../models/User';
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
// 展开/收起(分组手风琴与子版块)的时长。箭头旋转、内容淡入、后续行的位移必须共用同一个值,
// 否则就是箭头转完了内容才冒出来的那种「不同步」。
const EXPAND_MS: number = 180;
const TAB_CATEGORY: number = 0;
const TAB_TAG: number = 1;

// 两个 Tab 内部的手风琴分组:同时最多展开一组,点已展开的那组即两组全收。
// 只有「我的版块 / 我的标签」非空时手风琴才成立,否则整棵树/热门候选直接铺开(见 categoryAccordion/tagAccordion)。
const GROUP_NONE: number = -1;
const GROUP_MINE: number = 0;
const GROUP_ALL: number = 1;

// @Builder 收单个对象参数(ArkTS/Rollup 对多参数 @Builder 会报 Argument name clash)。
interface CategoryRowParams {
  category: TopicCategory;
  isChild: boolean;
  // 图标兜底用的父版块;顶级版块传自身。
  parent: TopicCategory;
}

// 标签行:「我的标签」「热门标签」「搜索结果」三处共用一个 Builder,故先归一成这个形状。
// id/slug 可缺(热门候选没有 slug、极端情况下连 id 都没有),拼路由时 tagSegment 会自行退回按名字。
interface TagRowParams {
  name: string;
  id?: number;
  slug?: string;
}

interface GroupHeaderParams {
  label: string;
  // 点击时要切哪个 Tab 的手风琴(TAB_CATEGORY / TAB_TAG)。
  tab: number;
  group: number;
  // 组内条数,收起时它是「这组里有什么」的唯一线索;为 0 时不显示(热门标签还没取回来的情形)。
  count: number;
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
  // 网页版侧栏自选的标签(current_user.sidebar_tags),置顶在标签页最前。空 = 未登录或没配置过。
  @Prop myTags: SidebarTag[] = [];
  // 同上,自选版块的 id(current_user.sidebar_category_ids)。只有 id,展示所需的名字/颜色去 categories 里查。
  @Prop myCategoryIds: number[] = [];
  // 「我的站点」区是否显示(设置页开关);关掉后整区不渲染。
  @Prop sitesEntryEnabled: boolean = true;
  // 要展示的站点(已按 showInDrawer 过滤且有序);为空时只留标题行,点进管理页添加。
  @Prop sites: SiteDef[] = [];
  // 草稿条件:抽屉里的每一次勾选都改它。受控——状态由宿主(首页)持有,
  // 因为抽屉内容随开合挂载/卸载,草稿留在组件内部会被一起丢掉(与 expandedIds 同理)。
  @Prop draft: TopicListQuery = createDefaultTopicListQuery();
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
  // 两个 Tab 各自的手风琴状态。默认展开「我的」:自选的那几个是高频入口,整棵树/热门候选收着,想翻再点。
  // 不提到宿主持有(与 draft/expandedIds 不同):每次开抽屉回到这个默认是想要的行为,
  // 而抽屉内容关闭即卸载,组件内 @State 正好天然复位。
  @State private categoryGroup: number = GROUP_MINE;
  @State private tagGroup: number = GROUP_MINE;
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
      // 与用户的显示开关取与:这功能靠复用主站 OAuth 免登录进生态站点,换站后无从谈起。
      if (this.sitesEntryEnabled && SiteCapabilities.ecosystemSites) {
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
    // 热门候选只在它真要显示时才取:手风琴默认收着热门组,一切过来就打一次请求是白打。
    if (index === TAB_TAG && this.hotListVisible()) {
      this.loadHotTagsIfNeeded();
    }
  }

  // 手风琴:点已展开的那组即收起(两组全收),点另一组即换过去。
  // 改状态包在 animateTo 里,后续行的位移才跟箭头旋转同一条曲线;内容自身的淡入见 expandTransition。
  private toggleGroup(tab: number, group: number): void {
    const next: number = this.isGroupOpen(tab, group) ? GROUP_NONE : group;
    this.getUIContext().animateTo({ duration: EXPAND_MS, curve: Curve.EaseOut }, () => {
      if (tab === TAB_CATEGORY) {
        this.categoryGroup = next;
        return;
      }
      this.tagGroup = next;
    });
    // 取候选放在动画外:请求回来得晚,和这段动画无关(列表刷新自己另起一次布局)。
    if (tab === TAB_TAG && next === GROUP_ALL) {
      this.loadHotTagsIfNeeded();
    }
  }

  // 子版块开合:与分组手风琴同一条动画,免得两种展开手感不一样。
  // 展开态由宿主持有(expandedIds),所以这里包着的是回调——状态变更在闭包内同步发生,能被动画捕获。
  private toggleExpand(categoryId: number): void {
    this.getUIContext().animateTo({ duration: EXPAND_MS, curve: Curve.EaseOut }, () => {
      this.onToggleExpand(categoryId);
    });
  }

  private isGroupOpen(tab: number, group: number): boolean {
    return (tab === TAB_CATEGORY ? this.categoryGroup : this.tagGroup) === group;
  }

  // q 为空即「取热门标签前 limit 个」,不用先猜着打字。已经取过且上下文没变就不再打。
  private loadHotTagsIfNeeded(): void {
    if (this.tagResultsLoaded && !this.tagScopeDirty) {
      return;
    }
    this.tagScopeDirty = false;
    this.clearTagDebounce();
    this.loadTagSuggestions(this.tagQuery.trim());
  }

  // ==================== ② 版块 ====================

  @Builder
  private CategoryTab() {
    Column() {
      this.AllCategoriesRow()

      // 有自选版块时两组走手风琴(同时只展开一组);没有就退回原样——整棵树直接铺开、不套分组标题,
      // 免得未登录的人对着两个空标题发愣。
      if (this.categoryAccordion()) {
        this.GroupHeader({
          label: '我的版块',
          tab: TAB_CATEGORY,
          group: GROUP_MINE,
          count: this.myCategories().length
        })
        if (this.isGroupOpen(TAB_CATEGORY, GROUP_MINE)) {
          Column() {
            this.MyCategoryList()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .transition(this.expandTransition())
        }

        this.GroupHeader({
          label: '所有版块',
          tab: TAB_CATEGORY,
          group: GROUP_ALL,
          count: this.topLevelCategories().length
        })
        if (this.isGroupOpen(TAB_CATEGORY, GROUP_ALL)) {
          Column() {
            this.CategoryTree()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .transition(this.expandTransition())
        }
      } else {
        this.CategoryTree()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 「我的版块」:网页版侧栏自选的那批,置顶一份。同一个版块在「所有版块」那棵树里还会再出现一次,
   * 这是有意的——置顶组是快捷方式,不是把版块从树里搬走(与 Discourse 侧栏的行为一致)。
   *
   * 展示逻辑与那棵树完全相同:主版块带展开箭头、子版块从箭头里出来。侧栏只勾主版块时
   * (linux.do 的常态)子版块并不在 sidebar_category_ids 里,靠这里补齐,否则置顶组就成了
   * 一串点不进子版块的死链。子版块展开态与树共用 expandedIds,两处同步开合是有意的。
   */
  @Builder
  private MyCategoryList() {
    ForEach(this.myCategories(), (category: TopicCategory) => {
      this.CategoryRow({ category: category, isChild: false, parent: this.parentOf(category) })
      if (this.isExpanded(category.id)) {
        Column() {
          ForEach(this.childrenOf(category.id), (child: TopicCategory) => {
            this.CategoryRow({ category: child, isChild: true, parent: category })
          }, (child: TopicCategory) => `mc${child.id}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .transition(this.expandTransition())
      }
    }, (category: TopicCategory) => `m${category.id}`)
  }

  // 版块树的筛选统一走 CategoryIndex,与发帖分类选择器共用同一套(避免两处规则漂移)。
  @Builder
  private CategoryTree() {
    ForEach(this.topLevelCategories(), (topCat: TopicCategory) => {
      // 顶级版块自身作图标兜底(getCategoryIcon 先看自身、再看父,自作父为无副作用空操作)。
      this.CategoryRow({ category: topCat, isChild: false, parent: topCat })
      if (this.isExpanded(topCat.id)) {
        Column() {
          ForEach(this.childrenOf(topCat.id), (child: TopicCategory) => {
            this.CategoryRow({ category: child, isChild: true, parent: topCat })
          }, (child: TopicCategory) => `c${child.id}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .transition(this.expandTransition())
      }
    }, (topCat: TopicCategory) => `p${topCat.id}`)
  }

  /**
   * 展开/收起时内容自身的过渡:淡入淡出。展开略慢于收起(180/140)——收起时用户已经决定不看了,
   * 拖着不走反而碍事。后续行的位移不靠这里,靠改状态时外面那层 animateTo(见 toggleGroup/toggleExpand)。
   */
  private expandTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: EXPAND_MS, curve: Curve.EaseOut }),
      TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseIn })
    );
  }

  /**
   * 分组标题(我的版块 / 所有版块 / 我的标签 / 热门标签)。左侧箭头指示展开态,整行都是热区。
   * 与版块行的箭头是两回事:那个开合子版块,这个开合整组。
   */
  @Builder
  private GroupHeader(p: GroupHeaderParams) {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.text_faint')])
          .rotate({ angle: this.isGroupOpen(p.tab, p.group) ? 90 : 0 })
          .animation({ duration: EXPAND_MS, curve: Curve.EaseOut })
      }
      .width(18)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })

      Text(p.label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      if (p.count > 0) {
        Text(`${p.count}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 12, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleGroup(p.tab, p.group);
    })
  }

  // 「不限版块」= 取消版块限定。确认制下必须有这么一项,否则选错了版块没法退回全站。
  // 名字刻意避开「全部/所有版块」:那是下面那个分组标题(=完整版块列表),两者一个是筛选值、一个是列表入口。
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

      Text('不限版块')
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
            .animation({ duration: EXPAND_MS, curve: Curve.EaseOut })
        }
        .height('100%')
        .width(56)
        .margin({ right: -16 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.toggleExpand(p.category.id);
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

  /**
   * 标签页。布局与交互一律对齐版块页:顶部一条「不限标签」= 取消限定,下面两组走同一套手风琴,
   * 每行也是同一种行(48 高、选中态高亮 + 右侧勾),不再用卡片包着的小行,也不再单独显示已选胶囊
   * ——选中态直接画在行上,和版块页看起来是一个东西。
   *
   * 只多一个搜索框:标签有几百个,没有搜索这一页就只剩「我的 + 热门 8 个」,够不着其余的。
   */
  @Builder
  private TagTab() {
    Column() {
      // 搜索框自己缩进 16(与筛选 chips 对齐);下面的行是通栏的,缩进由行内 padding 给,
      // 所以这里得单独包一层。包的是 Row + 内层 layoutWeight(1) 而不是 Column + width('100%'):
      // 后者实测会溢出抽屉右边缘 32vp —— 子节点的百分比宽度并不总按父容器内容区算,
      // 而 layoutWeight 是在 padding 之后分配剩余宽度的,与百分比语义无关。给 Row 加 margin 同理会溢出。
      Row() {
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
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(10)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 6 })

      this.AllTagsRow()

      // 有自选标签且没在搜索时走手风琴。搜索态一律直出结果:那时用户要的是搜出来的东西,
      // 再让他先点开一个分组纯属添堵。
      if (this.tagAccordion()) {
        this.GroupHeader({ label: '我的标签', tab: TAB_TAG, group: GROUP_MINE, count: this.myTags.length })
        // 「我的标签」不显示每个标签的计数——SidebarTagSerializer 不回 count,
        // 硬凑一个还得为每个标签单独打一次请求,不值得。
        if (this.isGroupOpen(TAB_TAG, GROUP_MINE)) {
          Column() {
            ForEach(this.myTags, (tag: SidebarTag) => {
              this.TagRow({ name: tag.name, id: tag.id, slug: tag.slug })
            }, (tag: SidebarTag) => `mt${tag.id !== undefined ? tag.id : tag.name}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .transition(this.expandTransition())
        }

        this.GroupHeader({
          label: '热门标签',
          tab: TAB_TAG,
          group: GROUP_ALL,
          count: this.hotTagResults().length
        })
      }

      // 手风琴开着时热门组要展开才画;搜索态/无自选标签时它就是唯一的列表,直接画。
      if (this.hotListVisible() && this.hotTagResults().length > 0) {
        Column() {
          ForEach(this.hotTagResults(), (tag: TagSuggestion) => {
            this.TagRow({ name: tag.name, id: tag.id, slug: undefined })
          }, (tag: TagSuggestion) => `tr${tag.id}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .transition(this.expandTransition())
      } else if (this.hotListVisible() && !this.tagLoading) {
        // 热门组收着时不出这句(hotListVisible 已经挡住):那时页面上明明有「我的标签」可点,
        // 「暂无可选标签」是句错话。展开了却取不到东西(请求失败/该版块下没标签)才该说这句。
        Text(this.tagQuery.trim().length > 0 ? '没有匹配的标签' : '暂无可选标签')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
      }
    }
    .width('100%')
    .padding({ top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  // 「不限标签」= 取消标签限定,与版块页的「不限版块」一一对应。
  // 原先这件事由顶部那枚「已选」胶囊上的 ✕ 负责,现在选中态画在行上,取消也回到行里。
  @Builder
  private AllTagsRow() {
    Row() {
      Row() {
        FaIconView({
          icon: this.iconOf('tags'),
          color: this.draft.tag === undefined ? $r('app.color.brand') : $r('app.color.text_secondary'),
          iconSize: 14
        })
      }
      .width(18)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })

      Text('不限标签')
        .fontSize(15)
        .fontWeight(this.draft.tag === undefined ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.draft.tag === undefined ? $r('app.color.brand') : $r('app.color.text_primary'))
        .layoutWeight(1)

      if (this.draft.tag === undefined) {
        FaIconView({ icon: this.iconOf('check'), color: $r('app.color.brand'), iconSize: 13 })
      }
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 12, right: 16 })
    .backgroundColor(this.draft.tag === undefined ? $r('app.color.surface_muted') : Color.Transparent)
    .onClick(() => {
      this.setTag(undefined);
    })
  }

  /**
   * 标签行。几何与选中态跟 CategoryRow 完全一致(48 高、18 宽图标位、选中即整行高亮 + 右侧勾),
   * 「我的标签」「热门标签」「搜索结果」三处共用。
   *
   * 不再显示 `×话题数`:版块行没有这一列,留着两页就长得不一样。热门程度本来也只是排序依据。
   */
  @Builder
  private TagRow(p: TagRowParams) {
    Row() {
      // 标签自己的专属图标(与帖子卡片上的标签徽章同一套);没登记过图标的退回通用小标签图标,
      // 图标位始终占着,文字才是齐的。
      Row() {
        FaIconView({
          icon: this.iconOf(this.tagIconId(p.name)),
          color: getTagColor(p.name),
          iconSize: 14
        })
      }
      .width(18)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })

      Text(p.name)
        .fontSize(15)
        .fontWeight(this.isTagSelected(p.name) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.isTagSelected(p.name) ? $r('app.color.brand') : $r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.isTagSelected(p.name)) {
        FaIconView({ icon: this.iconOf('check'), color: $r('app.color.brand'), iconSize: 13 })
      }
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 12, right: 16 })
    .backgroundColor(this.isTagSelected(p.name) ? $r('app.color.surface_muted') : Color.Transparent)
    .onClick(() => {
      // 与点版块同款语义:点即选中(单选,替换掉原来那个),不做「再点一次取消」——
      // 取消统一交给上面的「不限标签」,两页的退出方式因此也一致。
      this.setTag({ id: p.id, name: p.name, slug: p.slug });
    })
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
    // 但选版块是抽屉里最高频的动作,不能每点一下就打一次联想请求——热门候选此刻没在显示时
    // (不在标签页、或手风琴把热门组收着)只记脏,等它真要显示时再取。
    if (this.activeTab !== TAB_TAG || !this.hotListVisible()) {
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

  private handleCategoryTap(category: TopicCategory): void {
    // 受限版块:拉起登录;否则选中它(顶级版块本身也可选,展开靠右侧箭头独立热区)。
    if (this.isRestricted(category)) {
      this.onRequireLogin();
      return;
    }
    this.setCategory(category);
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

    // 「没输搜索词 + 没选版块」= 要的是站点热门标签,而不是一次联想查询。
    // 这份数据 /site.json 里就有(top_tags),而首页早已为版块树拉过那个接口 —— 直接读缓存,
    // 既省一次请求,又绕开 /tags/filter/search 的 max_tag_search_results 上限
    // (默认只有 5,超了整个请求会被拒,曾导致 meta.discourse.org 上「暂无可选标签」)。
    if (query.length === 0 && scope === undefined) {
      const top: TopicTag[] = CategoryIndex.topTags();
      if (top.length > 0) {
        this.tagSeq++;
        this.tagLoading = false;
        this.tagResults = CategoryDrawer.toSuggestions(top);
        this.tagResultsLoaded = true;
        return;
      }
      // 拿不到就照旧走联想接口兜底:站点信息可能还没加载完,或该站没开标签功能。
    }

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
      // 已选中的标签**不再**从候选里剔除:选中态现在画在行上(与版块行一致),
      // 剔掉反而让人以为标签消失了,而且选中项从列表里凭空抽走会让下面的行往上跳。
      this.tagResults = result.data;
      this.tagResultsLoaded = true;
      return;
    }
    this.tagResults = [];
    Log.i(`${LOG_TAG} tag suggest failed status=${result.statusCode}`);
  }

  // top_tags 只有 {id,name,slug},没有 count/description —— 抽屉的标签行只用到 name,
  // 缺的字段给零值即可,不必为此再查一遍。
  private static toSuggestions(tags: TopicTag[]): TagSuggestion[] {
    const list: TagSuggestion[] = [];
    for (let index: number = 0; index < tags.length; index++) {
      const tag: TopicTag = tags[index];
      list.push({ id: tag.id ?? 0, name: tag.name, text: tag.name, count: 0 });
    }
    return list;
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

  // 标签页的手风琴只在「有自选标签且没在搜索」时成立:一旦打了字,就该只剩搜索结果,
  // 两组并排会分不清哪个是搜出来的。
  // 注意自选标签与版块无关(sidebar_tags 是全站维度),选了版块也照常显示——代价是可能点出个空列表,
  // 但 Discourse 的 /tags/c/... 路由本身就允许这种交叉,隐藏掉反而让人以为功能丢了。
  private tagAccordion(): boolean {
    return this.myTags.length > 0 && this.tagQuery.trim().length === 0;
  }

  private categoryAccordion(): boolean {
    return this.myCategories().length > 0;
  }

  // 热门候选/搜索结果这一段此刻要不要显示。它同时是「该不该发请求」的判据:
  // 收在手风琴里没显示就不发,展开或进入搜索态时才发。
  private hotListVisible(): boolean {
    return !this.tagAccordion() || this.isGroupOpen(TAB_TAG, GROUP_ALL);
  }

  private isMyTag(name: string): boolean {
    return this.myTags.some((tag: SidebarTag) => tag.name === name);
  }

  // 热门候选里剔掉已经在「我的标签」里的那些,同一个标签不在两组各出现一次。
  // 搜索态不剔:那时手风琴不在场,再剔就等于搜不到自己的标签了。
  private hotTagResults(): TagSuggestion[] {
    if (!this.tagAccordion()) {
      return this.tagResults;
    }
    return this.tagResults.filter((tag: TagSuggestion) => !this.isMyTag(tag.name));
  }

  // sidebar_category_ids 只有 id,展示要的名字/颜色/父子关系去 /site.json 那份分类表里查(查不到的跳过);
  // 排序对齐网页版侧栏,规则见 CategoryIndex.sidebarOrdered。
  private myCategories(): TopicCategory[] {
    return CategoryIndex.sidebarOrdered(this.categories, this.myCategoryIds);
  }

  // 置顶组里的版块可能是子版块,图标兜底要拿它的父版块;取不到就用自身(getCategoryIcon 对此是空操作)。
  private parentOf(category: TopicCategory): TopicCategory {
    const parent: TopicCategory | undefined = CategoryIndex.find(this.categories, category.parentCategoryId);
    return parent !== undefined ? parent : category;
  }

  // 标签徽章的图标 id:登记过专属图标就用它,没有则退回通用小标签图标(图标位不留空)。
  private tagIconId(name: string): string {
    const icon: FaIconDefinition | undefined = getTagIcon(name);
    return icon !== undefined ? icon.id : 'tag';
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
