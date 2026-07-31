import { TopicCategory, TopicTag } from '../../models/Topic';
import { FeedDef, FeedKey, FeedPrefs } from '../site/FeedPrefs';

/**
 * 首页列表的查询条件。
 *
 * Discourse 把「看什么」拆成两个正交的维度,别把它们当成互斥的单选:
 *  · filter(latest/hot/top/unread/new)= 排序与范围,落在 URL 尾部的 `/l/{filter}`
 *  · scope(版块 + 标签)= 取值范围,落在 URL 的前缀
 *
 * 路径 = scope 前缀 + `/l/{filter}.json`。四种 scope 组合:
 *  · 全站      → `/{filter}.json`                                  ← 唯一没有 /l/ 的
 *  · 版块      → `/c/{cSlug}/{cId}/l/{filter}.json`
 *  · 标签      → `/tag/{tSlug}/{tId}/l/{filter}.json`
 *  · 版块+标签 → `/tags/c/{cSlug}/{cId}/{tSlug}/{tId}/l/{filter}.json`
 *
 * 标签只能有一个:linux.do 的标签过滤不支持多选。Discourse core 另有 `/tags/intersection/a/b`
 * 走多标签,但那条路由既没有 `/l/{filter}` 变体、语义又被强制成「同时包含」,这里不用。
 */
export interface TopicListQuery {
  filter: string;
  // undefined = 不限版块(全站)。
  category?: TopicCategory;
  // undefined = 不限标签。
  tag?: TopicTag;
}

/** 全默认:全站 · 最新 · 不限标签。 */
export function createDefaultTopicListQuery(): TopicListQuery {
  return { filter: FeedKey.LATEST, category: undefined, tag: undefined };
}

/** 拷一份可独立编辑的草稿。 */
export function cloneTopicListQuery(query: TopicListQuery): TopicListQuery {
  return { filter: query.filter, category: query.category, tag: query.tag };
}

export function isDefaultTopicListQuery(query: TopicListQuery): boolean {
  return query.filter === FeedKey.LATEST && query.category === undefined && query.tag === undefined;
}

/** 两份条件是否等价。抽屉「确认」按钮据此判断有没有真的改动,避免打一次无意义的请求。 */
export function sameTopicListQuery(a: TopicListQuery, b: TopicListQuery): boolean {
  if (a.filter !== b.filter) {
    return false;
  }
  const aCategoryId: number = a.category !== undefined ? a.category.id : 0;
  const bCategoryId: number = b.category !== undefined ? b.category.id : 0;
  if (aCategoryId !== bCategoryId) {
    return false;
  }
  // 标签按名字比:列表接口回的标签常常只有名字,拿 id 比会把同一个标签认成两个。
  const aTagName: string = a.tag !== undefined ? a.tag.name : '';
  const bTagName: string = b.tag !== undefined ? b.tag.name : '';
  return aTagName === bTagName;
}

/**
 * 该过滤器是否需要登录。Discourse.filters 里除 latest/top/hot 外都要会话;
 * 本项目暴露的 5 个入口里,unread 与 new 属于此列。
 */
export function filterRequiresLogin(filter: string): boolean {
  return filter === FeedKey.UNREAD || filter === FeedKey.NEW;
}

// `category_slug_path_with_id` 是 glob 段:末段是数字 id 时服务端直接按 id 认,
// 所以子版块也只需要 `{slug}/{id}` 两段,不必拼出完整的父子路径。拿不到 slug 时退回纯 id。
function categorySegment(category: TopicCategory): string {
  const slug: string = category.slug !== undefined ? category.slug : '';
  return slug.length > 0 ? `${encodeURIComponent(slug)}/${category.id}` : `${category.id}`;
}

// slug + id 是 linux.do 前端自己在用的形式,对中文标签名最稳(此时 slug 退化成 `{id}-tag`);
// 列表接口常常只回标签名,拿不到 id/slug 时退回按名字的路由(/tag/:tag_name),官方同样支持。
function tagSegment(tag: TopicTag): string {
  const slug: string = tag.slug !== undefined ? tag.slug : '';
  const id: number = tag.id !== undefined ? tag.id : 0;
  if (id > 0 && slug.length > 0) {
    return `${encodeURIComponent(slug)}/${id}`;
  }
  return encodeURIComponent(tag.name);
}

