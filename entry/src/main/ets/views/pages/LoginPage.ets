import { Log } from '../../services/logging/Log';
import webview from '@ohos.web.webview';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { CookiePresenceSnapshot } from '../../services/web/WebSessionManager';
import { WebSessionManager } from '../../services/web/WebSessionManager';
import { LoginKeyboardBridge } from '../../services/web/LoginKeyboardBridge';
import { window } from '@kit.ArkUI';

const LOG_TAG: string = '[ArkDO][Login]';
// 收键盘这条链路的日志统一用这个标签(与 LoginKeyboardBridge 里的一致),便于一次 grep 全链路。
const KBD_TAG: string = '[ArkDO][LoginKbd]';
const CHALLENGE_POLL_INTERVAL_MS: number = 1000;
const MAX_CHALLENGE_POLL_COUNT: number = 90;
// 登录态轮询:Discourse SPA 登录成功走客户端路由跳转(pushState),不触发 onPageEnd,
// 单靠 URL 判定会漏检。改盯登录令牌 cookie `_t`(登出时无、登录后下发)兜住这条路径。
const LOGIN_POLL_INTERVAL_MS: number = 800;
const AUTH_COOKIE_NAME: string = '_t';

@Component
export struct LoginPage {
  onClose: () => void = () => {};
  onLoginSuccess: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  // 收键盘桥:登录页专用,只暴露一个「请收起软键盘」的方法。见 LoginKeyboardBridge 的注释。
  private keyboardBridge: LoginKeyboardBridge = new LoginKeyboardBridge();
  private winClass: window.Window | undefined = undefined;
  /**
   * 注入时机绑在「软键盘弹起」上,而不是 onPageEnd。
   *
   * 登录前面还有一个加载/中转页,onPageEnd 多半是给那个页面触发的,之后真正的表单是客户端路由
   * 出来的 —— 那时既不会再有 onPageEnd,先前注入的监听也早被新文档冲掉了。
   * 而键盘弹起意味着用户已经点进了表单里的输入框:此刻文档一定是最终那个,且可交互。
   *
   * 每次弹起都注入一遍:脚本自身有 __arkdoLoginKbdReady 标记挡重复,而标记随文档销毁自动失效,
   * 换了文档正好重新挂上,不需要我们跟踪页面状态。
   */
  private onAvoidAreaChange: (data: window.AvoidAreaOptions) => void = (data: window.AvoidAreaOptions) => {
    if (data.type !== window.AvoidAreaType.TYPE_KEYBOARD) {
      return;
    }
    if (this.getUIContext().px2vp(data.area.bottomRect.height) > 0) {
      this.injectKeyboardDismissScript();
    }
  };
  private challengePollTimer: number = -1;
  private challengePollCount: number = 0;
  private hasReloadedAfterChallenge: boolean = false;
  // 登录态轮询:检测 `_t` cookie 从"无"变"有"即判定登录成功;单次守卫防与 onPageEnd 路径重复触发。
  private loginPollTimer: number = -1;
  private initialAuthCookiePresent: boolean = false;
  private hasSignaledLoginSuccess: boolean = false;

  aboutToAppear(): void {
    window.getLastWindow(this.getUIContext().getHostContext() as common.Context).then((win: window.Window) => {
      this.winClass = win;
      win.on('avoidAreaChange', this.onAvoidAreaChange);
    }).catch(() => {
      Log.i(`${KBD_TAG} listen keyboard failed`);
    });
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('LoginPage');
    // 记录进入登录页时的登录令牌基线(常态为无),只在其后新出现时才判成功,避免误触发。
    this.initialAuthCookiePresent = WebSessionManager.hasCookie(AUTH_COOKIE_NAME);
    this.startLoginCookiePolling();
  }

  aboutToDisappear(): void {
    if (this.winClass) {
      this.winClass.off('avoidAreaChange', this.onAvoidAreaChange);
      this.winClass = undefined;
    }
    this.stopChallengeCookiePolling();
    this.stopLoginCookiePolling();
  }

