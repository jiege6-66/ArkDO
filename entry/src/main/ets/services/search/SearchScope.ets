/**
 * 搜索类型(对齐 Discourse 整页搜索右上角那个下拉,只取我们要的两种)。
 *
 * 注意:这两种类型在官方**不是同一个接口**,别想当然地都往 /search.json 上挂
 * (frontend/discourse/app/controllers/full-page-search.js 里是个 switch):
 *
 * - topics_posts(默认)→ GET /search.json?q=&page=,高级语法(category:/tags:/@user…)只对它生效;
 * - users             → GET /u/search/users?term=&limit=,与 /search.json 无关,且无分页。
 *
 * 所以「高级筛选」只在 topics_posts 下显示——用户搜索压根不经过 Discourse 的
 * advanced_filter 那套解析,把 category:xxx 拼进去只会被当成普通字符串。
 *
 * (官方还有第三种 categories_tags,已按需求去掉。)
 */

export const SEARCH_TYPE_TOPICS: string = 'topics_posts';
export const SEARCH_TYPE_USERS: string = 'users';

export interface SearchTypeOption {
  value: string;
  /** 下拉里的名字,也是搜索框右侧那个入口上显示的短名。 */
  label: string;
  /** 该类型下输入框的占位文字。 */
  placeholder: string;
}

export const SEARCH_TYPE_OPTIONS: SearchTypeOption[] = [
  { value: SEARCH_TYPE_TOPICS, label: '帖子', placeholder: '搜索帖子…' },
  { value: SEARCH_TYPE_USERS, label: '用户', placeholder: '搜索用户…' }
];

export function searchTypeLabel(value: string): string {
  for (let index: number = 0; index < SEARCH_TYPE_OPTIONS.length; index++) {
    if (SEARCH_TYPE_OPTIONS[index].value === value) {
      return SEARCH_TYPE_OPTIONS[index].label;
    }
  }
  return SEARCH_TYPE_OPTIONS[0].label;
}

export function searchTypePlaceholder(value: string): string {
  for (let index: number = 0; index < SEARCH_TYPE_OPTIONS.length; index++) {
    if (SEARCH_TYPE_OPTIONS[index].value === value) {
      return SEARCH_TYPE_OPTIONS[index].placeholder;
    }
  }
  return SEARCH_TYPE_OPTIONS[0].placeholder;
}
