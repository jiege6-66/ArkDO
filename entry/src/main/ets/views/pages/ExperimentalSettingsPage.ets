import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { RealtimeTopicsPrefs } from '../../services/realtime/RealtimeTopicsPrefs';
import { RealtimePostsPrefs } from '../../services/realtime/RealtimePostsPrefs';
import { AnimatedAvatarPrefs } from '../../services/avatar/AnimatedAvatarPrefs';
import { HoldingHandManager } from '../../common/utils/HoldingHandManager';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';

// 实验性功能子页:从设置页拆出。收纳「实时更新话题」「智感握姿」两个本地开关,
// 纯 preferences 读写,不依赖宿主注入。
@Component
export struct ExperimentalSettingsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  // 实时更新话题开关(默认关),进页时从 preferences 载入。
  @State private realtimeTopicsEnabled: boolean = false;
  // 帖子实时更新开关(默认关),进页时从 preferences 载入。
  @State private realtimePostsEnabled: boolean = false;
  // 动态头像开关(默认开),进页时从 preferences 载入。
  @State private animatedAvatarEnabled: boolean = true;
  // 智感握姿开关(默认关),进页时从 HoldingHandManager 读取。
  @State private smartReachEnabled: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.realtimeTopicsEnabled = RealtimeTopicsPrefs.isEnabled();
    this.realtimePostsEnabled = RealtimePostsPrefs.isEnabled();
    this.animatedAvatarEnabled = AnimatedAvatarPrefs.isEnabled();
    this.smartReachEnabled = HoldingHandManager.isEnabled();
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
          this.RealtimeTopicsCell()
          this.HairlineInset()
          this.RealtimePostsCell()
          this.HairlineInset()
          this.AnimatedAvatarCell()
          this.HairlineInset()
          this.SmartReachCell()
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
          mainTitle: '实验性功能'
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
  private RealtimeTopicsCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('实时更新话题')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('首页实时接收新话题/更新提示')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.realtimeTopicsEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.realtimeTopicsEnabled = isOn;
          RealtimeTopicsPrefs.setEnabled(getContext(this), isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private RealtimePostsCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('帖子实时更新')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('打开帖子后实时接收他人的新回复')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.realtimePostsEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.realtimePostsEnabled = isOn;
          RealtimePostsPrefs.setEnabled(getContext(this), isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private AnimatedAvatarCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.person'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('动态头像')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('播放动图头像与角标;关闭则只显示静止画面')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.animatedAvatarEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.animatedAvatarEnabled = isOn;
          AnimatedAvatarPrefs.setEnabled(getContext(this), isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private SmartReachCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('智感握姿')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('识别单手握持方向，把悬浮按钮移到顺手一侧')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.smartReachEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.smartReachEnabled = isOn;
          HoldingHandManager.setEnabled(getContext(this), isOn);
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
}
