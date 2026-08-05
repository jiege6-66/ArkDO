import { Log } from '../logging/Log';
import { User } from '../../models/User';

const LOG_TAG: string = '[ArkDO][CurrentUserBus]';

export type CurrentUserListener = (user: User) => void;

/**
 * 静默会话快照总线。
 *
 * 通知轮询本来就在打 /session/current.json(4~6 分钟一次;通知到达、回前台时还会即时刷),
 * 但过去只从响应里取了未读数,其余字段——侧栏自选的标签与版块、草稿数——全扔了,
 * 结果用户在网页端改完侧栏,App 要等到杀进程重进才跟上。这条总线把那份完整解析结果转给根页面。
 *
 * 「静默」是它与 SessionEventBus 的分界:
 *  · SessionEventBus = 「会话可能变了,去重查一次」——会改登录态,会让头像转 loading。
 *  · 这条 = 「顺路带回来的一份数据,你自己挑要用的」——订阅方绝不能拿它改登录态。
 *    轮询发现真的登出时走的仍是 SessionEventBus,不是这里。
 *
 * 只传数据不带策略:采纳哪些字段、什么前提下采纳,由订阅方(RootTabPage)和它那堆会话策略放在一起决定。
 */
export class CurrentUserEventBus {
  private static listeners: Map<number, CurrentUserListener> = new Map();
  private static nextListenerId: number = 0;

  static subscribe(listener: CurrentUserListener): () => void {
    const listenerId: number = CurrentUserEventBus.nextListenerId;
    CurrentUserEventBus.nextListenerId++;
    CurrentUserEventBus.listeners.set(listenerId, listener);

    return () => {
      CurrentUserEventBus.listeners.delete(listenerId);
    };
  }

  // 不保留 last:这是「顺路刷新」而非状态源,新订阅者该去看 RootTabPage 已经落定的 currentUser,
  // 而不是补一发可能已经过期的旧快照。
  static publish(user: User): void {
    const listeners: CurrentUserListener[] = [];
    CurrentUserEventBus.listeners.forEach((listener: CurrentUserListener) => {
      listeners.push(listener);
    });

    Log.i(`${LOG_TAG} publish userId=${user.id} sidebarTags=${user.sidebarTags?.length ?? 0} listeners=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](user);
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }
}
