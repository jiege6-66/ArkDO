import { AppConstants, LINUX_DO_HOST } from '../../common/constants/AppConstants';
import { ACTIVE_FORUM_NAME_KEY, ACTIVE_FORUM_TICK, ACTIVE_FORUM_URL_KEY, bumpTick } from '../../common/constants/StorageKeys';
import { ForumDef, ForumPrefs } from './ForumPrefs';
import { Log } from '../logging/Log';
import { SiteUrl } from './SiteUrl';
import { common } from '@kit.AbilityKit';

const LOG_TAG: string = '[ArkDO][CurrentSite]';

/**
 * 「当前论坛」的运行时状态。全 app 站点相关地址的唯一事实来源。
 *
 * 依赖方向:CurrentSite → AppConstants(单向 setActiveSite 推入)。AppConstants 不反向
 * import 站点模块,否则成环。
 *
 * ## epoch(代次)
 * 切站不是瞬时的:旧站还有在途请求、宿主 webview 还挂在旧 origin 上。这些迟到的响应
 * 回来时若直接写入状态,就会把旧站的帖子/用户塞进新站的界面。故每次切站 epoch +1,
 * 发请求时记下当时的 epoch,回调里比对 —— 不等就整条丢弃。判据是「发起时的代次」而非
 * 「站点地址」,因为来回切回同一个站也必须让中间那批响应失效。
 */
export class CurrentSite {
  private static active: ForumDef | undefined = undefined;
  private static epochValue: number = 0;
  private static listeners: Array<() => void> = [];

  // ==================== 生命周期 ====================

  /**
   * 冷启动初始化。必须早于 DoH 下发与任何页面挂载 —— 那些都要读 BASE_URL。
   * 未选定或存储里的 id 已失效时,回落到列表第一个;列表为空则保持未配置状态,
   * 由首启引导页接手。
   */
  static init(context: common.Context): void {
    const forums: ForumDef[] = ForumPrefs.getForums(context);
    if (forums.length === 0) {
      CurrentSite.apply(undefined);
      Log.i(`${LOG_TAG} init: no forum configured`);
      return;
    }
    const savedId: string = ForumPrefs.getActiveId(context);
    let picked: ForumDef = forums[0];
    for (let index: number = 0; index < forums.length; index++) {
      if (forums[index].id === savedId) {
        picked = forums[index];
        break;
      }
    }
    // 回落时把 id 写回去,避免每次冷启动都要重新回落一遍。
    if (picked.id !== savedId) {
      ForumPrefs.setActiveId(context, picked.id);
    }
    CurrentSite.apply(picked);
    Log.i(`${LOG_TAG} init: active=${picked.baseUrl}`);
  }

  /**
   * 切换当前论坛。持久化 + 推入 AppConstants + epoch 自增 + 通知订阅者。
   * 切到同一个站直接返回 false,免得白重建一遍宿主 webview。
   */
  static switchTo(context: common.Context, forum: ForumDef): boolean {
    const current: ForumDef | undefined = CurrentSite.active;
    if (current && current.id === forum.id) {
      return false;
    }
    ForumPrefs.setActiveId(context, forum.id);
    CurrentSite.apply(forum);
    CurrentSite.epochValue += 1;
    Log.i(`${LOG_TAG} switch to ${forum.baseUrl} epoch=${CurrentSite.epochValue}`);
    CurrentSite.notify();
    return true;
  }

  /**
   * 论坛列表被改动后重新裁定当前论坛(新增第一个、删掉当前那个等场景)。
   * 当前论坛仍在列表里就原样保留,否则按 init 的规则重选。
   */
  static reconcile(context: common.Context): void {
    const forums: ForumDef[] = ForumPrefs.getForums(context);
    const current: ForumDef | undefined = CurrentSite.active;
    if (current) {
      for (let index: number = 0; index < forums.length; index++) {
        if (forums[index].id === current.id) {
          return;
        }
      }
    }
    const before: string = current ? current.baseUrl : '';
    if (forums.length === 0) {
      CurrentSite.apply(undefined);
      ForumPrefs.setActiveId(context, '');
    } else {
      ForumPrefs.setActiveId(context, forums[0].id);
      CurrentSite.apply(forums[0]);
    }
    const after: string = CurrentSite.active ? CurrentSite.active.baseUrl : '';
    if (before !== after) {
      CurrentSite.epochValue += 1;
      Log.i(`${LOG_TAG} reconcile: ${before} → ${after} epoch=${CurrentSite.epochValue}`);
      CurrentSite.notify();
    }
  }