/**
 * 按条件拼出主题列表的请求路径。page 从 0 起(0 即首页,不带 page 参数)。
 *
 * 注意 id 形式的标签路由带 `format: :json` 约束,`.json` 后缀不能省。
 */
export function buildTopicListPath(query: TopicListQuery, page: number): string {
  const suffix: string = page > 0 ? `?page=${page}` : '';
  const tag: TopicTag | undefined = query.tag;
  const category: TopicCategory | undefined = query.category;

  if (tag !== undefined && category !== undefined) {
    return `/tags/c/${categorySegment(category)}/${tagSegment(tag)}/l/${query.filter}.json${suffix}`;
  }
  if (tag !== undefined) {
    return `/tag/${tagSegment(tag)}/l/${query.filter}.json${suffix}`;
  }
  if (category !== undefined) {
    return `/c/${categorySegment(category)}/l/${query.filter}.json${suffix}`;
  }
  // 全站是唯一不带 /l/ 前缀的 scope:/latest.json、/hot.json、/unread.json…
  return `/${query.filter}.json${suffix}`;
}

function filterLabel(filter: string): string {
  const def: FeedDef | undefined = FeedPrefs.feedDef(filter);
  return def !== undefined ? def.label : '';
}

/**
 * 顶栏主标题:取最有辨识度的那一项(版块 → 标签 → 过滤器)。全默认时回空串,由调用方换成应用名。
 * 不带 `#`/图标之类的修饰——顶栏会在前面画对应的分类/标签图标,前缀符号就多余了。
 */
export function topicListPrimaryTitle(query: TopicListQuery): string {
  if (query.category !== undefined) {
    return query.category.name;
  }
  if (query.tag !== undefined) {
    return query.tag.name;
  }
  return query.filter === FeedKey.LATEST ? '' : filterLabel(query.filter);
}

/**
 * 顶栏副行的前半段:当前排序名。副行一旦要出现就总是写出来,包括默认的「最新」——
 * 副行此时本来就要为标签开,顺手把排序补全反而让这一行不至于太空。
 * 副行不出现时回空串。
 */
export function topicListSummaryLead(query: TopicListQuery): string {
  return hasTopicListSummary(query) ? filterLabel(query.filter) : '';
}

/**
 * 副行里要不要再挂一个标签。只有「版块 + 标签」都选了时才需要:
 * 此时主标题被版块占着,标签没别的地方可显示。
 */
export function topicListSummaryTag(query: TopicListQuery): TopicTag | undefined {
  return query.category !== undefined ? query.tag : undefined;
}

/**
 * 顶栏要不要在主标题下面长出一行副行。两种情况才需要:
 *  · 换过排序(非「最新」)—— 但没有 scope 时不算,那时排序名本身就是主标题,副行再写一遍是重复
 *  · 版块和标签都选了 —— 主标题被版块占着,标签没别处可去
 * 其余情况(只选版块、只选标签、只换排序)主标题独占一行,顶栏保持干净。
 */
export function hasTopicListSummary(query: TopicListQuery): boolean {
  const hasScope: boolean = query.category !== undefined || query.tag !== undefined;
  if (!hasScope) {
    return false;
  }
  return query.filter !== FeedKey.LATEST || topicListSummaryTag(query) !== undefined;
}

/** 副行的纯文本形态(不带图标的场合用)。 */
export function topicListSummary(query: TopicListQuery): string {
  const parts: string[] = [];
  const lead: string = topicListSummaryLead(query);
  if (lead.length > 0) {
    parts.push(lead);
  }
  const tag: TopicTag | undefined = topicListSummaryTag(query);
  if (tag !== undefined) {
    parts.push(tag.name);
  }
  return parts.join(' · ');
}

/**
 * 抽屉确认区用的完整描述:与顶栏副行不同,这里不省略任何一项(用户正盯着它决定要不要点「查看结果」),
 * 且没有 scope 时显式写出「全站」,免得只剩一个「最新」孤零零地挂在那里。
 */
export function describeTopicListQuery(query: TopicListQuery): string {
  const parts: string[] = [];
  parts.push(filterLabel(query.filter));
  if (query.category !== undefined) {
    parts.push(query.category.name);
  } else if (query.tag === undefined) {
    parts.push('全站');
  }
  if (query.tag !== undefined) {
    parts.push(query.tag.name);
  }
  return parts.join(' · ');
}
