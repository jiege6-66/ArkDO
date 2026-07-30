import { Log } from '../logging/Log';
import { User } from '../../models/User';
import { ArkWebNetworkBridge } from '../network/ArkWebNetworkBridge';
import { NetworkResult } from '../network/NetworkTypes';
import { MessageBusData, MessageBusEvent, MessageBusPresenceUser } from '../message/MessageBusEventBus';

const LOG_TAG: string = '[ArkDO][Presence]';
// 展示上限：对齐 Discourse presence_max_users_shown 默认值 5。
const MAX_SHOWN: number = 5;

// Discourse GET /presence/get 单个频道的状态(presence.js:170-183)。
interface PresenceGetState {
  users?: MessageBusPresenceUser[];
  last_message_id?: number;
  count?: number;
}

// 详情页"谁正在回复"下行(只读)服务：
//   1) GET /presence/get 取初始在场用户 + last_message_id；
//   2) 经长轮询循环订阅 MessageBus 频道 /presence/discourse-presence/reply/<id>，收 entering/leaving 增量；
//   3) 本地维护在场列表，滤掉自己、截到 MAX_SHOWN，回调给页面驱动 ReplyingPresenceBar。
// 不做上行(不上报自己在回复)——那是块 1，另议。
export class TopicPresenceService {
  private bridgeProvider: () => ArkWebNetworkBridge;
  private currentUserId: () => number;
  private onChange: (users: User[]) => void;
  private topicId: number = 0;
  // Discourse presence 频道名(不含 /presence 前缀)与其对应的 MessageBus 频道名(含前缀)。
  private presenceChannel: string = '';
  private busChannel: string = '';
  private started: boolean = false;
  // 全量在场用户(含自己，按进入顺序)。展示时再滤自己 + slice。
  private users: User[] = [];
  // 序号：作废过期的 GET 响应(快速换帖/重同步时)。
  private syncSeq: number = 0;

  constructor(bridgeProvider: () => ArkWebNetworkBridge, currentUserId: () => number,
    onChange: (users: User[]) => void) {
    this.bridgeProvider = bridgeProvider;
    this.currentUserId = currentUserId;
    this.onChange = onChange;
  }

  // 进入某帖：确定频道名并同步一次。重复对同一帖调用安全(幂等)。
  start(topicId: number): void {
    if (this.started && this.topicId === topicId) {
      return;
    }
    this.stop();
    this.started = true;
    this.topicId = topicId;
    this.presenceChannel = `/discourse-presence/reply/${topicId}`;
    this.busChannel = `/presence${this.presenceChannel}`;
    this.syncNow();
  }

  // 离开/关闭：退订 MessageBus 频道、清空、作废在途 GET。
  stop(): void {
    if (!this.started) {
      return;
    }
    this.bridgeProvider().unsubscribeChannel(this.busChannel);
    this.started = false;
    this.topicId = 0;
    this.presenceChannel = '';
    this.busChannel = '';
    this.users = [];
    this.syncSeq++;
    this.emit();
  }

  // 长轮询循环重启(config-ready)后重同步：重取初始态并重订阅(频道可能随新 state 重建而丢失)。
  resync(): void {
    if (!this.started) {
      return;
    }
    this.syncNow();
  }

  // MessageBus 事件入口：只认本帖 presence 频道上的增量消息。
  handleBusEvent(event: MessageBusEvent): void {
    if (!this.started || event.type !== 'message' || event.channel !== this.busChannel) {
      return;
    }
    const data: MessageBusData | undefined = event.data;
    if (data === undefined || data === null) {
      return;
    }
    let changed: boolean = false;
    const leaving: number[] | undefined = data.leaving_user_ids;
    if (Array.isArray(leaving) && leaving.length > 0) {
      const kept: User[] = this.users.filter((u: User) => leaving.indexOf(u.id) < 0);
      if (kept.length !== this.users.length) {
        this.users = kept;
        changed = true;
      }
    }
    const entering: MessageBusPresenceUser[] | undefined = data.entering_users;
    if (Array.isArray(entering) && entering.length > 0) {
      entering.forEach((raw: MessageBusPresenceUser) => {
        const mapped: User | undefined = this.mapUser(raw);
        if (mapped === undefined) {
          return;
        }
        const user: User = mapped;
        if (this.users.every((u: User) => u.id !== user.id)) {
          this.users = this.users.concat([user]);
          changed = true;
        }
      });
    }
    if (changed) {
      this.emit();
    }
  }

  // 取初始态并订阅增量。GET 回来后用 last_message_id 作订阅起点，闭合 GET 与订阅之间的窗口。
  private async syncNow(): Promise<void> {
    const seq: number = ++this.syncSeq;
    const path: string = `/presence/get?channels%5B%5D=${encodeURIComponent(this.presenceChannel)}`;
    const response: NetworkResult<string> = await this.bridgeProvider().getJson(path);
    if (seq !== this.syncSeq || !this.started) {
      return; // 已过期或已停
    }
    let lastId: number = -1;
    if (response.success && response.data !== undefined) {
      try {
        const parsed: Record<string, PresenceGetState> =
          JSON.parse(response.data) as Record<string, PresenceGetState>;
        const state: PresenceGetState | undefined = parsed[this.presenceChannel];
        if (state !== undefined && state !== null) {
          this.users = this.mapUsers(state.users);
          if (typeof state.last_message_id === 'number') {
            lastId = state.last_message_id;
          }
        }
      } catch (error) {
        Log.i(`${LOG_TAG} parse /presence/get failed error=${JSON.stringify(error)}`);
      }
    } else {
      Log.i(`${LOG_TAG} /presence/get failed status=${response.statusCode}`);
    }
    // 订阅增量频道(挂进运行中的长轮询循环)。起点=last_message_id(缺则 -1 只收新)。
    this.bridgeProvider().subscribeChannel(this.busChannel, lastId);
    Log.i(`${LOG_TAG} synced topicId=${this.topicId} initialUsers=${this.users.length} lastId=${lastId}`);
    this.emit();
  }

  private mapUsers(raw?: MessageBusPresenceUser[]): User[] {
    const list: User[] = [];
    if (Array.isArray(raw)) {
      raw.forEach((item: MessageBusPresenceUser) => {
        const mapped: User | undefined = this.mapUser(item);
        if (mapped !== undefined) {
          list.push(mapped);
        }
      });
    }
    return list;
  }

  private mapUser(raw: MessageBusPresenceUser): User | undefined {
    if (raw === undefined || raw === null || typeof raw.id !== 'number' || typeof raw.username !== 'string') {
      return undefined;
    }
    return {
      id: raw.id,
      username: raw.username,
      displayName: typeof raw.name === 'string' ? raw.name : undefined,
      avatarTemplate: typeof raw.avatar_template === 'string' ? raw.avatar_template : undefined
    };
  }

  // 计算展示列表：滤掉自己、截到 MAX_SHOWN，回调页面。
  private emit(): void {
    const me: number = this.currentUserId();
    const shown: User[] = this.users.filter((u: User) => u.id !== me).slice(0, MAX_SHOWN);
    this.onChange(shown);
  }
}
