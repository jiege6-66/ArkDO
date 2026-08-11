import { common } from '@kit.AbilityKit';
import { BooleanPref } from '../../common/prefs/AppSettingsStore';

/** AppStorage 中「动态头像」开关的 key，供 UserAvatar 通过 @StorageProp 响应式绑定。 */
export const ANIMATED_AVATAR_ENABLED_STORAGE_KEY: string = 'animatedAvatarEnabled';

// 默认开：动图头像是更贴近网页端的观感。只有用户显式关过(存 false)才为关。
const PREF: BooleanPref =
  new BooleanPref('[ArkDO][AnimatedAvatar]', 'animated_avatar_enabled', ANIMATED_AVATAR_ENABLED_STORAGE_KEY, true);

/**
 * 「动态头像」开关：控制头像与 flair 角标是否播放动图。
 *
 * 关：       头像一律取首帧渲染成静态图 —— 走 host webview 取字节 + createPixelMap 的路径，
 *          PixelMap 天然只有一帧，不会动；flair 角标同理。
 * 开(默认)：  linux.do 的 avatar_template 在 CDN(ldstatic.com)上本身常是动图内容，
 *          交给原生 Image 直载即会自动播放；同时优先使用 animated_avatar 候选。
 *
 * 代价是列表里多个头像同时播动图会让渲染树每帧变脏；若遇掉帧，可在实验性功能里关掉作对照
 * (这个开关也是排查掉帧的对照工具)。注意：关闭时头像改走 webview 桥取字节，首次加载会比
 * 原生 Image 慢(缓存命中后无差别)。
 *
 * 持久化 + AppStorage 响应式镜像的通用实现见 BooleanPref;本类只是保留静态门面。
 */
export class AnimatedAvatarPrefs {
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
