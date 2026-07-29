import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][Ldc]';

export type LdcCreditChangedListener = () => void;

/**
 * LDC 余额变化广播。
 *
 * 详情页拿到新数据(含首次登录 credit 之后的那次)时通知一声,个人中心据此把入口行的数字刷新成
 * 最新的。个人中心是二级页,压在详情页下面不会重新 aboutToAppear,没有这条广播它会一直显示
 * 进详情页之前的旧值(或「去登录」)。数据本身走 LdcCreditSession 的缓存,广播只负责叫醒。
 */
export class LdcCreditEventBus {
  private static listeners: Map<number, LdcCreditChangedListener> = new Map();
  private static nextListenerId: number = 0;

  static subscribe(listener: LdcCreditChangedListener): () => void {
    const listenerId: number = LdcCreditEventBus.nextListenerId;
    LdcCreditEventBus.nextListenerId++;
    LdcCreditEventBus.listeners.set(listenerId, listener);

    return () => {
      LdcCreditEventBus.listeners.delete(listenerId);
    };
  }

  static notifyCreditChanged(): void {
    const listeners: LdcCreditChangedListener[] = [];
    LdcCreditEventBus.listeners.forEach((listener: LdcCreditChangedListener) => {
      listeners.push(listener);
    });

    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        Log.i(`${LOG_TAG} credit listener failed error=${JSON.stringify(error)}`);
      }
    }
  }
}
