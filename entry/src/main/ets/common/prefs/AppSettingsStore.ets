import { Log } from '../../services/logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/**
 * 全 app 共用的偏好库 `app_settings` 的访问入口,以及建立在它之上的「一个布尔开关」通用实现。
 *
 * ## 为什么要有这一层
 * 改造前有七个开关类(RealtimeTopics / RealtimePosts / LotteryTip / BadgeFilter /
 * AnimatedAvatar / ChallengeShortcut / FabGlass),每个 50~70 行,彼此只差四个常量:
 * pref 键、AppStorage 键、日志前缀、默认值。连注释结构都是复制的。加一个新开关的成本是
 * 「复制六十行再改四处」,而漏改其中一处不会有任何编译错误。
 *
 * 同时它们各自 `getPreferencesSync(context, ...)`:EntryAbility.onCreate 里连着七次同步 IO,
 * 全落在冷启动的关键路径上,而且拿的本来就是同一个库。这里缓存住实例,只有第一次真的开库。
 */
const PREF_STORE_NAME: string = 'app_settings';
const LOG_TAG: string = '[ArkDO][Prefs]';

export class AppSettingsStore {
  private static cached: preferences.Preferences | undefined = undefined;

  /**
   * 取共享的偏好库实例(首次调用才真的开库)。开库失败返回 undefined —— 调用方一律回落到
   * 默认值,不因为存储异常打断任何主流程。
   */
  static acquire(context: common.UIAbilityContext | common.Context): preferences.Preferences | undefined {
    const cached: preferences.Preferences | undefined = AppSettingsStore.cached;
    if (cached !== undefined) {
      return cached;
    }
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      AppSettingsStore.cached = store;
      return store;
    } catch (error) {
      Log.i(`${LOG_TAG} open store failed`);
      return undefined;
    }
  }

  /**
   * 读一个布尔值。**读不到时返回 undefined**,而不是悄悄回落到默认值。
   *
   * 这个区分是必要的:调用方要靠它分辨「盘上确实存着 false」和「这次根本没读成」。
   * 混为一谈的话,一次偶发的读失败会被当成"已读到默认值"记下来(loaded=true),
   * 于是本次会话再也不重试 —— 用户磁盘上明明存着他的设置,开关却整个会话卡在默认值。
   * 注意:键不存在**不算**失败,getSync 会正常返回 fallback。
   */
  static tryGetBoolean(context: common.UIAbilityContext | common.Context, key: string,
    fallback: boolean): boolean | undefined {
    const store: preferences.Preferences | undefined = AppSettingsStore.acquire(context);
    if (store === undefined) {
      return undefined;
    }
    try {
      const value: preferences.ValueType = store.getSync(key, fallback);
      return typeof value === 'boolean' ? value : fallback;
    } catch (error) {
      Log.i(`${LOG_TAG} read failed key=${key}`);
      return undefined;
    }
  }

  /** tryGetBoolean 的便捷形态:不关心「是没读到还是读到了默认值」的调用方用。 */
  static getBoolean(context: common.UIAbilityContext | common.Context, key: string, fallback: boolean): boolean {
    const value: boolean | undefined = AppSettingsStore.tryGetBoolean(context, key, fallback);
    return value !== undefined ? value : fallback;
  }

  static getNumber(context: common.UIAbilityContext | common.Context, key: string, fallback: number): number {
    const store: preferences.Preferences | undefined = AppSettingsStore.acquire(context);
    if (store === undefined) {
      return fallback;
    }
    try {
      const value: preferences.ValueType = store.getSync(key, fallback);
      return typeof value === 'number' ? value : fallback;
    } catch (error) {
      Log.i(`${LOG_TAG} read failed key=${key}`);
      return fallback;
    }
  }

  /** 写入并落盘。失败只记日志:内存镜像已经更新,本次会话的行为仍然正确,只是重启后回退。 */
  static putBoolean(context: common.UIAbilityContext | common.Context, key: string, value: boolean): void {
    AppSettingsStore.put(context, key, value);
  }

  static putNumber(context: common.UIAbilityContext | common.Context, key: string, value: number): void {
    AppSettingsStore.put(context, key, value);
  }

  private static put(context: common.UIAbilityContext | common.Context, key: string,
    value: preferences.ValueType): void {
    const store: preferences.Preferences | undefined = AppSettingsStore.acquire(context);
    if (store === undefined) {
      return;
    }
    try {
      store.putSync(key, value);
      store.flush();
    } catch (error) {
      Log.i(`${LOG_TAG} write failed key=${key}`);
    }
  }
}

/**
 * 一个「布尔开关」:preferences 持久化 + 内存镜像 + AppStorage 响应式镜像。
 *
 * 三份状态各有分工,缺一不可:
 *  · preferences —— 跨冷启动持久化
 *  · 内存镜像     —— 同步读取路径用(渲染时不能 await)
 *  · AppStorage  —— 让页面经 @StorageProp 即时响应开关翻转,无需重启
 *
 * storageKey 传空串表示「不需要 AppStorage 镜像」(如 ChallengeShortcutPrefs,只有详情页
 * 自己同步读)。
 */
export class BooleanPref {
  private readonly logTag: string;
  private readonly prefKey: string;
  private readonly storageKey: string;
  private readonly defaultValue: boolean;
  private cachedValue: boolean;
  private loaded: boolean = false;

  constructor(logTag: string, prefKey: string, storageKey: string, defaultValue: boolean) {
    this.logTag = logTag;
    this.prefKey = prefKey;
    this.storageKey = storageKey;
    this.defaultValue = defaultValue;
    this.cachedValue = defaultValue;
  }

  isEnabled(): boolean {
    return this.cachedValue;
  }

  /**
   * 冷启动调用一次:读盘回填内存镜像并种入 AppStorage,保证任何页面挂载前镜像已就绪。
   *
   * 读失败时用默认值先顶上,但**不置 loaded** —— 下一次 load() 还要再试。
   * 有的开关不止在冷启动读(如 ChallengeShortcutPrefs 进设置页时还会读一次),
   * 靠这个重试才能从一次偶发的存储异常里自愈;一旦把失败也记成"已加载",
   * 用户就只能靠手动拨一下开关才能把自己的设置救回来。
   */
  load(context: common.UIAbilityContext | common.Context): boolean {
    if (!this.loaded) {
      const read: boolean | undefined =
        AppSettingsStore.tryGetBoolean(context, this.prefKey, this.defaultValue);
      if (read !== undefined) {
        this.cachedValue = read;
        this.loaded = true;
      } else {
        this.cachedValue = this.defaultValue;
      }
    }
    this.mirror();
    return this.cachedValue;
  }

  /** 用户切换开关:更新内存镜像 + AppStorage(触发订阅页面响应)+ 写盘持久化。 */
  setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    this.cachedValue = enabled;
    this.loaded = true;
    this.mirror();
    AppSettingsStore.putBoolean(context, this.prefKey, enabled);
    Log.i(`${this.logTag} enabled=${enabled}`);
  }

  private mirror(): void {
    if (this.storageKey.length > 0) {
      AppStorage.setOrCreate<boolean>(this.storageKey, this.cachedValue);
    }
  }
}
