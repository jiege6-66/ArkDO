import { TopicCategory } from '../../models/Topic';

/**
 * 高级搜索筛选条件:UI 上选出来的条件 → /search.json 的 q 串。
 *
 * 语法不是凭印象拼的,逐条对齐 Discourse 官方实现:
 * - 服务端 core lib/search.rb 的 advanced_filter 正则(决定哪些 token 会被识别、值怎么解析);
 * - 前端 frontend/discourse/app/components/search-advanced-options.gjs 的拼串规则
 *   (决定同一个条件官方是拼 `#slug` 还是 `category:id`、多标签用 `,` 还是 `+`)。
 *
 * 关键点(容易拼错的):
 * - 分类:官方优先拼 slug 简写 `#slug`,子分类是 `#父slug:子slug`,没有 slug 才退回 `category:id`。
 *   `category:` 的值服务端按 slug/name/纯数字 id 三种方式匹配,所以 id 兜底是有效的。
 *   不带 `=` 前缀时服务端会连带子分类一起搜(`#=slug` 才是精确只搜本分类)。
 * - 标签:`tags:a,b` 是「任一」,`tags:a+b` 是「全部」——分隔符本身就是语义,不能随便换。
 * - 位置:大部分是 `in:xxx`,只有图片是 `with:images`(官方 IN_OPTIONS_MAPPING 里的特例)。
 * - 时间:`before:` / `after:` 的值服务端 Search.word_to_date 支持 `YYYY-MM-DD` 与「N 天前」的纯数字,
 *   这里统一折算成绝对日期再拼,避免相对值随缓存漂移。
 * - 帖数/浏览量:`min_posts:` `max_posts:` `min_views:` `max_views:`(注意是 posts 不是 post)。
 * - 排序:`order:` 只有 latest / oldest / latest_topic / oldest_topic / views / likes / read 有实现分支,
 *   不在表里的值服务端会当成未知 order 直接忽略,所以别自造。
 * - 相关性是「不拼 order」,不是 `order:relevance`。
 *
 * 注:服务端其实允许「不输关键词、只带筛选条件」的搜索
 * (search.rb 判无效是 `@term.blank? && @filters.blank? && @order.blank?` 三者全空),
 * 但本 App 产品上要求必须先有关键词,筛选条件只用来收窄结果 —— 见 SearchOverlay.canSearch()。
 */

/** 下拉/多选里的一个选项。 */
export interface SearchFilterOption {
  value: string;
  label: string;
}

export const SEARCH_TIME_BEFORE: string = 'before';
export const SEARCH_TIME_AFTER: string = 'after';

/** 需要登录态才有意义的「我的」相关位置筛选(对齐官方 inOptionsForUsers)。 */
export const SEARCH_IN_USER_OPTIONS: SearchFilterOption[] = [
  { value: 'created', label: '我创建的' },
  { value: 'posted', label: '我发言过的' },
  { value: 'likes', label: '我点赞的' },
  { value: 'bookmarks', label: '我收藏的' },
  { value: 'seen', label: '我读过的' },
  { value: 'unseen', label: '我没读过的' },
  { value: 'watching', label: '我关注的' },
  { value: 'tracking', label: '我跟踪的' }
];

/** 与登录无关的帖子属性 / 搜索范围(对齐官方 inOptionsForAll)。 */
export const SEARCH_IN_POST_OPTIONS: SearchFilterOption[] = [
  { value: 'title', label: '仅搜标题' },
  { value: 'first', label: '仅搜主楼' },
  { value: 'pinned', label: '置顶话题' },
  { value: 'wiki', label: 'Wiki 帖' },
  { value: 'images', label: '含图片' }
];

/**
 * 话题状态。前 6 项是 core 的 status: 过滤器;
 * solved / unsolved 由 discourse-solved 插件用 register_search_advanced_filter 注册,
 * linux.do 装了该插件(帖子有「已解决」标记),故一并给出。
 */
export const SEARCH_STATUS_OPTIONS: SearchFilterOption[] = [
  { value: 'open', label: '开放中' },
  { value: 'closed', label: '已关闭' },
  { value: 'archived', label: '已归档' },
  { value: 'public', label: '公开' },
  { value: 'noreplies', label: '无回复' },
  { value: 'single_user', label: '仅一人参与' },
  { value: 'solved', label: '已解决' },
  { value: 'unsolved', label: '未解决' }
];

