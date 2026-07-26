import { TopicCategory } from '../../models/Topic';
import { findClosingTag, findOpenTag, findTagEnd, getTagName, isBlockTag, isClosingTag,
  isHeadingTag } from './html/HtmlLexer';
import { bestSrcFromTag, extractAttr, hasClass, hasClassContaining, parsePositiveNumber } from './html/HtmlAttrs';
import { RichBlock, RichBlockType, RichInlineNode, RichInlineType, RichListItem, RichTableCell,
  RichTableRow } from './RichContentTypes';
import { hasVisibleInlines, parseInlines, trimLeadingEmptyText } from './InlineHtmlParser';
import { cssVar, decodeHtmlEntities, extractCodeLanguage, extractElementInner, firstAnchorHref,
  firstAnchorText, firstElementInner, firstElementInnerByClass, firstImgWithClass, firstOpenTagByClass,
  firstTagMatch, hostFromUrl, htmlToPlainText, lastSvgWithId, resolveUrl,
  stripTagsKeepingLines } from './HtmlContentUtils';

// 行内小图(emoji/小图标)的尺寸上限,与渲染层 PostRichContent.SMALL_IMAGE_MAX 对齐:
// 宽或高超过它的独立 <img>(或动图)视为整幅内容图,提升为 IMAGE 块,不再压成 18px 行内图。
const INLINE_IMAGE_MAX: number = 48;


// callout 类型别名 → 归一类型(与 discourse-quote-callouts settings.yml 的 alias 一致)。
const CALLOUT_ALIASES: Map<string, string> = ((): Map<string, string> => {
  const m: Map<string, string> = new Map();
  m.set('summary', 'abstract');
  m.set('tldr', 'abstract');
  m.set('hint', 'tip');
  m.set('important', 'tip');
  m.set('check', 'success');
  m.set('done', 'success');
  m.set('help', 'question');
  m.set('faq', 'question');
  m.set('caution', 'warning');
  m.set('attention', 'warning');
  m.set('fail', 'failure');
  m.set('missing', 'failure');
  m.set('error', 'danger');
  m.set('cite', 'quote');
  return m;
})();

interface CalloutStyleDef {
  color: string;
  icon: string;
}

// 归一类型 → 主色 + 图标 id。取值为 discourse-quote-callouts 上游默认(settings.yml)。
const CALLOUT_STYLES: Map<string, CalloutStyleDef> = ((): Map<string, CalloutStyleDef> => {
  const m: Map<string, CalloutStyleDef> = new Map();
  m.set('note', { color: '#086ddd', icon: 'far-pen-to-square' });
  m.set('abstract', { color: '#00bfbc', icon: 'far-clipboard' });
  m.set('info', { color: '#027aff', icon: 'far-lightbulb' });
  m.set('todo', { color: '#027aff', icon: 'far-circle-check' });
  m.set('tip', { color: '#00bfbc', icon: 'fire-flame-curved' });
  m.set('success', { color: '#44cf6e', icon: 'check' });
  m.set('question', { color: '#ec7500', icon: 'far-circle-question' });
  m.set('warning', { color: '#ec7500', icon: 'triangle-exclamation' });
  m.set('failure', { color: '#e93147', icon: 'xmark' });
  m.set('danger', { color: '#e93147', icon: 'bolt' });
  m.set('bug', { color: '#e93147', icon: 'bug' });
  m.set('example', { color: '#7852ee', icon: 'list' });
  m.set('quote', { color: '#9e9e9e', icon: 'quote-left' });
  return m;
})();

// 无法识别的类型:回退主色/图标(settings.yml 的 callout_fallback_*),行为按 note 处理。
const CALLOUT_FALLBACK: CalloutStyleDef = { color: '#027aff', icon: 'far-pen-to-square' };

interface CalloutStyle {
  kind: string;
  color: string;
  icon: string;
}

// blockquote 首段命中 [!type]± 才是 callout。type 仅取 ASCII 字母(与上游一致),
// 非字母(如 [!名称])不识别,原样退回普通引用。可选 +/- 折叠标记,后随可选一个空格。
const CALLOUT_MARKER: RegExp = /^\s*\[!([a-zA-Z]+)\]([+-]?)\s?/;

interface SummaryInfo {
  title: string;
  contentHtml: string;
}

interface LightboxUnit {
  before: string;
  html: string;
  after: string;
}

export class CookedHtmlParser {
  static parse(html: string): RichBlock[] {
    const source: string = html ? html : '';
    const blocks: RichBlock[] = CookedHtmlParser.parseBlocks(source);
    const visible: RichBlock[] = blocks.filter((block: RichBlock) => CookedHtmlParser.hasBlockContent(block));
    return CookedHtmlParser.mergeAdjacentParagraphs(visible);
  }

  // 把相邻的纯文本段落(PARAGRAPH)合并进同一段,块之间插入 paragraphBreak 换行。原因:每个 PARAGRAPH
  // 渲染成一个独立 Text,而 ArkUI 的 Text 选区是组件私有的,跨 Text 无法连续选中/复制。合并后连续
  // 正文段落进同一个 Text,长按可一路选到底(参考帖 2.x 用 <br> 同段能连选、3.x 另起 <p> 就断)。
  // 只合并相邻 PARAGRAPH;标题/图片/引用/列表/代码/onebox 等非文本块天然隔断,跨它们仍不可连选。
  private static mergeAdjacentParagraphs(blocks: RichBlock[]): RichBlock[] {
    const out: RichBlock[] = [];
    for (let i: number = 0; i < blocks.length; i++) {
      const block: RichBlock = blocks[i];
      const prev: RichBlock | undefined = out.length > 0 ? out[out.length - 1] : undefined;
      if (block.type === RichBlockType.PARAGRAPH && block.inlines &&
        prev && prev.type === RichBlockType.PARAGRAPH && prev.inlines) {
        const separator: RichInlineNode = { type: RichInlineType.LINE_BREAK, text: '\n', paragraphBreak: true };
        const merged: RichInlineNode[] = prev.inlines.concat([separator], block.inlines);
        out[out.length - 1] = { type: RichBlockType.PARAGRAPH, inlines: merged };
      } else {
        out.push(block);
      }
    }
    return out;
  }

  static toPlainText(html: string): string {
    return htmlToPlainText(html);
  }

  // 把一段(通常是单段落的)HTML 解析为行内节点(文字 + 行内 emoji 图片等),
  // 供 boost 气泡这类需要「文字与 emoji 混排」的短内容行内渲染。外层 <p>/<div> 会被忽略。
  static toInlineNodes(html: string): RichInlineNode[] {
    return parseInlines(html ? html : '');
  }

