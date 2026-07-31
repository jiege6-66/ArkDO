import { Log } from '../logging/Log';
import { ChallengeEventBus } from '../challenge/ChallengeEventBus';
import { ChallengeState } from '../network/NetworkTypes';

const LOG_TAG: string = '[ArkDO][MessageBus]';

// Presence 频道 payload 里的用户(BasicUserSerializer：id/username/name/avatar_template)。
export interface MessageBusPresenceUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
}

// /latest、/new、/unread 三个频道消息里的 payload(topic_tracking_state.rb 的 publish_* 方法)。
// 频道本身是全局的、不随当前列表的筛选条件变,要不要算进当前列表全靠这里的字段自行比对。
// tags 只给 id 不给名字,且受服务端 SiteSetting.tagging_enabled 控制,可能整个缺席。
export interface MessageBusTopicTag {
  id?: number;
}

export interface MessageBusTopicPayload {
  category_id?: number;
  tags?: MessageBusTopicTag[];
}

export interface MessageBusData {
  topic_id?: number;
  message_type?: string;
  payload?: MessageBusTopicPayload;
  // /presence/<channel> 频道 payload(presence_channel.rb:335-347)：谁进入/离开"正在回复"。
  entering_users?: MessageBusPresenceUser[];
  leaving_user_ids?: number[];
  count_delta?: number;
  // /notification/<id> 频道 payload 的未读数（user.rb publish_notifications_state:921-931，已核源码）。
  // 铃铛角标用 all_unread_notifications_count（总未读，含私信）；unread_notifications 只含
  // high_priority=FALSE，漏私信，不能用于角标。unread_high_priority_notifications 为高优先级子集。
  all_unread_notifications_count?: number;
  unread_notifications?: number;
  unread_high_priority_notifications?: number;
  // /topic/<id> 频道 payload（post.rb publish_change_to_clients!:229-239，已核源码）。
  // id=帖子 id；post_number=楼号；type=动作类型（新楼为 'created'，还有 revised/deleted 等）。
  id?: number;
  post_number?: number;
  type?: string;
}

export interface MessageBusEvent {
  type: string;
  channel?: string;
  messageId?: number;
  data?: MessageBusData;
  statusCode?: number;
  stage?: string;
  message?: string;
}

export type MessageBusListener = (event: MessageBusEvent) => void;

export function parseMessageBusEvent(payload: string): MessageBusEvent | undefined {
  try {
    const event: MessageBusEvent = JSON.parse(payload) as MessageBusEvent;
    if (!event || typeof event.type !== 'string') {
      return undefined;
    }
    if (event.type === 'message') {
      if (typeof event.channel !== 'string' || typeof event.messageId !== 'number' ||
        !Number.isFinite(event.messageId)) {
        return undefined;
      }
    }
    return event;
  } catch (error) {
    return undefined;
  }
}

/**
 * /latest 频道上会计入「新的或更新的话题」的 message_type(白名单)。
 *
 * 这个频道跑的不止新话题 —— topic_tracking_state.rb 往 LATEST_MESSAGE_BUS_CHANNEL 发四种消息:
 *   · latest    (publish_latest) 话题被顶起来了     → 计入
 *   · new_topic (publish_new)    新建话题           → 计入
 *   · muted     (publish_muted)   有人静音了该话题   → 不计
 *   · unmuted   (publish_unmuted) 有人取消静音       → 不计
 * 官方前端 topic-tracking-state.js 的 notifyIncoming 同样只认前两种。
 *
 * 用白名单而不是「排除 muted/unmuted」的黑名单:将来 Discourse 往这个频道加新类型时,
 * 白名单默认不计、顶多漏报;黑名单会默默把它算成新话题,又变回现在这个 bug。
 */
const INCOMING_TOPIC_MESSAGE_TYPES: string[] = ['latest', 'new_topic'];

export function extractMessageBusTopicId(event: MessageBusEvent | undefined): number | undefined {
  if (!event || event.type !== 'message' || !event.data) {
    return undefined;
  }
  const messageType: string | undefined = event.data.message_type;
  if (messageType === undefined || INCOMING_TOPIC_MESSAGE_TYPES.indexOf(messageType) < 0) {
    return undefined;
  }
  const topicId: number | undefined = event.data.topic_id;
  if (topicId === undefined || !Number.isFinite(topicId) || topicId <= 0) {
    return undefined;
  }
  return Math.floor(topicId);
}

// 取该消息所属版块 id。拿不到(payload 缺席或字段非法)回 undefined,由调用方决定宽松还是从严。
export function extractMessageBusCategoryId(event: MessageBusEvent | undefined): number | undefined {
  if (!event || event.type !== 'message' || !event.data || !event.data.payload) {
    return undefined;
  }
  const categoryId: number | undefined = event.data.payload.category_id;
  if (categoryId === undefined || !Number.isFinite(categoryId) || categoryId <= 0) {
    return undefined;
  }
  return Math.floor(categoryId);
}

// 从 /topic/<id> 频道事件里取"新建帖子"的 post id：仅 type==='created' 且 data.id 为正整数时返回。
// 其它动作类型（revised/deleted/...）与无 type 的整帖刷新消息一律返回 undefined（P2 MVP 只做新楼）。
export function extractCreatedPostId(event: MessageBusEvent | undefined): number | undefined {
  if (!event || event.type !== 'message' || !event.data || event.data.type !== 'created') {
    return undefined;
  }
  const postId: number | undefined = event.data.id;
  if (postId === undefined || !Number.isFinite(postId) || postId <= 0) {
    return undefined;
  }
  return Math.floor(postId);
}

export class MessageBusEventBus {
  private static listeners: Map<number, MessageBusListener> = new Map();
  private static nextListenerId: number = 0;

  static subscribe(listener: MessageBusListener): () => void {
    const listenerId: number = MessageBusEventBus.nextListenerId;
    MessageBusEventBus.nextListenerId++;
    MessageBusEventBus.listeners.set(listenerId, listener);
    return () => {
      MessageBusEventBus.listeners.delete(listenerId);
    };
  }

  static publishPayload(payload: string): void {
    const event: MessageBusEvent | undefined = parseMessageBusEvent(payload);
    if (!event) {
      Log.i(`${LOG_TAG} ignored malformed bridge payload`);
      return;
    }
    if (event.type === 'challenge') {
      const statusCode: number = event.statusCode !== undefined && Number.isFinite(event.statusCode)
        ? event.statusCode : 0;
      ChallengeEventBus.notifyChallengeRequired('/message-bus', statusCode, ChallengeState.REQUIRED);
    }
    MessageBusEventBus.publish(event);
  }

  static publish(event: MessageBusEvent): void {
    const listeners: MessageBusListener[] = [];
    MessageBusEventBus.listeners.forEach((listener: MessageBusListener) => {
      listeners.push(listener);
    });
    Log.i(`${LOG_TAG} event type=${event.type} stage=${event.stage ?? ''} channel=${event.channel ?? ''} ` +
      `messageId=${event.messageId ?? 0} status=${event.statusCode ?? 0} message=${event.message ?? ''} ` +
      `listeners=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](event);
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }
}
