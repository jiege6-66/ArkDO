/** 内容入口标识:除 CREATED 外与 Discourse feed 接口一一对应。 */
export enum FeedKey {
  LATEST = 'latest',
  // top 与 hot 是 Discourse 的两个不同榜单,别混:
  // - top(/top.json):历史高分榜,可按时间范围筛,偏长期积累 → 本项目叫「排行榜」
  // - hot(/hot.json):当前热度,按「点赞 ÷ (发帖小时数+2)^gravity」时间衰减排,偏近期有互动的新帖 → 「热门」
  TOP = 'top',
  HOT = 'hot',
  UNREAD = 'unread',
  NEW = 'new',
  // 唯一一个不是 Discourse filter 名的 key:它是 latest + `order=created`,拼装规则见 TopicListQuery。
  // Discourse 没有「按发布时间」的 filter —— latest 排的是 bumped_at,老帖被回复就顶上来。
  CREATED = 'created'
}

/** 一个内容入口的展示元数据。requiresLogin 的入口未登录时在抽屉里置灰(不隐藏)。 */
export interface FeedDef {
  key: string;
  label: string;
  requiresLogin: boolean;
}

// 「最新」恒在抽屉首位,是默认排序。
const LATEST_FEED: FeedDef = { key: FeedKey.LATEST, label: '最新', requiresLogin: false };

// 「最新」之外的内置入口,顺序即抽屉里 chips 的排列。
//
// 这些曾经可以在设置页里勾选启用并拖动排序;首页筛选改成 chips 之后五个入口只占两行,
// 没有再裁剪的必要,那组设置连同 feed_enabled_order 这个持久化键一起删了(旧数据留着不读)。
const OPTIONAL_FEEDS: FeedDef[] = [
  // 紧挨着「最新」放:两者同为全站时间流,差别只在排序键(bumped_at vs created_at),放一起才好对比。
  // 纯服务端排序,不看个人已读状态,故不需要登录。
  { key: FeedKey.CREATED, label: '最新发布', requiresLogin: false },
  // 「热门」原先挂在 top 上是名实不符(top 是历史高分榜),现已归位:hot=热门、top=排行榜。
  { key: FeedKey.HOT, label: '热门', requiresLogin: false },
  { key: FeedKey.TOP, label: '排行榜', requiresLogin: false },
  { key: FeedKey.UNREAD, label: '未读', requiresLogin: true },
  // 曾叫「新主题」,名实不符:linux.do 开着 new_new_view,/new.json 回的是「未读 + 从没打开过」
  // 的合集,还按 bumped_at 排(抓包实测 30 条里 3 条是读过一半的老帖,最新发布的那条被压到第 8 位)。
  // 想要「刚发出来的帖子」看 CREATED。
  { key: FeedKey.NEW, label: '未读新帖', requiresLogin: true }
];

/** 内容入口的元数据表:抽屉顶部的过滤器 chips 按「最新 + 其余」渲染,标签与登录要求都从这儿取。 */
export class FeedPrefs {
  /** 「最新」入口(恒在首位)。 */
  static latestFeed(): FeedDef {
    return LATEST_FEED;
  }

  /** 「最新」之外的入口。 */
  static optionalFeeds(): FeedDef[] {
    return OPTIONAL_FEEDS.slice();
  }

  /** 按 key 找入口元数据(含 latest)。 */
  static feedDef(key: string): FeedDef | undefined {
    if (key === FeedKey.LATEST) {
      return LATEST_FEED;
    }
    for (let index: number = 0; index < OPTIONAL_FEEDS.length; index++) {
      if (OPTIONAL_FEEDS[index].key === key) {
        return OPTIONAL_FEEDS[index];
      }
    }
    return undefined;
  }
}
