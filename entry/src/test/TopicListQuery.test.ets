import { describe, it, expect } from '@ohos/hypium';
import { TopicCategory, TopicTag } from '../main/ets/models/Topic';
import { FeedKey } from '../main/ets/services/site/FeedPrefs';
import {
  buildTopicListPath,
  createDefaultTopicListQuery,
  describeTopicListQuery,
  filterRequiresLogin,
  isDefaultTopicListQuery,
  sameTopicListQuery,
  topicListPrimaryTitle,
  topicListSummary,
  hasTopicListSummary,
  topicListSummaryLead,
  topicListSummaryTag,
  TopicListQuery
} from '../main/ets/services/topic/TopicListQuery';

const DEV: TopicCategory = { id: 98, name: '开发调优', color: '', textColor: '', slug: 'domestic' };
// slug 缺失的版块(站点元数据里偶有):退回纯 id 段。
const NO_SLUG: TopicCategory = { id: 7, name: '无 slug', color: '', textColor: '' };

// 有 id + slug 的标签走 slug/id 路由;只有名字的走按名字的路由。
const TAG_WITH_ID: TopicTag = { id: 1461, name: '三方客户端', slug: '1461-tag' };
const TAG_NAME_ONLY: TopicTag = { name: 'linux' };

function queryOf(filter: string, category?: TopicCategory, tag?: TopicTag): TopicListQuery {
  return { filter: filter, category: category, tag: tag };
}

