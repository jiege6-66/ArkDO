// 行内解析层:把一段 HTML 解析为行内节点序列(文字/链接/行内代码/行内图片/行内公式/换行)。
// 只依赖内容工具(HtmlContentUtils)与词法/属性层,不依赖块级解析核心,故无循环依赖。
import { RichInlineNode, RichInlineType } from './RichContentTypes';
import { decodeHtmlEntities, htmlToPlainText, resolveUrl } from './HtmlContentUtils';
import { findClosingTag, findTagEnd, getTagName, isClosingTag, isSelfClosingTag,
  shouldReadChildrenAsPlainText } from './html/HtmlLexer';
import { extractAttr, hasClass, hasClassContaining } from './html/HtmlAttrs';

class InlineState {
  bold: number = 0;
  italic: number = 0;
  code: number = 0;
  hrefStack: string[] = [];
  // 与 hrefStack 同步入栈:当前链接是否为附件下载链接。
  attachmentStack: boolean[] = [];
  // 每遇到一个 <span> 就入栈(是否带 spoiler class);</span> 出栈。
  // 闭合标签不带 class,只能整体跟踪 span 嵌套才能正确配对。
  spanSpoilerStack: boolean[] = [];

  clone(): InlineState {
    const state: InlineState = new InlineState();
    state.bold = this.bold;
    state.italic = this.italic;
    state.code = this.code;
    state.hrefStack = this.hrefStack.slice();
    state.attachmentStack = this.attachmentStack.slice();
    state.spanSpoilerStack = this.spanSpoilerStack.slice();
    return state;
  }

  currentHref(): string {
    if (this.hrefStack.length === 0) {
      return '';
    }
    return this.hrefStack[this.hrefStack.length - 1];
  }

  currentAttachment(): boolean {
    if (this.attachmentStack.length === 0) {
      return false;
    }
    return this.attachmentStack[this.attachmentStack.length - 1];
  }

  currentSpoiler(): boolean {
    for (let index: number = 0; index < this.spanSpoilerStack.length; index++) {
      if (this.spanSpoilerStack[index]) {
        return true;
      }
    }
    return false;
  }
}