  private static parseBlocks(html: string): RichBlock[] {
    const blocks: RichBlock[] = [];
    let index: number = 0;
    let pendingInlineHtml: string = '';

    const flushPendingInline = (): void => {
      const inlines: RichInlineNode[] = parseInlines(pendingInlineHtml);
      pendingInlineHtml = '';
      if (hasVisibleInlines(inlines)) {
        blocks.push({
          type: RichBlockType.PARAGRAPH,
          inlines
        });
      }
    };

    while (index < html.length) {
      const nextTagStart: number = html.indexOf('<', index);
      if (nextTagStart < 0) {
        pendingInlineHtml = `${pendingInlineHtml}${html.substring(index)}`;
        break;
      }

      if (nextTagStart > index) {
        pendingInlineHtml = `${pendingInlineHtml}${html.substring(index, nextTagStart)}`;
      }

      const tagEnd: number = findTagEnd(html, nextTagStart);
      if (tagEnd < 0) {
        pendingInlineHtml = `${pendingInlineHtml}${html.substring(nextTagStart)}`;
        break;
      }

      const openTag: string = html.substring(nextTagStart, tagEnd + 1);
      if (isClosingTag(openTag)) {
        // 行内元素的闭标签(</a></span></strong>…)属于当前 pending 行内内容,必须保留;
        // 否则未包 <p> 的裸文本(如引用预览、blockquote 直排文本)里 <a>…</a> 会失衡,
        // 闭标签被丢弃后其后文本被误当作未闭合链接的一部分整段染蓝可点。仅块级闭标签可安全跳过。
        if (!isBlockTag(getTagName(openTag))) {
          pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        }
        index = tagEnd + 1;
        continue;
      }

      const tagName: string = getTagName(openTag);
      if (tagName.length === 0) {
        pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        index = tagEnd + 1;
        continue;
      }

      if (!isBlockTag(tagName)) {
        pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        index = tagEnd + 1;
        continue;
      }

      flushPendingInline();

      if (tagName === 'hr') {
        blocks.push({ type: RichBlockType.DIVIDER });
        index = tagEnd + 1;
        continue;
      }

      if (tagName === 'img') {
        const imageBlock: RichBlock | undefined = CookedHtmlParser.imageBlockFromTag(openTag, '');
        if (imageBlock) {
          blocks.push(imageBlock);
        }
        index = tagEnd + 1;
        continue;
      }

      const closeStart: number = findClosingTag(html, tagEnd + 1, tagName);
      if (closeStart < 0) {
        pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        index = tagEnd + 1;
        continue;
      }

      const closeEnd: number = findTagEnd(html, closeStart);
      if (closeEnd < 0) {
        index = html.length;
        continue;
      }

      const innerHtml: string = html.substring(tagEnd + 1, closeStart);
      blocks.push(...CookedHtmlParser.blockFromElement(tagName, openTag, innerHtml));
      index = closeEnd + 1;
    }

    flushPendingInline();
    return blocks;
  }