/**
 * 排序,取官方整页搜索「排序依据」下拉里的那六项(名字也照抄官方中文):
 * 相关性 / 最新帖子 / 最新话题 / 赞最多 / 浏览最多 / 最近阅读。
 * 空值 = 相关性,是默认项,且**不拼 order token**(拼 order:relevance 会被服务端当未知排序忽略)。
 * order:read 只对登录用户生效(search.rb 里是 `@order == :read && @guardian.user`)。
 * 服务端另有 oldest / oldest_topic 分支,但官方下拉没给,这里也不自作主张加。
 */
export const SEARCH_ORDER_OPTIONS: SearchFilterOption[] = [
  { value: '', label: '相关性' },
  { value: 'latest', label: '最新帖子' },
  { value: 'latest_topic', label: '最新话题' },
  { value: 'likes', label: '赞最多' },
  { value: 'views', label: '浏览最多' },
  { value: 'read', label: '最近阅读' }
];

/** 发布时间的快捷区间(天数),选中即折算成绝对日期拼 after:。 */
export const SEARCH_TIME_PRESETS: SearchFilterOption[] = [
  { value: '7', label: '最近 7 天' },
  { value: '30', label: '最近 30 天' },
  { value: '90', label: '最近 90 天' },
  { value: '365', label: '最近一年' }
];

/** 官方 IN_OPTIONS_MAPPING:只有 images 走 with:,其余都是 in:。 */
function inKeywordFor(value: string): string {
  return value === 'images' ? 'with' : 'in';
}

/** 只留数字:min_posts 等服务端正则是 (\d+),混进别的字符整个 token 会被当成普通搜索词。 */
export function digitsOnly(raw: string): string {
  let out: string = '';
  for (let index: number = 0; index < raw.length; index++) {
    const ch: string = raw.charAt(index);
    if (ch >= '0' && ch <= '9') {
      out += ch;
    }
  }
  return out;
}

/** Date → YYYY-MM-DD(服务端 word_to_date 认这个格式)。 */
export function formatSearchDate(date: Date): string {
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  const mm: string = month < 10 ? `0${month}` : `${month}`;
  const dd: string = day < 10 ? `0${day}` : `${day}`;
  return `${date.getFullYear()}-${mm}-${dd}`;
}

/** 「最近 N 天」→ 绝对日期(拼 after: 用)。 */
export function daysAgoToSearchDate(days: number): string {
  const date: Date = new Date();
  date.setDate(date.getDate() - days);
  return formatSearchDate(date);
}

export class SearchFilters {
  // 分类:id 用于兜底 category:id,slug/parentSlug 用于官方优先的 #slug 简写,name 只用于展示。
  categoryId: number = -1;
  categorySlug: string = '';
  categoryParentSlug: string = '';
  categoryName: string = '';
  // 标签名(非 id):tags: 过滤器按名字匹配。
  tags: string[] = [];
  // true → tags:a+b(同时含全部标签);false → tags:a,b(含任一)。
  tagsMatchAll: boolean = false;
  // 发帖人用户名,拼成 @username。
  username: string = '';
  // in:/with: 多选,值取自 SEARCH_IN_USER_OPTIONS / SEARCH_IN_POST_OPTIONS。
  inFilters: string[] = [];
  status: string = '';
  timeWhen: string = SEARCH_TIME_AFTER;
  timeDate: string = '';
  minPosts: string = '';
  maxPosts: string = '';
  minViews: string = '';
  maxViews: string = '';
  order: string = '';

  /**
   * 按字段拷贝。写成静态方法是有意的:@Prop 传进子组件的实例是 ArkUI 深拷贝出来的,
   * 不能指望它还带着原型方法,所以拷贝源只读字段、不调用源对象上的方法。
   */
  static copyOf(src: SearchFilters): SearchFilters {
    const next: SearchFilters = new SearchFilters();
    next.categoryId = src.categoryId;
    next.categorySlug = src.categorySlug;
    next.categoryParentSlug = src.categoryParentSlug;
    next.categoryName = src.categoryName;
    next.tags = src.tags.slice();
    next.tagsMatchAll = src.tagsMatchAll;
    next.username = src.username;
    next.inFilters = src.inFilters.slice();
    next.status = src.status;
    next.timeWhen = src.timeWhen;
    next.timeDate = src.timeDate;
    next.minPosts = src.minPosts;
    next.maxPosts = src.maxPosts;
    next.minViews = src.minViews;
    next.maxViews = src.maxViews;
    next.order = src.order;
    return next;
  }

