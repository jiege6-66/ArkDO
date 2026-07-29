import { Log } from '../logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { LdcDailyStat, LdcUserInfo } from '../../models/LdcCredit';
import { ArkWebNetworkBridge } from '../network/ArkWebNetworkBridge';
import { ChallengeState, HttpHeaderEntry, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';
import { LdcCreditParser } from './LdcCreditParser';

const LOG_TAG: string = '[ArkDO][Ldc]';

// credit 的 XHR 指纹,照抓包对齐:后端按 x-requested-with 决定走 JSON 分支还是重定向到登录页。
// Referer 另经参数传(见 AppConstants.CREDIT_HOME_URL),两者缺一都可能拿不到 JSON。
const CREDIT_HEADERS: HttpHeaderEntry[] = [
  { name: 'X-Requested-With', value: 'XMLHttpRequest' }
];

const USER_INFO_PATH: string = '/api/v1/oauth/user-info';
const DAILY_STATS_PATH: string = '/api/v1/dashboard/stats/daily';

/**
 * LINUX DO Credit 服务。持有的 bridge 必须是挂在 **credit.linux.do 同源文档** 上的那一个
 * (见 LdcCreditWebHost):接口不回 CORS 头,从 linux.do 的 host webview 发跨源 fetch 会被浏览器挡。
 */
export class LdcCreditService {
  private bridge: ArkWebNetworkBridge;

  constructor(bridge: ArkWebNetworkBridge) {
    this.bridge = bridge;
  }

  async getUserInfo(): Promise<NetworkResult<LdcUserInfo>> {
    const result: NetworkResult<string> = await this.bridge.getJsonWithHeaders(
      USER_INFO_PATH, CREDIT_HEADERS, AppConstants.CREDIT_HOME_URL);
    if (!result.success || result.data === undefined) {
      Log.i(`${LOG_TAG} user-info failed status=${result.statusCode} challenge=${result.challengeState}`);
      return LdcCreditService.failureOf(result);
    }

    const info: LdcUserInfo | null = LdcCreditParser.parseUserInfo(result.data);
    if (!info) {
      Log.i(`${LOG_TAG} user-info unparsable bodyLength=${result.data.length}`);
      return {
        success: false,
        statusCode: result.statusCode,
        challengeState: result.challengeState,
        error: {
          code: NetworkErrorCode.UNEXPECTED_RESPONSE,
          message: 'LDC 账户信息解析失败。',
          requiresChallenge: false
        }
      };
    }

    Log.i(`${LOG_TAG} user-info loaded trustLevel=${info.trustLevel}`);
    return {
      success: true,
      statusCode: result.statusCode,
      challengeState: ChallengeState.NONE,
      data: info
    };
  }

  async getDailyStats(days: number): Promise<NetworkResult<LdcDailyStat[]>> {
    const safeDays: number = days > 0 ? Math.floor(days) : 7;
    const result: NetworkResult<string> = await this.bridge.getJsonWithHeaders(
      `${DAILY_STATS_PATH}?days=${safeDays}`, CREDIT_HEADERS, AppConstants.CREDIT_HOME_URL);
    if (!result.success || result.data === undefined) {
      Log.i(`${LOG_TAG} daily stats failed status=${result.statusCode} challenge=${result.challengeState}`);
      return LdcCreditService.failureOf(result);
    }

    const stats: LdcDailyStat[] | null = LdcCreditParser.parseDailyStats(result.data);
    if (!stats) {
      Log.i(`${LOG_TAG} daily stats unparsable bodyLength=${result.data.length}`);
      return {
        success: false,
        statusCode: result.statusCode,
        challengeState: result.challengeState,
        error: {
          code: NetworkErrorCode.UNEXPECTED_RESPONSE,
          message: 'LDC 获取记录解析失败。',
          requiresChallenge: false
        }
      };
    }

    Log.i(`${LOG_TAG} daily stats loaded days=${stats.length}`);
    return {
      success: true,
      statusCode: result.statusCode,
      challengeState: ChallengeState.NONE,
      data: stats
    };
  }

  // 把字符串结果的失败原样透传成目标类型的失败(保留状态码/挑战态,供上层区分需过盾与普通失败)。
  private static failureOf<T>(result: NetworkResult<string>): NetworkResult<T> {
    return {
      success: false,
      statusCode: result.statusCode,
      challengeState: result.challengeState,
      error: result.error ? result.error : {
        code: NetworkErrorCode.NETWORK_FAILURE,
        message: 'LDC 请求失败。',
        requiresChallenge: false
      }
    };
  }
}
