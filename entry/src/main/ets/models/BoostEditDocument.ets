export enum BoostTokenType {
  TEXT = 'text',
  EMOJI = 'emoji'
}

export interface BoostEditToken {
  type: BoostTokenType;
  value: string;
}

export type EmojiNamePredicate = (name: string) => boolean;

export class BoostEditDocument {
  static parse(raw: string, isKnownEmoji: EmojiNamePredicate): BoostEditToken[] {
    const tokens: BoostEditToken[] = [];
    let textStart: number = 0;
    let cursor: number = 0;
    while (cursor < raw.length) {
      if (raw.charAt(cursor) !== ':') {
        cursor++;
        continue;
      }
      const closing: number = raw.indexOf(':', cursor + 1);
      if (closing < 0) {
        break;
      }
      const name: string = raw.substring(cursor + 1, closing);
      if (name.length === 0 || !isKnownEmoji(name)) {
        cursor = closing;
        continue;
      }
      BoostEditDocument.appendText(tokens, raw.substring(textStart, cursor));
      tokens.push({ type: BoostTokenType.EMOJI, value: name });
      cursor = closing + 1;
      textStart = cursor;
    }
    BoostEditDocument.appendText(tokens, raw.substring(textStart));
    return tokens;
  }

  static serialize(tokens: BoostEditToken[]): string {
    let raw: string = '';
    for (let index: number = 0; index < tokens.length; index++) {
      const token: BoostEditToken = tokens[index];
      raw += token.type === BoostTokenType.EMOJI ? `:${token.value}:` : token.value;
    }
    return raw;
  }

  static logicalLength(tokens: BoostEditToken[]): number {
    let count: number = 0;
    for (let index: number = 0; index < tokens.length; index++) {
      const token: BoostEditToken = tokens[index];
      count += token.type === BoostTokenType.EMOJI ? 1 : BoostEditDocument.codePointLength(token.value);
    }
    return count;
  }

  static logicalLengthTrimmed(tokens: BoostEditToken[]): number {
    if (tokens.length === 0) {
      return 0;
    }
    const copy: BoostEditToken[] = [];
    for (let index: number = 0; index < tokens.length; index++) {
      const token: BoostEditToken = tokens[index];
      const snapshot: BoostEditToken = { type: token.type, value: token.value };
      copy.push(snapshot);
    }
    while (copy.length > 0 && copy[0].type === BoostTokenType.TEXT) {
      copy[0].value = copy[0].value.trimStart();
      if (copy[0].value.length > 0) {
        break;
      }
      copy.shift();
    }
    while (copy.length > 0 && copy[copy.length - 1].type === BoostTokenType.TEXT) {
      const lastIndex: number = copy.length - 1;
      copy[lastIndex].value = copy[lastIndex].value.trimEnd();
      if (copy[lastIndex].value.length > 0) {
        break;
      }
      copy.pop();
    }
    return BoostEditDocument.logicalLength(copy);
  }

  static logicalLengthOfRaw(raw: string, isKnownEmoji: EmojiNamePredicate): number {
    return BoostEditDocument.logicalLength(BoostEditDocument.parse(raw.trim(), isKnownEmoji));
  }

  static needsSpaceBeforeEmoji(tokens: BoostEditToken[]): boolean {
    const raw: string = BoostEditDocument.serialize(tokens);
    return raw.length > 0 && raw.trimEnd().length === raw.length;
  }

  private static appendText(tokens: BoostEditToken[], value: string): void {
    if (value.length === 0) {
      return;
    }
    const lastIndex: number = tokens.length - 1;
    if (lastIndex >= 0 && tokens[lastIndex].type === BoostTokenType.TEXT) {
      tokens[lastIndex].value += value;
      return;
    }
    tokens.push({ type: BoostTokenType.TEXT, value: value });
  }

  // ArkTS 的 string.length 按 UTF-16 code unit 计数；这里把代理对视为一个用户字符。
  private static codePointLength(value: string): number {
    let count: number = 0;
    let index: number = 0;
    while (index < value.length) {
      const first: number = value.charCodeAt(index);
      if (first >= 0xD800 && first <= 0xDBFF && index + 1 < value.length) {
        const second: number = value.charCodeAt(index + 1);
        if (second >= 0xDC00 && second <= 0xDFFF) {
          index += 2;
          count++;
          continue;
        }
      }
      index++;
      count++;
    }
    return count;
  }
}
