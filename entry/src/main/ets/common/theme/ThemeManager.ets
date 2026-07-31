import { Log } from '../../services/logging/Log';
import { common, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ImmersiveWindow } from '../utils/ImmersiveWindow';

const LOG_TAG: string = '[ArkDO][Theme]';
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_THEME_MODE: string = 'themeMode';

/** AppStorage 中主题模式的 key，供 UI 通过 @StorageLink/@StorageProp 绑定。 */
export const THEME_MODE_STORAGE_KEY: string = 'themeMode';

/**
 * AppStorage 中「当前是否为深色渲染」的布尔 key。资源色(app.color.*)靠限定符自动翻转,
 * 但非资源的染色(如公式位图 colorFilter 矩阵、烘进数值的色值)拿不到限定符,须靠此布尔手动切换。
 * 取值同时考虑强制主题(DARK/LIGHT)与「跟随系统」下的系统实际明暗,供 @StorageProp 响应式绑定。
 */
export const APP_IS_DARK_STORAGE_KEY: string = 'appIsDark';

/** 三态主题模式：跟随系统 / 强制浅色 / 强制深色。 */
export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

/**
 * 集中管理应用颜色模式：负责 ThemeMode 与系统 ColorMode 的映射、preferences 持久化、
 * AppStorage 状态同步，以及调用 setColorMode 让 ArkUI 重新解析颜色资源。
 */
export class ThemeManager {
  // 「当前生效的颜色模式是否为深色」,取自 Configuration.colorMode——即 ArkUI 解析 app.color.*
  // 限定符时用的那个模式,所以它天然与资源色一致;「跟随系统」下它就等于系统明暗。
  // 早期版本这里用 mediaquery('(dark-mode: true)') 取系统明暗,但那个 API 要求有 UI 实例,
  // 而 init 跑在 EntryAbility.onCreate(窗口还没建),部分机型上恒返回 false 且 change 不回调,
  // 导致深色模式下 appIsDark 一直是 false(高亮底色、公式染色错用浅色)。
  private static effectiveIsDark: boolean = false;
  private static currentMode: ThemeMode = ThemeMode.SYSTEM;

  /** 纯映射：ThemeMode -> 系统 ColorMode（便于单测）。 */
  static toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
    switch (mode) {
      case ThemeMode.LIGHT:
        return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      case ThemeMode.DARK:
        return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      default:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
  }

  /** 纯解析：把持久化的字符串还原为 ThemeMode，非法值回退到 SYSTEM。 */
  static parseMode(raw: string): ThemeMode {
    switch (raw) {
      case ThemeMode.LIGHT:
        return ThemeMode.LIGHT;
      case ThemeMode.DARK:
        return ThemeMode.DARK;
      default:
        return ThemeMode.SYSTEM;
    }
  }

  /** 纯映射：主题模式 + 当前生效明暗 -> 是否按深色渲染（便于单测）。 */
  static resolveIsDark(mode: ThemeMode, effectiveIsDark: boolean): boolean {
    switch (mode) {
      case ThemeMode.DARK:
        return true;
      case ThemeMode.LIGHT:
        return false;
      default:
        return effectiveIsDark;
    }
  }

  /** 应用启动时调用：读取上次选择并应用；首次无记录等价于跟随系统。 */
  static init(context: common.UIAbilityContext): void {
    let mode: ThemeMode = ThemeMode.SYSTEM;
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      const raw: string = store.getSync(PREF_KEY_THEME_MODE, ThemeMode.SYSTEM) as string;
      mode = ThemeManager.parseMode(raw);
    } catch (err) {
      Log.e(`${LOG_TAG} read theme mode failed: ${JSON.stringify(err)}`);
    }
    ThemeManager.currentMode = mode;
    AppStorage.setOrCreate(THEME_MODE_STORAGE_KEY, mode);
    // 必须早于 applyColorMode 读:强制主题一经下发,config.colorMode 就变成那个强制值,
    // 再读就拿不到系统明暗了。此刻读到的才是系统当前明暗,正是「跟随系统」要的初值。
    ThemeManager.applyConfiguration(context.config);
    ThemeManager.applyColorMode(context, mode);
    // config.colorMode 缺省(NOT_SET)时上面不会写 AppStorage,这里兜底播种一次,保证首帧有值。
    ThemeManager.recomputeIsDark();
  }

  /**
   * 颜色模式配置变化：由 EntryAbility 的 onConfigurationUpdate（系统切深浅色 / 定时深色触发）
   * 与 onForeground（回前台补读，防止后台期间的变化漏收）转发进来。
   */
  static applyConfiguration(config: Configuration): void {
    const colorMode: ConfigurationConstant.ColorMode | undefined = config.colorMode;
    if (colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      ThemeManager.effectiveIsDark = true;
    } else if (colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      ThemeManager.effectiveIsDark = false;
    } else {
      // NOT_SET / undefined:这次配置不带颜色模式信息(如只改了字体大小),保持上次值。
      return;
    }
    ThemeManager.recomputeIsDark();
  }

  /** 用户切换主题：立即应用 + 持久化 + 同步 AppStorage 供 UI 高亮。 */
  static setMode(context: common.Context, mode: ThemeMode): void {
    ThemeManager.currentMode = mode;
    AppStorage.setOrCreate(THEME_MODE_STORAGE_KEY, mode);
    ThemeManager.applyColorMode(context, mode);
    ThemeManager.recomputeIsDark();
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      store.putSync(PREF_KEY_THEME_MODE, mode);
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} persist theme mode failed: ${JSON.stringify(err)}`);
    }
  }

  private static applyColorMode(context: common.Context, mode: ThemeMode): void {
    try {
      context.getApplicationContext().setColorMode(ThemeManager.toColorMode(mode));
    } catch (err) {
      Log.e(`${LOG_TAG} setColorMode failed: ${JSON.stringify(err)}`);
    }
  }

  // 计算「当前是否深色渲染」并写入 AppStorage:强制主题优先,SYSTEM 时取当前生效的颜色模式。
  // 资源色靠限定符自动翻转,此布尔只服务于非资源染色(公式位图 colorFilter、烘进数值的高亮色等)。
  private static recomputeIsDark(): void {
    const dark: boolean = ThemeManager.resolveIsDark(ThemeManager.currentMode, ThemeManager.effectiveIsDark);
    // 值没变就不写,避免无谓地惊动所有 @StorageProp('appIsDark') 的组件重渲染。
    if (AppStorage.get<boolean>(APP_IS_DARK_STORAGE_KEY) !== dark) {
      AppStorage.setOrCreate(APP_IS_DARK_STORAGE_KEY, dark);
    }
    // 常驻全屏布局下系统栏图标色不随颜色模式自动翻转,须随主题手动同步(深色浅图标、浅色深图标)。
    ImmersiveWindow.applyBarContentColor(dark);
  }
}
