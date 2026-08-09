import { AppConstants } from '../../common/constants/AppConstants';

// 表情字典:name → url。结构就是 Discourse `GET /emojis.json` 的原样响应
// ({ 组名: [{ name, url, tonable, ... }] }),覆盖标准 twemoji + 该站的自定义表情组。
// 用于把 user_status.emoji(如 "lollipop"、"tieba_003")这类"只有短名"的具名表情渲染成图片,
// 以及给表情选择器提供分组数据。
//
// 数据从**当前论坛**动态拉取(见 EmojiCatalogService),不再内置 rawfile:
// 那份 284KB 的导出只对 linux.do 成立,别的论坛自定义表情完全不同。

// 标准表情的 url 是站内相对路径(/images/emoji/twemoji/xxx.png?v=15),站点实际经 CDN 提供;
// 走 CDN 既与站点一致、又绕开主站 CF。自定义表情已是协议相对绝对地址,只补协议。
//
// 必须是函数而不是模块级 const:STATIC_CDN_BASE 现在跟当前论坛走(见 AppConstants),
// 用 const 会在模块加载那一刻把值冻住 —— 那时可能还没选定站点(空串),拼出来就是
// 没有 host 的 /images/emoji/...,表情全裂;切站后也不会跟着变。
function emojiCdnBase(): string {
  return AppConstants.STATIC_CDN_BASE;
}

interface RawEmojiEntry {
  name?: string;
  url?: string;
  tonable?: boolean;
  created_by?: string;
}

export interface EmojiItem {
  name: string;
  url: string;
  groupKey: string;
  tonable: boolean;
  createdBy?: string;
}

export interface EmojiGroup {
  key: string;
  items: EmojiItem[];
}

const emojiUrlMap: Map<string, string> = new Map();
const emojiNameByUrl: Map<string, string> = new Map();
const emojiItemMap: Map<string, EmojiItem> = new Map();
let emojiGroups: EmojiGroup[] = [];
let emojiUrlsLoaded: boolean = false;

export function loadEmojiUrlsFromJson(json: string): number {
  emojiUrlMap.clear();
  emojiNameByUrl.clear();
  emojiItemMap.clear();
  emojiGroups = [];

  let parsed: Record<string, RawEmojiEntry[]>;
  try {
    parsed = JSON.parse(json) as Record<string, RawEmojiEntry[]>;
  } catch (err) {
    emojiUrlsLoaded = true;
    return 0;
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    emojiUrlsLoaded = true;
    return 0;
  }

  const groupKeys: string[] = Object.keys(parsed);
  for (let g: number = 0; g < groupKeys.length; g++) {
    const groupKey: string = groupKeys[g];
    const entries: RawEmojiEntry[] = parsed[groupKey];
    if (!Array.isArray(entries)) {
      continue;
    }
    const items: EmojiItem[] = [];
    for (let i: number = 0; i < entries.length; i++) {
      const entry: RawEmojiEntry = entries[i];
      if (entry && typeof entry.name === 'string' && entry.name.length > 0 &&
        typeof entry.url === 'string' && entry.url.length > 0) {
        const resolvedUrl: string = resolveEmojiUrl(entry.url);
        const item: EmojiItem = {
          name: entry.name,
          url: resolvedUrl,
          groupKey: groupKey,
          tonable: entry.tonable === true,
          createdBy: entry.created_by
        };
        items.push(item);
        emojiUrlMap.set(item.name, item.url);
        emojiNameByUrl.set(item.url, item.name);
        emojiItemMap.set(item.name, item);
      }
    }
    if (items.length > 0) {
      emojiGroups.push({ key: groupKey, items: items });
    }
  }

  emojiUrlsLoaded = true;
  return emojiUrlMap.size;
}

// 具名表情短名 → 可直接喂 Image 的绝对 url;未收录(极少数别名/未知)→ undefined,调用方跳过渲染。
export function getEmojiUrl(name?: string): string | undefined {
  if (!name || name.length === 0) {
    return undefined;
  }
  return emojiUrlMap.get(name);
}

export function getEmojiNameByUrl(url?: string): string | undefined {
  if (!url || url.length === 0) {
    return undefined;
  }
  return emojiNameByUrl.get(url);
}

// 返回目录快照，调用方可以安全切换/筛选分组，不会改坏全局注册表。
export function getEmojiGroups(): EmojiGroup[] {
  const groups: EmojiGroup[] = [];
  for (let index: number = 0; index < emojiGroups.length; index++) {
    const group: EmojiGroup = emojiGroups[index];
    const snapshot: EmojiGroup = { key: group.key, items: group.items.slice() };
    groups.push(snapshot);
  }
  return groups;
}

export function getEmojiItem(name?: string): EmojiItem | undefined {
  if (!name || name.length === 0) {
    return undefined;
  }
  return emojiItemMap.get(name);
}

export function hasLoadedEmojiUrls(): boolean {
  return emojiUrlsLoaded;
}

/** 清空字典。切站时调用 —— 各站的自定义表情完全不同,旧站的表留着会渲染出不存在的图。 */
export function resetEmojiUrls(): void {
  emojiUrlMap.clear();
  emojiNameByUrl.clear();
  emojiItemMap.clear();
  emojiGroups = [];
  emojiUrlsLoaded = false;
}

/** 已收录条数。0 = 还没拉到(首启或刚切站),消费方按"查不到"处理即可。 */
export function emojiCount(): number {
  return emojiUrlMap.size;
}

function resolveEmojiUrl(rawUrl: string): string {
  if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
    return rawUrl;
  }
  // 自定义表情:协议相对(//linuxdo-uploads.s3.ldstatic.com/...),补 https。
  if (rawUrl.startsWith('//')) {
    return `https:${rawUrl}`;
  }
  // 标准 twemoji:站内相对(/images/emoji/...),挂 CDN。
  if (rawUrl.startsWith('/')) {
    return `${emojiCdnBase()}${rawUrl}`;
  }
  return `${emojiCdnBase()}/${rawUrl}`;
}
