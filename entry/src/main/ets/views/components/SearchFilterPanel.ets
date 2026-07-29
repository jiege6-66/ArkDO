import { Log } from '../../services/logging/Log';
import { TopicCategory } from '../../models/Topic';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { TagSuggestion, TopicService } from '../../services/topic/TopicService';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import {
  daysAgoToSearchDate,
  digitsOnly,
  formatSearchDate,
  SEARCH_IN_POST_OPTIONS,
  SEARCH_IN_USER_OPTIONS,
  SEARCH_ORDER_OPTIONS,
  SEARCH_STATUS_OPTIONS,
  SEARCH_TIME_AFTER,
  SEARCH_TIME_BEFORE,
  SEARCH_TIME_PRESETS,
  SearchFilterOption,
  SearchFilters
} from '../../services/search/SearchFilters';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { getCategoryColor, getCategoryIcon } from './TopicBadgeUtils';

const LOG_TAG: string = '[ArkDO][Search]';
// 标签联想防抖:与搜索框同一量级,避免每次击键都打 /tags/filter/search。
const TAG_DEBOUNCE_MS: number = 300;
// 分类树展开/收起的动画时长(展开转场、箭头翻转、父行展开子项共用同一个值与曲线)。
const CATEGORY_EXPAND_MS: number = 220;
// 分类树每行的固定行高。行高写死而不用上下 padding 撑,是为了让右侧箭头热区能取 height('100%')
// ——热区若自带固定高度,会连同行 padding 一起把行撑高,分类之间就空出一大截。
const CATEGORY_ROW_HEIGHT: number = 44;

// @Builder 的参数一律打包成单个对象传:多个位置参数是「按值传递」,
// 传进去的值被捕获一次就不再重算,选中态变了 chip 不会重新上色;
// 单对象参数才是「按引用传递」,状态变化能带动 @Builder 内部刷新。
interface CategoryRowParams {
  category: TopicCategory;
  parent: TopicCategory | undefined;
  isChild: boolean;
}

interface ChipParams {
  label: string;
  selected: boolean;
  onTap: () => void;
}

interface NumberFieldParams {
  placeholder: string;
  value: string;
  onValue: (next: string) => void;
}

/**
 * 高级筛选面板(承载在 SearchOverlay 的 bindSheet 里)。
 *
 * 面板内改的是一份草稿(draft),点「应用」才回吐给 SearchOverlay 去拼 q、发请求;
 * 这样拖动数字、连点几个条件不会各触发一次搜索。
 *
 * 条件本身的语法语义见 SearchFilters —— 这里只负责把选择塞进那份数据结构。
 */
@Component
export struct SearchFilterPanel {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  isArkWebReady: boolean = false;
  // 分类树由 SearchOverlay 传入(它已经为结果项徽标加载过一份,不再重复请求)。
  @Prop categories: TopicCategory[] = [];
  // 外部当前生效的条件。父组件每次都传新实例,@Watch 据此把草稿同步回最新值
  // (面板被复用而没有重新走 aboutToAppear 时也能对齐)。
  @Prop @Watch('syncDraft') seed: SearchFilters = new SearchFilters();
  onApply: (filters: SearchFilters) => void = () => {};
  onClose: () => void = () => {};

  @State private draft: SearchFilters = new SearchFilters();
  @State private categoryExpanded: boolean = false;
  @State private expandedParentId: number = -1;
  @State private tagQuery: string = '';
  @State private tagResults: TagSuggestion[] = [];
  @State private tagLoading: boolean = false;
  private tagDebounceTimer: number = -1;
  // 标签联想请求序号:丢弃过期响应。
  private tagSeq: number = 0;

  aboutToAppear(): void {
    this.syncDraft();
    // q 为空即「取热门标签前 limit 个」,面板一打开就有候选可点,不用先猜着打字。
    // 与发帖页标签选择器是同一个接口(/tags/filter/search),只是不带 categoryId。
    this.loadTagSuggestions('');
  }

  aboutToDisappear(): void {
    this.clearTagDebounce();
  }

  // seed 是 @Prop 深拷贝进来的,只读它的字段、不调它的方法(拷贝后原型方法未必还在)。
  private syncDraft(): void {
    this.draft = SearchFilters.copyOf(this.seed);
  }

