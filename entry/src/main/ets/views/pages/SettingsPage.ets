import { Log } from '../../services/logging/Log';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { THEME_MODE_STORAGE_KEY, ThemeManager, ThemeMode } from '../../common/theme/ThemeManager';
import { FAB_GLASS_ENABLED_STORAGE_KEY, FabGlassPrefs } from '../../common/ui/FabGlassPrefs';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { SCRIM } from '../../common/theme/Palette';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { ACTIVE_FORUM_NAME_KEY } from '../../common/constants/StorageKeys';
import { AppConstants } from '../../common/constants/AppConstants';
import { SiteCapabilities } from '../../services/site/SiteCapabilities';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';

const LOG_TAG: string = '[ArkDO][Settings]';

// 与个人中心同款鸿蒙设置页式卡片分组:灰底 + 无描边圆角卡片。
//
// 设置页:顶层只保留高频项(外观)+ 分类入口(通知 / 网络与连接 / 实验性功能 / 我的站点)+ 关于。
// 各分类的繁重配置收进独立子页,由个人中心右上角齿轮入口 push 进入。
//
// 原先这里还有一组「首页内容入口」,用来勾选并拖动排序抽屉里露出哪几个 feed。首页筛选改成
// chips 之后五个入口只占两行,没有再裁剪的必要;而那套配置的默认值是空数组,反倒让新用户
// 只看得到一枚「最新」。整组连同拖拽排序一起删了,五个入口现在恒显。
@Component
export struct SettingsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  // 关于弹框里"开发者 @JoeyYin"跳原生用户主页(UserProfilePage,按 username 加载),push 由 RootTabPage 注入。
  onOpenUser: (username: string, displayName: string) => void = () => {};
  // 反馈与建议:打开站内反馈帖的原生详情页。本页拿不到 navPathStack,push 由 RootTabPage 注入。
  onOpenFeedback: () => void = () => {};
  // 四个分类子页入口:本页不持有 navPathStack,push 均由 RootTabPage 注入。
  onOpenPush: () => void = () => {};
  onOpenNetwork: () => void = () => {};
  onOpenExperimental: () => void = () => {};
  // 帖子列表样式子页(字号/字重/行高/行间距/头像)。与外观同组:都是纯观感设置。
  onOpenTopicListStyle: () => void = () => {};
  // 论坛管理/切换页:push 由 RootTabPage 注入。
  onOpenForums: () => void = () => {};
  // 站点管理页:与上面四个同款,push 由 RootTabPage 注入。
  onOpenSites: () => void = () => {};
  onOpenDiagnostics: () => void = () => {};
  @StorageLink(THEME_MODE_STORAGE_KEY) themeMode: ThemeMode = ThemeMode.SYSTEM;
  // 「悬浮按钮玻璃效果」开关:镜像 AppStorage,onChange 落盘后两处 FAB 即时响应。默认关。
  @StorageProp(FAB_GLASS_ENABLED_STORAGE_KEY) private fabGlassEnabled: boolean = false;
  // 当前论坛名:绑 AppStorage 镜像而非直接读 CurrentSite.displayName —— 后者是普通静态
  // getter,改名/切站后 ArkUI 不知道要重绘,副标题会一直停在旧值(要退回首页再进才更新)。
  @StorageProp(ACTIVE_FORUM_NAME_KEY) private activeForumName: string = '';
  @State private appVersion: string = '';
  private scroller: Scroller = new Scroller();
  private disclaimerDialogController: CustomDialogController = new CustomDialogController({
    builder: DisclaimerDialog(),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true
  });
  private aboutDialogController: CustomDialogController = new CustomDialogController({
    builder: AboutDialog({
      onOpenDeveloper: () => {
        this.onOpenUser('joeyyin', 'JoeyYin');
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.readAppVersion();
  }

  // 镜像尚未写入的那一帧兜底成 App 名,不留空副标题。
  private activeForumLabel(): string {
    return this.activeForumName.length > 0 ? this.activeForumName : AppConstants.APP_NAME;
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
    // 只当标题栏容器用,不参与分栏(分栏由 RootTabPage 根 Navigation 负责)。默认 Auto 会在
    // 宽度 ≥600vp 时自切 Split——平板横屏右详情栏就会多出一条可拖的分割线,菜单也被挤到线左边。
    .mode(NavigationMode.Stack)
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
        this.SettingCell($r('sys.symbol.textformat'), '帖子列表样式', '', () => {
          this.onOpenTopicListStyle();
        })
        this.HairlineInset()
        this.FabGlassRow()
      }
      .cardStyle()

      // 卡片:分类入口。繁重/低频配置各自收进子页。
      Column() {
        // 论坛切换排在最前:它决定了整个 App 在看哪个站,是这一组里唯一会改变内容来源的项。
        this.ForumCell()
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.bell'), '通知', '', () => {
          this.onOpenPush();
        })
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.wifi'), '网络与连接', '', () => {
          this.onOpenNetwork();
        })
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.gearshape'), '实验性功能', '', () => {
          this.onOpenExperimental();
        })
        // 站点管理的「正门」。抽屉里那行「我的站点」只是快捷方式,而它自己可以被开关藏起来——
        // 唯一入口能把自己藏掉是设计缺陷,所以这里必须有一条不受那个开关影响的路。
        // 整组仅在 linux.do 下露出:这功能靠复用主站 OAuth 免登录进生态站点,换站后无从谈起。
        if (SiteCapabilities.ecosystemSites) {
          this.HairlineInset()
          this.SettingCell($r('sys.symbol.house'), '我的站点', '', () => {
            this.onOpenSites();
          })
        }
      }
      .cardStyle()

      this.AboutGroup()

      Row()
        .width('100%')
        .height(40)
    }
    .width('100%')
  }

  /**
   * 论坛入口。副标题是当前论坛名,会随改名/切站变化。
   *
   * 刻意不走 SettingCell:那是个 @Builder,`value` 按值传参 —— ArkUI 里按值传进
   * @Builder 的参数变化**不会触发内部重绘**(要按引用 $$ 才行),副标题会一直停在旧值。
   * 走 SettingCell 传值的只有版本号那类永不变化的东西,所以一直没暴露这个问题。
   * 同页的「外观」也是为此单独建了 AppearanceCell —— 这里照同一套写法。
   */
  @Builder
  private ForumCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Text('论坛')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 14 })
      Text(this.activeForumLabel())
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '45%' })
        .margin({ right: 6 })
      this.ChevronIcon()
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .onClick(() => {
      this.onOpenForums();
    })
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
      // 反馈帖是写死的 topic id,只在 linux.do 上存在;换站后点进去会是一篇无关的帖子。
      if (SiteCapabilities.feedbackTopic) {
        this.SettingCell($r('sys.symbol.message'), '反馈与建议', '', () => {
          this.onOpenFeedback();
        })
        this.HairlineInset()
      }
      this.SettingCell($r('sys.symbol.info_circle'), '关于 ArkDO', this.getVersionLabel(), () => {
        this.aboutDialogController.open();
      })
      this.HairlineInset()
      // 免责声明:应用是通用客户端、内容来自用户自己添加的站点。审核会翻这里,用户也该看得到。
      this.SettingCell($r('sys.symbol.doc_text'), '免责声明', '', () => {
        this.disclaimerDialogController.open();
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
    ThemeManager.setMode(this.getUIContext().getHostContext() as common.Context, mode);
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
    FabGlassPrefs.setEnabled(this.getUIContext().getHostContext() as common.Context, enabled);
  }

  // ==================== 辅助 ====================

  private readAppVersion(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = this.formatAppVersion(info);
    } catch (err) {
      Log.i(`${LOG_TAG} read app version failed`);
    }
  }

  private getVersionLabel(): string {
    return this.appVersion.length > 0 ? this.appVersion : '';
  }

  private formatAppVersion(info: bundleManager.BundleInfo): string {
    return `v${info.versionName} (Build ${info.versionCode})`;
  }
}

