import { common } from '@kit.AbilityKit';
import { BooleanPref } from '../../common/prefs/AppSettingsStore';

/** AppStorage 中「帖子内新回复提醒」开关的 key，供详情页通过 @StorageProp 响应式绑定。 */
export const REALTIME_POSTS_ENABLED_STORAGE_KEY: string = 'realtimePostsEnabled';

// 默认关：属实验性功能，需用户在实验性功能里主动开启。
const PREF: BooleanPref =
  new BooleanPref('[ArkDO][RealtimePosts]', 'realtime_posts_enabled', REALTIME_POSTS_ENABLED_STORAGE_KEY, false);

/**
 * 「帖子内新回复提醒」开关：控制进入帖子详情后是否订阅 /topic/<id> 实时接收他人新回复。
 * 与「首页新话题提醒」(首页提示条)相互独立。开启后打开帖子期间多订一个临时频道
 * (MessageBus 长轮询本就为通知常驻运行，开销极低)。
 *
 * 持久化 + AppStorage 响应式镜像的通用实现见 BooleanPref;本类只是保留静态门面。
 */
export class RealtimePostsPrefs {
  static isEnabled(): boolean {
    return PREF.isEnabled();
  }

  static load(context: common.UIAbilityContext | common.Context): boolean {
    return PREF.load(context);
  }

  static setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): void {
    PREF.setEnabled(context, enabled);
  }
}