export function parseInlines(html: string): RichInlineNode[] {
  const out: RichInlineNode[] = [];
  const state: InlineState = new InlineState();
  let buffer: string = '';
  let index: number = 0;

  const appendText = (raw: string): void => {
    let text: string = decodeHtmlEntities(raw);
    if (text.length === 0) {
      return;
    }
    // HTML 语义:源码里的换行/缩进/连续空格是不可见排版空白,浏览器折叠成单个空格。此前解析器
    // 原样保留,导致 <br> 后紧跟的源码换行(<br>\n2.1)多出一个真换行,<br> 行距凭空翻倍。
    // 折叠这类空白(nbsp   不在其列,予以保留)。
    text = text.replace(/[ \t\r\n\f]+/g, ' ');
    // 段首及 <br>/段落换行之后的行首空白不可见,去掉,避免每行多一个前导空格。
    const prevNode: RichInlineNode | undefined = out.length > 0 ? out[out.length - 1] : undefined;
    if (!prevNode || prevNode.type === RichInlineType.LINE_BREAK) {
      text = text.replace(/^ /, '');
    }
    if (text.length === 0) {
      return;
    }

    const href: string = state.currentHref();
    const type: RichInlineType = state.code > 0 ? RichInlineType.CODE : (href.length > 0 ? RichInlineType.LINK : RichInlineType.TEXT);
    const attachment: boolean = type === RichInlineType.LINK && state.currentAttachment();
    const spoiler: boolean = state.currentSpoiler();
    const last: RichInlineNode | undefined = out.length > 0 ? out[out.length - 1] : undefined;
    if (last &&
      last.type === type &&
      (last.href ? last.href : '') === href &&
      !!last.attachment === attachment &&
      !!last.spoiler === spoiler &&
      !!last.bold === state.bold > 0 &&
      !!last.italic === state.italic > 0 &&
      !!last.code === state.code > 0) {
      last.text = `${last.text}${text}`;
      return;
    }

    const token: RichInlineNode = {
      type,
      text,
      bold: state.bold > 0,
      italic: state.italic > 0,
      code: state.code > 0
    };
    if (href.length > 0) {
      token.href = href;
    }
    if (attachment) {
      token.attachment = true;
    }
    if (spoiler) {
      token.spoiler = true;
    }
    out.push(token);
  };

  const flush = (): void => {
    if (buffer.length === 0) {
      return;
    }
    appendText(buffer);
    buffer = '';
  };

  while (index < html.length) {
    const tagStart: number = html.indexOf('<', index);
    if (tagStart < 0) {
      buffer = `${buffer}${html.substring(index)}`;
      break;
    }

    if (tagStart > index) {
      buffer = `${buffer}${html.substring(index, tagStart)}`;
    }

    const tagEnd: number = findTagEnd(html, tagStart);
    if (tagEnd < 0) {
      buffer = `${buffer}${html.substring(tagStart)}`;
      break;
    }

    const tag: string = html.substring(tagStart, tagEnd + 1);
    const tagName: string = getTagName(tag);
    const closing: boolean = isClosingTag(tag);
    const selfClosing: boolean = isSelfClosingTag(tag);

    if (tagName === 'br') {
      flush();
      out.push({ type: RichInlineType.LINE_BREAK, text: '\n' });
    } else if (tagName === 'strong' || tagName === 'b') {
      flush();
      state.bold = Math.max(0, state.bold + (closing ? -1 : 1));
    } else if (tagName === 'em' || tagName === 'i') {
      flush();
      state.italic = Math.max(0, state.italic + (closing ? -1 : 1));
    } else if (tagName === 'code') {
      flush();
      state.code = Math.max(0, state.code + (closing ? -1 : 1));
    } else if (tagName === 'span') {
      // discourse-math 行内公式:<span class="math">裸 LaTeX</span>。整体抽成一个 MATH token,
      // 里面的 LaTeX 不再当纯文本泄进正文流(否则会显示 \frac{...} 之类源码)。
      if (!closing && !selfClosing && hasClass(tag, 'math')) {
        flush();
        const mathClose: number = findClosingTag(html, tagEnd + 1, 'span');
        if (mathClose > tagEnd) {
          const latex: string = htmlToPlainText(html.substring(tagEnd + 1, mathClose));
          if (latex.length > 0) {
            out.push({ type: RichInlineType.MATH, text: latex });
          }
          const mathCloseEnd: number = findTagEnd(html, mathClose);
          index = mathCloseEnd >= 0 ? mathCloseEnd + 1 : mathClose;
          continue;
        }
      }
      flush();
      if (closing) {
        state.spanSpoilerStack.pop();
      } else if (!selfClosing) {
        state.spanSpoilerStack.push(hasClassContaining(tag, 'spoiler'));
      }
    } else if (tagName === 'a') {
      flush();
      if (closing) {
        state.hrefStack.pop();
        state.attachmentStack.pop();
      } else {
        const resolvedHref: string = resolveUrl(extractAttr(tag, 'href'));
        state.hrefStack.push(resolvedHref);
        // 附件下载链接:显式 class="attachment",或指向 /uploads/ 的站内链接。
        const isAttachment: boolean = hasClass(tag, 'attachment') ||
          /^https?:\/\/[^\/]*linux\.do\/uploads\//i.test(resolvedHref) ||
          resolvedHref.indexOf('/uploads/') === 0;
        state.attachmentStack.push(isAttachment);
      }
    } else if (tagName === 'img' && !closing) {
      flush();
      const src: string = resolveUrl(extractAttr(tag, 'src'));
      const alt: string = decodeHtmlEntities(extractAttr(tag, 'alt'));
      if (src.length > 0) {
        const imageToken: RichInlineNode = {
          type: RichInlineType.IMAGE,
          text: alt.length > 0 ? alt : ' ',
          src,
          alt,
          href: state.currentHref()
        };
        if (state.currentSpoiler()) {
          imageToken.spoiler = true;
        }
        out.push(imageToken);
      } else if (alt.length > 0) {
        appendText(alt);
      }
    } else if (!selfClosing && !closing && shouldReadChildrenAsPlainText(tagName)) {
      const closeStart: number = findClosingTag(html, tagEnd + 1, tagName);
      if (closeStart > tagEnd) {
        const inner: string = html.substring(tagEnd + 1, closeStart);
        appendText(htmlToPlainText(inner));
        const closeEnd: number = findTagEnd(html, closeStart);
        index = closeEnd >= 0 ? closeEnd + 1 : closeStart;
        continue;
      }
    }

    index = tagEnd + 1;
  }

  flush();
  return compactInlines(out);
}

