// HTML 内容纯函数工具:实体解码、纯文本抽取、URL 解析、CSS 变量读取,以及按标签名/class
// 定位元素内层 HTML 的查找器。只依赖词法层(HtmlLexer)、属性层(HtmlAttrs)与站点常量,
// 不依赖富内容解析核心(CookedHtmlParser),故可被解析器与其它模块安全复用。
import { AppConstants } from '../../common/constants/AppConstants';
import { findClosingTag, findOpenTag, findTagEnd, getTagName, isClosingTag } from './html/HtmlLexer';
import { extractAttr, hasClassContaining } from './html/HtmlAttrs';

// 站内 emoji 图片的相对路径前缀,resolveUrl 据此把它们挂 CDN 而非主站。
const EMOJI_PATH_PREFIX: string = '/images/emoji/';

export function decodeHtmlEntities(text: string): string {
  return (text ? text : '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x([0-9a-fA-F]+);/g, (_match: string, hex: string): string => {
      const code: number = parseInt(hex, 16);
      return isNaN(code) ? '' : String.fromCharCode(code);
    })
    .replace(/&#([0-9]+);/g, (_match: string, dec: string): string => {
      const code: number = parseInt(dec, 10);
      return isNaN(code) ? '' : String.fromCharCode(code);
    });
}

export function normalizeText(text: string): string {
  return text
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n[ \t]+/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function stripTagsKeepingLines(html: string): string {
  let text: string = html ? html : '';
  text = text.replace(/<br\s*\/?>/gi, '\n');
  text = text.replace(/<\/p>/gi, '\n');
  text = text.replace(/<\/div>/gi, '\n');
  text = text.replace(/<\/li>/gi, '\n');
  text = text.replace(/<li\b[^>]*>/gi, '- ');
  text = text.replace(/<[^>]+>/g, '');
  return decodeHtmlEntities(text);
}

// 把 HTML 转为规范化纯文本(去标签、保留换行语义、折叠多余空白)。
export function htmlToPlainText(html: string): string {
  return normalizeText(stripTagsKeepingLines(html));
}

export function resolveUrl(rawUrl: string): string {
  const url: string = decodeHtmlEntities(rawUrl).trim();
  if (url.length === 0 || url.startsWith('upload://')) {
    return url;
  }
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  if (url.startsWith('//')) {
    return `https:${url}`;
  }
  if (url.startsWith(EMOJI_PATH_PREFIX)) {
    // 正文 cooked 里的 emoji 服务端已改写成 CDN 绝对地址,但 discourse-boosts 的 cooked 不走那套改写,
    // 吐的是站内相对路径。拼 BASE_URL 会得到必然加载不出的主站直链,故这里挂 CDN(同一份文件)。
    return `${AppConstants.STATIC_CDN_BASE}${url}`;
  }
  if (url.startsWith('/')) {
    return `${AppConstants.BASE_URL}${url}`;
  }
  return url;
}

export function hostFromUrl(url: string): string {
  const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/]+)/i);
  return match ? match[1] : '';
}

// 取 style 里某个 CSS 变量的值(如 --category-badge-color: #9cb6c4)。
export function cssVar(style: string, name: string): string {
  const pattern: RegExp = new RegExp(`${name}\\s*:\\s*([^;]+)`, 'i');
  const match: RegExpMatchArray | null = style.match(pattern);
  return match ? match[1].trim() : '';
}

export function extractCodeLanguage(codeOpenTag: string): string {
  const className: string = extractAttr(codeOpenTag, 'class');
  const languageMatch: RegExpMatchArray | null = className.match(/(?:lang|language)-([a-zA-Z0-9_+-]+)/);
  if (!languageMatch) {
    return '';
  }
  return languageMatch[1];
}

export function firstTagMatch(html: string, pattern: RegExp): string {
  const match: RegExpMatchArray | null = html.match(pattern);
  return match ? match[0] : '';
}

// 第一个 class 含指定关键字的 <img> 的完整标签。
export function firstImgWithClass(html: string, keyword: string): string {
  const lower: string = html.toLowerCase();
  let cursor: number = 0;
  while (cursor < html.length) {
    const start: number = lower.indexOf('<img', cursor);
    if (start < 0) {
      return '';
    }
    const end: number = findTagEnd(html, start);
    if (end < 0) {
      return '';
    }
    const tag: string = html.substring(start, end + 1);
    if (hasClassContaining(tag, keyword)) {
      return tag;
    }
    cursor = end + 1;
  }
  return '';
}

