import { Log } from '../../services/logging/Log';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { bundleManager } from '@kit.AbilityKit';
import { THEME_MODE_STORAGE_KEY, ThemeManager, ThemeMode } from '../../common/theme/ThemeManager';
import { FAB_GLASS_ENABLED_STORAGE_KEY, FabGlassPrefs } from '../../common/ui/FabGlassPrefs';
import { FeedDef, FeedPrefs } from '../../services/site/FeedPrefs';
import { SitePrefs } from '../../services/site/SitePrefs';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { SCRIM } from '../../common/theme/Palette';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';

const LOG_TAG: string = '[ArkDO][Settings]';

// 与个人中心同款鸿蒙设置页式卡片分组:灰底 + 无描边圆角卡片。
// 内容入口配置行高:拖动排序按此行高换算跟手位移与让位步长。
const FEED_ROW_H: number = 52;

// 设置页:顶层只保留高频项(外观)+ 分类入口(通知 / 网络与安全 / 实验性功能 / 诊断日志)
// + 首页内容入口 + 关于。各分类的繁重配置收进独立子页,由个人中心右上角齿轮入口 push 进入。
@Component
export struct SettingsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  // 打开站内 Web 页:关于弹框里"开发者 @JoeyYin"跳 linux.do 个人资料页复用此链路,由 RootTabPage 注入。
  onOpenWeb: (url: string, title?: string) => void = () => {};
  // 反馈与建议:打开站内反馈帖的原生详情页。本页拿不到 navPathStack,push 由 RootTabPage 注入。
  onOpenFeedback: () => void = () => {};
  // 四个分类子页入口:本页不持有 navPathStack,push 均由 RootTabPage 注入。
  onOpenPush: () => void = () => {};
  onOpenNetwork: () => void = () => {};
  onOpenExperimental: () => void = () => {};
  onOpenDiagnostics: () => void = () => {};
  @StorageLink(THEME_MODE_STORAGE_KEY) themeMode: ThemeMode = ThemeMode.SYSTEM;
  // 「悬浮按钮玻璃效果」开关:镜像 AppStorage,onChange 落盘后两处 FAB 即时响应。默认关。
  @StorageProp(FAB_GLASS_ENABLED_STORAGE_KEY) private fabGlassEnabled: boolean = false;
  @State private appVersion: string = '';
  // 首页内容入口:启用且有序的可选入口 key(不含恒在的最新)。
  @State private enabledFeeds: string[] = [];
  // 抽屉「我的站点」区总开关。站点不是 feed(点它是 push 页面而非切内容流),故不并入
  // feed_enabled_order 而用独立键:那个结构里空数组=全关,表达不了"默认开"。
  @State private sitesEntryEnabled: boolean = true;
  // 拖动排序状态:draggingIndex=被拖行原始下标(-1 为未拖动);dragOffsetY=浮起行跟手位移;
  // hoverIndex=当前落位槽位(邻行据此实时让位)。松手后吸附到 hoverIndex 再提交顺序。
  @State private draggingIndex: number = -1;
  @State private dragOffsetY: number = 0;
  @State private hoverIndex: number = -1;
  private scroller: Scroller = new Scroller();
  private aboutDialogController: CustomDialogController = new CustomDialogController({
    builder: AboutDialog({
      onOpenDeveloper: () => {
        this.onOpenWeb('https://linux.do/u/joeyyin/', 'JoeyYin');
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.readAppVersion();
    this.enabledFeeds = FeedPrefs.getEnabledKeys(getContext(this));
    this.sitesEntryEnabled = SitePrefs.isEntryEnabled(getContext(this));
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
      this.SettingsScrollableContent()
      this.SettingsTitleBarOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg_gray'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ==================== Builder ====================

  @Builder
  private SettingsScrollableContent() {
    Scroll(this.scroller) {
      Column() {
        Blank()
          .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))
        this.SettingsContent()
      }
      .width('100%')
      .padding({ left: PAGE_MARGIN, right: PAGE_MARGIN })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private SettingsTitleBarOverlay() {
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
          mainTitle: '设置'
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
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private SettingsContent() {
    Column() {
      // 卡片:外观(高频,内联)
      Column() {
        this.AppearanceCell()
        this.HairlineInset()
        this.FabGlassRow()
      }
      .cardStyle()

      // 卡片:分类入口。繁重/低频配置各自收进子页。
      Column() {
        this.SettingCell($r('sys.symbol.bell'), '通知', '', () => {
          this.onOpenPush();
        })
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.security_shield'), '网络与连接', '', () => {
          this.onOpenNetwork();
        })
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.gearshape'), '实验性功能', '', () => {
          this.onOpenExperimental();
        })
      }
      .cardStyle()

      this.FeedGroup()

      this.AboutGroup()

      Row()
        .width('100%')
        .height(40)
    }
    .width('100%')
  }

  @Builder
  private AppearanceCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.dark_mode'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Text('外观')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 14 })
      Text(this.getThemeModeLabel())
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .margin({ right: 6 })
      this.ChevronIcon()
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .bindMenu([
      {
        value: '跟随系统',
        action: (): void => {
          this.setThemeMode(ThemeMode.SYSTEM);
        }
      },
      {
        value: '浅色',
        action: (): void => {
          this.setThemeMode(ThemeMode.LIGHT);
        }
      },
      {
        value: '深色',
        action: (): void => {
          this.setThemeMode(ThemeMode.DARK);
        }
      }
    ])
  }

  // 悬浮按钮玻璃效果:开⇒首页/详情页右下角 FAB 恢复模糊材质背板;关⇒当前透明样式。默认关。
  @Builder
  private FabGlassRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.circle_dashed'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('悬浮按钮玻璃效果')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('首页与详情页右下角按钮显示毛玻璃背景')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 })

      Toggle({ type: ToggleType.Switch, isOn: this.fabGlassEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.setFabGlassEnabled(isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private SettingCell(symbol: Resource, label: string, value: string, onCellClick?: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 14 })
      if (value.length > 0) {
        Text(value)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ right: 6 })
      }
      if (onCellClick !== undefined) {
        this.ChevronIcon()
      }
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .onClick(() => {
      if (onCellClick !== undefined) {
        onCellClick();
      }
    })
  }

  // 关于组:反馈入口直开站内反馈帖;关于弹框展示版本号与开发者链接;诊断日志入口进子页。
  @Builder
  private AboutGroup() {
    this.GroupLabel('关于')
    Column() {
      this.SettingCell($r('sys.symbol.message'), '反馈与建议', '', () => {
        this.onOpenFeedback();
      })
      this.HairlineInset()
      this.SettingCell($r('sys.symbol.info_circle'), '关于 ArkDO', this.getVersionLabel(), () => {
        this.aboutDialogController.open();
      })
      this.HairlineInset()
      this.SettingCell($r('sys.symbol.exclamationmark_circle'), '诊断日志', '', () => {
        this.onOpenDiagnostics();
      })
    }
    .cardStyle()
    // GroupLabel 自带 18 上内边距,抹平 cardStyle 的 12 上外边距,免得组标题与卡片间空一截。
    .margin({ top: 0 })
  }

  // 首页内容入口:最新恒在(默认、不可关不可拖);可选入口勾选启用,启用项可拖动排序。
  @Builder
  private FeedGroup() {
    this.GroupLabel('首页内容入口')
    Column() {
      // 最新:默认入口,常驻不可配。
      Row() {
        Text('最新')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('默认')
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
      }
      .width('100%')
      .height(FEED_ROW_H)
      .padding({ left: CARD_PADDING, right: CARD_PADDING })

      // 启用区:长按整行抬起、跟手拖动,邻行实时让位,松手吸附落位(只有启用项参与排序)。
      if (this.enabledFeeds.length > 0) {
        this.HairlineInset()
        Column() {
          ForEach(this.enabledFeeds, (key: string, index: number) => {
            this.EnabledFeedRow(key, index)
          }, (key: string) => key)
        }
        .width('100%')
        .clip(false)
      }

      // 未启用区:关闭态,勾选即启用(移入启用区末尾)。
      if (this.disabledFeeds().length > 0) {
        this.HairlineInset()
        ForEach(this.disabledFeeds(), (feed: FeedDef) => {
          this.DisabledFeedRow(feed)
        }, (feed: FeedDef) => feed.key)
      }

      // 我的站点:独立开关,不参与上面那套启用/排序(站点之间的排序在站点管理页里做)。
      this.HairlineInset()
      this.SitesEntryRow()
    }
    .cardStyle()
    .clip(true)
    .margin({ top: 0 })
  }

  @Builder
  private SitesEntryRow() {
    Row() {
      Column() {
        Text('我的站点')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('在侧边栏显示站点入口')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.sitesEntryEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.setSitesEntryEnabled(isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private EnabledFeedRow(key: string, index: number) {
    Row() {
      this.DragHandle()
      Text(this.feedLabel(key))
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: true })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          if (!isOn) {
            this.disableFeed(key);
          }
        })
    }
    .width('100%')
    .height(FEED_ROW_H)
    .padding({ left: CARD_PADDING, right: CARD_PADDING })
    .backgroundColor($r('app.color.surface_card'))
    // 被拖行浮起在最上层;其余行按 hoverIndex 上下让位。
    .zIndex(this.draggingIndex === index ? 1 : 0)
    .translate({ y: this.rowTranslateY(index) })
    .scale(this.draggingIndex === index ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
    .shadow(this.draggingIndex === index
      ? { radius: 12, color: SCRIM, offsetY: 4 }
      : { radius: 0, color: Color.Transparent })
    // 长按抬起后转拖动:先长按拿到拖动权,再用竖向 Pan 跟手,避免与外层滚动抢手势。
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: 300 })
          .onAction(() => this.beginDrag(index)),
        PanGesture({ direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => this.updateDrag(event.offsetY))
          .onActionEnd(() => this.endDrag())
          .onActionCancel(() => this.endDrag())
      )
    )
  }

  @Builder
  private DisabledFeedRow(feed: FeedDef) {
    Row() {
      Text(feed.label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
      if (feed.requiresLogin) {
        Text('需登录')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .margin({ left: 8 })
      }
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: false })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          if (isOn) {
            this.enableFeed(feed.key);
          }
        })
    }
    .width('100%')
    .height(FEED_ROW_H)
    .padding({ left: CARD_PADDING, right: CARD_PADDING })
  }

  // 拖动手柄:三条短发丝线,提示可拖(实际拖动靠长按整行)。
  @Builder
  private DragHandle() {
    Column({ space: 3 }) {
      Divider().width(14).strokeWidth(1.5).color($r('app.color.text_faint'))
      Divider().width(14).strokeWidth(1.5).color($r('app.color.text_faint'))
      Divider().width(14).strokeWidth(1.5).color($r('app.color.text_faint'))
    }
    .justifyContent(FlexAlign.Center)
    .width(16)
  }

  @Builder
  private HairlineInset() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.border'))
      .margin({ left: CARD_PADDING, right: CARD_PADDING })
  }

  @Builder
  private GroupLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.text_faint'))
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 18, bottom: 8 })
  }

  @Builder
  private ChevronIcon() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(18)
      .fontColor([$r('app.color.text_faint')])
  }

  // ==================== 外观 ====================

  private setThemeMode(mode: ThemeMode): void {
    ThemeManager.setMode(getContext(this), mode);
  }

  private getThemeModeLabel(): string {
    if (this.themeMode === ThemeMode.LIGHT) {
      return '浅色';
    }
    if (this.themeMode === ThemeMode.DARK) {
      return '深色';
    }
    return '跟随系统';
  }

  // 玻璃效果开关:写盘 + 同步 AppStorage 镜像,首页/详情页 FAB 经 @StorageProp 即时响应,无需重启。
  private setFabGlassEnabled(enabled: boolean): void {
    FabGlassPrefs.setEnabled(getContext(this), enabled);
  }

  // ==================== 首页内容入口 ====================

  private feedLabel(key: string): string {
    const def: FeedDef | undefined = FeedPrefs.feedDef(key);
    return def ? def.label : key;
  }

  // 未启用的可选入口(保持 optionalFeeds 原始顺序)。
  private disabledFeeds(): FeedDef[] {
    const all: FeedDef[] = FeedPrefs.optionalFeeds();
    const result: FeedDef[] = [];
    for (let index: number = 0; index < all.length; index++) {
      if (this.enabledFeeds.indexOf(all[index].key) < 0) {
        result.push(all[index]);
      }
    }
    return result;
  }

  private enableFeed(key: string): void {
    if (this.enabledFeeds.indexOf(key) >= 0) {
      return;
    }
    const next: string[] = this.enabledFeeds.slice();
    next.push(key);
    this.persistFeeds(next);
  }

  private disableFeed(key: string): void {
    const next: string[] = this.enabledFeeds.slice();
    const index: number = next.indexOf(key);
    if (index < 0) {
      return;
    }
    next.splice(index, 1);
    this.persistFeeds(next);
  }

  // 被拖行浮起后,其余行让位的位移量:被拖行本身跟手,夹在原位与落位之间的行整体上/下移一格。
  private rowTranslateY(index: number): number {
    if (this.draggingIndex < 0) {
      return 0;
    }
    if (index === this.draggingIndex) {
      return this.dragOffsetY;
    }
    const from: number = this.draggingIndex;
    const to: number = this.hoverIndex;
    if (from < to && index > from && index <= to) {
      return -FEED_ROW_H;
    }
    if (from > to && index >= to && index < from) {
      return FEED_ROW_H;
    }
    return 0;
  }

  // 长按达成:抬起该行(轻微放大+投影),进入拖动。
  private beginDrag(index: number): void {
    this.hoverIndex = index;
    this.dragOffsetY = 0;
    animateTo({ duration: 150, curve: Curve.FastOutSlowIn }, () => {
      this.draggingIndex = index;
    });
  }

  // 拖动中:跟手位移(夹在启用区上下边界内),按半格阈值更新落位槽,邻行动画让位。
  private updateDrag(offsetY: number): void {
    if (this.draggingIndex < 0) {
      return;
    }
    const len: number = this.enabledFeeds.length;
    const maxUp: number = -this.draggingIndex * FEED_ROW_H;
    const maxDown: number = (len - 1 - this.draggingIndex) * FEED_ROW_H;
    let y: number = offsetY;
    if (y < maxUp) {
      y = maxUp;
    }
    if (y > maxDown) {
      y = maxDown;
    }
    this.dragOffsetY = y;
    let hover: number = this.draggingIndex + Math.round(y / FEED_ROW_H);
    if (hover < 0) {
      hover = 0;
    }
    if (hover > len - 1) {
      hover = len - 1;
    }
    if (hover !== this.hoverIndex) {
      animateTo({ duration: 180, curve: Curve.Friction }, () => {
        this.hoverIndex = hover;
      });
    }
  }

  // 松手:浮起行吸附到落位槽,动画结束后提交新顺序并清空拖动态(此刻数组与画面已一致,无跳变)。
  private endDrag(): void {
    if (this.draggingIndex < 0) {
      return;
    }
    const from: number = this.draggingIndex;
    const to: number = this.hoverIndex;
    animateTo({
      duration: 180,
      curve: Curve.FastOutSlowIn,
      onFinish: () => this.commitReorder(from, to)
    }, () => {
      this.dragOffsetY = (to - from) * FEED_ROW_H;
    });
  }

  private commitReorder(from: number, to: number): void {
    if (from >= 0 && to >= 0 && from !== to && from < this.enabledFeeds.length) {
      const next: string[] = this.enabledFeeds.slice();
      const moved: string[] = next.splice(from, 1);
      const target: number = to > next.length ? next.length : to;
      next.splice(target, 0, moved[0]);
      this.persistFeeds(next);
    }
    this.draggingIndex = -1;
    this.hoverIndex = -1;
    this.dragOffsetY = 0;
  }

  private persistFeeds(keys: string[]): void {
    this.enabledFeeds = keys;
    FeedPrefs.setEnabledKeys(getContext(this), keys);
  }

  // 站点入口开关:首页每次开抽屉都重读 preferences,故写完即生效,无需通知首页。
  private setSitesEntryEnabled(enabled: boolean): void {
    this.sitesEntryEnabled = enabled;
    SitePrefs.setEntryEnabled(getContext(this), enabled);
  }

  // ==================== 辅助 ====================

  private readAppVersion(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
    } catch (err) {
      Log.i(`${LOG_TAG} read app version failed`);
    }
  }

  private getVersionLabel(): string {
    return this.appVersion.length > 0 ? `v${this.appVersion}` : '';
  }
}

