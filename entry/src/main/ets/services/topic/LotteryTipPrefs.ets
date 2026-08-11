import { common } from '@kit.AbilityKit';
import { BooleanPref } from '../../common/prefs/AppSettingsStore';

/** AppStorage 中「抽奖帖提醒」开关的 key,供详情页通过 @StorageProp 响应式绑定。 */
export const LOTTERY_TIP_ENABLED_STORAGE_KEY: string = 'lotteryTipEnabled';

// 默认开:提醒本身是给用户挡下「永久禁言」这种不可逆后果的,默认关等于没做。
// 读盘失败也回落到开 —— 宁可多提示一次,也不要因为存储异常把安全提醒静默掉。
const PREF: BooleanPref =
  new BooleanPref('[ArkDO][LotteryTip]', 'lottery_tip_enabled', LOTTERY_TIP_ENABLED_STORAGE_KEY, true);

/**
 * 「抽奖帖提醒」开关。
 *
 * 卡片不记「看过了」——每进一个抽奖帖都展开显示,想彻底不看的人走这个开关,
 * 它是唯一的持久化逃生口(卡片上的收起只在本次浏览有效)。
 *
 * 持久化 + AppStorage 响应式镜像的通用实现见 BooleanPref;本类只是保留静态门面。
 */
export class LotteryTipPrefs {
  static isEnabled(): boolean {
    return PREF.isEnabled();
  }

  static load(context: common.UIAbilityContext | common.Context): boolean {
    return PREF.load(context);
  }

  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    PREF.setEnabled(context, enabled);
  }
}
