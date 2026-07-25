import { buffer } from '@kit.ArkTS';
import resourceManager from '@ohos.resourceManager';
import { AppConstants } from '../../common/constants/AppConstants';

// linux.do 的 GET /emojis.json 导出:{ 组名: [{ name, url, ... }] }。
// 覆盖标准 twemoji + 4 个自定义组(b站/飞书/贴吧/小红书),共 ~2367 条,是 name→url 的权威字典。
// 用于把 user_status.emoji(如 "lollipop"、"tieba_003")这类"只有短名"的具名表情渲染成图片。
export const LINUXDO_EMOJIS_RAWFILE = 'linuxdo_emojis.json';

// 标准表情的 url 是站内相对路径(/images/emoji/twemoji/xxx.png?v=15),站点实际经 CDN 提供;
// 走 CDN 既与站点一致、又绕开主站 CF。自定义表情已是协议相对绝对地址,只补协议。
const EMOJI_CDN_BASE = AppConstants.STATIC_CDN_BASE;

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

export function loadEmojiUrlsFromRawContent(rawContent: Uint8Array): number {
  try {
    const json: string = buffer.from(rawContent as ArrayBufferLike).toString('utf8');
    return loadEmojiUrlsFromJson(json);
  } catch (err) {
    emojiUrlMap.clear();
    emojiNameByUrl.clear();
    emojiItemMap.clear();
    emojiGroups = [];
    emojiUrlsLoaded = true;
    return 0;
  }
}

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

// 惰性兜底:若 EntryAbility 启动加载缺失,首次取用时按需补载。
export function ensureEmojiUrlsLoaded(manager: resourceManager.ResourceManager): number {
  if (emojiUrlsLoaded && emojiUrlMap.size > 0) {
    return emojiUrlMap.size;
  }
  try {
    const rawContent: Uint8Array = manager.getRawFileContentSync(LINUXDO_EMOJIS_RAWFILE);
    return loadEmojiUrlsFromRawContent(rawContent);
  } catch (err) {
    emojiUrlMap.clear();
    emojiNameByUrl.clear();
    emojiItemMap.clear();
    emojiGroups = [];
    emojiUrlsLoaded = true;
    return 0;
  }
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
    return `${EMOJI_CDN_BASE}${rawUrl}`;
  }
  return `${EMOJI_CDN_BASE}/${rawUrl}`;
}
