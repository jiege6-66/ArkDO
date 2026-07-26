import { describe, it, expect } from '@ohos/hypium';
import {
  addIncomingTopicId,
  addIncomingTopicMessage,
  clearHomeIncomingTopics,
  createHomeIncomingTopicsState,
  HomeIncomingTopicsState,
  homeIncomingTopicsCount,
  nextDebugIncomingTopicId,
  removeIncomingTopicsSnapshot,
  snapshotHomeIncomingTopics
} from '../main/ets/services/home/HomeIncomingTopicsController';

export default function homeIncomingTopicsControllerTest() {
  describe('homeIncomingTopicsControllerTest', () => {
    it('startsEmpty', 0, () => {
      const state: HomeIncomingTopicsState = createHomeIncomingTopicsState();

      expect(homeIncomingTopicsCount(state)).assertEqual(0);
      expect(state.topicIds.length).assertEqual(0);
    });

    it('addsUniqueTopicIdsOnly', 0, () => {
      let state: HomeIncomingTopicsState = createHomeIncomingTopicsState();

      state = addIncomingTopicId(state, 100001);
      state = addIncomingTopicId(state, 100001);
      state = addIncomingTopicId(state, 100002);

      expect(homeIncomingTopicsCount(state)).assertEqual(2);
      expect(state.topicIds[0]).assertEqual(100001);
      expect(state.topicIds[1]).assertEqual(100002);
    });

    it('ignoresInvalidTopicIds', 0, () => {
      let state: HomeIncomingTopicsState = createHomeIncomingTopicsState();

      state = addIncomingTopicId(state, 0);
      state = addIncomingTopicId(state, -1);

      expect(homeIncomingTopicsCount(state)).assertEqual(0);
    });

    it('clearsIncomingTopics', 0, () => {
      let state: HomeIncomingTopicsState = createHomeIncomingTopicsState();
      state = addIncomingTopicId(state, 100001);

      state = clearHomeIncomingTopics(state);

      expect(homeIncomingTopicsCount(state)).assertEqual(0);
    });

    it('generatesDeterministicDebugTopicIds', 0, () => {
      let state: HomeIncomingTopicsState = createHomeIncomingTopicsState();

      expect(nextDebugIncomingTopicId(state)).assertEqual(100001);
      state = addIncomingTopicId(state, nextDebugIncomingTopicId(state));
      expect(nextDebugIncomingTopicId(state)).assertEqual(100002);
    });

    it('removesOnlyTopicsCoveredBySuccessfulRefresh', 0, () => {
      let state: HomeIncomingTopicsState = createHomeIncomingTopicsState();
      state = addIncomingTopicMessage(state, 100001, 11);
      state = addIncomingTopicMessage(state, 100002, 12);
      const snapshot: HomeIncomingTopicsState = snapshotHomeIncomingTopics(state);
      state = addIncomingTopicMessage(state, 100003, 13);

      state = removeIncomingTopicsSnapshot(state, snapshot);

      expect(homeIncomingTopicsCount(state)).assertEqual(1);
      expect(state.topicIds[0]).assertEqual(100003);
    });

    it('keepsTopicUpdatedAgainWhileRefreshWasRunning', 0, () => {
      let state: HomeIncomingTopicsState = createHomeIncomingTopicsState();
      state = addIncomingTopicMessage(state, 42, 1001);
      const snapshot: HomeIncomingTopicsState = snapshotHomeIncomingTopics(state);

      state = addIncomingTopicMessage(state, 42, 1002);
      state = removeIncomingTopicsSnapshot(state, snapshot);

      expect(homeIncomingTopicsCount(state)).assertEqual(1);
      expect(state.topicIds[0]).assertEqual(42);
      expect(state.messageIds[0]).assertEqual(1002);
    });

  });
}
