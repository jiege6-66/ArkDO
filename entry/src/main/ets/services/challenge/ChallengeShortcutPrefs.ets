import { common } from '@kit.AbilityKit';
import { BooleanPref } from '../../common/prefs/AppSettingsStore';

// 默认关:多数用户从不撞盾,常驻入口只会碍眼;打开后也不是常驻——还要真的探测到 timings
// 被盾拦下才显示(见 ChallengeShortcutEventBus)。
// storageKey 传空串:这个开关没有 @StorageProp 订阅方,详情页在 aboutToAppear 里同步读一次即可。
const PREF: BooleanPref =
  new BooleanPref('[ArkDO][ChallengeShortcut]', 'challenge_shortcut_enabled', '', false);

/**
 * 「帖子页过盾快捷入口」开关的持久化。
 *
 * 对外仍是 async 门面:设置页有 `await ChallengeShortcutPrefs.load(...)` 的调用点,
 * 改成同步会牵动它们。内部走共享库的同步读写(整个库只开一次),没有真正的异步等待。
 */
export class ChallengeShortcutPrefs {
  static isEnabled(): boolean {
    return PREF.isEnabled();
  }

  // 冷启动/进设置页时载入一次,回填内存镜像。
  static async load(context: common.UIAbilityContext | common.Context): Promise<boolean> {
    return PREF.load(context);
  }

  static async setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): Promise<void> {
    PREF.setEnabled(context, enabled);
  }
}