  private static blockFromElement(tagName: string, openTag: string, innerHtml: string): RichBlock[] {
    if (tagName === 'p') {
      // 只有 emoji 的段落也必须走 ImageSpan；否则会被下面的“单图段落”快路径提升为大图块。
      if (CookedHtmlParser.isEmojiOnlyParagraph(innerHtml)) {
        return CookedHtmlParser.paragraphBlocks(innerHtml);
      }
      const imageBlock: RichBlock | undefined = CookedHtmlParser.singleImageParagraph(innerHtml);
      if (imageBlock) {
        return [imageBlock];
      }
      const imageBlocks: RichBlock[] = CookedHtmlParser.imageContainerBlocks(innerHtml);
      if (imageBlocks.length > 0) {
        return imageBlocks;
      }
      // Discourse 会把 <audio>/<video> 裹进 <p>(内部还带一个降级 <a> 链接)。这里先把内嵌媒体
      // 提升为播放块,否则会落到 mixedBlocks/行内解析,只剩那条降级链接被当正文渲染成裸链接。
      const mediaBlocks: RichBlock[] | undefined = CookedHtmlParser.mediaParagraphBlocks(innerHtml);
      if (mediaBlocks) {
        return mediaBlocks;
      }
      return CookedHtmlParser.mixedBlocks(innerHtml);
    }

    if (isHeadingTag(tagName)) {
      return [{
        type: RichBlockType.HEADING,
        level: Number(tagName.substring(1)),
        inlines: parseInlines(innerHtml)
      }];
    }

    if (tagName === 'aside' && hasClass(openTag, 'quote')) {
      // Discourse 话题/帖子引用:头部(头像+标题链接+分类徽章)抽成结构化数据,正文取截断预览,
      // 渲染成带头部的引用卡。兼容新式 quote-title__text-content 与老式 <div class="title"> 两种标记。
      // 判据是标题里有没有指向话题的 <a> 链接:有=跨帖引用→卡片;无(同帖内引用楼层,只显示「用户名:」)
      // 或缺 data-topic → 返回 undefined,落到下方回退成普通引用。
      const topicQuote: RichBlock | undefined = CookedHtmlParser.topicQuoteFromAside(openTag, innerHtml);
      if (topicQuote) {
        return [topicQuote];
      }
    }

    if (tagName === 'blockquote' || (tagName === 'aside' && hasClass(openTag, 'quote'))) {
      let quoteBlocks: RichBlock[] = CookedHtmlParser.parseBlocks(innerHtml);
      if (tagName === 'aside') {
        // Discourse 引用：<aside class="quote"> 内的 <blockquote> 才是引用正文，
        // 展开它，避免正文再被包成一层带竖线的嵌套引用。
        quoteBlocks = CookedHtmlParser.unwrapNestedQuotes(quoteBlocks);
      } else {
        // 纯 <blockquote>(非 aside 用户引用):首段 [!type]± 命中则升级为 callout 提示框。
        const callout: RichBlock | undefined = CookedHtmlParser.calloutFromQuote(quoteBlocks);
        if (callout) {
          return [callout];
        }
      }
      return [{
        type: RichBlockType.QUOTE,
        blocks: quoteBlocks.length > 0 ? quoteBlocks : CookedHtmlParser.paragraphBlocks(innerHtml)
      }];
    }

    // Discourse 链接预览：<aside class="onebox ...">，或个别站点用 <div class="onebox">。
    // 抽出 header.source(favicon+域名) 与 article.onebox-body(标题/描述/缩略图)渲染成卡片。
    if ((tagName === 'aside' || tagName === 'div') && hasClassContaining(openTag, 'onebox')) {
      return [CookedHtmlParser.oneboxBlock(innerHtml)];
    }

    if (tagName === 'details') {
      return [CookedHtmlParser.disclosureBlockFromDetails(innerHtml)];
    }

    if (tagName === 'pre') {
      return [CookedHtmlParser.codeBlockFromPre(innerHtml)];
    }

    if (tagName === 'ul' || tagName === 'ol') {
      return [CookedHtmlParser.listBlockFromHtml(innerHtml, tagName === 'ol')];
    }

    // discourse-poll:<div class="poll" data-poll-name="...">。产出轻量 POLL 占位块(只带 name),
    // 保持它在正文流的正确位置;真正的票数/选项/交互由渲染层按 name 关联 TopicPost.polls 的动态数据。
    if (hasClassContaining(openTag, 'poll') ||
      extractAttr(openTag, 'data-poll-name').length > 0) {
      const pollName: string = extractAttr(openTag, 'data-poll-name');
      return [{
        type: RichBlockType.POLL,
        pollName: pollName.length > 0 ? pollName : 'poll'
      }];
    }

    // discourse-spoiler-alert 块级剧透:<div class="spoiler">(web 端揭示后变 spoiled)。
    // 内部照常递归解析,遮蔽交给渲染层,避免旧「待实现」占位把明文泄出来。
    if (hasClassContaining(openTag, 'spoiler') ||
      hasClassContaining(openTag, 'spoiled')) {
      const spoilerBlocks: RichBlock[] = CookedHtmlParser.parseBlocks(innerHtml);
      return [{
        type: RichBlockType.SPOILER,
        blocks: spoilerBlocks
      }];
    }

    if (tagName === 'audio' || tagName === 'video') {
      const mediaBlock: RichBlock | undefined = CookedHtmlParser.mediaBlockFromElement(tagName, openTag, innerHtml);
      if (mediaBlock) {
        return [mediaBlock];
      }
    }

    // discourse-math 块级公式:<div class="math">裸 LaTeX</div>。API 只给源码,排版交渲染层的
    // 离屏引擎;这里只抽出 LaTeX 存进 MATH 块的 text。须在 detectUnsupportedKind 之前拦截。
    if (hasClass(openTag, 'math')) {
      const latex: string = htmlToPlainText(innerHtml);
      return latex.length > 0 ? [{ type: RichBlockType.MATH, text: latex }] : [];
    }

    // Markdown 表格:<table> 直挂或裹在 <div class="md-table"> 里都在此拦截,抽成结构化块。
    // 须在 detectUnsupportedKind 之前(否则会落回「待实现:表格」占位)。解析失败(无有效行)返回
    // undefined,自然退回下方占位兜底。
    const tableBlock: RichBlock | undefined = CookedHtmlParser.tableBlockFrom(tagName, innerHtml);
    if (tableBlock) {
      return [tableBlock];
    }

    const unsupportedKind: string = CookedHtmlParser.detectUnsupportedKind(tagName, openTag, innerHtml);
    if (unsupportedKind.length > 0) {
      return [CookedHtmlParser.unsupportedBlock(unsupportedKind, innerHtml)];
    }

    if (tagName === 'figure' || tagName === 'div') {
      const imageBlocks: RichBlock[] = CookedHtmlParser.imageContainerBlocks(innerHtml);
      if (imageBlocks.length > 0) {
        return imageBlocks;
      }
      const text: string = htmlToPlainText(innerHtml);
      if (text.length > 0) {
        return CookedHtmlParser.mixedBlocks(innerHtml);
      }
    }

    const fallbackText: string = htmlToPlainText(innerHtml);
    if (fallbackText.length === 0) {
      return [];
    }
    return [{
      type: RichBlockType.UNSUPPORTED,
      text: fallbackText
    }];
  }

  private static paragraphBlocks(html: string): RichBlock[] {
    const inlines: RichInlineNode[] = parseInlines(html);
    if (!hasVisibleInlines(inlines)) {
      return [];
    }
    return [{
      type: RichBlockType.PARAGRAPH,
      inlines
    }];
  }

  // 解析 Discourse 话题引用 <aside class="quote" data-topic data-post> 的头部与预览。
  // 缺少目标 topic 时返回 undefined,让调用方回退成普通引用。
  private static topicQuoteFromAside(openTag: string, innerHtml: string): RichBlock | undefined {
    const topicId: number = parsePositiveNumber(extractAttr(openTag, 'data-topic'));
    if (topicId <= 0) {
      return undefined;
    }
    const postNumber: number = parsePositiveNumber(extractAttr(openTag, 'data-post'));

    // 头像:title 区里 class 含 avatar 的 <img>。
    const avatarTag: string = firstImgWithClass(innerHtml, 'avatar');
    const avatarUrl: string = avatarTag.length > 0
      ? resolveUrl(extractAttr(avatarTag, 'src')) : '';

    // 标题 + 链接:优先取新式 quote-title__text-content;取不到再退回老式 <div class="title"> 的内部。
    let titleContent: string = firstElementInnerByClass(innerHtml, 'quote-title__text-content');
    if (titleContent.length === 0) {
      titleContent = firstElementInnerByClass(innerHtml, 'title');
    }
    // 用户名(头像身份,兼作缺显示名时的兜底标题)。
    const username: string = decodeHtmlEntities(extractAttr(openTag, 'data-username'));

    // 标题文字取第一个 <a>(话题链接,class 无 badge)的内部;href 取该开标签的 href 属性。
    const titleAnchor: string = CookedHtmlParser.firstTopicTitleAnchor(titleContent);
    let title: string;
    let href: string;
    let category: TopicCategory | undefined;
    let isReply: boolean = false;
    if (titleAnchor.length > 0) {
      // 跨话题引用:title 里带话题链接 → 标题取链接文字、href 取链接、分类取徽章。
      title = decodeHtmlEntities(
        htmlToPlainText(firstElementInner(titleContent, 'a')));
      href = resolveUrl(extractAttr(titleAnchor, 'href'));
      // 分类徽章:badge-category span 上带 data-category-id + --category-badge-* 变量 + 名字 + 图标 svg。
      category = CookedHtmlParser.categoryFromBadge(titleContent);
    } else {
      isReply = true;
      // 同帖回复引用:title 只有「显示名:」无链接 → 用 aside 属性组卡。
      // 标题取 data-display-name(缺则退 data-username);跳转按 data-topic/data-post 自拼站内帖链接。
      let displayName: string = decodeHtmlEntities(extractAttr(openTag, 'data-display-name'));
      if (displayName.length === 0) {
        displayName = username;
      }
      title = displayName;
      href = resolveUrl(`/t/topic/${topicId}/${postNumber > 0 ? postNumber : 1}`);
      category = undefined;
    }

    // 正文预览:第一个 <blockquote> 的内部 HTML(截断预览),交渲染层内嵌解析。
    const preview: string = firstElementInner(innerHtml, 'blockquote');

    const block: RichBlock = {
      type: RichBlockType.TOPIC_QUOTE,
      text: preview,
      quoteTopicId: topicId,
      // 缺 data-post(如 [quote="user, topic:123"] 只带话题不带楼层)保持 0,不兜底成 1:
      // 否则展开 chevron 仍显示,一点会拉到该话题主楼(1楼)当"被引用全文",与卡片预览的引用片段不符。
      // 0 会让渲染层(quotePostNumber > 0)不显示展开箭头,只保留跳转,从根上避免拉错楼。
      quotePostNumber: postNumber
    };
    if (avatarUrl.length > 0) {
      block.quoteAvatarUrl = avatarUrl;
    }
    if (username.length > 0) {
      block.quoteAuthor = username;
    }
    if (title.length > 0) {
      block.quoteTitle = title;
    }
    if (href.length > 0) {
      block.href = href;
    }
    if (category) {
      block.quoteCategory = category;
    }
    if (isReply) {
      block.quoteIsReply = true;
    }
    return block;
  }

