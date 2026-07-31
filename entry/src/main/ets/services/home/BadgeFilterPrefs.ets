import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][BadgeFilter]';
// 与 ThemeManager / RealtimeTopicsPrefs 等共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'badge_filter_enabled';

/** AppStorage 中「点分类/标签快速筛选」开关的 key,供首页通过 @StorageProp 响应式绑定。 */
export const BADGE_FILTER_ENABLED_STORAGE_KEY: string = 'badgeFilterEnabled';

/**
 * 「点分类/标签快速筛选」开关的持久化 + AppStorage 响应式镜像。
 *
 * 默认关:开着时帖子行上的徽章会抢走点击,而整行点击是「打开帖子」这个最高频的动作 ——
 * 误触代价不对称,所以让用户显式打开。
 *
 * preferences 负责跨冷启动持久化;AppStorage 镜像让首页在设置页翻转开关后即时生效(@StorageProp),
 * 无需重启。与 RealtimeTopicsPrefs 同一套写法。
 */
export class BadgeFilterPrefs {
  // 内存镜像:同步读取路径用,避免每次 await。首次 load 后由 setEnabled 维护。
  private static cachedEnabled: boolean = false;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return BadgeFilterPrefs.cachedEnabled;
  }

  /** 冷启动调用一次:读盘回填内存镜像并种入 AppStorage,保证任何页面挂载前镜像已就绪(默认关)。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    if (!BadgeFilterPrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, false);
        BadgeFilterPrefs.cachedEnabled = value === true;
        BadgeFilterPrefs.loaded = true;
      } catch (error) {
        // 读失败按默认关处理:该功能非核心,不该因存储异常影响启动。
        Log.i(`${LOG_TAG} load failed, fallback to disabled`);
        BadgeFilterPrefs.cachedEnabled = false;
      }
    }
    AppStorage.setOrCreate<boolean>(BADGE_FILTER_ENABLED_STORAGE_KEY, BadgeFilterPrefs.cachedEnabled);
    return BadgeFilterPrefs.cachedEnabled;
  }

  /** 用户切换开关:更新内存镜像 + AppStorage(触发首页响应)+ 写盘持久化。 */
  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    BadgeFilterPrefs.cachedEnabled = enabled;
    BadgeFilterPrefs.loaded = true;
    AppStorage.setOrCreate<boolean>(BADGE_FILTER_ENABLED_STORAGE_KEY, enabled);
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
