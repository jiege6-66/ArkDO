import { Log } from '../../services/logging/Log';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { LinuxDoConstants } from '../../common/constants/AppConstants';
import { LdcDailyStat, LdcUserInfo } from '../../models/LdcCredit';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { LdcCreditEventBus } from '../../services/credit/LdcCreditEventBus';
import { LdcCreditService } from '../../services/credit/LdcCreditService';
import { LdcCreditSession } from '../../services/credit/LdcCreditSession';
import { WebSessionManager } from '../../services/web/WebSessionManager';
import { LdcCreditWebHost } from '../components/LdcCreditWebHost';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';
import { formatLdcAmount, ldcAmountValue, ldcDayLabel } from '../../common/utils/LdcFormat';

const LOG_TAG: string = '[ArkDO][LdcPage]';
// 最近记录的天数。接口以 days 参数控制,7 天正好一屏放得下,不做分页。
const RECENT_DAYS: number = 7;
// 登录轮询:credit 的登录态就是 linux_do_credit_session_id 这枚 cookie,OAuth 回跳没有可靠的
// 完成回调(会经 linux.do 授权页多次跳转),故与 CfChallengePage 同法——轮询 cookie 出现即算成功。
const LOGIN_POLL_INTERVAL_MS: number = 1000;
const MAX_LOGIN_POLL_COUNT: number = 180;
// 收支条的最小可见宽度:非零金额哪怕很小也画出一点,避免看起来像 0。
const BAR_MIN_PERCENT: number = 4;

enum LdcPhase {
  LOADING = 0,
  READY = 1,
  // credit 未登录:显示「去登录」。与 linux.do 的登录态无关——两边是各自独立的会话。
  ANON = 2,
  ERROR = 3,
  // 登录进行中:credit 页面全屏可见,用户在里面走 LinuxDO OAuth。
  LOGGING_IN = 4
}

/**
 * LINUX DO Credit 页:个人中心的 Credit 入口进来。
 *
 * credit.linux.do 与 linux.do 不同源且同样在 CF 后面,故本页自持一个 credit 同源的隐藏 Web
 * (LdcCreditWebHost)作为注入式 fetch 的宿主,再用原生控件画余额与最近 7 天收支。
 */