  // 从 title 区取第一个指向话题的 <a>(class 不含 badge-category)的完整开标签。
  private static firstTopicTitleAnchor(titleContent: string): string {
    const lower: string = titleContent.toLowerCase();
    let cursor: number = 0;
    while (cursor < titleContent.length) {
      const start: number = lower.indexOf('<a', cursor);
      if (start < 0) {
        return '';
      }
      const end: number = findTagEnd(titleContent, start);
      if (end < 0) {
        return '';
      }
      const tag: string = titleContent.substring(start, end + 1);
      if (!hasClassContaining(tag, 'badge-category')) {
        return tag;
      }
      cursor = end + 1;
    }
    return '';
  }

  // 从 badge-category__wrapper 里的 <span class="badge-category" ...> 抽出分类。缺 id/名字则返回 undefined。
  private static categoryFromBadge(titleContent: string): TopicCategory | undefined {
    const badgeInner: string = firstElementInnerByClass(titleContent, 'badge-category__wrapper');
    if (badgeInner.length === 0) {
      return undefined;
    }
    const spanOpen: string = firstOpenTagByClass(badgeInner, 'badge-category');
    const idText: string = extractAttr(spanOpen, 'data-category-id');
    const id: number = parsePositiveNumber(idText);
    const name: string = decodeHtmlEntities(
      htmlToPlainText(firstElementInnerByClass(badgeInner, 'badge-category__name')));
    if (name.length === 0) {
      return undefined;
    }
    const style: string = extractAttr(spanOpen, 'style');
    const color: string = cssVar(style, '--category-badge-color');
    const textColor: string = cssVar(style, '--category-badge-text-color');
    // 图标:徽章内最内层 <svg id="xxx">(外层是 fa 包装 svg)。取 id 作图标名交 getCategoryIcon 归一。
    const iconId: string = extractAttr(lastSvgWithId(badgeInner), 'id');

    const category: TopicCategory = {
      id: id > 0 ? id : 0,
      name,
      color: color.length > 0 ? color.replace('#', '') : '6B7280',
      textColor: textColor.length > 0 ? textColor.replace('#', '') : 'FFFFFF'
    };
    if (iconId.length > 0) {
      category.icon = iconId;
    }
    return category;
  }

  private static unwrapNestedQuotes(blocks: RichBlock[]): RichBlock[] {
    const out: RichBlock[] = [];
    for (let index: number = 0; index < blocks.length; index++) {
      const block: RichBlock = blocks[index];
      if (block.type === RichBlockType.QUOTE && block.blocks && block.blocks.length > 0) {
        for (let inner: number = 0; inner < block.blocks.length; inner++) {
          out.push(block.blocks[inner]);
        }
      } else {
        out.push(block);
      }
    }
    return out;
  }

  // 把已解析好的引用子块尝试识别为 callout。首段(段落)首个文本节点以 [!type]± 开头才算命中,
  // 否则返回 undefined 让调用方回退成普通引用。命中后:剥掉标记,首行(遇 <br> 截断)作标题,
  // 换行后的残余与其余子块作正文。
  private static calloutFromQuote(quoteBlocks: RichBlock[]): RichBlock | undefined {
    if (quoteBlocks.length === 0) {
      return undefined;
    }
    const first: RichBlock = quoteBlocks[0];
    if (first.type !== RichBlockType.PARAGRAPH || !first.inlines || first.inlines.length === 0) {
      return undefined;
    }
    const head: RichInlineNode = first.inlines[0];
    if (head.type !== RichInlineType.TEXT) {
      return undefined;
    }
    const match: RegExpMatchArray | null = head.text.match(CALLOUT_MARKER);
    if (!match) {
      return undefined;
    }

    const rawType: string = match[1].toLowerCase();
    const fold: string = match[2] ? match[2] : '';
    const style: CalloutStyle = CookedHtmlParser.resolveCalloutStyle(rawType);

    // 去掉首文本节点里的 [!type]± 标记(其余标题文本/样式保留)。
    head.text = head.text.replace(CALLOUT_MARKER, '');

    // 标题段可能内含 <br>:换行前为标题,换行后回落成正文首段。
    const firstLineInlines: RichInlineNode[] = [];
    const overflowInlines: RichInlineNode[] = [];
    let hitBreak: boolean = false;
    for (let i: number = 0; i < first.inlines.length; i++) {
      const node: RichInlineNode = first.inlines[i];
      if (!hitBreak && node.type === RichInlineType.LINE_BREAK) {
        hitBreak = true;
        continue;
      }
      if (hitBreak) {
        overflowInlines.push(node);
      } else {
        firstLineInlines.push(node);
      }
    }

    const titleInlines: RichInlineNode[] = trimLeadingEmptyText(firstLineInlines);

    const contentBlocks: RichBlock[] = [];
    if (overflowInlines.length > 0 && hasVisibleInlines(overflowInlines)) {
      contentBlocks.push({
        type: RichBlockType.PARAGRAPH,
        inlines: overflowInlines
      });
    }
    for (let i: number = 1; i < quoteBlocks.length; i++) {
      contentBlocks.push(quoteBlocks[i]);
    }

    return {
      type: RichBlockType.CALLOUT,
      calloutKind: style.kind,
      calloutColor: style.color,
      calloutIcon: style.icon,
      collapsible: fold.length > 0,
      defaultExpanded: fold !== '-',
      titleInlines,
      blocks: contentBlocks
    };
  }

