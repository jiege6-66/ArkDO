import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][DraftBus]';

export type DraftDeletedListener = (draftKey: string) => void;

// 草稿可能从列表手动删除，也可能在发帖成功后由编辑器清理。
// 删除方只负责发布事实，根页面统一维护个人页角标，避免跨多层组件传回调。
export class DraftEventBus {
  private static listeners: Map<number, DraftDeletedListener> = new Map();
  private static nextListenerId: number = 0;

  static subscribeDeleted(listener: DraftDeletedListener): () => void {
    const listenerId: number = DraftEventBus.nextListenerId;
    DraftEventBus.nextListenerId++;
    DraftEventBus.listeners.set(listenerId, listener);
    return () => {
      DraftEventBus.listeners.delete(listenerId);
    };
  }

  static notifyDeleted(draftKey: string): void {
    const snapshot: DraftDeletedListener[] = [];
    DraftEventBus.listeners.forEach((listener: DraftDeletedListener) => {
      snapshot.push(listener);
    });
    Log.i(`${LOG_TAG} deleted key=${draftKey} listeners=${snapshot.length}`);
    for (let index: number = 0; index < snapshot.length; index++) {
      try {
        snapshot[index](draftKey);
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed key=${draftKey} error=${JSON.stringify(error)}`);
      }
    }
  }
}