@Component
export struct LdcCreditPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  // 进入即拉起登录(个人中心点「去登录」时为真)。
  @Prop startLogin: boolean = false;
  scroller: Scroller = new Scroller();
  onBack: () => void = () => {};

  @State private phase: LdcPhase = LdcPhase.LOADING;
  @State private info?: LdcUserInfo = undefined;
  @State private dailyStats: LdcDailyStat[] = [];
  @State private errorMessage: string = '';
  // 宿主挂载开关:未登录态不必起 webview,省一次页面加载。
  @State private hostActive: boolean = false;
  // 宿主的导航目标,改这个值即触发一次真实跳转(登录时跳 credit 站内页)。
  @State private hostNavTarget: string = '';
  // 宿主新建时的首屏地址。宿主已挂载时改 hostNavTarget 跳转,未挂载时改这里再挂上——
  // 后者不能用 hostNavTarget,@Watch 对初值不触发。
  private hostInitialUrl: string = LinuxDoConstants.CREDIT_BOOTSTRAP_URL;

  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private isHostReady: boolean = false;
  private isLoading: boolean = false;
  private loginPollTimer: number = -1;
  private loginPollCount: number = 0;

  aboutToAppear(): void {
    WebSessionManager.configureCookieAccess('LdcCreditPage');
    // 先把上次的余额画出来,避免请求回来前整页空着;随后的请求会原地覆盖。
    this.info = LdcCreditSession.getCachedInfo();

    if (this.startLogin || !LdcCreditSession.hasSession()) {
      if (this.startLogin) {
        this.beginLogin();
      } else {
        this.phase = LdcPhase.ANON;
      }
      return;
    }
    this.phase = LdcPhase.LOADING;
    this.hostActive = true;
  }

  aboutToDisappear(): void {
    this.stopLoginPolling();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // credit 宿主必须垫在**栈底**。取数时它近透明、被上层内容完全遮挡,满视口只是为了给 CF 挑战 JS
      // 一个真实浏览器环境(1×1 会被判机器人)。放到栈顶试过:即便 opacity 0.01 且 hitTestBehavior=None,
      // 内嵌 Web 是原生绘制面,仍会吞掉落在它上面的点击——表现就是标题栏返回键点不动。
      if (this.hostActive) {
        Column() {
          // 登录态让出顶栏高度,好让上面那条「取消」栏不遮住 credit 页面自己的头部。
          if (this.phase === LdcPhase.LOGGING_IN) {
            Blank()
              .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))
          }
          LdcCreditWebHost({
            bridge: this.bridge,
            interactive: this.phase === LdcPhase.LOGGING_IN,
            initialUrl: this.hostInitialUrl,
            navTarget: this.hostNavTarget,
            onReady: () => {
              this.onHostReady();
            },
            onLoadFailed: () => {
              this.onHostLoadFailed();
            },
            onPageSettled: (url: string) => {
              this.onHostPageSettled(url);
            }
          })
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
      }

      // 登录态整块让位:内容与标题栏都不渲染,宿主才露得出来;只压一条能退出登录流程的顶栏。
      if (this.phase === LdcPhase.LOGGING_IN) {
        this.LoginTopBar()
      } else {
        this.ScrollableContent()
        this.TitleBarOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg_gray'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ==================== 顶栏 ====================

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
          mainTitle: 'LINUX DO Credit'
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

  // 登录态顶栏:盖在全屏 credit 页面之上,提供退出登录流程的出口。
  @Builder
  private LoginTopBar() {
    Row() {
      Text('登录 LINUX DO Credit')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text('取消')
        .fontSize(15)
        .fontColor($r('app.color.ld_accent'))
        .onClick(() => {
          this.cancelLogin();
        })
    }
    .width('100%')
    .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))
    .padding({ left: PAGE_MARGIN + 4, right: PAGE_MARGIN + 4, top: this.sysTopInset })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }

  // ==================== 内容 ====================

  @Builder
  private ScrollableContent() {
    Scroll(this.scroller) {
      Column() {
        Blank()
          .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))

        if (this.phase === LdcPhase.READY && this.info) {
          this.BalanceCard(this.info)
          this.DailyCard()
          this.PoweredByFooter()
        } else if (this.phase === LdcPhase.ANON) {
          this.MessageState('未登录 LINUX DO Credit', '使用 LINUX DO 账号登录后,即可查看余额与获取记录', true, false)
        } else if (this.phase === LdcPhase.ERROR) {
          this.MessageState('暂时无法获取', this.errorMessage.length > 0 ? this.errorMessage : '可能是网络问题或需要完成人机验证', false, true)
        } else if (this.phase === LdcPhase.LOADING) {
          this.LoadingState()
        }

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
  private BalanceCard(info: LdcUserInfo) {
    Column() {
      Text('可用余额')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row() {
        Text(formatLdcAmount(info.availableBalance))
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('LDC')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_faint'))
          .margin({ left: 6, bottom: 4 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 4 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))
        .margin({ top: 14, bottom: 14 })

      Row() {
        this.MetricCell('社区余额', formatLdcAmount(info.communityBalance))
        this.MetricCell('待结算', formatLdcAmount(info.pendingBalance))
      }
      .width('100%')

      Row() {
        this.MetricCell('剩余额度', formatLdcAmount(info.remainQuota))
        this.MetricCell('每日限额', formatLdcAmount(info.dailyLimit))
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding(CARD_PADDING)
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private MetricCell(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DailyCard() {
    Column() {
      Row() {
        Text(`最近 ${RECENT_DAYS} 天`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`共 +${formatLdcAmount(this.totalIncome())}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ldc_income'))
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 6 })

      if (this.dailyStats.length > 0) {
        ForEach(this.dailyStats, (stat: LdcDailyStat) => {
          this.DailyRow(stat)
        }, (stat: LdcDailyStat) => stat.date)
      } else {
        Text('最近没有获取记录')
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 10, bottom: CARD_PADDING })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DailyRow(stat: LdcDailyStat) {
    Column() {
      Row() {
        Text(ldcDayLabel(stat.date))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (ldcAmountValue(stat.expense) > 0) {
          Text(`-${formatLdcAmount(stat.expense)}`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ld_danger'))
            .margin({ right: 10 })
        }
        Text(ldcAmountValue(stat.income) > 0 ? `+${formatLdcAmount(stat.income)}` : '—')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ldcAmountValue(stat.income) > 0 ? $r('app.color.ldc_income') : $r('app.color.text_faint'))
      }
      .width('100%')

      // 收入条:按当期最大值等比,给 7 天的多寡一个一眼可辨的形状。
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(5)
          .borderRadius(2.5)
          .backgroundColor($r('app.color.surface_muted'))
        Column()
          .width(this.incomeBarWidth(stat))
          .height(5)
          .borderRadius(2.5)
          .backgroundColor($r('app.color.ldc_income'))
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 11, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PoweredByFooter() {
    Row() {
      Text('数据来自 ')
        .fontSize(12)
        .fontColor($r('app.color.text_faint'))
      Text('credit.linux.do')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 18, bottom: 10 })
  }

  @Builder
  private LoadingState() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.ld_accent'))
      Text('正在获取 Credit 数据')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 14 })
    }
    .width('100%')
    .height(280)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private MessageState(title: string, subtitle: string, loginable: boolean, retryable: boolean) {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(40)
        .fontColor([$r('app.color.text_faint')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
      Text(subtitle)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
        .padding({ left: 24, right: 24 })
      if (loginable) {
        Button('去登录')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.ld_accent'))
          .height(42)
          .padding({ left: 40, right: 40 })
          .borderRadius(21)
          .margin({ top: 22 })
          .onClick(() => {
            this.beginLogin();
          })
      }
      if (retryable) {
        Button('重试')
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.ld_accent'))
          .height(42)
          .padding({ left: 40, right: 40 })
          .borderRadius(21)
          .margin({ top: 22 })
          .onClick(() => {
            this.retry();
          })
      }
    }
    .width('100%')
    .height(320)
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 宿主事件 ====================

  private onHostReady(): void {
    this.isHostReady = true;
    if (this.phase === LdcPhase.LOGGING_IN) {
      return;
    }
    this.loadAll();
  }

  private onHostLoadFailed(): void {
    if (this.phase === LdcPhase.LOGGING_IN || this.phase === LdcPhase.READY) {
      return;
    }
    this.errorMessage = '连接 credit.linux.do 失败,请检查网络后重试';
    this.phase = LdcPhase.ERROR;
  }

  // OAuth 回跳会连着触发好几次 onPageEnd(linux.do 授权页 → credit 回调 → 站内页),
  // 每次都复查一遍 cookie,让登录成功尽早被发现(轮询只是兜底)。
  private onHostPageSettled(url: string): void {
    if (this.phase !== LdcPhase.LOGGING_IN) {
      return;
    }
    Log.i(`${LOG_TAG} login page settled sameSite=${url.startsWith(LinuxDoConstants.CREDIT_BASE_URL)}`);
    this.settleLoginIfSessionExists();
  }

  // ==================== 数据加载 ====================

  private loadAll(): void {
    if (this.isLoading || !this.isHostReady) {
      return;
    }
    this.isLoading = true;
    const service: LdcCreditService = new LdcCreditService(this.bridge);
    this.loadUserInfo(service);
    this.loadDailyStats(service);
  }

  private async loadUserInfo(service: LdcCreditService): Promise<void> {
    const result: NetworkResult<LdcUserInfo> = await service.getUserInfo();
    this.isLoading = false;
    if (result.success && result.data) {
      this.info = result.data;
      this.phase = LdcPhase.READY;
      LdcCreditSession.setCachedInfo(result.data);
      // 个人中心的入口行压在本页下面不会重新 appear,靠这条广播刷新它的数字。
      LdcCreditEventBus.notifyCreditChanged();
      return;
    }

    // 401 = credit 会话过期或从未登录(与 linux.do 的登录态无关),转「去登录」而非报错。
    if (result.statusCode === 401) {
      LdcCreditSession.clearCache();
      this.info = undefined;
      this.phase = LdcPhase.ANON;
      LdcCreditEventBus.notifyCreditChanged();
      return;
    }

    this.errorMessage = result.error ? result.error.message : '';
    this.phase = LdcPhase.ERROR;
  }

  private async loadDailyStats(service: LdcCreditService): Promise<void> {
    const result: NetworkResult<LdcDailyStat[]> = await service.getDailyStats(RECENT_DAYS);
    if (result.success && result.data) {
      this.dailyStats = LdcCreditPage.sortNewestFirst(result.data);
    }
  }

  // 官方界面是最新的一天在最上面。接口给的顺序不保证,故按日期串倒序自己排一遍——
  // 日期是 'YYYY-MM-DD' 定长格式,字典序即时间序,不必解析成 Date。
  private static sortNewestFirst(stats: LdcDailyStat[]): LdcDailyStat[] {
    const sorted: LdcDailyStat[] = stats.slice();
    sorted.sort((left: LdcDailyStat, right: LdcDailyStat) => right.date.localeCompare(left.date));
    return sorted;
  }

  private retry(): void {
    this.errorMessage = '';
    this.phase = LdcPhase.LOADING;
    if (!this.hostActive) {
      this.hostActive = true;
      return;
    }
    this.loadAll();
  }

  // ==================== 登录 ====================

  // 拉起 credit 登录:把宿主切成全屏可交互并导航到站内页,由用户在真实页面里走完 LinuxDO OAuth。
  // 不自己拼 OAuth 地址——授权链路是 credit 自己的,跟着它的页面走才不会因端点变更而失效。
  private beginLogin(): void {
    this.phase = LdcPhase.LOGGING_IN;
    if (this.hostActive) {
      // 宿主已在跑(取数失败后改走登录):就地导航到站内页。
      this.hostNavTarget = LinuxDoConstants.CREDIT_HOME_URL;
    } else {
      // 宿主还没起:让它直接以站内页开局,别先加载一遍 JSON 接口再跳。
      this.hostInitialUrl = LinuxDoConstants.CREDIT_HOME_URL;
      this.hostActive = true;
    }
    this.startLoginPolling();
  }

  private cancelLogin(): void {
    this.stopLoginPolling();
    if (LdcCreditSession.hasSession()) {
      this.phase = LdcPhase.LOADING;
      this.loadAll();
      return;
    }
    this.phase = LdcPhase.ANON;
  }

  private startLoginPolling(): void {
    if (this.loginPollTimer >= 0) {
      return;
    }
    this.loginPollCount = 0;
    this.loginPollTimer = setInterval(() => {
      this.loginPollCount++;
      if (this.settleLoginIfSessionExists()) {
        return;
      }
      if (this.loginPollCount >= MAX_LOGIN_POLL_COUNT) {
        Log.i(`${LOG_TAG} login polling timeout`);
        this.stopLoginPolling();
      }
    }, LOGIN_POLL_INTERVAL_MS);
  }

  private stopLoginPolling(): void {
    if (this.loginPollTimer < 0) {
      return;
    }
    clearInterval(this.loginPollTimer);
    this.loginPollTimer = -1;
  }

  // cookie 一出现就收尾:落盘 cookie、收起登录页、直接取数(此刻文档已在 credit 站内页,同源可用)。
  private settleLoginIfSessionExists(): boolean {
    if (!LdcCreditSession.hasSession()) {
      return false;
    }
    Log.i(`${LOG_TAG} credit session established`);
    WebSessionManager.saveCookies('LdcCreditPage');
    this.stopLoginPolling();
    this.phase = LdcPhase.LOADING;
    this.loadAll();
    return true;
  }

  // ==================== 计算辅助 ====================

  private totalIncome(): string {
    let total: number = 0;
    for (let index: number = 0; index < this.dailyStats.length; index++) {
      total += ldcAmountValue(this.dailyStats[index].income);
    }
    // 合计是派生的展示值,这里才允许落到数值域;逐日金额本身始终保持字符串原样。
    return `${Math.round(total * 100) / 100}`;
  }

  private incomeBarWidth(stat: LdcDailyStat): string {
    const value: number = ldcAmountValue(stat.income);
    if (value <= 0) {
      return '0%';
    }
    let max: number = 0;
    for (let index: number = 0; index < this.dailyStats.length; index++) {
      const current: number = ldcAmountValue(this.dailyStats[index].income);
      if (current > max) {
        max = current;
      }
    }
    if (max <= 0) {
      return '0%';
    }
    const percent: number = (value / max) * 100;
    return `${percent < BAR_MIN_PERCENT ? BAR_MIN_PERCENT : Math.round(percent * 10) / 10}%`;
  }
}