  // 类型 → 主色/图标。先按别名归一,再查样式表;未命中用 fallback 色/图标,kind 保留原始串。
  private static resolveCalloutStyle(rawType: string): CalloutStyle {
    const alias: string | undefined = CALLOUT_ALIASES.get(rawType);
    const canonical: string = alias ? alias : rawType;
    const def: CalloutStyleDef | undefined = CALLOUT_STYLES.get(canonical);
    if (def) {
      return { kind: canonical, color: def.color, icon: def.icon };
    }
    return { kind: rawType, color: CALLOUT_FALLBACK.color, icon: CALLOUT_FALLBACK.icon };
  }

  private static codeBlockFromPre(innerHtml: string): RichBlock {
    const codeOpenMatch: RegExpMatchArray | null = innerHtml.match(/<code\b[^>]*>/i);
    const codeOpenTag: string = codeOpenMatch ? codeOpenMatch[0] : '';
    let codeHtml: string = innerHtml;
    if (codeOpenMatch) {
      const openEnd: number = innerHtml.indexOf(codeOpenTag) + codeOpenTag.length;
      const closeStart: number = innerHtml.toLowerCase().lastIndexOf('</code>');
      if (closeStart >= openEnd) {
        codeHtml = innerHtml.substring(openEnd, closeStart);
      }
    }

    return {
      type: RichBlockType.CODE,
      text: decodeHtmlEntities(stripTagsKeepingLines(codeHtml)).trim(),
      language: extractCodeLanguage(codeOpenTag)
    };
  }

  private static listBlockFromHtml(innerHtml: string, ordered: boolean): RichBlock {
    const items: RichListItem[] = [];
    let index: number = 0;
    const lower: string = innerHtml.toLowerCase();
    while (index < innerHtml.length) {
      const openStart: number = lower.indexOf('<li', index);
      if (openStart < 0) {
        break;
      }
      const openEnd: number = findTagEnd(innerHtml, openStart);
      if (openEnd < 0) {
        break;
      }
      const closeStart: number = findClosingTag(innerHtml, openEnd + 1, 'li');
      if (closeStart < 0) {
        break;
      }
      const closeEnd: number = findTagEnd(innerHtml, closeStart);
      const itemHtml: string = innerHtml.substring(openEnd + 1, closeStart);
      // 列表项里裹了块级图(lightbox/大图)时,走 mixedBlocks 把文字与图片拆成块级序列;
      // 纯文字/行内(含 emoji)项保持原有的行内快路径。findImageUnit 只认块级图,emoji 不触发。
      if (CookedHtmlParser.findImageUnit(itemHtml) !== undefined) {
        items.push({
          inlines: [],
          blocks: CookedHtmlParser.mixedBlocks(itemHtml)
        });
      } else {
        items.push({
          inlines: parseInlines(itemHtml)
        });
      }
      index = closeEnd >= 0 ? closeEnd + 1 : closeStart + 5;
    }

    return {
      type: RichBlockType.LIST,
      ordered,
      items
    };
  }

  // 从 <table>(或含 <table> 的包裹元素,如 <div class="md-table">)抽出结构化表格块。
  // 无有效行时返回 undefined,交由调用方回退到占位。
  private static tableBlockFrom(tagName: string, innerHtml: string): RichBlock | undefined {
    let tableInner: string = '';
    if (tagName === 'table') {
      tableInner = innerHtml;
    } else if (innerHtml.toLowerCase().indexOf('<table') >= 0) {
      tableInner = extractElementInner(innerHtml, 'table');
    }
    if (tableInner.length === 0) {
      return undefined;
    }

    const rows: RichTableRow[] = CookedHtmlParser.tableRowsFromHtml(tableInner);
    if (rows.length === 0) {
      return undefined;
    }
    return {
      type: RichBlockType.TABLE,
      tableRows: rows
    };
  }

  private static tableRowsFromHtml(tableHtml: string): RichTableRow[] {
    const rows: RichTableRow[] = [];
    let search: number = 0;
    while (search < tableHtml.length) {
      const trStart: number = findOpenTag(tableHtml, 'tr', search);
      if (trStart < 0) {
        break;
      }
      const trOpenEnd: number = findTagEnd(tableHtml, trStart);
      if (trOpenEnd < 0) {
        break;
      }
      const trClose: number = findClosingTag(tableHtml, trOpenEnd + 1, 'tr');
      if (trClose < 0) {
        break;
      }
      const rowHtml: string = tableHtml.substring(trOpenEnd + 1, trClose);
      const cells: RichTableCell[] = CookedHtmlParser.tableCellsFromRow(rowHtml);
      if (cells.length > 0) {
        const allHeader: boolean = cells.every((cell: RichTableCell) => cell.header === true);
        rows.push({ cells, header: allHeader });
      }
      const trCloseEnd: number = findTagEnd(tableHtml, trClose);
      search = trCloseEnd >= 0 ? trCloseEnd + 1 : trClose + 1;
    }
    return rows;
  }

  private static tableCellsFromRow(rowHtml: string): RichTableCell[] {
    const cells: RichTableCell[] = [];
    let index: number = 0;
    while (index < rowHtml.length) {
      const thStart: number = findOpenTag(rowHtml, 'th', index);
      const tdStart: number = findOpenTag(rowHtml, 'td', index);
      if (thStart < 0 && tdStart < 0) {
        break;
      }
      const isHeader: boolean = thStart >= 0 && (tdStart < 0 || thStart < tdStart);
      const cellStart: number = isHeader ? thStart : tdStart;
      const cellTag: string = isHeader ? 'th' : 'td';
      const openEnd: number = findTagEnd(rowHtml, cellStart);
      if (openEnd < 0) {
        break;
      }
      const closeStart: number = findClosingTag(rowHtml, openEnd + 1, cellTag);
      if (closeStart < 0) {
        break;
      }
      const cellHtml: string = rowHtml.substring(openEnd + 1, closeStart);
      cells.push({
        inlines: parseInlines(cellHtml),
        header: isHeader
      });
      const closeEnd: number = findTagEnd(rowHtml, closeStart);
      index = closeEnd >= 0 ? closeEnd + 1 : closeStart + 1;
    }
    return cells;
  }

