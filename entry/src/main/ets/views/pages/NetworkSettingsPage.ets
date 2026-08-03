import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { DohManager, DohServer } from '../../services/network/DohManager';
import { ChallengeShortcutPrefs } from '../../services/challenge/ChallengeShortcutPrefs';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { SETTINGS_DOH_TICK } from '../../common/constants/StorageKeys';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';

// 网络与连接子页:从设置页拆出。收纳 DoH 配置入口、刷新 Cloudflare 通行证、帖子页过盾入口开关。
// 过盾入口与刷新通行证同源(都在处理 CF 拦截),故归到一处。
@Component
export struct NetworkSettingsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  // 打开 DoH 配置子页:本页拿不到 navPathStack,push 由 RootTabPage 注入。
  onOpenDoh: () => void = () => {};
  // 主动过盾:通知 RootTabPage 打开交互式 Cloudflare 验证页(唯一能真正拿到新 cf_clearance 的路径)。
  onActiveChallenge: () => void = () => {};
  // RootTabPage 在本页 NavDestination onShown 时自增此 AppStorage 计数(本页此刻已在前台,
  // @StorageProp 变更能可靠触发重渲染)。被 DoH 配置页覆盖后 pop 回来常驻不重建,靠它
  // @Watch 重读 DoH 摘要——不依赖 @Prop 流入(NavDestination 子树不随父 @State 重建)。
  @StorageProp(SETTINGS_DOH_TICK) @Watch('onShownRefresh') private dohTick: number = 0;
  // DoH 摘要:关闭显示"已关闭",启用显示当前生效服务器名;每次进入/重新可见即从 DohManager 重算。
  @State private dohSummary: string = '已关闭';
  // 帖子页过盾快捷入口开关(默认关),进页时从 preferences 载入。
  @State private challengeShortcutEnabled: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refreshDohSummary();
    this.loadChallengeShortcutEnabled();
  }

  // NavDestination 重新可见(从 DoH 配置页 pop 回)时由 dohTick 变更触发,重读最新 DoH 摘要。
  private onShownRefresh(): void {
    this.refreshDohSummary();
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
      this.ScrollableContent()
      this.TitleBarOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg_gray'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ==================== Builder ====================

  @Builder
  private ScrollableContent() {
    Scroll(this.scroller) {
      Column() {
        Blank()
          .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))

        Column() {
          this.DohCell()
          this.HairlineInset()
          // 主动过盾:打开交互式 CF 验证页(https://linux.do/challenge)手动过 Cloudflare。
          this.SettingCell($r('sys.symbol.checkmark_shield'), '刷新 Cloudflare 通行证', '', () => {
            this.onActiveChallenge();
          })
          this.HairlineInset()
          this.ChallengeShortcutCell()
        }
        .cardStyle()

        Row()
          .width('100%')
          .height(40)
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
          mainTitle: '网络与连接'
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

  // DoH 行单独成 Builder:直接读 this.dohSummary(而非当参数传给 SettingCell)。@Builder 的
  // 按值参数不随 @State 变化重渲染,而直接引用组件状态的 @Builder 会——这样切换 DoH pop 回来
  // 摘要文字才会真正刷新(参数式的 SettingCell 只有整页重建才更新)。
  @Builder
  private DohCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.security_shield'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Text('DoH 配置')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 14 })
      if (this.dohSummary.length > 0) {
        Text(this.dohSummary)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ right: 6 })
      }
      this.ChevronIcon()
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .onClick(() => {
      this.onOpenDoh();
    })
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

  // 帖子页过盾快捷入口开关。默认关:多数人从不撞盾,常驻入口只会碍眼。
  // 打开也不等于常驻——还要真的探测到阅读上报被 CF 拦下才亮(见 ChallengeShortcutEventBus)。
  @Builder
  private ChallengeShortcutCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.lock_shield'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('帖子页显示过盾入口')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('阅读被 CF 拦截时，帖子右上角出现快捷验证')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.challengeShortcutEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.challengeShortcutEnabled = isOn;
          ChallengeShortcutPrefs.setEnabled(this.hostContext(), isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private HairlineInset() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.border'))
      .margin({ left: CARD_PADDING, right: CARD_PADDING })
  }

  @Builder
  private ChevronIcon() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(18)
      .fontColor([$r('app.color.text_faint')])
  }

  // ==================== 逻辑 ====================

  // 宿主 Context 收口。getContext(this) 已废弃,统一从 UIContext 取,免得每个调用点各写一遍 cast。
  private hostContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  // 直接从 DohManager 读当前开关与生效服务器,组装摘要文案;不依赖 @StorageProp 的跨页刷新。
  private refreshDohSummary(): void {
    const context: common.Context = this.hostContext();
    const enabled: boolean = DohManager.isEnabled(context);
    const active: DohServer = DohManager.getActiveServer(context);
    this.dohSummary = enabled ? active.name : '已关闭';
  }

  private async loadChallengeShortcutEnabled(): Promise<void> {
    this.challengeShortcutEnabled = await ChallengeShortcutPrefs.load(this.hostContext());
  }
}
