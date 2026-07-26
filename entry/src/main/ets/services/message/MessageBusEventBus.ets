import { Log } from '../logging/Log';
import { ChallengeEventBus } from '../challenge/ChallengeEventBus';
import { ChallengeState } from '../network/NetworkTypes';

const LOG_TAG: string = '[ArkDO][MessageBus]';

export interface MessageBusData {
  topic_id?: number;
  message_type?: string;
  // /notification/<id> 频道 payload 的未读数（user.rb publish_notifications_state:921-931，已核源码）。
  // 铃铛角标用 all_unread_notifications_count（总未读，含私信）；unread_notifications 只含
  // high_priority=FALSE，漏私信，不能用于角标。unread_high_priority_notifications 为高优先级子集。
  all_unread_notifications_count?: number;
  unread_notifications?: number;
  unread_high_priority_notifications?: number;
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