  private static unsupportedBlock(kind: string, innerHtml: string): RichBlock {
    const text: string = htmlToPlainText(innerHtml);
    return {
      type: RichBlockType.UNSUPPORTED,
      unsupportedKind: kind,
      text: text.length > 0 ? text : `${kind}待实现`
    };
  }

  private static disclosureBlockFromDetails(innerHtml: string): RichBlock {
    const summaryInfo: SummaryInfo = CookedHtmlParser.extractSummary(innerHtml);
    const contentBlocks: RichBlock[] = CookedHtmlParser.parseBlocks(summaryInfo.contentHtml);
    return {
      type: RichBlockType.DISCLOSURE,
      title: summaryInfo.title.length > 0 ? summaryInfo.title : '详情',
      blocks: contentBlocks.length > 0 ? contentBlocks : CookedHtmlParser.paragraphBlocks(summaryInfo.contentHtml)
    };
  }

  private static oneboxBlock(innerHtml: string): RichBlock {
    const block: RichBlock = { type: RichBlockType.ONEBOX };

    // 头部 <header class="source">:站点图标 + 域名文字。缺失时退回整段查找。
    const headerInner: string = extractElementInner(innerHtml, 'header');
    const headerHtml: string = headerInner.length > 0 ? headerInner : innerHtml;
    const faviconTag: string = firstTagMatch(headerHtml, /<img\b[^>]*>/i);
    if (faviconTag.length > 0) {
      const favSrc: string = resolveUrl(extractAttr(faviconTag, 'src'));
      if (favSrc.length > 0) {
        block.faviconUrl = favSrc;
      }
    }
    const domainText: string = firstAnchorText(headerHtml);
    const sourceHref: string = firstAnchorHref(headerHtml);

    // 正文 <article class="onebox-body">:标题(h3/h4)、描述(首个 p)、缩略图。
    const bodyInner: string = extractElementInner(innerHtml, 'article');
    const bodyHtml: string = bodyInner.length > 0 ? bodyInner : innerHtml;

    let titleHtml: string = extractElementInner(bodyHtml, 'h3');
    if (titleHtml.length === 0) {
      titleHtml = extractElementInner(bodyHtml, 'h4');
    }
    const title: string = htmlToPlainText(titleHtml);
    const titleHref: string = firstAnchorHref(titleHtml);

    const description: string = htmlToPlainText(extractElementInner(bodyHtml, 'p'));

    const thumbTag: string = firstTagMatch(bodyHtml, /<img\b[^>]*>/i);
    if (thumbTag.length > 0) {
      const thumbSrc: string = resolveUrl(extractAttr(thumbTag, 'src'));
      if (thumbSrc.length > 0) {
        block.thumbnailUrl = thumbSrc;
      }
    }

    const href: string = titleHref.length > 0 ? titleHref : sourceHref;
    if (href.length > 0) {
      block.href = href;
    }
    const domain: string = domainText.length > 0 ? domainText : hostFromUrl(href);
    if (domain.length > 0) {
      block.domain = domain;
    }
    if (title.length > 0) {
      block.title = title;
    }
    if (description.length > 0) {
      block.description = description;
    }
    return block;
  }

  private static extractSummary(innerHtml: string): SummaryInfo {
    const openMatch: RegExpMatchArray | null = innerHtml.match(/<summary\b[^>]*>/i);
    if (!openMatch) {
      return {
        title: '详情',
        contentHtml: innerHtml
      };
    }

    const openStart: number = innerHtml.indexOf(openMatch[0]);
    const openEnd: number = openStart + openMatch[0].length;
    const closeStart: number = innerHtml.toLowerCase().indexOf('</summary>', openEnd);
    if (closeStart < 0) {
      return {
        title: '详情',
        contentHtml: innerHtml
      };
    }

    const closeEnd: number = closeStart + '</summary>'.length;
    const summaryHtml: string = innerHtml.substring(openEnd, closeStart);
    return {
      title: htmlToPlainText(summaryHtml),
      contentHtml: `${innerHtml.substring(0, openStart)}${innerHtml.substring(closeEnd)}`
    };
  }

  private static detectUnsupportedKind(tagName: string, openTag: string, innerHtml: string): string {
    const combined: string = `${openTag}\n${innerHtml}`.toLowerCase();
    if (hasClassContaining(openTag, 'poll') ||
      extractAttr(openTag, 'data-poll-name').length > 0 ||
      combined.indexOf('data-poll-name') >= 0) {
      return '投票';
    }

    if (tagName === 'table' || combined.indexOf('<table') >= 0) {
      return '表格';
    }

    // <video>/<audio> 已由 mediaBlockFromElement 提升为播放块,这里只兜住 iframe 类嵌入(YouTube/B 站等)。
    if (tagName === 'iframe' || combined.indexOf('<iframe') >= 0) {
      return '视频/嵌入内容';
    }

    if (hasClassContaining(openTag, 'onebox')) {
      return '链接预览';
    }

    if (hasClassContaining(openTag, 'math') ||
      combined.indexOf('math-container') >= 0 ||
      combined.indexOf('<math') >= 0) {
      return '数学公式';
    }

    return '';
  }

  private static singleImageParagraph(innerHtml: string): RichBlock | undefined {
    const withoutBreaks: string = innerHtml.replace(/<br\s*\/?>/gi, '').trim();
    const imageMatch: RegExpMatchArray | null = withoutBreaks.match(/^<img\b[^>]*>$/i);
    if (imageMatch) {
      return CookedHtmlParser.imageBlockFromTag(imageMatch[0], '');
    }

    const linkedImageMatch: RegExpMatchArray | null = withoutBreaks.match(/^<a\b[^>]*>(<img\b[^>]*>)<\/a>$/i);
    if (linkedImageMatch) {
      const linkMatch: RegExpMatchArray | null = withoutBreaks.match(/^<a\b[^>]*>/i);
      return CookedHtmlParser.imageBlockFromTag(linkedImageMatch[1], linkMatch ? extractAttr(linkMatch[0], 'href') : '');
    }

    const uploadPreviewMatch: RegExpMatchArray | null =
      withoutBreaks.match(/^<a\b[^>]*>(<img\b[^>]*>)<\/a>\s*<a\b[^>]*>[^<]*<\/a>$/i);
    if (uploadPreviewMatch) {
      const linkMatch: RegExpMatchArray | null = withoutBreaks.match(/^<a\b[^>]*>/i);
      return CookedHtmlParser.imageBlockFromTag(uploadPreviewMatch[1], linkMatch ? extractAttr(linkMatch[0], 'href') : '');
    }
    return undefined;
  }

