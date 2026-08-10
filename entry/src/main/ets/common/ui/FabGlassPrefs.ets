import { Log } from '../../services/logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][FabGlass]';
// 与 ThemeManager / RealtimeTopicsPrefs / FeedPrefs 共用同一个 preferences 库，只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'fab_glass_enabled';
const PREF_KEY_RADIUS: string = 'fab_glass_radius';

/** AppStorage 中「悬浮按钮玻璃效果」开关的 key，供首页与详情页 FAB 通过 @StorageProp 响应式绑定。 */
export const FAB_GLASS_ENABLED_STORAGE_KEY: string = 'fabGlassEnabled';
/** 同上，磨砂半径。标量键而非打包对象：AppStorage 里改对象字段不会穿透到 @StorageProp。 */
export const FAB_GLASS_RADIUS_STORAGE_KEY: string = 'fabGlassRadius';

/**
 * 磨砂半径(vp)取值区间。默认 28 即改造前的硬编码值，保证不动设置的老用户升级后观感分毫不变。
 *
 * 下限取 4 而不是 0：0 等于「没有磨砂」，那是开关关掉该做的事，滑块滑到底还留一点材质，
 * 才不会出现「开关开着却和关掉一模一样」的错态。上限 60 之后再加已看不出差别，只是白费 GPU。
 */
export const FAB_GLASS_RADIUS_MIN: number = 4;
export const FAB_GLASS_RADIUS_MAX: number = 60;
export const FAB_GLASS_RADIUS_DEFAULT: number = 28;

/** 钳制：任何入口(读盘、滑块、外部调用)都要过这里。 */
export function clampFabGlassRadius(value: number): number {
  if (!Number.isFinite(value)) {
    return FAB_GLASS_RADIUS_DEFAULT;
  }
  return Math.min(FAB_GLASS_RADIUS_MAX, Math.max(FAB_GLASS_RADIUS_MIN, Math.round(value)));
}

/**
 * 「悬浮按钮玻璃效果」开关与磨砂半径的持久化 + AppStorage 响应式镜像。默认关：默认沿用当前的
 * 透明 FAB，打开后首页与详情页右下角 FAB 恢复模糊材质背板(backgroundEffect + 主题底色 + 细高光)。
 * preferences 负责跨冷启动持久化；AppStorage 镜像让两处 FAB 能即时响应开关翻转与滑块拖动，无需重启。
 *
 * 写盘与预览分离：滑块 onChange 每帧都来，只更新内存与 AppStorage(两处 FAB 即时跟手)，
 * 松手(SliderChangeMode.End/Click)时才调 flushRadius 落盘，避免每帧 store.flush() 卡顿。
 */
export class FabGlassPrefs {
  // 内存镜像：同步读取路径用，避免每次 await。首次 load 后由各 setter 维护。
  private static cachedEnabled: boolean = false;
  private static cachedRadius: number = FAB_GLASS_RADIUS_DEFAULT;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return FabGlassPrefs.cachedEnabled;
  }

  static radius(): number {
    return FabGlassPrefs.cachedRadius;
  }

  /** 冷启动调用一次：读盘回填内存镜像并种入 AppStorage，保证任何页面挂载前镜像已就绪（默认关）。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    if (!FabGlassPrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, false);
        FabGlassPrefs.cachedEnabled = value === true;
        const rawRadius: preferences.ValueType = store.getSync(PREF_KEY_RADIUS, FAB_GLASS_RADIUS_DEFAULT);
        FabGlassPrefs.cachedRadius =
          clampFabGlassRadius(typeof rawRadius === 'number' ? rawRadius : FAB_GLASS_RADIUS_DEFAULT);
        FabGlassPrefs.loaded = true;
      } catch (error) {
        // 读失败按默认处理：纯外观开关，不该因存储异常影响启动。
        Log.i(`${LOG_TAG} load failed, fallback to defaults`);
        FabGlassPrefs.cachedEnabled = false;
        FabGlassPrefs.cachedRadius = FAB_GLASS_RADIUS_DEFAULT;
      }
    }
    FabGlassPrefs.mirror();
    return FabGlassPrefs.cachedEnabled;
  }

  /** 用户切换开关：更新内存镜像 + AppStorage（触发两处 FAB 响应）+ 写盘持久化。 */
  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    FabGlassPrefs.cachedEnabled = enabled;
    FabGlassPrefs.loaded = true;
    FabGlassPrefs.mirror();
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

  /** 拖动滑块：只更新内存与镜像(两处 FAB 即时跟手)，不落盘。返回钳制后的值供设置页回显。 */
  static setRadius(value: number): number {
    FabGlassPrefs.cachedRadius = clampFabGlassRadius(value);
    FabGlassPrefs.mirror();
    return FabGlassPrefs.cachedRadius;
  }

  /** 滑块松手时调一次：把当前半径落盘。 */
  static flushRadius(context: common.UIAbilityContext | common.Context): void {
    FabGlassPrefs.loaded = true;
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      store.putSync(PREF_KEY_RADIUS, FabGlassPrefs.cachedRadius);
      store.flush();
      Log.i(`${LOG_TAG} radius=${FabGlassPrefs.cachedRadius}`);
    } catch (error) {
      Log.i(`${LOG_TAG} save failed radius=${FabGlassPrefs.cachedRadius}`);
    }
  }

  private static mirror(): void {
    AppStorage.setOrCreate<boolean>(FAB_GLASS_ENABLED_STORAGE_KEY, FabGlassPrefs.cachedEnabled);
    AppStorage.setOrCreate<number>(FAB_GLASS_RADIUS_STORAGE_KEY, FabGlassPrefs.cachedRadius);
  }
}
