import { describe, it, expect } from '@ohos/hypium';
import { TopicTag } from '../main/ets/models/Topic';
import {
  hasAdvancedPromotionTag,
  hasLotteryTag,
  LotteryNoticeContext,
  shouldShowLotteryNotice
} from '../main/ets/services/topic/LotteryTopicRule';

// 便捷构造:大多数用例只关心标签,其余条件取「普通读者进一个开放帖」这个默认场景。
function contextOf(tags: TopicTag[]): LotteryNoticeContext {
  return {
    tags: tags,
    closed: false,
    archived: false,
    createdById: 100,
    currentUserId: 200
  };
}

export default function lotteryTopicRuleTest() {
  describe('lotteryTopicRuleTest', () => {
    it('showsNoticeForLotteryTaggedTopic', 0, () => {
      expect(shouldShowLotteryNotice(contextOf([{ name: '抽奖' }]))).assertTrue();
    });

    it('matchesLotteryTagByContainmentSoVariantsCount', 0, () => {
      expect(hasLotteryTag([{ name: '抽奖活动' }])).assertTrue();
      expect(hasLotteryTag([{ name: ' 抽奖 ' }])).assertTrue();
      expect(hasLotteryTag([{ name: '福利' }])).assertFalse();
      expect(hasLotteryTag([])).assertFalse();
    });

    it('skipsNoticeWithoutLotteryTag', 0, () => {
      expect(shouldShowLotteryNotice(contextOf([{ name: '公告' }]))).assertFalse();
    });

    // 高级推广帖不受抽奖回复规则约束:排除判定优先于命中判定。
    it('skipsNoticeWhenAdvancedPromotionTagWinsOverLotteryTag', 0, () => {
      const tags: TopicTag[] = [{ name: '抽奖' }, { id: 1514, name: '高级推广', slug: '1514-tag' }];

      expect(shouldShowLotteryNotice(contextOf(tags))).assertFalse();
    });

    // 列表/书签等接口只回字符串标签,经 mapTag 后没有 id;此时要靠 name 兜底认出高级推广。
    it('matchesAdvancedPromotionTagByIdOrName', 0, () => {
      expect(hasAdvancedPromotionTag([{ id: 1514, name: '' }])).assertTrue();
      expect(hasAdvancedPromotionTag([{ name: '高级推广' }])).assertTrue();
      expect(hasAdvancedPromotionTag([{ id: 31, name: '公告' }])).assertFalse();
    });

    // 已开奖/已归档 ⇒ 回不了帖,提醒纯属噪音。
    it('skipsNoticeWhenTopicClosedOrArchived', 0, () => {
      const closed: LotteryNoticeContext = contextOf([{ name: '抽奖' }]);
      closed.closed = true;
      const archived: LotteryNoticeContext = contextOf([{ name: '抽奖' }]);
      archived.archived = true;

      expect(shouldShowLotteryNotice(closed)).assertFalse();
      expect(shouldShowLotteryNotice(archived)).assertFalse();
    });

    it('skipsNoticeForTopicOwner', 0, () => {
      const own: LotteryNoticeContext = contextOf([{ name: '抽奖' }]);
      own.currentUserId = own.createdById;

      expect(shouldShowLotteryNotice(own)).assertFalse();
    });

    // 未登录(0)撞上未知楼主(0)不能被当成「这是我自己的帖子」。
    it('showsNoticeForAnonymousReaderWhenOwnerUnknown', 0, () => {
      const anonymous: LotteryNoticeContext = contextOf([{ name: '抽奖' }]);
      anonymous.createdById = 0;
      anonymous.currentUserId = 0;

      expect(shouldShowLotteryNotice(anonymous)).assertTrue();
    });
  });
}
