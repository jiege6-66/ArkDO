import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][AnimatedAvatar]';
// 与 ThemeManager / RealtimePostsPrefs / FeedPrefs 共用同一个 preferences 库，只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'animated_avatar_enabled';

/** AppStorage 中「动态头像」开关的 key，供 UserAvatar 通过 @StorageProp 响应式绑定。 */
export const ANIMATED_AVATAR_ENABLED_STORAGE_KEY: string = 'animatedAvatarEnabled';

/**
 * 「动态头像」开关：控制头像与 flair 角标是否播放动图。
 *
 * 关(默认)：头像一律取首帧渲染成静态图 —— 走 host webview 取字节 + createPixelMap 的路径，
 *          PixelMap 天然只有一帧，不会动；flair 角标同理。
 * 开：       linux.do 的 avatar_template 在 CDN(ldstatic.com)上本身常是动图内容，
 *          交给原生 Image 直载即会自动播放；同时优先使用 animated_avatar 候选。
 *
 * 默认关的原因：列表里十几个头像同时播放动图，会让渲染树每帧都变脏。这个开关同时也是
 * 排查掉帧时的对照工具 —— 开/关两次操作即可判断卡顿是否来自动图。
 *
 * 注意：关闭时头像改走 webview 桥取字节，首次加载会比原生 Image 慢(缓存命中后无差别)。
 * preferences 持久化 + AppStorage 镜像(响应式即时生效)。
 */
export class AnimatedAvatarPrefs {
  // 内存镜像：同步读取路径用，避免每次 await。首次 load 后由 setEnabled 维护。
  private static cachedEnabled: boolean = false;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return AnimatedAvatarPrefs.cachedEnabled;
  }

  /** 冷启动调用一次：读盘回填内存镜像并种入 AppStorage，保证任何页面挂载前镜像已就绪(默认关)。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    if (!AnimatedAvatarPrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, false);
        AnimatedAvatarPrefs.cachedEnabled = value === true;
        AnimatedAvatarPrefs.loaded = true;
      } catch (error) {
        // 读失败按默认关处理：静态头像是更保守的表现，不该因存储异常反而放开动图。
        Log.i(`${LOG_TAG} load failed, fallback to disabled`);
        AnimatedAvatarPrefs.cachedEnabled = false;
      }
    }
    AppStorage.setOrCreate<boolean>(ANIMATED_AVATAR_ENABLED_STORAGE_KEY, AnimatedAvatarPrefs.cachedEnabled);
    return AnimatedAvatarPrefs.cachedEnabled;
  }

  /** 用户切换开关：更新内存镜像 + AppStorage(触发所有在屏头像重取) + 写盘持久化。 */
  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    AnimatedAvatarPrefs.cachedEnabled = enabled;
    AnimatedAvatarPrefs.loaded = true;
    AppStorage.setOrCreate<boolean>(ANIMATED_AVATAR_ENABLED_STORAGE_KEY, enabled);
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
