import { AppConstants } from '../../common/constants/AppConstants';
import { LdcUserInfo } from '../../models/LdcCredit';
import { WebSessionManager } from '../web/WebSessionManager';

// 余额缓存有效期。个人中心每次进入都重新拉一次要额外起一个 webview,代价明显;窗口内直接用缓存
// 秒出,过期才后台刷新。5 分钟对「看一眼余额」这个场景足够新。
const CACHE_TTL_MS: number = 5 * 60 * 1000;

/**
 * credit.linux.do 的登录态与余额缓存。
 *
 * 登录态就是 linux_do_credit_session_id 这枚 cookie 的存在性——值一律不读、不存、不打日志,
 * 全部交给 webview 的 cookie 仓管理。判定用 credit 自己的 URL 查:cookie 仓按域隔离,
 * 拿 linux.do 去查这枚 cookie 永远查不到。
 */
export class LdcCreditSession {
  private static cachedInfo?: LdcUserInfo = undefined;
  private static cachedAt: number = 0;

  static hasSession(): boolean {
    return WebSessionManager.hasCookieForUrl(AppConstants.CREDIT_BASE_URL, AppConstants.CREDIT_SESSION_COOKIE);
  }

  // 缓存的余额,不看新鲜度——用于先把上次的数字画出来避免空窗,随后后台刷新覆盖。
  static getCachedInfo(): LdcUserInfo | undefined {
    return LdcCreditSession.cachedInfo;
  }

  // 缓存是否还在有效期内。为真时可以跳过这次网络请求(连带跳过起 webview)。
  static isCacheFresh(): boolean {
    return LdcCreditSession.cachedInfo !== undefined &&
      Date.now() - LdcCreditSession.cachedAt < CACHE_TTL_MS;
  }

  static setCachedInfo(info: LdcUserInfo): void {
    LdcCreditSession.cachedInfo = info;
    LdcCreditSession.cachedAt = Date.now();
  }

  // 登出 credit / 请求判定为未登录时清掉,避免个人中心继续显示一个已经不属于当前会话的余额。
  static clearCache(): void {
    LdcCreditSession.cachedInfo = undefined;
    LdcCreditSession.cachedAt = 0;
  }
}
