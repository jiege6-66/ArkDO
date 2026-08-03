import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][RealtimeTopics]';
// 与 ThemeManager / ChallengeShortcutPrefs / FeedPrefs 共用同一个 preferences 库，只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'realtime_topics_enabled';

/** AppStorage 中「首页新话题提醒」开关的 key，供宿主 webview 与首页通过 @StorageProp 响应式绑定。 */
export const REALTIME_TOPICS_ENABLED_STORAGE_KEY: string = 'realtimeTopicsEnabled';

/**
 * 「首页新话题提醒」开关的持久化 + AppStorage 响应式镜像。默认关：该功能会常驻后台长轮询，
 * 并非所有用户都需要。preferences 负责跨冷启动持久化；AppStorage 镜像让宿主 webview 的注入
 * 决策与首页提示条能即时响应开关翻转（@StorageProp + @Watch），无需重启。
 */
export class RealtimeTopicsPrefs {
  // 内存镜像：设置页种子值等同步读取路径用，避免每次 await。首次 load 后由 setEnabled 维护。
  private static cachedEnabled: boolean = false;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return RealtimeTopicsPrefs.cachedEnabled;
  }

  /** 冷启动调用一次：读盘回填内存镜像并种入 AppStorage，保证任何页面挂载前镜像已就绪（默认关）。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    if (!RealtimeTopicsPrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, false);
        RealtimeTopicsPrefs.cachedEnabled = value === true;
        RealtimeTopicsPrefs.loaded = true;
      } catch (error) {
        // 读失败按默认关处理：该功能非核心，不该因存储异常影响启动。
        Log.i(`${LOG_TAG} load failed, fallback to disabled`);
        RealtimeTopicsPrefs.cachedEnabled = false;
      }
    }
    AppStorage.setOrCreate<boolean>(REALTIME_TOPICS_ENABLED_STORAGE_KEY, RealtimeTopicsPrefs.cachedEnabled);
    return RealtimeTopicsPrefs.cachedEnabled;
  }

  /** 用户切换开关：更新内存镜像 + AppStorage（触发宿主/首页响应）+ 写盘持久化。 */
  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    RealtimeTopicsPrefs.cachedEnabled = enabled;
    RealtimeTopicsPrefs.loaded = true;
    AppStorage.setOrCreate<boolean>(REALTIME_TOPICS_ENABLED_STORAGE_KEY, enabled);
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