export default function topicListQueryTest() {
  describe('TopicListQuery', () => {

    // ===== 四种 scope × 过滤器 =====

    it('全站 scope 不带 /l/ 前缀', 0, () => {
      expect(buildTopicListPath(queryOf(FeedKey.LATEST), 0)).assertEqual('/latest.json');
      expect(buildTopicListPath(queryOf(FeedKey.HOT), 0)).assertEqual('/hot.json');
      expect(buildTopicListPath(queryOf(FeedKey.UNREAD), 0)).assertEqual('/unread.json');
      expect(buildTopicListPath(queryOf(FeedKey.NEW), 0)).assertEqual('/new.json');
      expect(buildTopicListPath(queryOf(FeedKey.TOP), 0)).assertEqual('/top.json');
    });

    it('版块 scope 拼 /c/{slug}/{id}/l/{filter}', 0, () => {
      expect(buildTopicListPath(queryOf(FeedKey.LATEST, DEV), 0))
        .assertEqual('/c/domestic/98/l/latest.json');
      // 改造前版块被写死成 latest,这条是本次要修的核心缺口。
      expect(buildTopicListPath(queryOf(FeedKey.UNREAD, DEV), 0))
        .assertEqual('/c/domestic/98/l/unread.json');
      expect(buildTopicListPath(queryOf(FeedKey.HOT, NO_SLUG), 0))
        .assertEqual('/c/7/l/hot.json');
    });

    it('标签 scope 优先用 slug/id,没有则按名字', 0, () => {
      expect(buildTopicListPath(queryOf(FeedKey.LATEST, undefined, TAG_WITH_ID), 0))
        .assertEqual('/tag/1461-tag/1461/l/latest.json');
      expect(buildTopicListPath(queryOf(FeedKey.NEW, undefined, TAG_WITH_ID), 0))
        .assertEqual('/tag/1461-tag/1461/l/new.json');
      expect(buildTopicListPath(queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY), 0))
        .assertEqual('/tag/linux/l/latest.json');
    });

    it('版块 + 标签走 /tags/c/...', 0, () => {
      expect(buildTopicListPath(queryOf(FeedKey.LATEST, DEV, TAG_WITH_ID), 0))
        .assertEqual('/tags/c/domestic/98/1461-tag/1461/l/latest.json');
      expect(buildTopicListPath(queryOf(FeedKey.UNREAD, DEV, TAG_WITH_ID), 0))
        .assertEqual('/tags/c/domestic/98/1461-tag/1461/l/unread.json');
    });

    it('非 ASCII 的标签名与版块 slug 会被 URL 编码', 0, () => {
      const path: string = buildTopicListPath(queryOf(FeedKey.LATEST, undefined, { name: '福利' }), 0);
      expect(path).assertEqual(`/tag/${encodeURIComponent('福利')}/l/latest.json`);
    });

    // ===== 分页 =====

    it('page>0 才带 page 参数', 0, () => {
      expect(buildTopicListPath(queryOf(FeedKey.LATEST), 2)).assertEqual('/latest.json?page=2');
      expect(buildTopicListPath(queryOf(FeedKey.LATEST, DEV), 1))
        .assertEqual('/c/domestic/98/l/latest.json?page=1');
      expect(buildTopicListPath(queryOf(FeedKey.LATEST, DEV, TAG_WITH_ID), 3))
        .assertEqual('/tags/c/domestic/98/1461-tag/1461/l/latest.json?page=3');
    });

    // ===== 条件比较 / 默认判定 =====

    it('默认条件是全站 · 最新 · 无标签', 0, () => {
      expect(isDefaultTopicListQuery(createDefaultTopicListQuery())).assertTrue();
      expect(isDefaultTopicListQuery(queryOf(FeedKey.UNREAD))).assertFalse();
      expect(isDefaultTopicListQuery(queryOf(FeedKey.LATEST, DEV))).assertFalse();
      expect(isDefaultTopicListQuery(queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY))).assertFalse();
    });

    it('sameTopicListQuery 三个维度都比', 0, () => {
      expect(sameTopicListQuery(queryOf(FeedKey.LATEST, DEV), queryOf(FeedKey.LATEST, DEV))).assertTrue();
      expect(sameTopicListQuery(queryOf(FeedKey.LATEST, DEV), queryOf(FeedKey.UNREAD, DEV))).assertFalse();
      expect(sameTopicListQuery(queryOf(FeedKey.LATEST, DEV), queryOf(FeedKey.LATEST))).assertFalse();
      expect(sameTopicListQuery(
        queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY),
        queryOf(FeedKey.LATEST, undefined, TAG_WITH_ID))).assertFalse();
      // 标签按名字比:同一个标签一边有 id 一边只有名字,不能算成两个。
      expect(sameTopicListQuery(
        queryOf(FeedKey.LATEST, undefined, TAG_WITH_ID),
        queryOf(FeedKey.LATEST, undefined, { name: '三方客户端' }))).assertTrue();
    });

    it('unread / new 需要登录,latest / hot / top 不需要', 0, () => {
      expect(filterRequiresLogin(FeedKey.UNREAD)).assertTrue();
      expect(filterRequiresLogin(FeedKey.NEW)).assertTrue();
      expect(filterRequiresLogin(FeedKey.LATEST)).assertFalse();
      expect(filterRequiresLogin(FeedKey.HOT)).assertFalse();
      expect(filterRequiresLogin(FeedKey.TOP)).assertFalse();
    });

    // ===== 顶栏文案 =====

    it('主标题按 版块 → 标签 → 过滤器 取,全默认时回空串', 0, () => {
      expect(topicListPrimaryTitle(createDefaultTopicListQuery())).assertEqual('');
      expect(topicListPrimaryTitle(queryOf(FeedKey.UNREAD))).assertEqual('未读');
      expect(topicListPrimaryTitle(queryOf(FeedKey.LATEST, DEV))).assertEqual('开发调优');
      // 顶栏会在名字前面画标签图标,所以标题本身不带 # 之类的前缀修饰。
      expect(topicListPrimaryTitle(queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY))).assertEqual('linux');
      // 版块优先于标签。
      expect(topicListPrimaryTitle(queryOf(FeedKey.LATEST, DEV, TAG_NAME_ONLY))).assertEqual('开发调优');
    });

    it('副行一旦出现就把排序名写全,包括默认的「最新」', 0, () => {
      expect(topicListSummaryLead(createDefaultTopicListQuery())).assertEqual('');
      // 只选了个版块/标签:副行不出现(标题独占一行),排序名也就无处可写。
      expect(topicListSummaryLead(queryOf(FeedKey.LATEST, DEV))).assertEqual('');
      expect(topicListSummaryLead(queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY))).assertEqual('');
      // 没有 scope 时排序名本身就是主标题,副行再写一遍就重复了。
      expect(topicListSummaryLead(queryOf(FeedKey.UNREAD))).assertEqual('');
      expect(topicListPrimaryTitle(queryOf(FeedKey.UNREAD))).assertEqual('未读');
      // 有 scope + 换过排序。
      expect(topicListSummaryLead(queryOf(FeedKey.UNREAD, DEV))).assertEqual('未读');
      expect(topicListSummaryLead(queryOf(FeedKey.HOT, undefined, TAG_NAME_ONLY))).assertEqual('热门');
      // 版块 + 标签:副行本来就要为标签开,「最新」顺手补全,免得这行太空。
      expect(topicListSummaryLead(queryOf(FeedKey.LATEST, DEV, TAG_NAME_ONLY))).assertEqual('最新');
      expect(topicListSummary(queryOf(FeedKey.LATEST, DEV, TAG_NAME_ONLY))).assertEqual('最新 · linux');
    });

    it('没东西可说时不长副行,主标题独占一行', 0, () => {
      expect(hasTopicListSummary(createDefaultTopicListQuery())).assertFalse();
      expect(hasTopicListSummary(queryOf(FeedKey.LATEST, DEV))).assertFalse();
      expect(hasTopicListSummary(queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY))).assertFalse();
      // 主标题已经是「未读」了,不该再长一行副行出来重复它。
      expect(hasTopicListSummary(queryOf(FeedKey.UNREAD))).assertFalse();
      expect(hasTopicListSummary(queryOf(FeedKey.UNREAD, DEV))).assertTrue();
      // 版块 + 标签:标签挤不进主标题,即便排序是默认的也得长副行。
      expect(hasTopicListSummary(queryOf(FeedKey.LATEST, DEV, TAG_NAME_ONLY))).assertTrue();
    });

    it('只有「版块 + 标签」都选了时,标签才挂到副行(否则它就是主标题)', 0, () => {
      expect(topicListSummaryTag(queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY))).assertUndefined();
      expect(topicListSummaryTag(queryOf(FeedKey.LATEST, DEV))).assertUndefined();
      const carried: TopicTag | undefined = topicListSummaryTag(queryOf(FeedKey.HOT, DEV, TAG_NAME_ONLY));
      expect(carried !== undefined).assertTrue();
      expect((carried as TopicTag).name).assertEqual('linux');
      expect(topicListSummary(queryOf(FeedKey.HOT, DEV, TAG_NAME_ONLY))).assertEqual('热门 · linux');
    });

    it('抽屉确认区的描述一项都不省,无 scope 时写明「全站」', 0, () => {
      expect(describeTopicListQuery(createDefaultTopicListQuery())).assertEqual('最新 · 全站');
      expect(describeTopicListQuery(queryOf(FeedKey.UNREAD))).assertEqual('未读 · 全站');
      expect(describeTopicListQuery(queryOf(FeedKey.UNREAD, DEV))).assertEqual('未读 · 开发调优');
      // 有标签时标签就是 scope,不再补「全站」。
      expect(describeTopicListQuery(queryOf(FeedKey.LATEST, undefined, TAG_NAME_ONLY)))
        .assertEqual('最新 · linux');
      expect(describeTopicListQuery(queryOf(FeedKey.LATEST, DEV, TAG_NAME_ONLY)))
        .assertEqual('最新 · 开发调优 · linux');
    });
  });
}
