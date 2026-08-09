import { Log } from '../logging/Log';
import { SiteUrl } from './SiteUrl';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][Forum]';
// 与 SitePrefs/DohManager/FeedPrefs 共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
// 单键存全量论坛(JSON 数组)。数组顺序即列表展示顺序。
const PREF_KEY_FORUMS: string = 'native_forums';
// 当前论坛的 id。空/失效时回落到列表第一个。
const PREF_KEY_ACTIVE_ID: string = 'active_forum_id';

/**
 * 用户添加的论坛(App 原生浏览的 Discourse 站点)。
 *
 * 与 SiteDef 的区别:ForumDef 是「原生浏览的主站点」,可切换,切换后全 app 的接口地址、
 * 登录态、缓存都跟着走;SiteDef 是「用 WebView 打开的生态站点快捷方式」,不影响主站。
 * 两者刻意分开,免得一个列表里混着两种语义完全不同的东西。
 */
export interface ForumDef {
  id: string;
  /** 展示名。留空时由调用方用域名兜底。 */
  name: string;
  /** 站点根地址,已规范化:带协议、无尾斜杠。 */
  baseUrl: string;
}

/** 首启引导用的候选论坛。都是公开的 Discourse 站点,仅作为示例供用户点选,不预置进列表。 */
export interface ForumSuggestion {
  name: string;
  baseUrl: string;
  desc: string;
}

export const FORUM_SUGGESTIONS: ForumSuggestion[] = [
  { name: 'Discourse Meta', baseUrl: 'https://meta.discourse.org', desc: 'Discourse 官方社区' },
  { name: 'Python 官方论坛', baseUrl: 'https://discuss.python.org', desc: 'Python 语言官方讨论区' },
  { name: 'Home Assistant', baseUrl: 'https://community.home-assistant.io', desc: '智能家居社区' },
  { name: 'Obsidian Forum', baseUrl: 'https://forum.obsidian.md', desc: 'Obsidian 笔记社区' }
];

/**
 * 论坛列表与「当前论坛」的持久化读写。只管存取与校验,不持有运行时状态
 * ——运行时状态在 CurrentSite。
 *
 * 不预置任何论坛:App 是通用 Discourse 客户端,只做容器,站点全部由用户自己添加。
 */
export class ForumPrefs {
  private static getStore(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
  }

  /** 读全量论坛(有序;非法项与重复 id 被剔除)。 */
  static getForums(context: common.Context): ForumDef[] {
    try {
      const store: preferences.Preferences = ForumPrefs.getStore(context);
      const raw: string = store.getSync(PREF_KEY_FORUMS, '') as string;
      if (raw.length === 0) {
        return [];
      }
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const valid: ForumDef[] = [];
      for (let index: number = 0; index < parsed.length; index++) {
        const forum: ForumDef | undefined = ForumPrefs.parseForum(parsed[index] as Object);
        if (forum && !ForumPrefs.containsId(valid, forum.id)) {
          valid.push(forum);
        }
      }
      return valid;
    } catch (err) {
      Log.e(`${LOG_TAG} read forums failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  static setForums(context: common.Context, forums: ForumDef[]): void {
    try {
      const store: preferences.Preferences = ForumPrefs.getStore(context);
      store.putSync(PREF_KEY_FORUMS, JSON.stringify(forums));
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} write forums failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 追加一个论坛。同 host 已存在则不重复添加,直接返回既有项
   * ——同一个站点被加两遍会出现「两个入口、两份缓存、同一份登录态」的怪状态。
   */
  static addForum(context: common.Context, name: string, urlInput: string): ForumDef | undefined {
    const baseUrl: string = SiteUrl.toBaseUrl(urlInput);
    if (baseUrl.length === 0) {
      return undefined;
    }
    const forums: ForumDef[] = ForumPrefs.getForums(context);
    const host: string = SiteUrl.hostOf(baseUrl);
    for (let index: number = 0; index < forums.length; index++) {
      if (SiteUrl.hostOf(forums[index].baseUrl) === host) {
        return forums[index];
      }
    }
    const trimmedName: string = name.trim();
    const added: ForumDef = {
      id: ForumPrefs.newId(),
      name: trimmedName.length > 0 ? trimmedName : host,
      baseUrl: baseUrl
    };
    forums.push(added);
    ForumPrefs.setForums(context, forums);
    return added;
  }

  /** 删除论坛。若删掉的是当前论坛,当前论坛 id 一并清空,由 CurrentSite 重新选。 */
  static removeForum(context: common.Context, id: string): void {
    const forums: ForumDef[] = ForumPrefs.getForums(context);
    const kept: ForumDef[] = [];
    for (let index: number = 0; index < forums.length; index++) {
      if (forums[index].id !== id) {
        kept.push(forums[index]);
      }
    }
    ForumPrefs.setForums(context, kept);
    if (ForumPrefs.getActiveId(context) === id) {
      ForumPrefs.setActiveId(context, '');
    }
  }

  static getActiveId(context: common.Context): string {
    try {
      const store: preferences.Preferences = ForumPrefs.getStore(context);
      return store.getSync(PREF_KEY_ACTIVE_ID, '') as string;
    } catch (err) {
      Log.e(`${LOG_TAG} read active id failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  static setActiveId(context: common.Context, id: string): void {
    try {
      const store: preferences.Preferences = ForumPrefs.getStore(context);
      store.putSync(PREF_KEY_ACTIVE_ID, id);
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} write active id failed: ${JSON.stringify(err)}`);
    }
  }

  /** 新论坛 id。时间戳 + 随机后缀:同一毫秒内连加两个也不撞。 */
  static newId(): string {
    const random: number = Math.floor(Math.random() * 100000);
    return `f${Date.now()}${random}`;
  }

  // ==================== 内部 ====================

  private static containsId(forums: ForumDef[], id: string): boolean {
    for (let index: number = 0; index < forums.length; index++) {
      if (forums[index].id === id) {
        return true;
      }
    }
    return false;
  }

  // 逐字段校验:id/baseUrl 不合法即整条丢弃(宁可少一个论坛,不让脏数据把首页打崩);
  // name 空则用域名兜底。baseUrl 一律重新规范化,兼容手工改过存储或旧版本写入的带尾斜杠值。
  private static parseForum(raw: Object): ForumDef | undefined {
    if (!raw) {
      return undefined;
    }
    const candidate: ForumDef = raw as ForumDef;
    if (typeof candidate.id !== 'string' || candidate.id.length === 0) {
      return undefined;
    }
    if (typeof candidate.baseUrl !== 'string') {
      return undefined;
    }
    const baseUrl: string = SiteUrl.toBaseUrl(candidate.baseUrl);
    if (baseUrl.length === 0) {
      return undefined;
    }
    const name: string = typeof candidate.name === 'string' && candidate.name.length > 0
      ? candidate.name
      : SiteUrl.hostOf(baseUrl);
    return { id: candidate.id, name: name, baseUrl: baseUrl };
  }
}
