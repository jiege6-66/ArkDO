import { describe, it, expect, beforeAll, afterAll } from '@ohos/hypium';
import { AppConstants, LINUX_DO_HOST } from '../main/ets/common/constants/AppConstants';
import {
  canAdoptLegacySubscription,
  legacyPushSubscriptionKey,
  pushSubscriptionKey
} from '../main/ets/services/push/PushSubscriptionStore';

/**
 * 推送订阅记录的键,以及"能不能认领旧键"的判定。
 *
 * 守的是一次真实事故:多站改造把键从 push_subscription_user_<id> 改成 ..._<id>@<host>,
 * 但没有迁移。老用户升级后本地记录整个读不到,而服务端订阅一个都没退 —— 设置页开关显示
 * "未开启"却照收通知、reconcile 从此不再自愈、登出也不再退订(跨账号泄露)。
 */
export default function pushSubscriptionKeysTest() {
  describe('PushSubscriptionKeys', () => {
    // AppConstants 的当前站点是进程级全局态,本组用例要改它。先存后还,免得泄漏给其它用例 ——
    // 用例的执行顺序不该成为谁能不能通过的前提。
    let savedBaseUrl: string = '';
    let savedHost: string = '';

    beforeAll(() => {
      savedBaseUrl = AppConstants.BASE_URL;
      savedHost = AppConstants.HOST;
    });

    afterAll(() => {
      AppConstants.setActiveSite(savedBaseUrl, savedHost);
    });

    it('scopes the current key by host', 0, () => {
      AppConstants.setActiveSite('https://linux.do', LINUX_DO_HOST);
      expect(pushSubscriptionKey(123)).assertEqual('push_subscription_user_123@linux.do');

      AppConstants.setActiveSite('https://meta.discourse.org', 'meta.discourse.org');
      expect(pushSubscriptionKey(123)).assertEqual('push_subscription_user_123@meta.discourse.org');
    });

    it('keeps the legacy key free of any host suffix', 0, () => {
      // 旧键的形状是既成事实(磁盘上就是这么存的),不能跟着当前站点变。
      AppConstants.setActiveSite('https://meta.discourse.org', 'meta.discourse.org');
      expect(legacyPushSubscriptionKey(123)).assertEqual('push_subscription_user_123');
    });

    it('distinguishes the two keys for the same user', 0, () => {
      AppConstants.setActiveSite('https://linux.do', LINUX_DO_HOST);
      const scoped: string = pushSubscriptionKey(7);
      const legacy: string = legacyPushSubscriptionKey(7);
      expect(scoped === legacy).assertFalse();
      expect(scoped.startsWith(legacy)).assertTrue();
    });

    it('adopts the legacy record only on linux.do', 0, () => {
      // 旧键是在 BASE_URL 还写死成 https://linux.do 的年代写下的,那条记录必然属于 linux.do。
      // 迁给"当前站"的话,停在自建论坛上的用户会凭空继承一条 linux.do 的订阅,
      // 于是拿着别人站的 subId/endpoint 去退订、去自愈。
      expect(canAdoptLegacySubscription(LINUX_DO_HOST)).assertTrue();
      expect(canAdoptLegacySubscription('meta.discourse.org')).assertFalse();
      expect(canAdoptLegacySubscription('')).assertFalse();
    });
  });
}
