import { Log } from '../../services/logging/Log';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { User } from '../../models/User';
import { PushRegistrationResult, PushStatusResult } from '../../services/push/PushSubscriptionService';
import { nextPushRefreshStart, PushRefreshStart } from '../../services/push/PushRefreshGate';
import { needsRelayConsent, PushRelayConfig, readCustomBaseUrl, resolvePushRelayConfig, saveCustomBaseUrl, saveRelayConsent } from '../../services/push/PushRelayConfig';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { showToast as promptToast } from '../../common/utils/Toast';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';

const LOG_TAG: string = '[ArkDO][PushSettings]';

// 测试推送冷却秒数,与中继的 RELAY_TEST_COOLDOWN 默认值对齐。
// 只影响本地按钮的倒计时展示;真正拦截在中继侧(按 subId,换设备重装都绕不过)。
const TEST_PUSH_COOLDOWN_SEC: number = 60;

// 通知子页:从设置页拆出。收纳系统推送开关、发送测试推送、推送中继地址,以及首启同意告知。
@Component
export struct PushSettingsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  // 系统推送:RootTabPage 注入,内部复用 ArkWeb 登录态完成 linux.do subscribe。
  // 必须是 @Prop:普通成员只在构造那一刻按值捕获,冷启动时会话校验还没回来就进本页的话,
  // 登录态会永久停在 false 的快照上,推送项一直显示"请先登录"、退出重进才好。
  // @Watch 在登录态真正落定(或登出/换号)时补刷一次推送状态。
  @Prop @Watch('onPushAccountChanged') currentUser: User = { id: 0, username: '' };
  @Prop @Watch('onPushAccountChanged') isLoggedIn: boolean = false;
  onEnablePush: () => Promise<PushRegistrationResult> = async () => {
    return { success: false, message: '推送服务未就绪' };
  };
  onDisablePush: () => Promise<PushRegistrationResult> = async () => {
    return { success: false, message: '推送服务未就绪' };
  };
  onRefreshPush: () => Promise<PushStatusResult> = async () => {
    return { enabled: false, message: '推送服务未就绪' };
  };
  onSendTestPush: () => Promise<PushStatusResult> = async () => {
    return { enabled: false, message: '推送服务未就绪' };
  };
  @State private pushEnabled: boolean = false;
  @State private pushRegistering: boolean = false;
  @State private pushTesting: boolean = false;
  @State private pushStatus: string = '未开启';
  @State private relaySummary: string = '';
  // 测试推送冷却倒计时(秒)。>0 时按钮显示秒数且不可点,与中继侧的按 subId 冷却对齐——
  // 这里只是体验层反馈,真正的防线在中继(换设备/重装都绕不过)。
  @State private testCooldownLeft: number = 0;
  private testCooldownTimer: number = -1;
  private pushRefreshSequence: number = 0;
  // 上次已据以刷新过推送状态的账号身份(未登录为空串)。见 onPushAccountChanged 的去重说明。
  private lastPushAccountKey: string = '';
  private scroller: Scroller = new Scroller();

  // 使用本项目运营的中继前的一次性告知。同意后记住,不再重复打扰。
  private relayConsentDialog: CustomDialogController = new CustomDialogController({
    builder: RelayConsentDialog({
      onAccept: () => {
        this.acceptRelayConsent();
      },
      onDecline: () => {
        this.declineRelayConsent();
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    // 不允许点遮罩关闭:关掉了开关状态会含糊,必须明确选一个。
    autoCancel: false
  });
  // 中继地址输入框。initialUrl 每次打开时由 promptRelayBaseUrl 重新灌入(见其注释)。
  private relayDialog: CustomDialogController = new CustomDialogController({
    builder: RelayBaseUrlDialog({
      // 闭包内惰性读:字段初始化此刻 this 上的方法尚可用,但值须调用时再取。
      onConfirm: (baseUrl: string) => {
        this.applyRelayBaseUrl(baseUrl);
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    // 与 onPushAccountChanged 共用去重基准:这里先记下挂载时的身份,避免 @Prop 首次同步
    // (对象换实例但账号没变)时白刷第二次。
    this.lastPushAccountKey = this.isLoggedIn ? `${this.currentUser.id}` : '';
    this.refreshRelaySummary();
    this.refreshPushState();
  }

  // 页面销毁时停掉冷却计时器,否则它会一直跑到 0 并持续触发已卸载组件的 @State 更新。
  aboutToDisappear(): void {
    this.stopTestCooldown();
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
          this.PushNotificationCell()
          // 测试推送紧跟开关:刚开完就想验一下是否真能收到,这是最顺的动线。
          // 中继地址属于"配置好就不再动"的项,排在后面。
          if (this.pushEnabled) {
            this.HairlineInset()
            this.TestPushNotificationCell()
          }
          this.HairlineInset()
          this.PushRelayCell()
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
          mainTitle: '通知'
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
  private PushNotificationCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.bell'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('系统推送通知')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.pushStatus)
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      if (this.pushRegistering) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.ld_accent'))
      } else {
        Toggle({ type: ToggleType.Switch, isOn: this.pushEnabled })
          .selectedColor($r('app.color.ld_accent'))
          .onChange((isOn: boolean) => {
            this.setPushEnabled(isOn);
          })
      }
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private TestPushNotificationCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.paperplane'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('发送测试推送')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('验证华为推送与点击跳转')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      if (this.pushTesting) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.ld_accent'))
      } else if (this.testCooldownLeft > 0) {
        // 冷却中显示剩余秒数:让用户知道为什么点不动,而不是默默失败。
        Text(`${this.testCooldownLeft}s`)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ right: 6 })
      } else {
        Text('发送')
          .fontSize(13)
          .fontColor($r('app.color.ld_accent'))
          .margin({ right: 6 })
        this.ChevronIcon()
      }
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    .onClick(() => {
      this.sendTestPush();
    })
  }

  // 中继地址:随包配置(relay-config.json,不进版本控制)缺失时,自行编译的用户靠这里填自己的中继。
  // 有随包配置时也允许覆盖,方便自建者切到自己的服务器。
  @Builder
  private PushRelayCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.wifi_router'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('推送中继地址')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.relaySummary)
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      this.ChevronIcon()
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    .onClick(() => {
      this.promptRelayBaseUrl();
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

  // 中继地址摘要:显示当前实际生效的地址,并标明它来自随包配置还是用户自填。
  private refreshRelaySummary(): void {
    const context: common.Context = this.hostContext();
    const custom: string = readCustomBaseUrl(context);
    const effective: PushRelayConfig = resolvePushRelayConfig(context);
    if (effective.baseUrl.length === 0) {
      this.relaySummary = '未配置，推送不可用';
      return;
    }
    this.relaySummary = custom.length > 0 ? `${effective.baseUrl}（自填）` : effective.baseUrl;
  }

  // 同意告知:记住选择,然后继续把推送开起来(此时 needsRelayConsent 已为 false,不会再弹)。
  private acceptRelayConsent(): void {
    saveRelayConsent(this.hostContext(), true);
    this.setPushEnabled(true);
  }

  // 谢绝:开关回到关闭态。这里的赋值有实际作用——弹框弹出前已乐观置 true,不改回来
  // 开关会停在"已开启"的样子,与实际状态不符。
  private declineRelayConsent(): void {
    this.pushEnabled = false;
    this.pushStatus = '未开启';
  }

  // 打开中继地址输入弹框。保存后重建服务实例(下次调用会重新解析配置),并刷新摘要。
  private promptRelayBaseUrl(): void {
    this.relayDialog.open();
  }

  private applyRelayBaseUrl(baseUrl: string): void {
    const context: common.Context = this.hostContext();
    if (!saveCustomBaseUrl(context, baseUrl)) {
      this.showToast('中继地址无效，需以 https:// 开头');
      return;
    }
    this.refreshRelaySummary();
    this.showToast(baseUrl.trim().length > 0 ? '已保存中继地址' : '已恢复为默认中继');
    // 地址变了,已有订阅指向的是旧中继:提示用户重开推送以迁移到新地址。
    if (this.pushEnabled) {
      this.showToast('中继已变更，请关闭再重新开启推送');
    }
  }

  // 登录态/账号变化(会话校验落定、登出、换号):本页可能早在校验返回前就已构造,
  // 此时推送项停在"请先登录";登录态到位后据此补刷一次。
  // 必须按"账号身份"去重再刷:currentUser 每次会话轮询都是新对象(RootTabPage 里
  // `this.currentUser = result.data`,未登录时还每次新建匿名对象),@Watch 会被反复触发,
  // 不去重的话每轮轮询都会触发一次完整重注册(取 token → 中继 → linux.do 写请求)。
  private onPushAccountChanged(): void {
    const accountKey: string = this.isLoggedIn ? `${this.currentUser.id}` : '';
    if (accountKey === this.lastPushAccountKey) {
      return;
    }
    this.lastPushAccountKey = accountKey;
    Log.i(`${LOG_TAG} push account changed loggedIn=${this.isLoggedIn} userId=${this.currentUser.id}`);
    this.refreshPushState();
  }

  private async setPushEnabled(isOn: boolean): Promise<void> {
    if (this.pushRegistering) {
      return;
    }
    // 乐观跟随用户拨动:失败/取消时再纠正回来。必须先赋值——否则 @State 的值没变化就
    // 不会重渲染,Toggle 会停在用户拨过去的位置,和实际状态对不上。
    this.pushEnabled = isOn;
    if (!this.isLoggedIn || this.currentUser.id <= 0) {
      this.pushEnabled = false;
      this.pushStatus = '请先登录论坛账号';
      this.showToast(this.pushStatus);
      return;
    }

    // 首次用本项目运营的中继开推送前,先把数据流向讲清楚并征得同意。
    // 自建中继的用户不弹(数据只经过他自己的机器);同意过一次就不再打扰。
    if (isOn && needsRelayConsent(this.hostContext())) {
      this.relayConsentDialog.open();
      return;
    }

    this.pushRegistering = true;
    this.pushStatus = isOn ? '正在注册' : '正在关闭';
    let result: PushRegistrationResult;
    try {
      result = isOn ? await this.onEnablePush() : await this.onDisablePush();
    } catch (err) {
      Log.i(`${LOG_TAG} push toggle exception target=${isOn} error=${JSON.stringify(err)}`);
      result = {
        success: false,
        message: isOn ? '推送注册异常' : '推送关闭异常'
      };
    }
    Log.i(`${LOG_TAG} push toggle result target=${isOn} success=${result.success} message=${result.message}`);
    this.pushRegistering = false;
    this.pushEnabled = isOn ? result.success : !result.success;
    this.pushStatus = result.success ? (isOn ? '已开启' : '未开启') : result.message;
    this.showToast(result.message);
  }

  private async sendTestPush(): Promise<void> {
    if (this.pushTesting || this.pushRegistering) {
      return;
    }
    if (this.testCooldownLeft > 0) {
      this.showToast(`请 ${this.testCooldownLeft} 秒后再试`);
      return;
    }
    if (!this.isLoggedIn || this.currentUser.id <= 0) {
      this.showToast('请先登录论坛账号');
      return;
    }
    if (!this.pushEnabled) {
      this.showToast('请先开启系统推送通知');
      return;
    }

    this.pushTesting = true;
    let result: PushStatusResult;
    try {
      result = await this.onSendTestPush();
    } catch (err) {
      Log.i(`${LOG_TAG} push test exception error=${JSON.stringify(err)}`);
      result = {
        enabled: false,
        message: '测试推送发送异常'
      };
    }
    this.pushTesting = false;
    this.showToast(result.message);
    // 无论成败都进入冷却:失败多半就是撞上了中继的冷却,此时更不该让用户继续猛点。
    this.startTestCooldown();
  }

  // 本地倒计时,与中继的按 subId 冷却窗口对齐(默认 60s)。
  private startTestCooldown(): void {
    this.stopTestCooldown();
    this.testCooldownLeft = TEST_PUSH_COOLDOWN_SEC;
    this.testCooldownTimer = setInterval(() => {
      this.testCooldownLeft--;
      if (this.testCooldownLeft <= 0) {
        this.stopTestCooldown();
      }
    }, 1000);
  }

  private stopTestCooldown(): void {
    if (this.testCooldownTimer !== -1) {
      clearInterval(this.testCooldownTimer);
      this.testCooldownTimer = -1;
    }
    this.testCooldownLeft = 0;
  }

  private async refreshPushState(): Promise<void> {
    if (!this.isLoggedIn || this.currentUser.id <= 0) {
      this.pushEnabled = false;
      this.pushStatus = '请先登录论坛账号';
      return;
    }
    const start: PushRefreshStart = nextPushRefreshStart(this.pushRefreshSequence, this.pushRegistering);
    if (!start.shouldStart) {
      return;
    }
    const sequence: number = start.sequence;
    this.pushRefreshSequence = sequence;
    this.pushRegistering = true;
    this.pushStatus = '检查中';
    let result: PushStatusResult;
    try {
      result = await this.onRefreshPush();
    } catch (err) {
      Log.i(`${LOG_TAG} push refresh exception error=${JSON.stringify(err)}`);
      result = {
        enabled: false,
        message: '推送状态检查失败'
      };
    }
    if (sequence !== this.pushRefreshSequence) {
      return;
    }
    this.pushRegistering = false;
    this.pushEnabled = result.enabled;
    this.pushStatus = result.message;
  }

  private showToast(message: string): void {
    promptToast(this.getUIContext(), message);
  }
}

// 使用本项目运营的中继前的一次性告知。
// 文案刻意不写"不收集任何数据"——中继解密后确实看得到通知标题与摘要,那是它的工作原理。
// 与其含糊其辞,不如把数据怎么流、我们不做什么讲清楚,并给出自建中继的出路。
// 排版上把大段说明拆成"一句话 + 三条要点",避免堆成一屏像法律条款没人看。
@CustomDialog
struct RelayConsentDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: RelayConsentDialog({}) });
  onAccept: () => void = () => {};
  onDecline: () => void = () => {};

  // 流程节点标签。四个节点要挤进弹框宽度,故字号与内边距都压得较小。
  @Builder
  private FlowChip(label: string) {
    Text(label)
      .fontSize(10.5)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 7, right: 7, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(6)
      .maxLines(1)
  }

  @Builder
  private FlowArrow() {
    SymbolGlyph($r('sys.symbol.arrow_right'))
      .fontSize(9)
      .fontColor([$r('app.color.text_faint')])
      .margin({ left: 3, right: 3 })
  }

  // 单条要点:小图标 + 一句话。图标顶对齐,文案换行时不会与图标错位。
  @Builder
  private PointRow(symbol: Resource, text: string) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(15)
        .fontColor([$r('app.color.text_faint')])
        .margin({ top: 2 })
      Text(text)
        .fontSize(13.5)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .margin({ left: 10 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 10 })
  }

  build() {
    Column() {
      // 顶部图标:给纯文字的告知一个视觉落点,避免一上来就是一屏字。
      Column() {
        SymbolGlyph($r('sys.symbol.bell_fill'))
          .fontSize(26)
          .fontColor([$r('app.color.ld_accent')])
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor($r('app.color.surface_muted'))
      .justifyContent(FlexAlign.Center)
      .margin({ top: 26, bottom: 14 })

      Text('开启推送前')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)

      // 点名 Discourse:通知走的是它的标准 Web Push 机制,不是我们自造的一套。
      // 说清出处比空口承诺更能建立信任,懂行的人也能自行验证。
      Text('站点使用 Discourse（开源论坛程序），通知按其标准的 Web Push 协议加密发出')
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 26, right: 26 })
        .margin({ top: 8, bottom: 16 })

      // 数据流向可视化:一眼看清经过谁、到哪去,比一段话更好读。
      Row() {
        this.FlowChip('Discourse')
        this.FlowArrow()
        this.FlowChip('中继')
        this.FlowArrow()
        this.FlowChip('华为推送')
        this.FlowArrow()
        this.FlowChip('你的手机')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 18 })

      // 三条要点:第一条讲清代价(诚实),后两条讲清边界(安心)。
      Column() {
        this.PointRow($r('sys.symbol.paperplane'), '中继需要解密才能转发，因此通知的标题和摘要会经过它')
        this.PointRow($r('sys.symbol.eye_slash'), '不保存这些内容，也不用作其他用途')
        this.PointRow($r('sys.symbol.lock_fill'), '中继上没有你的账号密码或登录凭证')
      }
      .width('100%')
      .padding({ left: 24, right: 24 })

      // 「已开源」这句是前面三条承诺的兑现凭据:不必信我们的说法,代码可自行查验。
      Text('想让数据只经过自己的机器？可在「推送中继地址」填入自建中继。中继代码已开源')
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ top: 16, bottom: 20 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))

      Row() {
        Button('暂不开启')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.onDecline();
            this.controller.close();
          })

        Divider()
          .vertical(true)
          .strokeWidth(0.5)
          .height(24)
          .color($r('app.color.border'))

        Button('明白了，开启')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            this.onAccept();
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('86%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_dialog'))
    .clip(true)
  }
}

