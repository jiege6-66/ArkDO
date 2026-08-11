import { common } from '@kit.AbilityKit';
import { BooleanPref } from '../../common/prefs/AppSettingsStore';

/** AppStorage 中「首页新话题提醒」开关的 key，供宿主 webview 与首页通过 @StorageProp 响应式绑定。 */
export const REALTIME_TOPICS_ENABLED_STORAGE_KEY: string = 'realtimeTopicsEnabled';

// 默认关：该功能会常驻后台长轮询，并非所有用户都需要。
const PREF: BooleanPref =
  new BooleanPref('[ArkDO][RealtimeTopics]', 'realtime_topics_enabled', REALTIME_TOPICS_ENABLED_STORAGE_KEY, false);

/**
 * 「首页新话题提醒」开关。持久化 + AppStorage 响应式镜像的通用实现见 BooleanPref；
 * 本类只是保留静态门面，让既有调用点无需改动。
 */
export class RealtimeTopicsPrefs {
  static isEnabled(): boolean {
    return PREF.isEnabled();
  }

  /** 冷启动调用一次：读盘回填内存镜像并种入 AppStorage，保证任何页面挂载前镜像已就绪。 */
  static load(context: common.UIAbilityContext | common.Context): boolean {
    return PREF.load(context);
  }

  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    PREF.setEnabled(context, enabled);
  }
}
