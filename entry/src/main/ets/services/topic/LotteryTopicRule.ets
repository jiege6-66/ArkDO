import { TopicTag } from '../../models/Topic';

// 抽奖帖提醒的判定与文案。抽成纯函数模块(不碰 UI、不碰存储)是为了能单测:
// 「什么算抽奖帖」这条判定牵着三个标签条件与两个状态条件,靠手点页面回归成本太高。
//
// 规则出处:官方公告帖「进一步优化对抽奖帖回复被举报的处理方式」(topic 1993635)——
// 抽奖帖里凑字数/复读/与奖品无关的回复被举报后,一律删除回复 + 记录举报次数 + 永久禁言。

// 公告帖 id。卡片底部「查看官方公告」按站内链接直开原生详情(LinkRouter 认这个形状的 URL)。
// 将来官方换公告,改这一个数字即可。
export const LOTTERY_RULES_TOPIC_ID: number = 1993635;
export const LOTTERY_RULES_TOPIC_URL: string = `https://linux.do/t/topic/${LOTTERY_RULES_TOPIC_ID}`;

// 「高级推广」标签(slug 1514-tag)。高级推广帖里的抽奖不受该规则约束,命中即不提示 ——
// 排除判定优先于命中判定,两个标签同时挂着时高级推广赢。
const PROMOTION_TAG_ID: number = 1514;
const PROMOTION_TAG_NAME: string = '高级推广';
// 抽奖标签按「包含」匹配而非全等,顺带覆盖「抽奖活动」这类变体。
const LOTTERY_TAG_KEYWORD: string = '抽奖';

// 回复框占位文字:顶层回复(参与抽奖的那条)才替换,定向回复某楼仍显示「回复<昵称>」。
export const LOTTERY_REPLY_PLACEHOLDER: string = '说说你为什么需要这个奖品…';
// 回复浮层顶上的一行提醒。只提示不拦截 —— 拦截会误伤正常回复,而这行字抬眼就能看见。
export const LOTTERY_REPLY_HINT: string = '抽奖帖：凑字数、复读、与奖品无关的回复被举报会被永久禁言';

// 提醒卡的展示前提。closed/archived 与楼主判定都要传:前者代表「已开奖/不能再回复」,
// 后者代表「这是我自己办的抽奖」,两种情况下提醒都只是噪音。
export interface LotteryNoticeContext {
  tags: TopicTag[];
  closed: boolean;
  archived: boolean;
  // 楼主 user id;未知传 0。
  createdById: number;
  // 当前登录用户 id;未登录传 0。
  currentUserId: number;
}

function normalizeTagName(name: string): string {
  return typeof name === 'string' ? name.trim() : '';
}

/** 标签里是否有「抽奖」(按包含匹配)。 */
export function hasLotteryTag(tags: TopicTag[]): boolean {
  if (!Array.isArray(tags)) {
    return false;
  }
  for (let index: number = 0; index < tags.length; index++) {
    const name: string = normalizeTagName(tags[index].name);
    if (name.indexOf(LOTTERY_TAG_KEYWORD) >= 0) {
      return true;
    }
  }
  return false;
}

/**
 * 标签里是否有「高级推广」。
 *
 * id 优先、name 兜底:帖子详情接口下发的标签是对象(带 id),但列表/书签等接口只给字符串,
 * 经 TopicService.mapTag 后就只剩 name。两条都判,判定在任何数据形态下都成立。
 */
export function hasAdvancedPromotionTag(tags: TopicTag[]): boolean {
  if (!Array.isArray(tags)) {
    return false;
  }
  for (let index: number = 0; index < tags.length; index++) {
    const tag: TopicTag = tags[index];
    if (tag.id === PROMOTION_TAG_ID || normalizeTagName(tag.name) === PROMOTION_TAG_NAME) {
      return true;
    }
  }
  return false;
}

/** 是否该在本帖顶部显示抽奖提醒卡。开关(LotteryTipPrefs)由调用方另判,这里只管帖子本身。 */
export function shouldShowLotteryNotice(context: LotteryNoticeContext): boolean {
  // 排除优先:高级推广帖不适用该规则。
  if (hasAdvancedPromotionTag(context.tags)) {
    return false;
  }
  if (!hasLotteryTag(context.tags)) {
    return false;
  }
  // 已开奖/已归档 ⇒ 回不了帖,也就没有被举报的风险。
  if (context.closed || context.archived) {
    return false;
  }
  // 自己办的抽奖不用被教育。两个 id 都得是有效值才判,免得未登录(0)撞上未知楼主(0)。
  if (context.createdById > 0 && context.currentUserId > 0 && context.createdById === context.currentUserId) {
    return false;
  }
  return true;
}
