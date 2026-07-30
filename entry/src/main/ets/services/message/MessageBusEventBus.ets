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

export interface MessageBusData {
  topic_id?: number;
  message_type?: string;
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

export function extractMessageBusTopicId(event: MessageBusEvent | undefined): number | undefined {
  if (!event || event.type !== 'message' || !event.data) {
    return undefined;
  }
  const topicId: number | undefined = event.data.topic_id;
  if (topicId === undefined || !Number.isFinite(topicId) || topicId <= 0) {
    return undefined;
  }
  return Math.floor(topicId);
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
