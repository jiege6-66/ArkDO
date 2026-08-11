import { common } from '@kit.AbilityKit';
import { BooleanPref } from '../../common/prefs/AppSettingsStore';

/** AppStorage 中「点分类/标签快速筛选」开关的 key,供首页通过 @StorageProp 响应式绑定。 */
export const BADGE_FILTER_ENABLED_STORAGE_KEY: string = 'badgeFilterEnabled';

// 默认关:开着时帖子行上的徽章会抢走点击,而整行点击是「打开帖子」这个最高频的动作 ——
// 误触代价不对称,所以让用户显式打开。
const PREF: BooleanPref =
  new BooleanPref('[ArkDO][BadgeFilter]', 'badge_filter_enabled', BADGE_FILTER_ENABLED_STORAGE_KEY, false);

/**
 * 「点分类/标签快速筛选」开关。
 * 持久化 + AppStorage 响应式镜像的通用实现见 BooleanPref;本类只是保留静态门面。
 */
export class BadgeFilterPrefs {
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
