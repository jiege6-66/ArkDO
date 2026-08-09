/**
 * 全局常量与「当前站点」派生地址。
 *
 * ArkDO 是通用 Discourse 客户端:站点由用户自己添加,不预置任何站点。所以站点相关的地址
 * 不再是编译期常量,而是由 CurrentSite 在切站时推进来(setActiveSite),再由下面的 getter
 * 派生。取 getter 而非改成方法,是为了让既有的 40 余处 `AppConstants.BASE_URL` 调用点
 * 一行都不用动。
 *
 * 依赖方向:CurrentSite → AppConstants(单向推入)。反过来会成环,故本类不 import 站点模块。
 */
export class AppConstants {
  static readonly APP_NAME: string = 'ArkDO';

  // ==================== 当前站点(运行时注入) ====================

  private static activeBaseUrl: string = '';
  private static activeHost: string = '';

  /** 由 CurrentSite 调用。baseUrl 须已去掉尾斜杠;未选站点时传空串。 */
  static setActiveSite(baseUrl: string, host: string): void {
    AppConstants.activeBaseUrl = baseUrl;
    AppConstants.activeHost = host;
  }

  /** 当前站点根地址,如 https://example.com。未选站点时为空串。 */
  static get BASE_URL(): string {
    return AppConstants.activeBaseUrl;
  }

  /** 当前站点 host,如 example.com。未选站点时为空串。 */
  static get HOST(): string {
    return AppConstants.activeHost;
  }

  /** 是否已选定站点。未选定时不应发起任何站点请求。 */
  static get HAS_ACTIVE_SITE(): boolean {
    return AppConstants.activeBaseUrl.length > 0;
  }

  // ==================== 站点派生地址 ====================

  // host webview 引导页:桥只需一个与站点同源的文档(定 origin、带 cookie、供注入 fetch),
  // 无需首页那套重型 SPA。加载极小的 /session/csrf.json,把冷启动首屏就绪从 ~30s 砍到建连级。
  // 同源、Discourse 必然存在、顺带预热 CSRF;CF 挡时照样返回挑战 HTML 跑 JS 种 cf_clearance。
  static get HOST_BOOTSTRAP_URL(): string {
    return `${AppConstants.activeBaseUrl}/session/csrf.json`;
  }

  static readonly LOGIN_PATH: string = '/login';

  static get LOGIN_URL(): string {
    return `${AppConstants.activeBaseUrl}${AppConstants.LOGIN_PATH}`;
  }

  static readonly CHALLENGE_PATH: string = '/challenge';

  static get CHALLENGE_URL(): string {
    return `${AppConstants.activeBaseUrl}${AppConstants.CHALLENGE_PATH}`;
  }

  // 站点静态资源 CDN。linux.do 的主站域名在 TLS 层被按 SNI 阻断,原生 Image 取不到图
  // (头像因此要绕 webview 桥);cdn.ldstatic.com 镜像同一份静态资源且不被拦,故站内相对的
  // 静态图(emoji 等)挂它而非 BASE_URL。这是 linux.do 特有的基础设施,别的站点没有对应镜像,
  // 一律回落到自己的 BASE_URL。
  static get STATIC_CDN_BASE(): string {
    return AppConstants.activeHost === LINUX_DO_HOST ? 'https://cdn.ldstatic.com' : AppConstants.activeBaseUrl;
  }

  // ==================== 站点无关 ====================

  static readonly DEFAULT_TIMEOUT_MS: number = 15000;
  // host webview 因 session 变化被 loadUrl 重载时，注入式 fetch 会排队等待其 onPageEnd。
  // 该超时用于兜底：万一 onPageEnd 因异常始终不触发，等待者也不会永久悬住。
  static readonly HOST_RELOAD_READY_TIMEOUT_MS: number = 5000;
  // Cloudflare 会校验 UA，且 cf_clearance 与请求时的 UA 绑定。验证页与后台请求页必须使用
  // 完全一致的真实浏览器 UA，否则验证页拿到的 cf_clearance 在后台 fetch 时会被判定失效。
  static readonly DEFAULT_USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
}

// ==================== linux.do 专属 ====================
// 以下是 linux.do 生态特有的站点/接口,不属于 Discourse 标准能力。仅当当前站点是 linux.do
// 时相关入口才出现(见 SiteCapabilities),换站自动隐藏。

/** linux.do 的 host。专属能力的判定基准。 */
export const LINUX_DO_HOST: string = 'linux.do';

export class LinuxDoConstants {
  // connect.linux.do:跨域(与主站不同源),经 SSO 复用主站会话自动登录。等级进度页专用。
  static readonly CONNECT_URL: string = 'https://connect.linux.do/';
  // credit.linux.do(LINUX DO Credit):同样跨域,且同样在 CF 后面。它的 API 只能由「credit
  // 同源文档」内的 fetch 发起——host webview 是主站源,跨源 fetch 会被 CORS 挡(该站不回 ACAO)。
  static readonly CREDIT_BASE_URL: string = 'https://credit.linux.do';
  // credit 桥的引导页:与 HOST_BOOTSTRAP_URL 同思路——只为拿一个 credit.linux.do 同源文档
  // (定 origin、带 cookie、供注入 fetch),故直接加载最轻的 JSON 接口而非 /home 那套 SPA。
  static readonly CREDIT_BOOTSTRAP_URL: string = 'https://credit.linux.do/api/v1/oauth/user-info';
  // credit 站内页:既是登录落地页,也是各 API 请求要求的 Referer(抓包对齐,后端会看)。
  static readonly CREDIT_HOME_URL: string = 'https://credit.linux.do/home';
  // credit.linux.do 的登录态凭证(经 LinuxDO OAuth 换取)。只判存在性,值一律不落代码、不落日志。
  static readonly CREDIT_SESSION_COOKIE: string = 'linux_do_credit_session_id';
  // 反馈与建议:站内反馈帖 https://linux.do/t/topic/2590051。设置页入口按 id 直开原生详情页,
  // 用户可就地回帖/点赞(复用登录态与 LoginGate),不走 WebView。
  static readonly FEEDBACK_TOPIC_ID: number = 2590051;
}