// 自建中继地址输入框。样式对齐同仓 AddDohDialog(原生鸿蒙 AlertDialog 风格)。
@CustomDialog
struct RelayBaseUrlDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: RelayBaseUrlDialog({}) });
  onConfirm: (baseUrl: string) => void = () => {};
  @State private url: string = '';

  // 自己读当前值,不由父页注入:CustomDialogController 在字段初始化时就固定了 builder 参数,
  // 外部注入的值会停在构造那一刻,改完再打开会显示旧值。
  aboutToAppear(): void {
    this.url = readCustomBaseUrl(this.getUIContext().getHostContext() as common.Context);
  }

  build() {
    Column() {
      Text('推送中继地址')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 22, bottom: 10 })

      Text('填写自建中继的地址。留空则使用应用自带配置。\n部署方法见项目仓库 server/ 目录。')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ bottom: 16 })

      Column() {
        TextInput({ placeholder: 'https://push.example.com', text: this.url })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.url = value;
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .margin({ bottom: 20 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.controller.close();
          })

        Divider()
          .vertical(true)
          .strokeWidth(0.5)
          .height(24)
          .color($r('app.color.border'))

        Button('保存')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            // 校验交给调用方(saveCustomBaseUrl 统一做 https 校验),这里只负责回传。
            this.onConfirm(this.url);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('86%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_dialog'))
    .clip(true)
  }
}