  /** 深拷贝:筛选状态整体作为 @State 值语义更新,改字段一律先 clone 再赋回,保证能触发刷新。 */
  clone(): SearchFilters {
    const next: SearchFilters = new SearchFilters();
    next.categoryId = this.categoryId;
    next.categorySlug = this.categorySlug;
    next.categoryParentSlug = this.categoryParentSlug;
    next.categoryName = this.categoryName;
    next.tags = this.tags.slice();
    next.tagsMatchAll = this.tagsMatchAll;
    next.username = this.username;
    next.inFilters = this.inFilters.slice();
    next.status = this.status;
    next.timeWhen = this.timeWhen;
    next.timeDate = this.timeDate;
    next.minPosts = this.minPosts;
    next.maxPosts = this.maxPosts;
    next.minViews = this.minViews;
    next.maxViews = this.maxViews;
    next.order = this.order;
    return next;
  }

  /** 是否有任何条件生效(决定「不输关键词也能搜」以及筛选按钮是否高亮)。 */
  hasAny(): boolean {
    return this.activeCount() > 0;
  }

  /** 生效条件条数,用于筛选按钮上的角标。 */
  activeCount(): number {
    let count: number = 0;
    if (this.categoryId >= 0) {
      count++;
    }
    if (this.tags.length > 0) {
      count++;
    }
    if (this.username.length > 0) {
      count++;
    }
    count += this.inFilters.length;
    if (this.status.length > 0) {
      count++;
    }
    if (this.timeDate.length > 0) {
      count++;
    }
    if (this.minPosts.length > 0) {
      count++;
    }
    if (this.maxPosts.length > 0) {
      count++;
    }
    if (this.minViews.length > 0) {
      count++;
    }
    if (this.maxViews.length > 0) {
      count++;
    }
    if (this.order.length > 0) {
      count++;
    }
    return count;
  }

  /** 分类的 q 片段:优先 #slug / #父:子,无 slug 退回 category:id(对齐官方)。 */
  private categoryToken(): string {
    if (this.categoryId < 0) {
      return '';
    }
    if (this.categorySlug.length === 0) {
      return `category:${this.categoryId}`;
    }
    if (this.categoryParentSlug.length > 0) {
      return `#${this.categoryParentSlug}:${this.categorySlug}`;
    }
    return `#${this.categorySlug}`;
  }

  /** 把关键词与筛选条件拼成最终的 q。关键词在前,筛选 token 在后,与官方一致。 */
  static buildQuery(term: string, filters: SearchFilters): string {
    const parts: string[] = [];
    const trimmed: string = term.trim();
    if (trimmed.length > 0) {
      parts.push(trimmed);
    }

    const category: string = filters.categoryToken();
    if (category.length > 0) {
      parts.push(category);
    }

    if (filters.tags.length > 0) {
      // 分隔符即语义:+ 全部命中,, 任一命中。
      parts.push(`tags:${filters.tags.join(filters.tagsMatchAll ? '+' : ',')}`);
    }

    if (filters.username.length > 0) {
      parts.push(`@${filters.username}`);
    }

    for (let index: number = 0; index < filters.inFilters.length; index++) {
      const value: string = filters.inFilters[index];
      parts.push(`${inKeywordFor(value)}:${value}`);
    }

    if (filters.status.length > 0) {
      parts.push(`status:${filters.status}`);
    }

    if (filters.timeDate.length > 0) {
      parts.push(`${filters.timeWhen}:${filters.timeDate}`);
    }

    if (filters.minPosts.length > 0) {
      parts.push(`min_posts:${filters.minPosts}`);
    }
    if (filters.maxPosts.length > 0) {
      parts.push(`max_posts:${filters.maxPosts}`);
    }
    if (filters.minViews.length > 0) {
      parts.push(`min_views:${filters.minViews}`);
    }
    if (filters.maxViews.length > 0) {
      parts.push(`max_views:${filters.maxViews}`);
    }

    // 相关度是「不拼 order」,拼 order:relevance 反而会被服务端当未知排序忽略。
    if (filters.order.length > 0) {
      parts.push(`order:${filters.order}`);
    }

    return parts.join(' ');
  }

  /** 记入历史用的分类标记:选了分类时把它带进历史词条,回填时能还原。 */
  static fromCategory(category: TopicCategory, parent: TopicCategory | undefined, base: SearchFilters): SearchFilters {
    const next: SearchFilters = base.clone();
    next.categoryId = category.id;
    next.categorySlug = category.slug ?? '';
    next.categoryParentSlug = parent ? (parent.slug ?? '') : '';
    next.categoryName = category.name;
    return next;
  }

}
