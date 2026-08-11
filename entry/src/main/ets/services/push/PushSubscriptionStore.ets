import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Log } from '../logging/Log';
import { PushRelayRegistration } from './PushSubscriptionService';
import { SiteScope } from '../site/SiteScope';
import { AppConstants, LINUX_DO_HOST } from '../../common/constants/AppConstants';

const LOG_TAG: string = '[ArkDO][PushStore]';
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_PREFIX: string = 'push_subscription_user_';

/** 带站点后缀的订阅记录键(当前形态)。 */
export function pushSubscriptionKey(userId: number): string {
  return SiteScope.key(`${PREF_KEY_PREFIX}${userId}`);
}

/**
 * 多站改造之前的订阅记录键(不带站点后缀)。
 * 只在迁移时读一次,读到即改写成带后缀的形态并清掉,见 adoptLegacyRecord。
 */
export function legacyPushSubscriptionKey(userId: number): string {
  return `${PREF_KEY_PREFIX}${userId}`;
}

/**
 * 当前站点能不能认领遗留的旧订阅记录。
 *
 * **只有 linux.do 可以**。旧键是在多站改造之前写下的,那时 AppConstants.BASE_URL 还是
 * 写死的 https://linux.do —— 所以那条记录必然属于 linux.do。若改成"迁给当前站",
 * 一个现在停在自建论坛上的用户会凭空继承一条 linux.do 的订阅记录,
 * 于是拿着别人站的 subId/endpoint 去退订、去自愈,只会把事情搞得更乱。
 */
export function canAdoptLegacySubscription(host: string): boolean {
  return host === LINUX_DO_HOST;
}

export interface StoredPushSubscription {
  desiredEnabled: boolean;
  subId: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  updatedAt: number;
}

interface StoredPushSubscriptionPayload {
  desiredEnabled?: boolean;
  subId?: string;
  endpoint?: string;
  p256dh?: string;
  auth?: string;
  updatedAt?: number;
}

export class PushSubscriptionStore {
  static get(context: common.Context, userId: number): StoredPushSubscription {
    try {
      let raw: string = PushSubscriptionStore.store(context).getSync(PushSubscriptionStore.key(userId), '') as string;
      if (raw.length === 0) {
        // 新键读不到时,试着认领多站改造之前留下的旧键(一次性,认领后旧键即清空)。
        raw = PushSubscriptionStore.adoptLegacyRecord(context, userId);
      }
      if (raw.length === 0) {
        return PushSubscriptionStore.empty();
      }
      const payload: StoredPushSubscriptionPayload = JSON.parse(raw) as StoredPushSubscriptionPayload;
      return {
        desiredEnabled: payload.desiredEnabled === true,
        subId: typeof payload.subId === 'string' ? payload.subId : '',
        endpoint: typeof payload.endpoint === 'string' ? payload.endpoint : '',
        p256dh: typeof payload.p256dh === 'string' ? payload.p256dh : '',
        auth: typeof payload.auth === 'string' ? payload.auth : '',
        updatedAt: typeof payload.updatedAt === 'number' ? payload.updatedAt : 0
      };
    } catch (err) {
      Log.i(`${LOG_TAG} read failed userId=${userId} error=${JSON.stringify(err)}`);
      return PushSubscriptionStore.empty();
    }
  }

  static saveEnabled(context: common.Context, userId: number, registration: PushRelayRegistration): void {
    PushSubscriptionStore.save(context, userId, {
      desiredEnabled: true,
      subId: registration.subId ?? '',
      endpoint: registration.endpoint,
      p256dh: registration.p256dh,
      auth: registration.auth,
      updatedAt: Date.now()
    });
  }

  static saveDisabled(context: common.Context, userId: number): void {
    PushSubscriptionStore.save(context, userId, {
      desiredEnabled: false,
      subId: '',
      endpoint: '',
      p256dh: '',
      auth: '',
      updatedAt: Date.now()
    });
  }

  static toRegistration(stored: StoredPushSubscription): PushRelayRegistration | undefined {
    if (stored.endpoint.length === 0 || stored.p256dh.length === 0 || stored.auth.length === 0) {
      return undefined;
    }
    return {
      subId: stored.subId,
      endpoint: stored.endpoint,
      p256dh: stored.p256dh,
      auth: stored.auth
    };
  }

  private static save(context: common.Context, userId: number, value: StoredPushSubscription): void {
    try {
      const store: preferences.Preferences = PushSubscriptionStore.store(context);
      store.putSync(PushSubscriptionStore.key(userId), JSON.stringify(value));
      store.flush();
    } catch (err) {
      Log.i(`${LOG_TAG} write failed userId=${userId} error=${JSON.stringify(err)}`);
    }
  }

  /**
   * 认领多站改造(SiteScope 分键)之前写下的订阅记录,返回其原始 JSON;没有可认领的返回空串。
   *
   * ## 为什么必须有这一步
   * 键从 `push_subscription_user_<id>` 改成 `..._<id>@<host>` 时没有做迁移,于是老用户
   * 升级后本地记录整个读不到,而**服务端的订阅一个都没退**。表现出来是三件事:
   *
   *   1. 设置页开关显示"未开启",通知却照收(refreshStatus 读的就是这条记录);
   *   2. reconcile() 因 desiredEnabled=false 直接返回,订阅从此失去自愈能力 ——
   *      push token 一轮换就静默失效,而界面上看不出任何异常;
   *   3. **登出不再退订**。disableForLogout 拿不到 registration 就提前返回,那条订阅
   *      连同 deviceToken 一起留在中继里,换号后本机继续收到上一个账号的私信/回复推送。
   *      这正是 disableForLogout 注释里点名要防的跨账号泄露。
   *
   * 认领是一次性的:读到就改写成带站点后缀的形态,并把旧键清空,后续调用不再走这条路。
   * 清空用 putSync('') 而不是删键 —— 读取侧本就以"空串 = 没有记录"为准,少依赖一个 API。
   */
  private static adoptLegacyRecord(context: common.Context, userId: number): string {
    if (!canAdoptLegacySubscription(AppConstants.HOST)) {
      return '';
    }
    try {
      const store: preferences.Preferences = PushSubscriptionStore.store(context);
      const legacyKey: string = legacyPushSubscriptionKey(userId);
      const raw: string = store.getSync(legacyKey, '') as string;
      if (raw.length === 0) {
        return '';
      }
      store.putSync(pushSubscriptionKey(userId), raw);
      store.putSync(legacyKey, '');
      store.flush();
      Log.i(`${LOG_TAG} adopted legacy subscription userId=${userId} host=${AppConstants.HOST}`);
      return raw;
    } catch (err) {
      Log.i(`${LOG_TAG} adopt legacy failed userId=${userId} error=${JSON.stringify(err)}`);
      return '';
    }
  }

  private static empty(): StoredPushSubscription {
    return {
      desiredEnabled: false,
      subId: '',
      endpoint: '',
      p256dh: '',
      auth: '',
      updatedAt: 0
    };
  }

  /**
   * 订阅记录的键。**必须带站点**:Discourse 的 userId 是站内自增整数,你在 A 站是 123、
   * 在 B 站也可能是 123 —— 只按 userId 分键,两个论坛的订阅记录会互相覆盖,导致
   * 「给 A 站注册的订阅被 B 站顶掉」「退订退到错的站」。
   *
   * 改键那次没做迁移,老用户的记录留在了不带后缀的旧键上,见 adoptLegacyRecord。
   */
  private static key(userId: number): string {
    return pushSubscriptionKey(userId);
  }

  private static store(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
  }
}