// 免责声明。刻意一个品牌都不提:它要说的是「内容不是我们的」,这句话不需要点名任何论坛
// 或论坛程序。功能层面的「支持基于 Discourse 搭建的站点」属于产品说明,放应用市场描述里,
// 与本声明分开 —— 免责声明里出现他人商标,容易被误读成需要授权。
@CustomDialog
struct DisclaimerDialog {
  controller?: CustomDialogController;

  build() {
    Column() {
      Text('免责声明')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 22, bottom: 16 })

      Scroll() {
        Text('本应用是第三方论坛客户端，不提供、不托管、不审核任何内容。\n\n' +
          '应用内显示的全部内容均来自你自行添加的第三方站点，由该站点及其运营方负责。' +
          '你选择访问哪些站点，完全由你自己决定。\n\n' +
          '本应用与任何论坛站点及其运营方之间，不存在隶属、合作或授权关系。')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Off)
      .padding({ left: 24, right: 24 })
      .margin({ bottom: 20 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))

      Button('知道了')
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.ld_accent'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(48)
        .onClick(() => {
          this.controller?.close();
        })
    }
    // 与本页 AboutDialog 同款:customStyle 下宽度自己给,并 clip 掉按钮按压高亮的直角溢出。
    .width('86%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(20)
    .clip(true)
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
      this.version = `v${info.versionName} (Build ${info.versionCode})`;
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

      Text('第三方论坛客户端')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      Text(this.version.length > 0 ? `版本 ${this.version}` : '版本 —')
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
