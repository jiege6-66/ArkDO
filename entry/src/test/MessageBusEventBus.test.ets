import { describe, it, expect } from '@ohos/hypium';
import {
  extractMessageBusCategoryId,
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
