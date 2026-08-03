import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][RealtimePosts]';
// 与 ThemeManager / RealtimeTopicsPrefs / FeedPrefs 共用同一个 preferences 库，只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'realtime_posts_enabled';

/** AppStorage 中「帖子内新回复提醒」开关的 key，供详情页通过 @StorageProp 响应式绑定。 */
export const REALTIME_POSTS_ENABLED_STORAGE_KEY: string = 'realtimePostsEnabled';

/**
 * 「帖子内新回复提醒」开关：控制进入帖子详情后是否订阅 /topic/<id> 实时接收他人新回复。
 * 与「首页新话题提醒」(首页提示条)相互独立。默认关：属实验性功能，需用户在实验性功能里主动开启；
 * 开启后打开帖子期间多订一个临时频道(MessageBus 长轮询本就为通知常驻运行，开销极低)。
 * preferences 持久化 + AppStorage 镜像(响应式即时启停)。
 */
export class RealtimePostsPrefs {
  // 内存镜像：同步读取路径用，避免每次 await。首次 load 后由 setEnabled 维护。
  private static cachedEnabled: boolean = false;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return RealtimePostsPrefs.cachedEnabled;
  }

  /** 冷启动调用一次：读盘回填内存镜像并种入 AppStorage，保证任何页面挂载前镜像已就绪(默认关)。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    if (!RealtimePostsPrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, false);
        RealtimePostsPrefs.cachedEnabled = value === true;
        RealtimePostsPrefs.loaded = true;
      } catch (error) {
        // 读失败按默认关处理：非核心功能，不该因存储异常影响默认行为。
        Log.i(`${LOG_TAG} load failed, fallback to disabled`);
        RealtimePostsPrefs.cachedEnabled = false;
      }
    }
    AppStorage.setOrCreate<boolean>(REALTIME_POSTS_ENABLED_STORAGE_KEY, RealtimePostsPrefs.cachedEnabled);
    return RealtimePostsPrefs.cachedEnabled;
  }

  /** 用户切换开关：更新内存镜像 + AppStorage(触发详情页响应) + 写盘持久化。 */
  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    RealtimePostsPrefs.cachedEnabled = enabled;
    RealtimePostsPrefs.loaded = true;
    AppStorage.setOrCreate<boolean>(REALTIME_POSTS_ENABLED_STORAGE_KEY, enabled);
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