// 关于 ArkDO 信息框:应用名 + 简介 + 版本(运行时读 bundleManager)+ 可点开发者链接 + 关闭。
// 版本自读而非由父按值传入,规避 CustomDialogController 字段初始化按值捕获空版本号。
@CustomDialog
struct AboutDialog {
  controller?: CustomDialogController;
  onOpenDeveloper: () => void = () => {};
  @State private version: string = '';

  aboutToAppear(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = info.versionName;
    } catch (err) {
      Log.i(`${LOG_TAG} about dialog read version failed`);
    }
  }

  build() {
    Column() {
      Text('ArkDO')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('Linux.do 第三方鸿蒙客户端')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      Text(this.version.length > 0 ? `版本 v${this.version}` : '版本 —')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .margin({ top: 14 })

      Row() {
        Text('开发者 ')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        Text('@JoeyYin')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            this.controller?.close();
            this.onOpenDeveloper();
          })
      }
      .margin({ top: 6 })

      Button('关闭')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .width('100%')
        .height(44)
        .borderRadius(22)
        .margin({ top: 24 })
        .onClick(() => {
          this.controller?.close();
        })
    }
    .width('82%')
    .padding({ left: 24, right: 24, top: 28, bottom: 20 })
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(20)
    .alignItems(HorizontalAlign.Center)
  }
}
