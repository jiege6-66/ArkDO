// 正文链接的点击数(Discourse link_counts)——建表与查表。
//
// 数据随 post JSON 下发,不在 cooked HTML 里,所以这一层负责把它收成一张
// 「渲染用 href → 点击数」的表,渲染层按 href 直接查表决定要不要在链接后挂灰色角标。
// 行为对齐官方 post-cooked 的 _showLinkCounts 与 click-track 的 isValidLink:
//   1. clicks < 1 不显示(而不是显示 0);
//   2. reflection(反链:别的帖引用了本帖)不显示——它根本不在本楼正文里;
//   3. 引用卡 <aside class="quote"> 里的链接不显示。那是别人帖子里的链接,点击数记在原帖上,
//      这里再标一遍等于把别人的数据挂到本楼名下。注意服务端**会**把引用里的链接算进 link_counts,
//      所以这一条必须自己滤,不能指望数据里没有;
//   4. 版块徽章 / 话题标签 / 灯箱图这类链接不显示(官方 isValidLink 同样排除)。
//
// 键取「resolveUrl 之后的 href」而非 link_counts 原始 url:渲染层的 token.href 是解析器
// resolveUrl 过的(解 HTML 实体 + 相对路径补主站域名),两边不统一就配不上。模糊匹配(去 query、
// 附件按包含)一次性在这里做完,渲染层只剩一次 Map.get,不必每帧重算。
//
// 建表放服务层而不是解析器:RichBlock 解析结果是按 cooked 缓存的,而点击数属于随 post JSON
// 变动的动态数据,混进去会被缓存钉死。

import { findClosingTag, findOpenTag, findTagEnd } from '../content/html/HtmlLexer';
import { hasClass, hasClassContaining, extractAttr } from '../content/html/HtmlAttrs';
import { resolveUrl } from '../content/HtmlContentUtils';
import { DiscourseLinkCount } from './TopicApiTypes';

// 建表。无可展示项返回 undefined,让 TopicPost.linkClicks 保持空缺,渲染层一次判空即可短路。
export function buildLinkClicks(cookedHtml: string,
                                counts: DiscourseLinkCount[] | undefined): Map<string, number> | undefined {
  if (!counts || counts.length === 0 || cookedHtml.length === 0) {
    return undefined;
  }

  const candidates: DiscourseLinkCount[] = [];
  for (let index: number = 0; index < counts.length; index++) {
    const item: DiscourseLinkCount = counts[index];
    const url: string | undefined = item.url;
    const clicks: number | undefined = item.clicks;
    if (typeof url !== 'string' || url.length === 0) {
      continue;
    }
    if (item.reflection === true) {
      continue;
    }
    if (typeof clicks !== 'number' || clicks < 1) {
      continue;
    }
    candidates.push(item);
  }
  if (candidates.length === 0) {
    return undefined;
  }

  const result: Map<string, number> = new Map();
  const hrefs: string[] = trackableHrefs(cookedHtml);
  for (let index: number = 0; index < hrefs.length; index++) {
    const href: string = hrefs[index];
    if (result.has(href)) {
      continue;
    }
    const clicks: number = matchClicks(candidates, href);
    if (clicks > 0) {
      result.set(href, clicks);
    }
  }

  return result.size > 0 ? result : undefined;
}

// 渲染层入口:按 href 取点击数,0 表示不挂角标。
export function clicksForHref(clicks: Map<string, number> | undefined, href: string): number {
  if (!clicks || href.length === 0) {
    return 0;
  }
  const hit: number | undefined = clicks.get(href);
  return hit === undefined ? 0 : hit;
}

// 给定 href 在 link_counts 里找对应计数。匹配顺序照抄官方:
// 精确匹配 → 去掉 query 再匹配(服务端对站内链接按去 query 的地址计数)→
// 附件按包含匹配(link_counts 给的是 /uploads/… 相对路径,而 href 已被补成带域名的绝对地址)。
function matchClicks(candidates: DiscourseLinkCount[], href: string): number {
  const queryAt: number = href.indexOf('?');
  const bare: string = queryAt > 0 ? href.substring(0, queryAt) : href;

  for (let index: number = 0; index < candidates.length; index++) {
    const url: string = candidates[index].url as string;
    if (url === href || url === bare) {
      return candidates[index].clicks as number;
    }
  }
  for (let index: number = 0; index < candidates.length; index++) {
    const url: string = candidates[index].url as string;
    if (url.indexOf('/uploads/') === 0 && href.indexOf(url) >= 0) {
      return candidates[index].clicks as number;
    }
  }
  return 0;
}

// 本楼正文里「可挂角标」的链接地址(已 resolveUrl,与渲染层的 token.href 同形)。
// 先整块剔掉引用卡,再逐个 <a> 过一遍排除名单。
function trackableHrefs(cookedHtml: string): string[] {
  const html: string = stripQuoteAsides(cookedHtml);
  const hrefs: string[] = [];
  let cursor: number = 0;

  while (cursor < html.length) {
    const openStart: number = findOpenTag(html, 'a', cursor);
    if (openStart < 0) {
      break;
    }
    const openEnd: number = findTagEnd(html, openStart);
    if (openEnd < 0) {
      break;
    }
    const tag: string = html.substring(openStart, openEnd + 1);
    cursor = openEnd + 1;

    // 版块徽章(badge-category)、话题标签(hashtag / hashtag-cooked)、灯箱大图(lightbox)、
    // 引用卡的回跳箭头(back):官方一律不挂角标。
    if (hasClassContaining(tag, 'hashtag') || hasClassContaining(tag, 'badge-category') ||
      hasClass(tag, 'lightbox') || hasClass(tag, 'back') || hasClass(tag, 'no-track-link')) {
      continue;
    }
    const href: string = resolveUrl(extractAttr(tag, 'href'));
    if (href.length > 0) {
      hrefs.push(href);
    }
  }

  return hrefs;
}

// 抹掉所有 <aside class="quote …">…</aside>(按嵌套深度配对,引用套引用也能整块吃掉),
// 留下本楼自己写的正文。只针对 quote:onebox 同样是 aside,但它是本楼链接的预览卡,要留下。
function stripQuoteAsides(html: string): string {
  let kept: string = '';
  let cursor: number = 0;

  while (cursor < html.length) {
    const openStart: number = findOpenTag(html, 'aside', cursor);
    if (openStart < 0) {
      break;
    }
    const openEnd: number = findTagEnd(html, openStart);
    if (openEnd < 0) {
      break;
    }
    if (!hasClass(html.substring(openStart, openEnd + 1), 'quote')) {
      // onebox 之类的 aside:原样留下,继续往后找。
      kept += html.substring(cursor, openEnd + 1);
      cursor = openEnd + 1;
      continue;
    }
    const closeStart: number = findClosingTag(html, openEnd + 1, 'aside');
    if (closeStart < 0) {
      // 配不上闭合标签(理论上不会):后面整段按引用丢掉,宁可少标也不错标。
      return kept + html.substring(cursor, openStart);
    }
    kept += html.substring(cursor, openStart);
    const closeEnd: number = findTagEnd(html, closeStart);
    cursor = closeEnd >= 0 ? closeEnd + 1 : closeStart;
  }

  return kept + html.substring(cursor);
}
