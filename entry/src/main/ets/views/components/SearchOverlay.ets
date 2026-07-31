import { KeyboardAvoidMode } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { common } from '@kit.AbilityKit';
import { Log } from '../../services/logging/Log';
import { Topic, TopicCategory } from '../../models/Topic';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SearchResult, TopicService } from '../../services/topic/TopicService';
import { SearchHistoryStore } from '../../services/search/SearchHistoryStore';
import { SearchFilters } from '../../services/search/SearchFilters';
import {
  SEARCH_TYPE_OPTIONS,
  SEARCH_TYPE_TOPICS,
  SEARCH_TYPE_USERS,
  SearchTypeOption,
  searchTypeLabel,
  searchTypePlaceholder
} from '../../services/search/SearchScope';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { User } from '../../models/User';
import { UserProfileService } from '../../services/user/UserProfileService';
import { UserAvatar } from './UserAvatar';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { SearchFilterPanel } from './SearchFilterPanel';
import { TopicListItem } from './TopicListItem';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { IMMERSIVE_PANEL_BLUR_RADIUS } from '../../common/ui/ImmersiveLightMaterial';

const LOG_TAG: string = '[ArkDO][Search]';
// 搜索输入框焦点 id:挂载后 requestFocus 弹软键盘。
const INPUT_FOCUS_ID: string = 'arkdoSearchInput';
// 输入停顿多久才真正发起搜索(边打字边搜,避免每次击键都请求)。
const DEBOUNCE_MS: number = 350;
// 少于该字数不发起搜索。linux.do 单个汉字也能搜出结果(站点把 min_search_term_length 调低了),
// 所以这里只挡空串,别再自作主张要求两个字——真正过短由服务端 filter_short_terms 兜底。
const MIN_TERM_LEN: number = 1;
// Discourse 整页搜索分页硬上限。
const MAX_SEARCH_PAGE: number = 10;
// 搜索栏正文高度：Row 内部 40vp，顶部 16vp、底部 12vp。状态栏高度运行时另行叠加。
// 列表使用同一个数值作为 contentStartOffset，确保首项初始落在搜索栏下方；开始滚动后
// offset 会随内容一起离场，列表的真实视口仍可延伸到固定搜索栏后面。
const SEARCH_BAR_CONTENT_HEIGHT: number = 68;
// 用户搜索一次取多少条(/u/search/users 无分页,官方整页搜索用的也是 20)。
const USER_SEARCH_LIMIT: number = 20;
// 高级筛选面板高度:占屏高的固定比例(不用 SheetSize.LARGE——那个基本等于整页)。
const FILTER_SHEET_HEIGHT: string = '78%';

// 一镜到底共享元素 id:顶栏放大镜(源)与搜索页前导放大镜(目标)标同一 id,
// 由 RootTabPage.openSearch/closeSearch 的 animateTo 插值。
export const SEARCH_ICON_GEOMETRY_ID: string = 'arkdo-search-icon';

// 帖子搜索页:顶部搜索条 + 下方历史/结果。
// 键盘避让走系统 RESIZE(输入框在顶、结果区自动收缩),无需像评论浮层那样手动监听 avoidAreaChange。
@Component
export struct SearchOverlay {
  // 窗口常驻全屏布局:页面根列铺满整屏,搜索栏自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  isArkWebReady: boolean = false;
  onClose: () => void = () => {};
  onOpenTopic: (topic: Topic) => void = () => {};
  // 「用户」类型的结果点进去 → 交给 SearchFlow 走它已有的 onOpenUser(SearchFlow 对外接口不变)。
  onOpenUser: (user: User) => void = () => {};

  @State private query: string = '';
  // 搜索类型:话题/帖子(默认)与用户。两者走两个不同接口,见 SearchScope。
  @State private searchType: string = SEARCH_TYPE_TOPICS;
  // 「用户」类型的结果(话题结果仍在 results 里)。
  @State private userResults: User[] = [];
  // 高级筛选条件(分类/标签/@用户/时间/范围/状态/排序)。与关键词一起拼成 /search.json 的 q。
  // 面板里改的是草稿,点「应用」才整体换成新实例回到这里,随即触发一次重搜。
  @State private filters: SearchFilters = new SearchFilters();
  @State private filterSheetVisible: boolean = false;
  @State private results: Topic[] = [];
  @State private history: string[] = [];
  // 分类树:结果项复用 TopicListItem 渲染分类/标签徽标时按 categoryId 查名。
  @State private categories: TopicCategory[] = [];
  // 当前搜索词拆出的普通高亮词(去掉 in:/#/@ 等高级语法),用于摘要命中染色。
  @State private highlights: string[] = [];
  private categoryIndex: CategoryIndex = new CategoryIndex();
  @State private isSearching: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = false;
  @State private hasSearched: boolean = false;
  @State private errorMessage: string = '';
  @State private requiresChallenge: boolean = false;
  private currentPage: number = 1;
  private debounceTimer: number = -1;
  // 请求序号:边打字边搜时丢弃过期响应(只认最后一次)。
  private searchSeq: number = 0;
  private seenTopicIds: Set<number> = new Set();