// 最靠后的带 id 的 <svg>(话题分类徽章图标外层是 fa 包装 svg,真正图标是内层 svg[id])。
export function lastSvgWithId(html: string): string {
  const lower: string = html.toLowerCase();
  let cursor: number = 0;
  let found: string = '';
  while (cursor < html.length) {
    const start: number = lower.indexOf('<svg', cursor);
    if (start < 0) {
      break;
    }
    const end: number = findTagEnd(html, start);
    if (end < 0) {
      break;
    }
    const tag: string = html.substring(start, end + 1);
    if (extractAttr(tag, 'id').length > 0) {
      found = tag;
    }
    cursor = end + 1;
  }
  return found;
}

// 第一个 class 含 keyword 的元素的开标签(用于取其属性,如 badge-category span 的 style/data-*)。
export function firstOpenTagByClass(html: string, keyword: string): string {
  const lower: string = html.toLowerCase();
  let cursor: number = 0;
  while (cursor < html.length) {
    const start: number = lower.indexOf('<', cursor);
    if (start < 0) {
      return '';
    }
    const end: number = findTagEnd(html, start);
    if (end < 0) {
      return '';
    }
    const tag: string = html.substring(start, end + 1);
    if (!isClosingTag(tag) && hasClassContaining(tag, keyword)) {
      return tag;
    }
    cursor = end + 1;
  }
  return '';
}

// 第一个 class 含 keyword 的元素的内部 HTML。
export function firstElementInnerByClass(html: string, keyword: string): string {
  const lower: string = html.toLowerCase();
  let cursor: number = 0;
  while (cursor < html.length) {
    const start: number = lower.indexOf('<', cursor);
    if (start < 0) {
      return '';
    }
    const end: number = findTagEnd(html, start);
    if (end < 0) {
      return '';
    }
    const tag: string = html.substring(start, end + 1);
    if (!isClosingTag(tag) && hasClassContaining(tag, keyword)) {
      const name: string = getTagName(tag);
      const closeStart: number = findClosingTag(html, end + 1, name);
      if (closeStart < 0) {
        return '';
      }
      return html.substring(end + 1, closeStart);
    }
    cursor = end + 1;
  }
  return '';
}

// 第一个指定标签名元素的内部 HTML。
export function firstElementInner(html: string, tagName: string): string {
  const lower: string = html.toLowerCase();
  const open: number = lower.indexOf(`<${tagName}`);
  if (open < 0) {
    return '';
  }
  const openEnd: number = findTagEnd(html, open);
  if (openEnd < 0) {
    return '';
  }
  const closeStart: number = findClosingTag(html, openEnd + 1, tagName);
  if (closeStart < 0) {
    return '';
  }
  return html.substring(openEnd + 1, closeStart);
}

// 取 html 中首个 <tagName ...>...</tagName> 的内层 HTML(标签名需按词边界匹配,避免 p 命中 picture)。
export function extractElementInner(html: string, tagName: string): string {
  const openStart: number = findOpenTag(html, tagName, 0);
  if (openStart < 0) {
    return '';
  }
  const openEnd: number = findTagEnd(html, openStart);
  if (openEnd < 0) {
    return '';
  }
  const closeStart: number = findClosingTag(html, openEnd + 1, tagName);
  if (closeStart < 0) {
    return '';
  }
  return html.substring(openEnd + 1, closeStart);
}

export function firstAnchorHref(html: string): string {
  const openTag: string = firstTagMatch(html, /<a\b[^>]*>/i);
  if (openTag.length === 0) {
    return '';
  }
  return resolveUrl(extractAttr(openTag, 'href'));
}

export function firstAnchorText(html: string): string {
  const openTag: string = firstTagMatch(html, /<a\b[^>]*>/i);
  if (openTag.length === 0) {
    return '';
  }
  const start: number = html.indexOf(openTag) + openTag.length;
  const closeStart: number = html.toLowerCase().indexOf('</a>', start);
  if (closeStart < 0) {
    return '';
  }
  return htmlToPlainText(html.substring(start, closeStart));
}