function compactInlines(inlines: RichInlineNode[]): RichInlineNode[] {
  const compacted: RichInlineNode[] = [];
  for (let index: number = 0; index < inlines.length; index++) {
    const token: RichInlineNode = inlines[index];
    if (token.type !== RichInlineType.LINE_BREAK) {
      compacted.push(token);
      continue;
    }

    const last: RichInlineNode | undefined = compacted.length > 0 ? compacted[compacted.length - 1] : undefined;
    if (last && last.type === RichInlineType.LINE_BREAK) {
      continue;
    }
    compacted.push(token);
  }
  const filtered: RichInlineNode[] =
    compacted.filter((token: RichInlineNode) => token.type !== RichInlineType.TEXT || token.text.length > 0);
  return trimInlineEdges(filtered);
}

function trimInlineEdges(inlines: RichInlineNode[]): RichInlineNode[] {
  let start: number = 0;
  let end: number = inlines.length;
  while (start < end && isBlankInline(inlines[start])) {
    start++;
  }
  while (end > start && isBlankInline(inlines[end - 1])) {
    end--;
  }
  const trimmed: RichInlineNode[] = (start === 0 && end === inlines.length) ? inlines : inlines.slice(start, end);
  if (trimmed.length === 0) {
    return trimmed;
  }
  // 去掉首个文本的前导空白、末个文本的尾随空白（标签间换行/缩进噪声，
  // 例如图片块之后紧跟的正文常带一个前导 '\n'）。
  const first: RichInlineNode = trimmed[0];
  if (first.type === RichInlineType.TEXT) {
    first.text = first.text.replace(/^\s+/, '');
  }
  const last: RichInlineNode = trimmed[trimmed.length - 1];
  if (last.type === RichInlineType.TEXT) {
    last.text = last.text.replace(/\s+$/, '');
  }
  return trimmed;
}

function isBlankInline(token: RichInlineNode): boolean {
  if (token.type === RichInlineType.LINE_BREAK) {
    return true;
  }
  return token.type === RichInlineType.TEXT && token.text.trim().length === 0;
}

export function hasVisibleInlines(inlines: RichInlineNode[]): boolean {
  for (let index: number = 0; index < inlines.length; index++) {
    const token: RichInlineNode = inlines[index];
    if (token.type === RichInlineType.IMAGE || token.type === RichInlineType.LINK) {
      return true;
    }
    if (token.type === RichInlineType.LINE_BREAK) {
      continue;
    }
    if (token.text.trim().length > 0) {
      return true;
    }
  }
  return false;
}

// 丢掉标题前导的空白文本节点(标记剥离后可能残留 "" 或空格),并去掉首个文本节点的左侧空格。
export function trimLeadingEmptyText(inlines: RichInlineNode[]): RichInlineNode[] {
  const out: RichInlineNode[] = inlines.slice();
  while (out.length > 0 && out[0].type === RichInlineType.TEXT && out[0].text.trim().length === 0) {
    out.shift();
  }
  if (out.length > 0 && out[0].type === RichInlineType.TEXT) {
    out[0].text = out[0].text.replace(/^\s+/, '');
  }
  return out;
}
