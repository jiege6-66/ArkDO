import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][LotteryTip]';
// 与 ThemeManager / BadgeFilterPrefs 等共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'lottery_tip_enabled';

/** AppStorage 中「抽奖帖提醒」开关的 key,供详情页通过 @StorageProp 响应式绑定。 */
export const LOTTERY_TIP_ENABLED_STORAGE_KEY: string = 'lotteryTipEnabled';

/**
 * 「抽奖帖提醒」开关的持久化 + AppStorage 响应式镜像。
 *
 * 默认开:提醒本身是给用户挡下「永久禁言」这种不可逆后果的,默认关等于没做。
 * 卡片不记「看过了」——每进一个抽奖帖都展开显示,想彻底不看的人走这个开关,
 * 它是唯一的持久化逃生口(卡片上的收起只在本次浏览有效)。
 *
 * 与 BadgeFilterPrefs 同一套写法:preferences 负责跨冷启动持久化,AppStorage 镜像让详情页
 * 在设置页翻转开关后即时生效,无需重启。
 */
export class LotteryTipPrefs {
  // 内存镜像:同步读取路径用,避免每次 await。首次 load 后由 setEnabled 维护。
  private static cachedEnabled: boolean = true;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return LotteryTipPrefs.cachedEnabled;
  }

  /** 冷启动调用一次:读盘回填内存镜像并种入 AppStorage,保证详情页挂载前镜像已就绪(默认开)。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    if (!LotteryTipPrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, true);
        LotteryTipPrefs.cachedEnabled = value !== false;
        LotteryTipPrefs.loaded = true;
      } catch (error) {
        // 读失败按默认开处理:宁可多提示一次,也不要因为存储异常把安全提醒静默掉。
        Log.i(`${LOG_TAG} load failed, fallback to enabled`);
        LotteryTipPrefs.cachedEnabled = true;
      }
    }
    AppStorage.setOrCreate<boolean>(LOTTERY_TIP_ENABLED_STORAGE_KEY, LotteryTipPrefs.cachedEnabled);
    return LotteryTipPrefs.cachedEnabled;
  }

  /** 用户切换开关:更新内存镜像 + AppStorage(触发详情页响应)+ 写盘持久化。 */
  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    LotteryTipPrefs.cachedEnabled = enabled;
    LotteryTipPrefs.loaded = true;
    AppStorage.setOrCreate<boolean>(LOTTERY_TIP_ENABLED_STORAGE_KEY, enabled);
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      store.putSync(PREF_KEY_ENABLED, enabled);
      store.flush();
      Log.i(`${LOG_TAG} enabled=${enabled}`);
    } catch (error) {
      Log.i(`${LOG_TAG} save failed enabled=${enabled}`);
    }
  }
}