  private static isEmojiOnlyParagraph(innerHtml: string): boolean {
    const imageTags: RegExpMatchArray | null = innerHtml.match(/<img\b[^>]*>/gi);
    if (!imageTags || imageTags.length === 0) {
      return false;
    }
    for (let index: number = 0; index < imageTags.length; index++) {
      if (!hasClassContaining(imageTags[index], 'emoji')) {
        return false;
      }
    }
    const residual: string = innerHtml
      .replace(/<img\b[^>]*>/gi, '')
      .replace(/<br\s*\/?>/gi, '')
      .trim();
    return residual.length === 0;
  }

  private static imageContainerBlocks(innerHtml: string): RichBlock[] {
    // Discourse 上传图片会包成 <div class="lightbox-wrapper"><a class="lightbox" href="原图">
    // <img src="优化图"><div class="meta">文件名/尺寸/大小</div></a></div>。
    // 去掉 meta 元信息与图标后若无实质文字，则视为纯图片容器，逐张渲染为图片块，
    // 忽略文件名与尺寸文字（否则会退化成一个 18px 小图标 + 蓝色链接）。
    const withoutMeta: string = innerHtml
      .replace(/<div\b[^>]*class\s*=\s*["'][^"']*meta[^"']*["'][^>]*>[\s\S]*?<\/div>/gi, '')
      .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, '');
    const residualText: string = htmlToPlainText(withoutMeta.replace(/<img\b[^>]*>/gi, ''));
    if (residualText.length > 0) {
      return [];
    }
    return CookedHtmlParser.collectImageBlocks(innerHtml);
  }

  private static collectImageBlocks(html: string): RichBlock[] {
    const blocks: RichBlock[] = [];
    let index: number = 0;
    let pendingHref: string = '';

    while (index < html.length) {
      const nextTag: number = html.indexOf('<', index);
      if (nextTag < 0) {
        break;
      }
      const tagEnd: number = findTagEnd(html, nextTag);
      if (tagEnd < 0) {
        break;
      }

      const tag: string = html.substring(nextTag, tagEnd + 1);
      const name: string = getTagName(tag);
      if (name === 'a') {
        pendingHref = isClosingTag(tag) ? '' : extractAttr(tag, 'href');
      } else if (name === 'img' && !isClosingTag(tag)) {
        const block: RichBlock | undefined = CookedHtmlParser.imageBlockFromTag(tag, pendingHref);
        if (block) {
          blocks.push(block);
        }
      }

      index = tagEnd + 1;
    }

    return blocks;
  }

  private static mixedBlocks(innerHtml: string): RichBlock[] {
    // 处理"图 + 文字混排"容器：Discourse 会把图片和正文塞进同一个 <p>，例如
    // <p><div class="lightbox-wrapper">图</div><br>文字</p>，或未套 lightbox 的独立大图/动图
    // <p>文字<br><img class="animated" width="690"></p>。按"图片单元"切分：图片各自成 IMAGE 块、
    // 文字成段落，避免大图退化成一个 18px 行内小图。
    const result: RichBlock[] = [];
    let rest: string = innerHtml;
    let guard: number = 0;
    while (rest.length > 0 && guard < 200) {
      guard++;
      const unit: LightboxUnit | undefined = CookedHtmlParser.findImageUnit(rest);
      if (!unit) {
        result.push(...CookedHtmlParser.paragraphBlocks(rest));
        break;
      }
      if (htmlToPlainText(unit.before).length > 0) {
        result.push(...CookedHtmlParser.paragraphBlocks(unit.before));
      }
      result.push(...CookedHtmlParser.collectImageBlocks(unit.html));
      rest = unit.after;
    }
    return result;
  }

  // 从混排 HTML 中切出下一个"图片单元"：优先匹配 lightbox 容器(div/a),其次匹配未被 lightbox
  // 包裹的独立大图/动图 <img>(见 isBlockLevelImageTag)。lightbox 容器的开标签总在其内部 <img>
  // 之前出现,故会先命中容器、整段切出,不会把容器内的图当独立图误切。
  private static findImageUnit(html: string): LightboxUnit | undefined {
    const lower: string = html.toLowerCase();
    let cursor: number = 0;
    while (cursor < html.length) {
      const tagStart: number = lower.indexOf('<', cursor);
      if (tagStart < 0) {
        return undefined;
      }
      const tagEnd: number = findTagEnd(html, tagStart);
      if (tagEnd < 0) {
        return undefined;
      }
      const tag: string = html.substring(tagStart, tagEnd + 1);
      const name: string = getTagName(tag);
      if ((name === 'div' || name === 'a') && !isClosingTag(tag) &&
        hasClassContaining(tag, 'lightbox')) {
        const closeStart: number = findClosingTag(html, tagEnd + 1, name);
        if (closeStart < 0) {
          return undefined;
        }
        const closeEnd: number = findTagEnd(html, closeStart);
        const unitEnd: number = closeEnd >= 0 ? closeEnd + 1 : closeStart;
        const unit: LightboxUnit = {
          before: html.substring(0, tagStart),
          html: html.substring(tagStart, unitEnd),
          after: html.substring(unitEnd)
        };
        return unit;
      }
      if (name === 'img' && !isClosingTag(tag) &&
        CookedHtmlParser.isBlockLevelImageTag(tag)) {
        const unit: LightboxUnit = {
          before: html.substring(0, tagStart),
          html: tag,
          after: html.substring(tagEnd + 1)
        };
        return unit;
      }
      cursor = tagEnd + 1;
    }
    return undefined;
  }

  // 判断一个独立 <img> 是否应按整幅图片块渲染:emoji 永远行内;动图(class="animated")或标注了
  // 大尺寸(宽或高 > INLINE_IMAGE_MAX)的图提升为块级。无尺寸又非动图的裸图保持行内(安全默认)。
  private static isBlockLevelImageTag(tag: string): boolean {
    if (hasClassContaining(tag, 'emoji')) {
      return false;
    }
    if (hasClassContaining(tag, 'animated')) {
      return true;
    }
    const width: number = parsePositiveNumber(extractAttr(tag, 'width'));
    const height: number = parsePositiveNumber(extractAttr(tag, 'height'));
    return width > INLINE_IMAGE_MAX || height > INLINE_IMAGE_MAX;
  }

  private static imageBlockFromTag(tag: string, href: string): RichBlock | undefined {
    // 优先取 srcset 里倍率最高的那档(通常 2x),而不是 src。
    // Discourse 的 src 是按 CSS 像素切的最小档(如 253×375),手机普遍 3x DPI,直接渲染必糊;
    // srcset 一般给到 2x(506×750),清晰度够且远小于原图(href,如 940×1388/132KB)——
    // 正文图最宽也就铺满屏宽,上原图纯属浪费流量与解码内存。
    const src: string = resolveUrl(
      bestSrcFromTag(tag));
    if (src.length === 0) {
      return undefined;
    }

    const block: RichBlock = {
      type: RichBlockType.IMAGE,
      src,
      alt: decodeHtmlEntities(extractAttr(tag, 'alt')),
      width: parsePositiveNumber(extractAttr(tag, 'width')),
      height: parsePositiveNumber(extractAttr(tag, 'height'))
    };

    const resolvedHref: string = resolveUrl(href);
    if (resolvedHref.length > 0) {
      block.href = resolvedHref;
    }
    return block;
  }

  // 从段落 HTML 中切出内嵌的 <audio>/<video>,提升为媒体块;媒体前后残留的文字各自成段。媒体元素
  // 内部的 <source> 与降级 <a> 链接连同整个媒体标签一并被切走,不会再作为正文链接重复渲染。
  // 未命中任何媒体则返回 undefined,交回上层走 mixedBlocks。
  private static mediaParagraphBlocks(innerHtml: string): RichBlock[] | undefined {
    const result: RichBlock[] = [];
    let rest: string = innerHtml;
    let found: boolean = false;
    let guard: number = 0;
    while (guard < 50) {
      guard++;
      const lower: string = rest.toLowerCase();
      const audioAt: number = lower.indexOf('<audio');
      const videoAt: number = lower.indexOf('<video');
      let tagStart: number = -1;
      let mediaTag: string = '';
      if (audioAt >= 0 && (videoAt < 0 || audioAt < videoAt)) {
        tagStart = audioAt;
        mediaTag = 'audio';
      } else if (videoAt >= 0) {
        tagStart = videoAt;
        mediaTag = 'video';
      }
      if (tagStart < 0) {
        break;
      }
      const tagEnd: number = findTagEnd(rest, tagStart);
      if (tagEnd < 0) {
        break;
      }
      const openTag: string = rest.substring(tagStart, tagEnd + 1);
      const closeStart: number = findClosingTag(rest, tagEnd + 1, mediaTag);
      if (closeStart < 0) {
        break;
      }
      const closeEnd: number = findTagEnd(rest, closeStart);
      const mediaInner: string = rest.substring(tagEnd + 1, closeStart);
      const mediaBlock: RichBlock | undefined = CookedHtmlParser.mediaBlockFromElement(mediaTag, openTag, mediaInner);
      if (!mediaBlock) {
        break;
      }
      const before: string = rest.substring(0, tagStart);
      if (htmlToPlainText(before).length > 0) {
        result.push(...CookedHtmlParser.paragraphBlocks(before));
      }
      result.push(mediaBlock);
      found = true;
      rest = closeEnd >= 0 ? rest.substring(closeEnd + 1) : '';
    }
    if (!found) {
      return undefined;
    }
    if (htmlToPlainText(rest).length > 0) {
      result.push(...CookedHtmlParser.paragraphBlocks(rest));
    }
    return result;
  }

  // <audio>/<video> → 媒体块。源优先取内部首个 <source src>(其 type 作 MIME),缺失时回退标签自身 src。
  // <video> 额外带 width/height 供渲染定尺寸。无有效 src 则返回 undefined,交回上层走「不支持」降级。
  private static mediaBlockFromElement(tagName: string, openTag: string, innerHtml: string): RichBlock | undefined {
    let src: string = '';
    let mediaType: string = '';
    const sourceMatch: RegExpMatchArray | null = innerHtml.match(/<source\b[^>]*>/i);
    if (sourceMatch) {
      src = extractAttr(sourceMatch[0], 'src');
      mediaType = extractAttr(sourceMatch[0], 'type');
    }
    if (src.length === 0) {
      src = extractAttr(openTag, 'src');
    }
    const resolvedSrc: string = resolveUrl(src);
    if (resolvedSrc.length === 0) {
      return undefined;
    }

    const block: RichBlock = {
      type: tagName === 'video' ? RichBlockType.VIDEO : RichBlockType.AUDIO,
      src: resolvedSrc
    };
    if (mediaType.length > 0) {
      block.mediaType = mediaType;
    }
    if (tagName === 'video') {
      block.width = parsePositiveNumber(extractAttr(openTag, 'width'));
      block.height = parsePositiveNumber(extractAttr(openTag, 'height'));
    }
    return block;
  }

  private static hasBlockContent(block: RichBlock): boolean {
    if (block.type === RichBlockType.PARAGRAPH || block.type === RichBlockType.HEADING) {
      return !!block.inlines && block.inlines.length > 0;
    }
    if (block.type === RichBlockType.QUOTE) {
      return !!block.blocks && block.blocks.length > 0;
    }
    if (block.type === RichBlockType.CODE || block.type === RichBlockType.MATH) {
      return !!block.text && block.text.length > 0;
    }
    if (block.type === RichBlockType.UNSUPPORTED) {
      return (!!block.text && block.text.length > 0) || (!!block.unsupportedKind && block.unsupportedKind.length > 0);
    }
    if (block.type === RichBlockType.IMAGE ||
      block.type === RichBlockType.AUDIO ||
      block.type === RichBlockType.VIDEO) {
      return !!block.src && block.src.length > 0;
    }
    if (block.type === RichBlockType.LIST) {
      return !!block.items && block.items.length > 0;
    }
    if (block.type === RichBlockType.TABLE) {
      return !!block.tableRows && block.tableRows.length > 0;
    }
    if (block.type === RichBlockType.DISCLOSURE) {
      return (!!block.title && block.title.length > 0) || (!!block.blocks && block.blocks.length > 0);
    }
    if (block.type === RichBlockType.SPOILER) {
      return !!block.blocks && block.blocks.length > 0;
    }
    if (block.type === RichBlockType.CALLOUT) {
      // 有标题或有正文即保留;二者皆空的极端情形也留着(至少能显示类型名标题)。
      return true;
    }
    if (block.type === RichBlockType.POLL) {
      // POLL 块无 inlines/blocks,仅靠 pollName 占位,别被内容过滤器丢掉。
      return true;
    }
    if (block.type === RichBlockType.ONEBOX) {
      return (!!block.href && block.href.length > 0) ||
        (!!block.title && block.title.length > 0) ||
        (!!block.domain && block.domain.length > 0);
    }
    return true;
  }
}
