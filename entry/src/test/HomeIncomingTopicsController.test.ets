import { describe, it, expect } from '@ohos/hypium';
import {
  addIncomingTopicId,
  addIncomingTopicMessage,
  clearHomeIncomingTopics,
  createHomeIncomingTopicsState,
  HomeIncomingTopicsState,
  homeIncomingTopicsCount,
  incomingTopicMatchesCategory,
  nextDebugIncomingTopicId,
  removeIncomingTopicsSnapshot,
  snapshotHomeIncomingTopics
} from '../main/ets/services/home/HomeIncomingTopicsController';
import { TopicCategory } from '../main/ets/models/Topic';

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

    // ===== 版块闸 =====

    it('incomingTopicMatchesCategory', 0, () => {
      const parent: TopicCategory = { id: 10, name: '父版块', color: '', textColor: '' };
      const child: TopicCategory = { id: 11, name: '子版块', color: '', textColor: '', parentCategoryId: 10 };
      const other: TopicCategory = { id: 20, name: '别处', color: '', textColor: '' };
      const all: TopicCategory[] = [parent, child, other];

      // 没限定版块:全站列表照单全收,连认不出版块的消息也收。
      expect(incomingTopicMatchesCategory(all, undefined, 20)).assertTrue();
      expect(incomingTopicMatchesCategory(all, undefined, undefined)).assertTrue();

      // 同一版块。
      expect(incomingTopicMatchesCategory(all, parent, 10)).assertTrue();
      // 看父版块时,子版块的新帖同样会出现在列表里,要收(对齐官方 notifyIncoming)。
      expect(incomingTopicMatchesCategory(all, parent, 11)).assertTrue();
      // 反过来不成立:看子版块时,父版块的帖子不属于这个列表。
      expect(incomingTopicMatchesCategory(all, child, 10)).assertFalse();
      // 无关版块。
      expect(incomingTopicMatchesCategory(all, parent, 20)).assertFalse();
      // 限定了版块却认不出消息来路:宁可漏报,也别把外版块的帖子插进来。
      expect(incomingTopicMatchesCategory(all, parent, undefined)).assertFalse();
    });

  });
}