  // ==================== 读取 ====================

  /** 是否已选定论坛。未选定时不应发起任何站点请求。 */
  static get isConfigured(): boolean {
    return CurrentSite.active !== undefined;
  }

  static get forum(): ForumDef | undefined {
    return CurrentSite.active;
  }

  /** 站点根地址,带协议、无尾斜杠。未配置时为空串。 */
  static get baseUrl(): string {
    const forum: ForumDef | undefined = CurrentSite.active;
    return forum ? forum.baseUrl : '';
  }

  static get host(): string {
    const forum: ForumDef | undefined = CurrentSite.active;
    return forum ? SiteUrl.hostOf(forum.baseUrl) : '';
  }

  /** 展示名。未配置时返回 App 名,免得界面上出现空标题。 */
  static get displayName(): string {
    const forum: ForumDef | undefined = CurrentSite.active;
    return forum ? forum.name : AppConstants.APP_NAME;
  }

  /** 当前代次。发请求时记下它,回调里用 isCurrentEpoch 校验。 */
  static get epoch(): number {
    return CurrentSite.epochValue;
  }

  /** 发起时的代次是否仍然有效。false 表示期间切过站,该响应必须丢弃。 */
  static isCurrentEpoch(epoch: number): boolean {
    return epoch === CurrentSite.epochValue;
  }

  /** 当前站点是否为 linux.do。专属能力的判定基准,详见 SiteCapabilities。 */
  static get isLinuxDo(): boolean {
    return CurrentSite.host === LINUX_DO_HOST;
  }

  // ==================== 变更订阅 ====================

  /**
   * 订阅切站事件。返回取消订阅的函数 —— 页面在 aboutToDisappear 里务必调用,
   * 否则被销毁的页面还会被回调,拿着失效的 this 写状态。
   */
  static subscribe(listener: () => void): () => void {
    CurrentSite.listeners.push(listener);
    return () => {
      const kept: Array<() => void> = [];
      for (let index: number = 0; index < CurrentSite.listeners.length; index++) {
        if (CurrentSite.listeners[index] !== listener) {
          kept.push(CurrentSite.listeners[index]);
        }
      }
      CurrentSite.listeners = kept;
    };
  }

  // ==================== 内部 ====================

  // 一处推入 AppConstants:全 app 的 BASE_URL / LOGIN_URL / HOST_BOOTSTRAP_URL 等
  // 都由它派生,所以这里是唯一的写入口。顺带刷 AppStorage 镜像给 UI 侧监听。
  private static apply(forum: ForumDef | undefined): void {
    CurrentSite.active = forum;
    const baseUrl: string = forum ? forum.baseUrl : '';
    AppConstants.setActiveSite(baseUrl, forum ? SiteUrl.hostOf(forum.baseUrl) : '');
    AppStorage.setOrCreate(ACTIVE_FORUM_URL_KEY, baseUrl);
    AppStorage.setOrCreate(ACTIVE_FORUM_NAME_KEY, forum ? forum.name : '');
    bumpTick(ACTIVE_FORUM_TICK);
  }

  // 逐个 try:一个订阅者抛异常不能连累后面的(尤其宿主 webview 的重建回调必须跑到)。
  private static notify(): void {
    const snapshot: Array<() => void> = CurrentSite.listeners.slice();
    for (let index: number = 0; index < snapshot.length; index++) {
      try {
        snapshot[index]();
      } catch (err) {
        Log.e(`${LOG_TAG} listener failed: ${JSON.stringify(err)}`);
      }
    }
  }
}