  aboutToAppear(): void {
    // 输入框在顶、键盘在底:用系统 RESIZE 让结果区自动收缩,顶部搜索条不被顶走。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.history = SearchHistoryStore.load(this.hostContext());
    this.loadCategories();
    this.focusInput();
  }

  // 加载分类树(结果项徽标用);通常 HomePage 已加载并缓存,这里 loadIfNeeded 快速返回。
  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null =
      await this.categoryIndex.loadIfNeeded(this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  aboutToDisappear(): void {
    this.clearDebounce();
    this.hideKeyboard();
    // 还原默认避让,避免影响后续其它页面。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 内容区:关键词未达字数且没有任何筛选条件时显示历史,否则显示结果。
      Stack() {
        if (!this.canSearch()) {
          this.HistoryView()
        } else {
          this.ResultsView()
        }
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)

      // 搜索栏固定在结果列表上层。栏本身包含状态栏避让空间，并在同一节点执行背景采样、
      // 模糊和半透明着色；结果滚入这里时才会呈现连续的沉浸光感，而不是单独悬空的模糊带。
      this.SearchBar()
    }
    .width('100%')
    .height('100%')
    // 内容区使用与顶部半透明材质相同的 RGB 基色。静止时上下连成一个完整表面；
    // 列表滚入搜索栏后，顶部仍通过 backdropBlur 呈现内容变化，而不是变成纯实色栏。
    .backgroundColor($r('app.color.immersive_search_page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 固定单一高度,不给 detents。给两档高度的话,面板底部那排「取消/应用」是贴着
    // sheet 底边的,拖拽改变 sheet 高度时按钮会跟着上下跑,变矮的过程中还会被压出屏幕再弹回来。
    // 面板内容本来就交给内部 Scroll 滚,没必要再让整个 sheet 可缩放。
    .bindSheet($$this.filterSheetVisible, this.FilterSheet(), {
      // 固定高度、不给 detents:面板底部那排「取消/应用」是贴着 sheet 底边的,
      // 一旦可拖拽改变 sheet 高度,按钮就会跟着上下跑、变矮过程中还会被压出屏幕再弹回来。
      // 高度取屏高的 78%,顶上留一截背景透出来,不做成整页那样闷。
      height: FILTER_SHEET_HEIGHT,
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.filterSheetVisible = false;
      }
    })
  }

  @Builder
  private FilterSheet() {
    SearchFilterPanel({
      bridge: this.bridge,
      isArkWebReady: this.isArkWebReady,
      categories: this.categories,
      seed: this.filters,
      onApply: (next: SearchFilters) => {
        this.applyFilters(next);
      },
      onClose: () => {
        this.filterSheetVisible = false;
      }
    })
  }

  // 搜索栏只有输入行:生效的筛选条件不在结果页顶部铺一排胶囊,
  // 要改条件就再点一次「高级筛选」进面板调,省得结果区被条件条占掉一截。
  // 条件是否生效由筛选图标的高亮 + 角标条数体现。
  @Builder
  private SearchBar() {
    Column() {
      this.SearchBarRow()
    }
    .width('100%')
    .padding({ top: 16 + this.sysTopInset, bottom: 12 })
    // 普通 ArkUI 搜索栏没有 HDS 标题栏的 systemMaterialEffect。与评论输入栏一样,
    // 直接在可见覆盖层上模糊其后方列表,再叠加主题半透明底色;底部细高光只负责
    // 收住材质边缘,不再使用原来的 1vp 实色 Divider。
    .backdropBlur(IMMERSIVE_PANEL_BLUR_RADIUS)
    .backgroundColor($r('app.color.immersive_search_bar_bg'))
    .border({
      width: { bottom: 0.5 },
      color: $r('app.color.immersive_search_bar_highlight')
    })
  }

  @Builder
  private SearchBarRow() {
    Row({ space: 8 }) {
      // 输入容器:放大镜 + 输入框 + 清除。
      Row({ space: 8 }) {
        // 一镜到底目标:与顶栏源图标同 geometryTransition id,搜索页出现时由源飞入至此。
        FaIconView({ icon: this.searchIcon(), color: $r('app.color.text_tertiary'), iconSize: 16 })
          .geometryTransition(SEARCH_ICON_GEOMETRY_ID, { follow: true })
          .transition(TransitionEffect.OPACITY)

        TextInput({ text: $$this.query, placeholder: searchTypePlaceholder(this.searchType) })
          .id(INPUT_FOCUS_ID)
          .layoutWeight(1)
          // 给足够高度让内容区容得下整根光标;padding 归零(左侧紧贴放大镜)。
          // 加垂直 padding 反而缩小内容区、切光标;TextInput 单行又不支持 lineHeight 撑行盒。
          .height(40)
          .padding({ left: 0, right: 0, top: 0, bottom: 0 })
          .backgroundColor(Color.Transparent)
          // TextInput 默认自带圆角背景 + 默认裁剪到自身圆角;显式归零,排除默认圆角裁掉光标。
          .borderRadius(0)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .enterKeyType(EnterKeyType.Search)
          // 输入框默认会吞掉返回事件，导致边缘返回第一次只收键盘；放行给 @Entry 关闭 SearchFlow。
          .stopBackPress(false)
          .onChange((value: string) => {
            this.handleQueryChanged(value);
          })
          .onSubmit(() => {
            this.handleSubmit();
          })

        if (this.query.length > 0) {
          Text('✕')
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.clearQuery();
            })
        }

        // 输入框内右侧:竖线 → 高级筛选漏斗 → 类型入口。
        // 漏斗与类型是两个独立热区(漏斗开筛选面板,类型开下拉菜单),所以分成两个 Row。
        Divider()
          .vertical(true)
          .height(18)
          .color($r('app.color.border'))
          .margin({ left: 2, right: 2 })

        // 高级筛选入口(仅「帖子」有意义:用户搜索不走 /search.json 的高级语法)。
        // Stack 必须 Center 对齐——用 TopEnd 会把图标本身也顶到容器顶部,看着比旁边高一截;
        // 角标由 offset 从中心推到右上角。
        if (this.searchType === SEARCH_TYPE_TOPICS) {
          Stack({ alignContent: Alignment.Center }) {
            // 系统 symbol「漏斗」= 筛选,跟随主题与字重,不用再维护一份 FA 矢量图。
            SymbolGlyph($r('sys.symbol.funnel'))
              .fontSize(17)
              .fontColor([this.filters.hasAny() ? $r('app.color.brand') : $r('app.color.text_secondary')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            if (this.filters.hasAny()) {
              Text(`${this.filters.activeCount()}`)
                .fontSize(9)
                .fontColor(Color.White)
                .textAlign(TextAlign.Center)
                .constraintSize({ minWidth: 13 })
                .height(13)
                .padding({ left: 3, right: 3 })
                .backgroundColor($r('app.color.brand'))
                .borderRadius(7)
                .offset({ x: 10, y: -8 })
            }
          }
          .width(30)
          .height(34)
          .clip(false)
          .onClick(() => {
            this.hideKeyboard();
            this.filterSheetVisible = true;
          })
        }

        // 搜索类型入口。两种类型走两个不同接口(见 SearchScope)。
        Row({ space: 3 }) {
          Text(searchTypeLabel(this.searchType))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(11)
            .fontColor([$r('app.color.text_tertiary')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
        .height(34)
        .padding({ left: 2, right: 6 })
        .alignItems(VerticalAlign.Center)
        .bindMenu(this.SearchTypeMenu())
      }
      .layoutWeight(1)
      // 高度由 TextInput(含上下 padding)撑,minHeight 兜底;别硬设 height 压死输入框裁掉光标。
      .constraintSize({ minHeight: 40 })
      .padding({ left: 12, right: 4 })
      .backgroundColor($r('app.color.immersive_search_field_bg'))
      .borderRadius(10)
      .alignItems(VerticalAlign.Center)
      .clip(false)

      Text('取消')
        .fontSize(15)
        .fontColor($r('app.color.brand'))
        .onClick(() => {
          this.hideKeyboard();
          this.onClose();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SearchTypeMenu() {
    Menu() {
      ForEach(SEARCH_TYPE_OPTIONS, (option: SearchTypeOption) => {
        MenuItem({
          content: option.label,
          endIcon: this.searchType === option.value ? $r('sys.media.ohos_ic_public_ok') : undefined
        })
          // 用 onClick 而不是 onChange:onChange 是给带选中态的菜单项用的,
          // 这里只是「点一下切类型」的动作项,onClick 才稳。
          .onClick(() => {
            this.switchSearchType(option.value);
          })
      }, (option: SearchTypeOption) => `sty${option.value}`)
    }
  }

  @Builder
  private HistoryView() {
    if (this.history.length === 0) {
      Column() {
        Text('输入关键词搜索帖子')
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.searchBarBottomOffset() })
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        ListItem() {
          Row() {
            Text('搜索历史')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            Text('清空')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .onClick(() => {
                this.clearHistory();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 6 })
        }

        ForEach(this.history, (term: string) => {
          ListItem() {
            Row({ space: 10 }) {
              FaIconView({ icon: this.searchIcon(), color: $r('app.color.text_tertiary'), iconSize: 14 })
              Text(term)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('✕')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
                .width(28)
                .height(28)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  this.removeHistory(term);
                })
            }
            .width('100%')
            .height(46)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.applyHistoryTerm(term);
            })
          }
        }, (term: string) => term)
      }
      .width('100%')
      .height('100%')
      .contentStartOffset(this.searchBarBottomOffset())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      // 滑动历史列表也收起键盘。历史标题已成为第一个 ListItem，因此可以与条目一起
      // 穿入搜索栏后方，不会留下一个固定在材质下方的第二层标题。
      .onScrollStart(() => {
        this.hideKeyboard();
      })
    }
  }

  @Builder
  private ResultsView() {
    Stack() {
      List() {
        if (this.searchType === SEARCH_TYPE_USERS) {
          ForEach(this.userResults, (user: User) => {
            ListItem() {
              this.UserResultRow(user)
            }
          }, (user: User) => `su${user.username}`)
        } else {
          ForEach(this.results, (topic: Topic) => {
            TopicListItem({
              topic: topic,
              category: CategoryIndex.find(this.categories, topic.categoryId),
              parentCategory: CategoryIndex.findParent(this.categories, topic.categoryId),
              searchHighlights: this.highlights,
              onTopicClick: (selected: Topic) => {
                this.handleResultClick(selected);
              },
              onUnreadBadgeClick: (selected: Topic) => {
                this.handleResultClick(selected);
              }
            })
          }, (topic: Topic) => `${topic.id}`)

          // 只有话题搜索分页(/u/search/users 与 /tags/filter/search 都是一次性返回)。
          if (this.results.length > 0) {
            ListItem() {
              Row() {
                if (this.isLoadingMore) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color($r('app.color.brand'))
                    .margin({ right: 8 })
                }
                Text(this.hasMore ? '上拉加载更多' : '没有更多了')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .height(54)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
      }
      .width('100%')
      .height('100%')
      .contentStartOffset(this.searchBarBottomOffset())
      .padding({ left: 16, right: 16 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onReachEnd(() => {
        this.loadMore();
      })
      // 一开始滑动结果列表就收起键盘,别挡着看结果。
      .onScrollStart(() => {
        this.hideKeyboard();
      })

      // 首次搜索加载中(尚无结果)。
      if (this.isSearching && this.resultCount() === 0) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.searchBarBottomOffset() })
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      } else if (this.errorMessage.length > 0 && this.resultCount() === 0) {
        Column() {
          Text(this.errorMessage)
            .fontSize(15)
            .fontColor($r('app.color.warning'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.searchBarBottomOffset() })
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      } else if (this.hasSearched && !this.isSearching && this.resultCount() === 0) {
        Column() {
          Text(this.emptyResultText())
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.searchBarBottomOffset() })
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  private UserResultRow(user: User) {
    Row({ space: 10 }) {
      UserAvatar({ user: user, avatarSize: 36 })
      Column({ space: 2 }) {
        Text(user.username)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (user.displayName !== undefined && user.displayName.length > 0) {
          Text(user.displayName)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.hideKeyboard();
      this.onOpenUser(user);
    })
  }

  // 切换搜索类型:清掉上一种类型的结果(接口不同、结构也不同),有词就立刻按新类型重搜。
  private switchSearchType(value: string): void {
    if (this.searchType === value) {
      return;
    }
    this.searchType = value;
    this.clearDebounce();
    this.resetResults();
    if (this.canSearch()) {
      this.runSearch(true);
    }
  }

  private resultCount(): number {
    if (this.searchType === SEARCH_TYPE_USERS) {
      return this.userResults.length;
    }
    return this.results.length;
  }

  private emptyResultText(): string {
    if (this.searchType === SEARCH_TYPE_USERS) {
      return '未找到相关用户';
    }
    return '未找到相关帖子';
  }

  // 输入变化:更新词、防抖后发起搜索;清空/过短且无筛选条件时回到历史态。
  private handleQueryChanged(value: string): void {
    this.query = value;
    this.clearDebounce();
    if (!this.canSearch()) {
      this.resetResults();
      return;
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.runSearch(true);
    }, DEBOUNCE_MS);
  }

  // 回车:立即搜索并记入历史(边打字边搜不写历史,只有主动提交/命中才留痕)。
  private handleSubmit(): void {
    this.clearDebounce();
    if (!this.canSearch()) {
      return;
    }
    this.saveHistory(this.trimmedQuery());
    this.runSearch(true);
  }

  // 应用筛选条件:换成新实例(值语义,驱动胶囊行与按钮角标刷新),关面板。
  // 没输关键词时不发搜索,而是把焦点交回输入框、弹出键盘等用户补词
  // (服务端其实允许「只有筛选条件」的搜索,但产品上要求先有关键词)。
  private applyFilters(next: SearchFilters): void {
    this.filters = next;
    this.filterSheetVisible = false;
    this.clearDebounce();
    if (this.trimmedQuery().length === 0) {
      this.focusInput();
      return;
    }
    if (!this.canSearch()) {
      this.resetResults();
      return;
    }
    this.runSearch(true);
  }

  // 能否发起搜索:必须有够长的关键词。筛选条件只负责收窄结果,不能单独成一次搜索。
  private canSearch(): boolean {
    return this.trimmedQuery().length >= MIN_TERM_LEN;
  }

  private handleResultClick(topic: Topic): void {
    // 点到结果算一次有效搜索,记入历史。
    this.saveHistory(this.trimmedQuery());
    this.hideKeyboard();
    this.onOpenTopic(topic);
  }

  private applyHistoryTerm(term: string): void {
    this.query = term;
    this.saveHistory(term);
    this.runSearch(true);
    // 点历史词已选定搜索目标,收起键盘让位给结果列表(不再 focusInput 弹键盘)。
    this.hideKeyboard();
  }

  // 收起软键盘:停当前输入会话(焦点可留在输入框,再次点击会重新弹出)。
  private hideKeyboard(): void {
    try {
      inputMethod.getController().stopInputSession();
    } catch (err) {
      // 收键盘失败不影响主流程。
    }
  }

  // 按当前搜索类型分派。三种类型是三个接口,只有话题搜索走 /search.json 与高级语法。
  private async runSearch(reset: boolean): Promise<void> {
    if (!this.canSearch()) {
      return;
    }
    if (!this.isArkWebReady) {
      this.errorMessage = '正在准备请求环境，请稍后重试';
      this.hasSearched = true;
      return;
    }
    if (this.searchType === SEARCH_TYPE_USERS) {
      await this.runUserSearch();
      return;
    }
    await this.runTopicSearch(reset);
  }

  // 用户搜索:GET /u/search/users?term=&limit=,一次性返回,无分页。
  private async runUserSearch(): Promise<void> {
    const term: string = this.trimmedQuery();
    const seq: number = this.searchSeq + 1;
    this.searchSeq = seq;
    this.isSearching = true;
    this.errorMessage = '';
    this.hasSearched = true;

    const result: NetworkResult<User[]> =
      await new UserProfileService(this.bridge).searchUsers(term, USER_SEARCH_LIMIT);

    if (seq !== this.searchSeq) {
      return;
    }
    this.isSearching = false;
    if (result.success && result.data) {
      this.userResults = result.data;
      this.errorMessage = '';
      return;
    }
    this.userResults = [];
    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.errorMessage = this.requiresChallenge ? '搜索遇到访问验证，请稍后重试' : '搜索失败，请检查网络后重试';
    Log.i(`${LOG_TAG} user search failed status=${result.statusCode}`);
  }

  private async runTopicSearch(reset: boolean): Promise<void> {
    const term: string = this.trimmedQuery();
    // 关键词与筛选条件拼成最终 q(语法对齐 Discourse 官方,见 SearchFilters)。
    const queryString: string = SearchFilters.buildQuery(term, this.filters);

    const page: number = reset ? 1 : this.currentPage + 1;
    const seq: number = this.searchSeq + 1;
    this.searchSeq = seq;

    if (reset) {
      this.isSearching = true;
      this.errorMessage = '';
      this.requiresChallenge = false;
      this.hasSearched = true;
      // 高亮词按本次搜索词定格(不随后续输入漂移;高级语法会被 parseHighlights 过滤掉)。
      this.highlights = this.parseHighlights(term);
    } else {
      this.isLoadingMore = true;
    }

    const service: TopicService = new TopicService(this.bridge);
    const result: NetworkResult<SearchResult> = await service.search(queryString, page);

    // 过期响应(用户已改词/翻页)直接丢弃。
    if (seq !== this.searchSeq) {
      return;
    }
    this.isSearching = false;
    this.isLoadingMore = false;

    if (result.success && result.data) {
      const hasMore: boolean = result.data.hasMore && page < MAX_SEARCH_PAGE;
      if (reset) {
        this.seenTopicIds = new Set();
        this.results = this.collect(result.data.topics);
      } else {
        this.results = this.results.concat(this.collect(result.data.topics));
      }
      this.currentPage = page;
      this.hasMore = hasMore;
      this.errorMessage = '';
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    if (reset) {
      this.errorMessage = this.requiresChallenge ? '搜索遇到访问验证，请稍后重试' : '搜索失败，请检查网络后重试';
    }
    Log.i(`${LOG_TAG} search failed page=${page} status=${result.statusCode} requiresChallenge=${this.requiresChallenge}`);
  }

  // 去重收集(同一主题不同页可能重复出现)。
  private collect(topics: Topic[]): Topic[] {
    const out: Topic[] = [];
    for (let index: number = 0; index < topics.length; index++) {
      const topic: Topic = topics[index];
      if (!this.seenTopicIds.has(topic.id)) {
        this.seenTopicIds.add(topic.id);
        out.push(topic);
      }
    }
    return out;
  }

  // 只有话题搜索分页;用户与类别/标签都是一次性返回,上拉不再请求。
  private loadMore(): void {
    if (this.searchType !== SEARCH_TYPE_TOPICS) {
      return;
    }
    if (this.isSearching || this.isLoadingMore || !this.hasMore || this.results.length === 0) {
      return;
    }
    this.runSearch(false);
  }

  private resetResults(): void {
    this.searchSeq++;
    this.results = [];
    this.userResults = [];
    this.seenTopicIds = new Set();
    this.currentPage = 1;
    this.hasMore = false;
    this.hasSearched = false;
    this.isSearching = false;
    this.isLoadingMore = false;
    this.errorMessage = '';
  }

  private clearQuery(): void {
    this.query = '';
    this.clearDebounce();
    this.resetResults();
    this.focusInput();
  }

  private saveHistory(term: string): void {
    if (term.length < MIN_TERM_LEN) {
      return;
    }
    this.history = SearchHistoryStore.add(this.hostContext(), term);
  }

  private removeHistory(term: string): void {
    this.history = SearchHistoryStore.remove(this.hostContext(), term);
  }

  private clearHistory(): void {
    SearchHistoryStore.clear(this.hostContext());
    this.history = [];
  }

  private focusInput(): void {
    setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(INPUT_FOCUS_ID);
    }, 120);
  }

  private clearDebounce(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
  }

  private trimmedQuery(): string {
    return this.query.trim();
  }

  private searchBarBottomOffset(): number {
    return this.sysTopInset + SEARCH_BAR_CONTENT_HEIGHT;
  }

  // 从搜索词拆出普通高亮词:去掉高级语法(in:title / category: / #版块 / @用户 / -排除)。
  // 长度只挡空串:这里原本要求 ≥2 个字符,是配合早先「最少两个字才搜」写的;
  // 现在单个汉字也能搜(见 MIN_TERM_LEN),再挡 1 个字就会出现「搜『搞』搜得到但结果里不高亮」。
  private parseHighlights(term: string): string[] {
    const parts: string[] = term.split(/\s+/);
    const out: string[] = [];
    for (let i: number = 0; i < parts.length; i++) {
      const p: string = parts[i];
      if (p.length === 0 || p.indexOf(':') >= 0) {
        continue;
      }
      const head: string = p.charAt(0);
      if (head === '#' || head === '@' || head === '-' || head === '+') {
        continue;
      }
      out.push(p);
    }
    return out;
  }

  private hostContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private searchIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('magnifying-glass');
    return def ? def : { id: 'magnifying-glass', rawfilePath: 'fa_icons/magnifying-glass.svg' };
  }


}
