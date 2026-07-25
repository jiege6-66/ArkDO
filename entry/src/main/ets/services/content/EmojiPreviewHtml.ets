import {
  findTagEnd,
  getTagName,
  isClosingTag,
  isSelfClosingTag
} from './html/HtmlLexer';

export type EmojiUrlResolver = (name: string) => string | undefined;

// 将 Markdown 渲染结果中的已知表情短码转成行内图片，仅用于本地预览。
export class EmojiPreviewHtml {
  static render(html: string, resolveUrl: EmojiUrlResolver): string {
    let result: string = '';
    let cursor: number = 0;
    let plainTextDepth: number = 0;

    while (cursor < html.length) {
      const tagStart: number = html.indexOf('<', cursor);
      if (tagStart < 0) {
        const tail: string = html.substring(cursor);
        result += plainTextDepth > 0 ? tail : EmojiPreviewHtml.renderText(tail, resolveUrl);
        break;
      }

      if (tagStart > cursor) {
        const text: string = html.substring(cursor, tagStart);
        result += plainTextDepth > 0 ? text : EmojiPreviewHtml.renderText(text, resolveUrl);
      }

      const tagEnd: number = findTagEnd(html, tagStart);
      if (tagEnd < 0) {
        const tail: string = html.substring(tagStart);
        result += plainTextDepth > 0 ? tail : EmojiPreviewHtml.renderText(tail, resolveUrl);
        break;
      }

      const tag: string = html.substring(tagStart, tagEnd + 1);
      const tagName: string = getTagName(tag);
      if (EmojiPreviewHtml.isPlainTextContainer(tagName)) {
        if (isClosingTag(tag)) {
          plainTextDepth = Math.max(0, plainTextDepth - 1);
        } else if (!isSelfClosingTag(tag)) {
          plainTextDepth++;
        }
      }
      result += tag;
      cursor = tagEnd + 1;
    }

    return result;
  }

  private static renderText(text: string, resolveUrl: EmojiUrlResolver): string {
    let result: string = '';
    let appendedUntil: number = 0;
    let searchFrom: number = 0;

    while (searchFrom < text.length) {
      const opening: number = text.indexOf(':', searchFrom);
      if (opening < 0) {
        break;
      }
      const closing: number = text.indexOf(':', opening + 1);
      if (closing < 0) {
        break;
      }
      const name: string = text.substring(opening + 1, closing);
      const url: string | undefined = name.length > 0 ? resolveUrl(name) : undefined;
      if (url && url.length > 0) {
        result += text.substring(appendedUntil, opening);
        result += EmojiPreviewHtml.imageTag(name, url);
        appendedUntil = closing + 1;
        searchFrom = appendedUntil;
      } else {
        // 从当前闭合冒号继续搜，可正确处理 :unknown::known: 这类相邻短码。
        searchFrom = closing;
      }
    }

    return result + text.substring(appendedUntil);
  }

  private static imageTag(name: string, url: string): string {
    const escapedName: string = EmojiPreviewHtml.escapeAttribute(`:${name}:`);
    const escapedUrl: string = EmojiPreviewHtml.escapeAttribute(url);
    return `<img class="emoji" src="${escapedUrl}" alt="${escapedName}" title="${escapedName}" width="20" height="20">`;
  }

  private static escapeAttribute(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  private static isPlainTextContainer(tagName: string): boolean {
    return tagName === 'code' ||
      tagName === 'pre' ||
      tagName === 'script' ||
      tagName === 'style' ||
      tagName === 'textarea';
  }
}
