import { Log } from '../../services/logging/Log';
import webview from '@ohos.web.webview';
import { LinuxDoConstants } from '../../common/constants/AppConstants';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][LdcHost]';
// 就绪看门狗:主框架既没 onPageEnd 也没报错(慢速僵死连接)时兜底判失败,不让调用方干等到超时。
const BOOT_WATCHDOG_MS: number = 12000;

/**
 * credit.linux.do 的注入式 fetch 宿主。与 ArkWebHost 同构,只是换了源。
 *
 * 存在的理由:credit 的接口不回 CORS 头,只有「credit 同源文档」内的 fetch 能拿到数据;而 credit
 * 同样在 CF 后面,原生 http 请求过不了盾。故这里真加载一个 credit 文档(最轻的那个 JSON 接口,
 * 只为定 origin),再把 bridge 挂上去——之后所有 credit 请求都走注入 fetch,天然带 cookie、过盾。
 *
 * 满视口 + 近透明:被上层不透明 UI 完全遮挡,视觉无变化;但给 CF 挑战 JS 一个真实浏览器视口
 * (1×1 会被判机器人),非交互挑战才可能在此静默跑通。login=true 时改为完全可见且可交互,
 * 用于让用户就地完成 LinuxDO OAuth 授权。
 */
@Component
export struct LdcCreditWebHost {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  // 可见交互模式:走登录流程时为 true(用户要能点授权按钮),取数时为 false(隐藏在底层)。
  @Prop interactive: boolean = false;
  // 首屏地址。默认是最轻的 JSON 接口(只为拿一个 credit 同源文档);登录流程改传站内页。
  // 与 navTarget 分工明确:本组件是新建的走 initialUrl,已挂载再要跳转才走 navTarget——
  // @Watch 对「创建时的初值」不触发,只靠 navTarget 会让新建即登录的那条路加载错页面。
  initialUrl: string = LinuxDoConstants.CREDIT_BOOTSTRAP_URL;
  // 导航目标。父组件改这个值即触发一次真实页面跳转(登录流程跳 credit 站内页);空串表示不跳。
  // Web 的 src 只在创建时生效,后续导航只能经 controller.loadUrl,故这里用 @Watch 转成一次调用。
  @Prop @Watch('onNavTargetChanged') navTarget: string = '';
  onReady: () => void = () => {};
  onLoadFailed: () => void = () => {};
  // 每次主框架加载完成都回调(含 OAuth 跳转落地),登录流程据此复查 cookie。
  onPageSettled: (url: string) => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private hasNotifiedReady: boolean = false;
  private hasReportedFailure: boolean = false;
  private bootWatchdogTimer: number = -1;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('LdcCreditWebHost');
    this.startBootWatchdog();
  }

  aboutToDisappear(): void {
    this.clearBootWatchdog();
  }

  build() {
    Web({ src: this.initialUrl, controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .onlineImageAccess(true)
      .imageAccess(true)
      .mixedMode(MixedMode.All)
      .cacheMode(CacheMode.Default)
      .javaScriptProxy(this.bridge.createJavaScriptProxy(this.controller))
      .onControllerAttached(() => {
        WebSessionManager.applyUserAgent(this.controller, 'LdcCreditWebHost');
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (this.hasNotifiedReady || !event.request.isMainFrame()) {
          return;
        }
        Log.i(`${LOG_TAG} main frame error code=${event.error.getErrorCode()} info=${event.error.getErrorInfo()}`);
        this.reportLoadFailed('errorReceive');
      })
      .onPageEnd((event: OnPageEndEvent) => {
        this.clearBootWatchdog();
        WebSessionManager.saveCookies('LdcCreditWebHost');
        this.bridge.attachController(this.controller);
        this.bridge.markHostReady();
        if (!this.hasNotifiedReady) {
          this.hasNotifiedReady = true;
          Log.i(`${LOG_TAG} host ready`);
          this.onReady();
        }
        this.onPageSettled(event.url);
      })
      .width('100%')
      .height('100%')
      .opacity(this.interactive ? 1 : 0.01)
      // 取数模式下压在页面底层:不吃触摸,免得挡住上层滚动/点击。登录模式必须可交互。
      .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
  }

  // 导航到 credit 站内页(登录流程用:让用户在真实页面里走完 LinuxDO OAuth)。
  private onNavTargetChanged(): void {
    const url: string = this.navTarget;
    if (url.length === 0) {
      return;
    }
    try {
      this.bridge.markHostReloading();
      this.controller.loadUrl(url);
    } catch (error) {
      // loadUrl 抛异常时不会有后续 onPageEnd,立即放行等待者以免请求悬住。
      this.bridge.markHostReady();
      Log.i(`${LOG_TAG} loadUrl failed error=${JSON.stringify(error)}`);
    }
  }

  private reportLoadFailed(reason: string): void {
    if (this.hasNotifiedReady || this.hasReportedFailure) {
      return;
    }
    this.hasReportedFailure = true;
    this.clearBootWatchdog();
    Log.i(`${LOG_TAG} load failed reason=${reason}`);
    // 放行排队的注入 fetch,让它们快速失败暴露「加载失败/重试」,而不是悬住到超时。
    this.bridge.markHostReady();
    this.onLoadFailed();
  }

  private startBootWatchdog(): void {
    this.clearBootWatchdog();
    this.hasReportedFailure = false;
    this.bootWatchdogTimer = setTimeout(() => {
      this.bootWatchdogTimer = -1;
      this.reportLoadFailed('watchdog');
    }, BOOT_WATCHDOG_MS);
  }

  private clearBootWatchdog(): void {
    if (this.bootWatchdogTimer >= 0) {
      clearTimeout(this.bootWatchdogTimer);
      this.bootWatchdogTimer = -1;
    }
  }
}