  build() {
    Column() {
      this.PanelHeader()

      Scroll() {
        Column({ space: 18 }) {
          this.CategorySection()
          this.TagSection()
          this.UsernameSection()
          this.StatusSection()
          this.TimeSection()
          this.RangeSection()
          this.InSection()
          this.OrderSection()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 4, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)

      this.PanelFooter()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
  }

  // 标题行:上方给 dragBar 让出位置,下方压一条分隔线收住,别让标题直接顶着 sheet 圆角。
  // 「重置」做成描边胶囊按钮(纯文字链接在这个位置太轻,也不像可点的)。
  @Builder
  private PanelHeader() {
    Column() {
      Row() {
        Text('高级筛选')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Row({ space: 5 }) {
          FaIconView({
            icon: this.resetIcon(),
            color: this.draft.hasAny() ? $r('app.color.brand') : $r('app.color.text_tertiary'),
            iconSize: 12
          })
          Text('重置')
            .fontSize(13)
            .fontColor(this.draft.hasAny() ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        }
        .height(30)
        .padding({ left: 12, right: 12 })
        .borderRadius(15)
        .backgroundColor(this.draft.hasAny() ? $r('app.color.info_soft_bg') : $r('app.color.surface_muted'))
        .border({
          width: 0.5,
          color: this.draft.hasAny() ? $r('app.color.brand') : $r('app.color.border')
        })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (!this.draft.hasAny()) {
            return;
          }
          this.draft = new SearchFilters();
          this.tagQuery = '';
          this.clearTagDebounce();
          this.loadTagSuggestions('');
        })
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)

      Divider()
        .width('100%')
        .height(0.5)
        .color($r('app.color.border'))
    }
    .width('100%')
    .padding({ top: 8 })
  }

  @Builder
  private PanelFooter() {
    Row({ space: 12 }) {
      Text('取消')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .height(44)
        .layoutWeight(1)
        .borderRadius(10)
        .backgroundColor($r('app.color.surface_muted'))
        .onClick(() => {
          this.onClose();
        })

      Text(this.draft.activeCount() > 0 ? `应用 (${this.draft.activeCount()})` : '应用')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .height(44)
        .layoutWeight(2)
        .borderRadius(10)
        .backgroundColor($r('app.color.brand'))
        .onClick(() => {
          this.onApply(this.draft.clone());
        })
    }
    .width('100%')
    // 底部留出手势条 + 一段呼吸位,按钮不贴着屏幕最下沿。
    .padding({ top: 10, bottom: 28 })
    // 文本按钮内容默认不撑满,加固定高度后靠 textAlign + height 居中。
    .alignItems(VerticalAlign.Center)
  }

  // ========== 分类 ==========

  @Builder
  private CategorySection() {
    Column({ space: 8 }) {
      this.SectionTitle('分类')

      Row() {
        Text(this.draft.categoryId >= 0 ? this.draft.categoryName : '所有分类')
          .fontSize(15)
          .fontColor(this.draft.categoryId >= 0 ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.text_tertiary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .rotate({ angle: this.categoryExpanded ? 180 : 0 })
          // 箭头翻转跟着展开动画一起走,而不是瞬间跳过去。
          .animation({ duration: CATEGORY_EXPAND_MS, curve: Curve.EaseInOut })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(10)
      .onClick(() => {
        this.toggleCategoryExpanded();
      })

      if (this.categoryExpanded) {
        Column() {
          Row() {
            Text('所有分类')
              .fontSize(15)
              .fontColor(this.draft.categoryId < 0 ? $r('app.color.brand') : $r('app.color.text_primary'))
              .layoutWeight(1)
            if (this.draft.categoryId < 0) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(15)
                .fontColor([$r('app.color.brand')])
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            }
          }
          .width('100%')
          .height(CATEGORY_ROW_HEIGHT)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.selectCategory(undefined, undefined);
          })

          ForEach(CategoryIndex.topLevelCategories(this.categories), (top: TopicCategory) => {
            this.CategoryRow({ category: top, parent: undefined, isChild: false })
            if (this.expandedParentId === top.id) {
              ForEach(CategoryIndex.childrenOf(this.categories, top.id), (child: TopicCategory) => {
                this.CategoryRow({ category: child, parent: top, isChild: true })
              }, (child: TopicCategory) => `sc${child.id}`)
            }
          }, (top: TopicCategory) => `sp${top.id}`)
        }
        .width('100%')
        // 不给树设高度上限:Column 本身不滚,加了 maxHeight + clip 会把超出的分类直接裁掉
        // 且滑不到(之前就是这个 bug)。让它整棵铺开,交给面板外层那个 Scroll 统一滚。
        .borderRadius(10)
        .backgroundColor($r('app.color.surface_muted'))
        // 展开/收起时淡入 + 从顶部微微下滑;配合 toggleCategoryExpanded 里的 animateTo,
        // 高度变化与这段位移同一条曲线,不再是「啪」地蹦出来。
        .transition(
          TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: -10 }))
            .animation({ duration: CATEGORY_EXPAND_MS, curve: Curve.EaseInOut })
        )
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CategoryRow(p: CategoryRowParams) {
    Row() {
      Row() {
        if (getCategoryIcon(p.category, p.parent)) {
          FaIconView({
            icon: getCategoryIcon(p.category, p.parent) as FaIconDefinition,
            color: getCategoryColor(p.category),
            iconSize: 14
          })
        } else {
          Circle().width(10).height(10).fill(getCategoryColor(p.category))
        }
      }
      .width(18)
      .justifyContent(FlexAlign.Center)

      Text(p.category.name)
        .fontSize(15)
        .fontColor(this.draft.categoryId === p.category.id ? $r('app.color.brand') : $r('app.color.text_primary'))
        .fontWeight(this.draft.categoryId === p.category.id ? FontWeight.Medium : FontWeight.Regular)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8 })