  build() {
    Column() {
      Row() {
        Blank()
        Text('登录')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.page_bg'))
      .border({
        width: { bottom: 1 },
        color: $r('app.color.border')
      })

      Web({ src: AppConstants.LOGIN_URL, controller: this.controller })
        .javaScriptProxy(this.keyboardBridge.createProxy(this.controller))
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .cacheMode(CacheMode.Default)
        .onControllerAttached(() => {
          WebSessionManager.applyUserAgent(this.controller, 'LoginPage');
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          Log.i(`${LOG_TAG} page begin url=${event.url}`);
        })
        .onPageEnd((event: OnPageEndEvent) => {
          Log.i(`${LOG_TAG} page end url=${event.url}`);
          WebSessionManager.saveCookies('LoginPage');
          this.logCfClearanceSnapshot('pageEnd');
          if (this.isLikelyLoggedInUrl(event.url)) {
            this.signalLoginSuccess('pageEnd', event.url);
          }
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          Log.i(`${LOG_TAG} load error url=${this.safeRequestUrl(event.request)} code=${this.safeErrorCode(event.error)} info=${this.safeErrorInfo(event.error)}`);
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          const url: string = this.safeRequestUrl(event.request);
          const statusCode: number = this.safeResponseCode(event.response);
          Log.i(`${LOG_TAG} http error url=${url} status=${statusCode} reason=${this.safeReasonMessage(event.response)}`);
          if (this.isChallengeRelatedHttpError(url, statusCode)) {
            this.startChallengeCookiePolling();
          }
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  // 键盘还杵着时点「登录」,ArkUI 的键盘避让已把整个 sheet 顶上去,hCaptcha 的验证弹层
  // 按顶起后的视口定位,弹出来有一截落在可视区外被裁掉,用户没法完成验证。
  // 实测手动收起键盘再点登录一切正常,所以在点击那一刻把键盘收掉即可。
  private injectKeyboardDismissScript(): void {
    // runJavaScript 可能同步抛(控制器未就绪等),不是所有失败都走 Promise 的 reject 分支。
    // 成败都不打扰用户:注入不上只是少了这层便利,登录本身照常可用,所以只留失败日志。
    try {
      this.controller.runJavaScript(LoginKeyboardBridge.script())
        .catch(() => {
          Log.i(`${KBD_TAG} script inject rejected`);
        });
    } catch (error) {
      Log.i(`${KBD_TAG} script inject threw`);
    }
  }

  private isChallengeRelatedHttpError(url: string, statusCode: number): boolean {
    if (statusCode !== 401 && statusCode !== 403 && statusCode !== 429) {
      return false;
    }
    return url.startsWith(AppConstants.LOGIN_URL) || url.indexOf('challenges.cloudflare.com') >= 0;
  }

  private isLikelyLoggedInUrl(url: string): boolean {
    if (!url.startsWith(AppConstants.BASE_URL)) {
      return false;
    }
    if (url.startsWith(AppConstants.LOGIN_URL) || url.startsWith(AppConstants.CHALLENGE_URL)) {
      return false;
    }
    return true;
  }

  // 登录态 cookie 轮询:登录页开着期间每 800ms 查一次 `_t`;新出现即判登录成功。
  // Discourse SPA 登录成功不必然触发 onPageEnd,这是补齐检测的主路径。页面关闭/成功即停。
  private startLoginCookiePolling(): void {
    if (this.loginPollTimer >= 0) {
      return;
    }
    this.loginPollTimer = setInterval(() => {
      const hasAuthCookie: boolean = WebSessionManager.hasCookie(AUTH_COOKIE_NAME);
      if (hasAuthCookie && !this.initialAuthCookiePresent) {
        this.signalLoginSuccess('cookiePoll', '');
      }
    }, LOGIN_POLL_INTERVAL_MS);
  }

  private stopLoginCookiePolling(): void {
    if (this.loginPollTimer < 0) {
      return;
    }
    clearInterval(this.loginPollTimer);
    this.loginPollTimer = -1;
  }

  // 登录成功统一出口:单次守卫,停掉两路轮询、落盘 cookie,再通知上层(关登录页 + 刷新会话)。
  private async signalLoginSuccess(source: string, url: string): Promise<void> {
    if (this.hasSignaledLoginSuccess) {
      return;
    }
    this.hasSignaledLoginSuccess = true;
    Log.i(`${LOG_TAG} login success signaled source=${source} url=${url}`);
    this.stopLoginCookiePolling();
    this.stopChallengeCookiePolling();
    await WebSessionManager.saveCookies('LoginPage');
    this.onLoginSuccess();
  }

  private startChallengeCookiePolling(): void {
    if (this.challengePollTimer >= 0 || this.hasReloadedAfterChallenge) {
      return;
    }

    this.challengePollCount = 0;
    Log.i(`${LOG_TAG} cf_clearance polling start`);
    this.challengePollTimer = setInterval(() => {
      this.challengePollCount++;
      const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
      if (snapshot.hasCookie) {
        Log.i(`${LOG_TAG} cf_clearance detected, reload login`);
        WebSessionManager.saveCookies('LoginPage');
        this.stopChallengeCookiePolling();
        this.reloadLoginAfterChallenge();
        return;
      }

      if (this.challengePollCount % 5 === 0) {
        Log.i(`${LOG_TAG} cf_clearance pending attempt=${this.challengePollCount}/${MAX_CHALLENGE_POLL_COUNT} cookieHeaderLength=${snapshot.headerLength}`);
      }

      if (this.challengePollCount >= MAX_CHALLENGE_POLL_COUNT) {
        Log.i(`${LOG_TAG} cf_clearance polling timeout`);
        this.stopChallengeCookiePolling();
      }
    }, CHALLENGE_POLL_INTERVAL_MS);
  }

  private stopChallengeCookiePolling(): void {
    if (this.challengePollTimer < 0) {
      return;
    }
    clearInterval(this.challengePollTimer);
    this.challengePollTimer = -1;
  }

  private reloadLoginAfterChallenge(): void {
    if (this.hasReloadedAfterChallenge) {
      return;
    }

    this.hasReloadedAfterChallenge = true;
    try {
      this.controller.loadUrl(AppConstants.LOGIN_URL);
    } catch (error) {
      Log.i(`${LOG_TAG} reload login failed error=${JSON.stringify(error)}`);
    }
  }

  private logCfClearanceSnapshot(stage: string): void {
    const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
    Log.i(`${LOG_TAG} cf_clearance snapshot stage=${stage} exists=${snapshot.hasCookie} cookieHeaderLength=${snapshot.headerLength}`);
  }

  private safeRequestUrl(request: WebResourceRequest): string {
    try {
      return request.getRequestUrl();
    } catch (error) {
      return '';
    }
  }

  private safeErrorCode(error: WebResourceError): number {
    try {
      return error.getErrorCode();
    } catch (err) {
      return 0;
    }
  }

  private safeErrorInfo(error: WebResourceError): string {
    try {
      return error.getErrorInfo();
    } catch (err) {
      return '';
    }
  }

  private safeResponseCode(response: WebResourceResponse): number {
    try {
      return response.getResponseCode();
    } catch (error) {
      return 0;
    }
  }

  private safeReasonMessage(response: WebResourceResponse): string {
    try {
      return response.getReasonMessage();
    } catch (error) {
      return '';
    }
  }
}
