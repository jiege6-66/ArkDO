import { Log } from '../../services/logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][FabGlass]';
// 与 ThemeManager / RealtimeTopicsPrefs / FeedPrefs 共用同一个 preferences 库，只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'fab_glass_enabled';

/** AppStorage 中「悬浮按钮玻璃效果」开关的 key，供首页与详情页 FAB 通过 @StorageProp 响应式绑定。 */
export const FAB_GLASS_ENABLED_STORAGE_KEY: string = 'fabGlassEnabled';

/**
 * 「悬浮按钮玻璃效果」开关的持久化 + AppStorage 响应式镜像。默认关：默认沿用当前的透明 FAB，
 * 打开后首页与详情页右下角 FAB 恢复模糊材质背板(backdropBlur + 主题底色 + 细高光)。
 * preferences 负责跨冷启动持久化；AppStorage 镜像让两处 FAB 能即时响应开关翻转，无需重启。
 */
export class FabGlassPrefs {
  // 内存镜像：同步读取路径用，避免每次 await。首次 load 后由 setEnabled 维护。
  private static cachedEnabled: boolean = false;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return FabGlassPrefs.cachedEnabled;
  }

  /** 冷启动调用一次：读盘回填内存镜像并种入 AppStorage，保证任何页面挂载前镜像已就绪（默认关）。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    if (!FabGlassPrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, false);
        FabGlassPrefs.cachedEnabled = value === true;
        FabGlassPrefs.loaded = true;
      } catch (error) {
        // 读失败按默认关处理：纯外观开关，不该因存储异常影响启动。
        Log.i(`${LOG_TAG} load failed, fallback to disabled`);
        FabGlassPrefs.cachedEnabled = false;
      }
    }
    AppStorage.setOrCreate<boolean>(FAB_GLASS_ENABLED_STORAGE_KEY, FabGlassPrefs.cachedEnabled);
    return FabGlassPrefs.cachedEnabled;
  }

  /** 用户切换开关：更新内存镜像 + AppStorage（触发两处 FAB 响应）+ 写盘持久化。 */
  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    FabGlassPrefs.cachedEnabled = enabled;
    FabGlassPrefs.loaded = true;
    AppStorage.setOrCreate<boolean>(FAB_GLASS_ENABLED_STORAGE_KEY, enabled);
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
