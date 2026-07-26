import { describe, it, expect } from '@ohos/hypium';
import {
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
        '{"type":"message","channel":"/latest","messageId":1001,"data":{"topic_id":375}}'
      );

      expect(event?.channel).assertEqual('/latest');
      expect(event?.messageId).assertEqual(1001);
      expect(extractMessageBusTopicId(event)).assertEqual(375);
    });

    it('rejectsMalformedPayloadsAndInvalidTopicIds', 0, () => {
      expect(parseMessageBusEvent('{bad json')).assertUndefined();
      expect(parseMessageBusEvent('{"type":"message","channel":3}')).assertUndefined();
      expect(extractMessageBusTopicId(parseMessageBusEvent(
        '{"type":"message","channel":"/latest","messageId":1,"data":{"topic_id":0}}'
      ))).assertUndefined();
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
