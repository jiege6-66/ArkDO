import { LdcDailyStat, LdcUserInfo } from '../../models/LdcCredit';

// credit.linux.do 接口的原始 JSON 形状。响应统一是 { error_msg, data },出错时 error_msg 非空。
interface RawCreditEnvelope {
  error_msg?: string;
  data?: RawCreditUserInfo;
}

interface RawDailyEnvelope {
  error_msg?: string;
  data?: RawDailyStat[];
}

// 金额全是字符串;唯独 daily_limit / trust_level / pay_score 是数字。混着来是服务端的既成事实,
// 不是笔误——故 daily_limit 单独按数字声明,再统一转成字符串对齐其余额度字段的展示。
interface RawCreditUserInfo {
  username?: string;
  nickname?: string;
  trust_level?: number;
  available_balance?: string;
  community_balance?: string;
  pending_balance?: string;
  remain_quota?: string;
  daily_limit?: number;
  total_receive?: string;
  total_payment?: string;
}

interface RawDailyStat {
  date?: string;
  income?: string;
  expense?: string;
}

export class LdcCreditParser {
  // 用户信息。data 缺失(未登录时后端只回 error_msg)返回 null,由调用方转成「去登录」态。
  static parseUserInfo(body: string): LdcUserInfo | null {
    let envelope: RawCreditEnvelope;
    try {
      envelope = JSON.parse(body) as RawCreditEnvelope;
    } catch (error) {
      return null;
    }
    const raw: RawCreditUserInfo | undefined = envelope ? envelope.data : undefined;
    if (!raw) {
      return null;
    }
    return {
      username: raw.username ? raw.username : '',
      nickname: raw.nickname ? raw.nickname : '',
      trustLevel: raw.trust_level !== undefined ? raw.trust_level : 0,
      availableBalance: LdcCreditParser.amountOf(raw.available_balance),
      communityBalance: LdcCreditParser.amountOf(raw.community_balance),
      pendingBalance: LdcCreditParser.amountOf(raw.pending_balance),
      remainQuota: LdcCreditParser.amountOf(raw.remain_quota),
      dailyLimit: raw.daily_limit !== undefined ? `${raw.daily_limit}` : '',
      totalReceive: LdcCreditParser.amountOf(raw.total_receive),
      totalPayment: LdcCreditParser.amountOf(raw.total_payment)
    };
  }

  // 最近 N 天收支。data 缺失或不是数组返回 null;空数组是合法结果(该账号这几天没有流水)。
  static parseDailyStats(body: string): LdcDailyStat[] | null {
    let envelope: RawDailyEnvelope;
    try {
      envelope = JSON.parse(body) as RawDailyEnvelope;
    } catch (error) {
      return null;
    }
    const raw: RawDailyStat[] | undefined = envelope ? envelope.data : undefined;
    if (!raw || !Array.isArray(raw)) {
      return null;
    }
    const stats: LdcDailyStat[] = [];
    for (let index: number = 0; index < raw.length; index++) {
      const item: RawDailyStat = raw[index];
      const date: string = item.date ? item.date : '';
      if (date.length === 0) {
        continue;
      }
      stats.push({
        date: date,
        income: LdcCreditParser.amountOf(item.income),
        expense: LdcCreditParser.amountOf(item.expense)
      });
    }
    return stats;
  }

  // 金额兜底成 '0':字段缺失时展示空字符串会让金额行看起来「加载失败」,而 0 是语义正确的。
  private static amountOf(value: string | undefined): string {
    return value !== undefined && value.length > 0 ? value : '0';
  }
}
