import { describe, it, expect } from '@ohos/hypium';
import {
  extractMessageBusCategoryId,
  extractMessageBusCreatedAt,
  extractMessageBusTopicId,
  MessageBusEvent,
  MessageBusEventBus,
  parseMessageBusEvent
} from '../main/ets/services/message/MessageBusEventBus';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../main/ets/services/challenge/ChallengeEventBus';
import { ChallengeState } from '../main/ets/services/network/NetworkTypes';

export default function messageBusEventBusTest() {
  describe('messageBusEventBusTest', () => {
    it('parsesLatestTopicMessage', 0, () => {
      const event: MessageBusEvent | undefined = parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":1001,"data":{"topic_id":375,"message_type":"latest"}}'
      );

      expect(event?.channel).assertEqual('/latest');
      expect(event?.messageId).assertEqual(1001);
      expect(extractMessageBusTopicId(event)).assertEqual(375);
    });

    it('rejectsMalformedPayloadsAndInvalidTopicIds', 0, () => {
      expect(parseMessageBusEvent('{bad json')).assertUndefined();
      expect(parseMessageBusEvent('{"type":"message","channel":3}')).assertUndefined();
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":1,"data":{"topic_id":0,"message_type":"latest"}}'
      ))).assertUndefined();
    });

    // /latest 上还跑着静音/取消静音,它们不是「新的或更新的话题」,计进去就成了凭空冒出的提示。
    it('ignoresMutedAndUnmutedOnLatestChannel', 0, () => {
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":2,"data":{"topic_id":375,"message_type":"muted"}}'
      ))).assertUndefined();
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":3,"data":{"topic_id":375,"message_type":"unmuted"}}'
      ))).assertUndefined();
      // 白名单:没有 message_type、或将来新增的未知类型,一律不计。
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":4,"data":{"topic_id":375}}'
      ))).assertUndefined();
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":5,"data":{"topic_id":375,"message_type":"whatever"}}'
      ))).assertUndefined();
    });

    it('extractsCategoryIdFromPayload', 0, () => {
      expect(extractMessageBusCategoryId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":8,"data":{"topic_id":9,"message_type":"latest","payload":{"category_id":98}}}'
      ))).assertEqual(98);
      // payload 整个缺席(服务端未开标签/字段变动),或 category_id 非法 → undefined,由调用方从严处理。
      expect(extractMessageBusCategoryId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":9,"data":{"topic_id":9,"message_type":"latest"}}'
      ))).assertUndefined();
      expect(extractMessageBusCategoryId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":10,"data":{"topic_id":9,"message_type":"latest","payload":{"category_id":0}}}'
      ))).assertUndefined();
    });

    it('countsNewTopicAndBumpedTopic', 0, () => {
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":6,"data":{"topic_id":41,"message_type":"new_topic"}}'
      ))).assertEqual(41);
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":7,"data":{"topic_id":42,"message_type":"latest"}}'
      ))).assertEqual(42);
    });

    // 「最新发布」按 created_at 排,被回复顶起来的老帖不该进提示条。/new 频道上只认 new_topic:
    // 万一将来 Discourse 往这个频道也发 latest,白名单会直接把它挡掉。
    it('rejectsBumpedTopicOnNewChannel', 0, () => {
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/new","messageId":20,"data":{"topic_id":41,"message_type":"new_topic"}}'
      ))).assertEqual(41);
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/new","messageId":21,"data":{"topic_id":42,"message_type":"latest"}}'
      ))).assertUndefined();
      // 同一条 latest 消息在 /latest 上照旧计入 —— 白名单是按频道分的,不是全局收紧。
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":22,"data":{"topic_id":42,"message_type":"latest"}}'
      ))).assertEqual(42);
    });

    // created_at 只有 /new 的 payload 带(publish_new);/latest 只有 bumped_at,取不到回空串。
    it('extractsCreatedAtFromNewChannelPayload', 0, () => {
      expect(extractMessageBusCreatedAt(parseMessageBusEvent(
        '{"type":"message","channel":"/new","messageId":23,"data":{"topic_id":9,"message_type":"new_topic",' +
        '"payload":{"category_id":6,"created_at":"2026-08-03T13:53:40.102Z"}}}'
      ))).assertEqual('2026-08-03T13:53:40.102Z');
      expect(extractMessageBusCreatedAt(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":24,"data":{"topic_id":9,"message_type":"latest",' +
        '"payload":{"category_id":6,"bumped_at":"2026-08-03T15:00:32.598Z"}}}'
      ))).assertEqual('');
      expect(extractMessageBusCreatedAt(parseMessageBusEvent(
        '{"type":"message","channel":"/new","messageId":25,"data":{"topic_id":9,"message_type":"new_topic"}}'
      ))).assertEqual('');
    });

    it('publishesValidPayloadToSubscribersOnly', 0, () => {
      let receivedChannel: string = '';
      const unsubscribe: () => void = MessageBusEventBus.subscribe((event: MessageBusEvent) => {
        receivedChannel = event.channel === undefined ? '' : event.channel;
      });

      MessageBusEventBus.publishPayload('{bad json');
      expect(receivedChannel).assertEqual('');
      MessageBusEventBus.publishPayload(
        '{"type":"message","channel":"/latest","messageId":2,"data":{"topic_id":376}}'
      );
      unsubscribe();

      expect(receivedChannel).assertEqual('/latest');
    });

    it('forwardsChallengePayloadToRecoveryBus', 0, () => {
      let receivedSource: string = '';
      let receivedStatusCode: number = 0;
      let receivedState: ChallengeState = ChallengeState.NONE;
      const unsubscribe: () => void = ChallengeEventBus.subscribe((event: ChallengeRequiredEvent) => {
        receivedSource = event.source;
        receivedStatusCode = event.statusCode;
        receivedState = event.challengeState;
      });

      MessageBusEventBus.publishPayload(
        '{"type":"challenge","statusCode":403,"message":"message bus blocked"}'
      );
      unsubscribe();

      expect(receivedSource).assertEqual('/message-bus');
      expect(receivedStatusCode).assertEqual(403);
      expect(receivedState).assertEqual(ChallengeState.REQUIRED);
    });
  });
}