      if (this.draft.categoryId === p.category.id) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(15)
          .fontColor([$r('app.color.brand')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }

      // 有子分类的父行:箭头是独立热区(点箭头展开,点名字选中父分类本身)。
      // 热区做成 44×44 的整块 Row(符号本身才 13vp,原来直接把 onClick 挂在符号上根本点不准),
      // 行的右内边距相应归零,让热区一直延伸到容器右边缘。
      if (!p.isChild && CategoryIndex.hasChildren(this.categories, p.category.id)) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(13)
            .fontColor([$r('app.color.text_tertiary')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .rotate({ angle: this.expandedParentId === p.category.id ? 90 : 0 })
            .animation({ duration: CATEGORY_EXPAND_MS, curve: Curve.EaseInOut })
        }
        // 只给宽度、高度撑满行高:热区仍是 44×44,但不再反过来把行撑高
        // (之前写死 height(44) 叠上行的上下 padding,整行变成 64vp,分类之间空一大截)。
        .width(44)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.toggleParentExpanded(p.category.id);
        })
      }
    }
    .width('100%')
    // 行高固定,不靠上下 padding 撑:这样右侧热区能安全地取 100% 行高。
    .height(CATEGORY_ROW_HEIGHT)
    .padding({
      left: p.isChild ? 26 : 12,
      // 父行右边那 44vp 的箭头热区自带留白,再加 padding 会把热区从边缘推开。
      right: !p.isChild && CategoryIndex.hasChildren(this.categories, p.category.id) ? 0 : 12
    })
    .onClick(() => {
      this.selectCategory(p.category, p.parent);
    })
    // 子分类是随父行展开才插进来的,给它同一套淡入 + 下滑;顶级行不参与(整棵树自己有转场)。
    .transition(
      p.isChild
        ? TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: -6 }))
          .animation({ duration: CATEGORY_EXPAND_MS, curve: Curve.EaseInOut })
        : TransitionEffect.IDENTITY
    )
  }

  // 展开/收起都包进 animateTo:布局高度的变化才会被插值,
  // 否则只有 transition 生效、后面的内容仍然是瞬间被顶下去。
  private toggleCategoryExpanded(): void {
    this.getUIContext().animateTo({ duration: CATEGORY_EXPAND_MS, curve: Curve.EaseInOut }, () => {
      this.categoryExpanded = !this.categoryExpanded;
    });
  }

  private toggleParentExpanded(parentId: number): void {
    this.getUIContext().animateTo({ duration: CATEGORY_EXPAND_MS, curve: Curve.EaseInOut }, () => {
      this.expandedParentId = this.expandedParentId === parentId ? -1 : parentId;
    });
  }

  private selectCategory(category: TopicCategory | undefined, parent: TopicCategory | undefined): void {
    const next: SearchFilters = this.draft.clone();
    if (!category) {
      next.categoryId = -1;
      next.categorySlug = '';
      next.categoryParentSlug = '';
      next.categoryName = '';
    } else {
      next.categoryId = category.id;
      next.categorySlug = category.slug ?? '';
      next.categoryParentSlug = parent ? (parent.slug ?? '') : '';
      next.categoryName = category.name;
    }
    this.draft = next;
    // 选中即收起,同样走动画,和展开是对称的。
    this.getUIContext().animateTo({ duration: CATEGORY_EXPAND_MS, curve: Curve.EaseInOut }, () => {
      this.categoryExpanded = false;
    });
  }

  // ========== 标签 ==========

  @Builder
  private TagSection() {
    Column({ space: 8 }) {
      Row() {
        Text('标签')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        // 多标签时才有「任一 / 全部」之分(对齐官方:两个以上标签才出 all_tags 勾选)。
        if (this.draft.tags.length > 1) {
          Row({ space: 6 }) {
            this.MiniToggle({
              label: '含任一',
              selected: !this.draft.tagsMatchAll,
              onTap: () => {
                const next: SearchFilters = this.draft.clone();
                next.tagsMatchAll = false;
                this.draft = next;
              }
            })
            this.MiniToggle({
              label: '全都含',
              selected: this.draft.tagsMatchAll,
              onTap: () => {
                const next: SearchFilters = this.draft.clone();
                next.tagsMatchAll = true;
                this.draft = next;
              }
            })
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.draft.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.draft.tags, (tag: string) => {
            Row({ space: 4 }) {
              Text(tag)
                .fontSize(13)
                .fontColor($r('app.color.brand'))
              Text('✕')
                .fontSize(11)
                .fontColor($r('app.color.brand'))
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .margin({ right: 8, bottom: 8 })
            .backgroundColor($r('app.color.info_soft_bg'))
            .borderRadius(12)
            .onClick(() => {
              const next: SearchFilters = this.draft.clone();
              next.tags = next.tags.filter((item: string) => item !== tag);
              if (next.tags.length < 2) {
                next.tagsMatchAll = false;
              }
              this.draft = next;
            })
          }, (tag: string) => `st${tag}`)
        }
        .width('100%')
      }

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

      if (this.tagResults.length === 0 && !this.tagLoading) {
        Text(this.tagQuery.trim().length > 0 ? '没有匹配的标签' : '暂无可选标签')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 14 })
      } else if (this.tagResults.length > 0) {
        Column() {
          ForEach(this.tagResults, (tag: TagSuggestion) => {
            Row() {
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
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => {
              this.addTag(tag.name);
            })
          }, (tag: TagSuggestion) => `sr${tag.id}`)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(10)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

  private async loadTagSuggestions(query: string): Promise<void> {
    if (!this.isArkWebReady) {
      return;
    }
    const seq: number = this.tagSeq + 1;
    this.tagSeq = seq;
    this.tagLoading = true;

    const result: NetworkResult<TagSuggestion[]> =
      await new TopicService(this.bridge).searchTagsSiteWide(query, []);

    if (seq !== this.tagSeq) {
      return;
    }
    this.tagLoading = false;
    if (result.success && result.data) {
      // 已选中的标签不再出现在候选里。
      this.tagResults = result.data.filter((tag: TagSuggestion) => this.draft.tags.indexOf(tag.name) < 0);
      return;
    }
    this.tagResults = [];
    Log.i(`${LOG_TAG} tag suggest failed status=${result.statusCode}`);
  }

  private addTag(name: string): void {
    if (this.draft.tags.indexOf(name) >= 0) {
      return;
    }
    const next: SearchFilters = this.draft.clone();
    next.tags = next.tags.concat([name]);
    this.draft = next;
    this.tagQuery = '';
    // 选完一个标签回到默认候选列表(而不是留个空列表),方便接着选第二个。
    this.clearTagDebounce();
    this.loadTagSuggestions('');
  }

  private clearTagDebounce(): void {
    if (this.tagDebounceTimer >= 0) {
      clearTimeout(this.tagDebounceTimer);
      this.tagDebounceTimer = -1;
    }
  }

  // ========== 发帖人 ==========

  @Builder
  private UsernameSection() {
    Column({ space: 8 }) {
      this.SectionTitle('发帖人')
      Row() {
        Text('@')
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ right: 4 })
        TextInput({ text: this.draft.username, placeholder: '用户名' })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({ left: 0, right: 0, top: 10, bottom: 10 })
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .onChange((value: string) => {
            const next: SearchFilters = this.draft.clone();
            // @user 是一个整 token,带空格会被拆成两个词,直接掐掉空白与前导 @。
            next.username = value.trim().replace(/^@+/, '').replace(/\s+/g, '');
            this.draft = next;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(10)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ========== 状态 ==========

  @Builder
  private StatusSection() {
    Column({ space: 8 }) {
      this.SectionTitle('话题状态')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SEARCH_STATUS_OPTIONS, (option: SearchFilterOption) => {
          this.ChoiceChip({
            label: option.label,
            selected: this.draft.status === option.value,
            onTap: () => {
              const next: SearchFilters = this.draft.clone();
              // 单选:再点一次已选中的就取消。
              next.status = next.status === option.value ? '' : option.value;
              this.draft = next;
            }
          })
        }, (option: SearchFilterOption) => `ss${option.value}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ========== 发布时间 ==========

  @Builder
  private TimeSection() {
    Column({ space: 8 }) {
      this.SectionTitle('发布时间')

      Row({ space: 8 }) {
        this.MiniToggle({
          label: '晚于',
          selected: this.draft.timeWhen === SEARCH_TIME_AFTER,
          onTap: () => {
            const next: SearchFilters = this.draft.clone();
            next.timeWhen = SEARCH_TIME_AFTER;
            this.draft = next;
          }
        })
        this.MiniToggle({
          label: '早于',
          selected: this.draft.timeWhen === SEARCH_TIME_BEFORE,
          onTap: () => {
            const next: SearchFilters = this.draft.clone();
            next.timeWhen = SEARCH_TIME_BEFORE;
            this.draft = next;
          }
        })

        Row({ space: 6 }) {
          FaIconView({ icon: this.calendarIcon(), color: $r('app.color.text_tertiary'), iconSize: 13 })
          Text(this.draft.timeDate.length > 0 ? this.draft.timeDate : '选择日期')
            .fontSize(14)
            .fontColor(this.draft.timeDate.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .height(34)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.pickDate();
        })

        if (this.draft.timeDate.length > 0) {
          Text('✕')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              const next: SearchFilters = this.draft.clone();
              next.timeDate = '';
              this.draft = next;
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 快捷区间:服务端 before:/after: 也认「N 天前」的纯数字,但这里折算成绝对日期再拼,
      // 免得历史记录里的相对天数隔天含义就变了。
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SEARCH_TIME_PRESETS, (preset: SearchFilterOption) => {
          this.ChoiceChip({
            label: preset.label,
            selected: this.isTimePresetActive(preset.value),
            onTap: () => {
              const next: SearchFilters = this.draft.clone();
              const date: string = daysAgoToSearchDate(parseInt(preset.value));
              if (next.timeWhen === SEARCH_TIME_AFTER && next.timeDate === date) {
                next.timeDate = '';
              } else {
                next.timeWhen = SEARCH_TIME_AFTER;
                next.timeDate = date;
              }
              this.draft = next;
            }
          })
        }, (preset: SearchFilterOption) => `stp${preset.value}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private isTimePresetActive(days: string): boolean {
    return this.draft.timeWhen === SEARCH_TIME_AFTER && this.draft.timeDate === daysAgoToSearchDate(parseInt(days));
  }

  private pickDate(): void {
    const selected: Date = this.draft.timeDate.length > 0 ? new Date(this.draft.timeDate) : new Date();
    this.getUIContext().showDatePickerDialog({
      start: new Date('2013-01-01'),
      end: new Date(),
      selected: selected,
      onDateAccept: (value: Date) => {
        const next: SearchFilters = this.draft.clone();
        next.timeDate = formatSearchDate(value);
        this.draft = next;
      }
    });
  }

  // ========== 帖子数 / 浏览量 ==========

  @Builder
  private RangeSection() {
    Column({ space: 8 }) {
      this.SectionTitle('帖子数')
      Row({ space: 10 }) {
        this.NumberField({
          placeholder: '最小值',
          value: this.draft.minPosts,
          onValue: (value: string) => {
            const next: SearchFilters = this.draft.clone();
            next.minPosts = value;
            this.draft = next;
          }
        })
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
        this.NumberField({
          placeholder: '最大值',
          value: this.draft.maxPosts,
          onValue: (value: string) => {
            const next: SearchFilters = this.draft.clone();
            next.maxPosts = value;
            this.draft = next;
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.SectionTitle('浏览量')
      Row({ space: 10 }) {
        this.NumberField({
          placeholder: '最小值',
          value: this.draft.minViews,
          onValue: (value: string) => {
            const next: SearchFilters = this.draft.clone();
            next.minViews = value;
            this.draft = next;
          }
        })
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
        this.NumberField({
          placeholder: '最大值',
          value: this.draft.maxViews,
          onValue: (value: string) => {
            const next: SearchFilters = this.draft.clone();
            next.maxViews = value;
            this.draft = next;
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private NumberField(p: NumberFieldParams) {
    TextInput({ text: p.value, placeholder: p.placeholder })
      .type(InputType.Number)
      .layoutWeight(1)
      .height(38)
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .fontSize(14)
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_tertiary'))
      .onChange((raw: string) => {
        // 服务端 min_posts 等的正则是 (\d+),掺进别的字符整个 token 会掉成普通搜索词。
        p.onValue(digitsOnly(raw));
      })
  }

  // ========== 范围 / 位置(in: 与 with:) ==========

  @Builder
  private InSection() {
    Column({ space: 8 }) {
      this.SectionTitle('搜索范围')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SEARCH_IN_POST_OPTIONS, (option: SearchFilterOption) => {
          this.ChoiceChip({
            label: option.label,
            selected: this.draft.inFilters.indexOf(option.value) >= 0,
            onTap: () => {
              this.toggleIn(option.value);
            }
          })
        }, (option: SearchFilterOption) => `sip${option.value}`)
      }
      .width('100%')

      this.SectionTitle('与我相关')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SEARCH_IN_USER_OPTIONS, (option: SearchFilterOption) => {
          this.ChoiceChip({
            label: option.label,
            selected: this.draft.inFilters.indexOf(option.value) >= 0,
            onTap: () => {
              this.toggleIn(option.value);
            }
          })
        }, (option: SearchFilterOption) => `siu${option.value}`)
      }
      .width('100%')

      Text('「与我相关」需要登录后才有结果。')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private toggleIn(value: string): void {
    const next: SearchFilters = this.draft.clone();
    if (next.inFilters.indexOf(value) >= 0) {
      next.inFilters = next.inFilters.filter((item: string) => item !== value);
    } else {
      next.inFilters = next.inFilters.concat([value]);
    }
    this.draft = next;
  }

  // ========== 排序 ==========

  @Builder
  private OrderSection() {
    Column({ space: 8 }) {
      this.SectionTitle('排序')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SEARCH_ORDER_OPTIONS, (option: SearchFilterOption) => {
          this.ChoiceChip({
            label: option.label,
            selected: this.draft.order === option.value,
            onTap: () => {
              const next: SearchFilters = this.draft.clone();
              next.order = option.value;
              this.draft = next;
            }
          })
        }, (option: SearchFilterOption) => `so${option.value}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ========== 通用小控件 ==========

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
  }

  @Builder
  private ChoiceChip(p: ChipParams) {
    Text(p.label)
      .fontSize(13)
      .fontColor(p.selected ? $r('app.color.brand') : $r('app.color.text_body'))
      .fontWeight(p.selected ? FontWeight.Medium : FontWeight.Regular)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .margin({ right: 8, bottom: 8 })
      .backgroundColor(p.selected ? $r('app.color.info_soft_bg') : $r('app.color.surface_muted'))
      .borderRadius(14)
      .onClick(() => {
        p.onTap();
      })
  }

  @Builder
  private MiniToggle(p: ChipParams) {
    Text(p.label)
      .fontSize(13)
      .fontColor(p.selected ? $r('app.color.brand') : $r('app.color.text_secondary'))
      .fontWeight(p.selected ? FontWeight.Medium : FontWeight.Regular)
      .height(34)
      .padding({ left: 12, right: 12 })
      .backgroundColor(p.selected ? $r('app.color.info_soft_bg') : $r('app.color.surface_muted'))
      .borderRadius(8)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        p.onTap();
      })
  }

  private calendarIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('calendar-days');
    return def ? def : { id: 'calendar-days', rawfilePath: 'fa_icons/calendar-days.svg' };
  }

  private resetIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('arrow-rotate-left');
    return def ? def : { id: 'arrow-rotate-left', rawfilePath: 'fa_icons/arrow-rotate-left.svg' };
  }
}
