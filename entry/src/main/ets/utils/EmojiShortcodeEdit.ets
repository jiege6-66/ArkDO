export type KnownEmojiPredicate = (name: string) => boolean;

export interface EmojiDeleteResult {
  text: string;
  caret: number;
}

export class EmojiShortcodeEdit {
  static deleteBackward(text: string, caret: number,
    isKnownEmoji: KnownEmojiPredicate): EmojiDeleteResult | undefined {
    if (caret <= 1 || caret > text.length || text.charAt(caret - 1) !== ':') {
      return undefined;
    }
    const opening: number = text.lastIndexOf(':', caret - 2);
    return EmojiShortcodeEdit.deleteRange(text, opening, caret, isKnownEmoji);
  }

  static deleteForward(text: string, caret: number,
    isKnownEmoji: KnownEmojiPredicate): EmojiDeleteResult | undefined {
    if (caret < 0 || caret >= text.length || text.charAt(caret) !== ':') {
      return undefined;
    }
    const closing: number = text.indexOf(':', caret + 1);
    return EmojiShortcodeEdit.deleteRange(text, caret, closing + 1, isKnownEmoji);
  }

  static deletePreviousCharacter(text: string, caret: number): EmojiDeleteResult | undefined {
    if (caret <= 0 || caret > text.length) {
      return undefined;
    }
    let start: number = caret - 1;
    const last: number = text.charCodeAt(start);
    if (last >= 0xDC00 && last <= 0xDFFF && start > 0) {
      const first: number = text.charCodeAt(start - 1);
      if (first >= 0xD800 && first <= 0xDBFF) {
        start--;
      }
    }
    return {
      text: text.substring(0, start) + text.substring(caret),
      caret: start
    };
  }

  private static deleteRange(text: string, start: number, end: number,
    isKnownEmoji: KnownEmojiPredicate): EmojiDeleteResult | undefined {
    if (start < 0 || end <= start + 2 || end > text.length) {
      return undefined;
    }
    const name: string = text.substring(start + 1, end - 1);
    if (!isKnownEmoji(name)) {
      return undefined;
    }
    return {
      text: text.substring(0, start) + text.substring(end),
      caret: start
    };
  }
}
