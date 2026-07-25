export const COMMENT_INPUT_SINGLE_LINE_HEIGHT: number = 40;
export const COMMENT_INPUT_MAX_HEIGHT: number = 120;
export const COMMENT_INPUT_LINE_HEIGHT: number = 24;
export const COMMENT_INPUT_EMOJI_SIZE: number = 22;
export const COMMENT_INPUT_EMOJI_VERTICAL_MARGIN: number =
  (COMMENT_INPUT_LINE_HEIGHT - COMMENT_INPUT_EMOJI_SIZE) / 2;
export const COMMENT_INPUT_HALF_LEADING: boolean = true;
export const COMMENT_INPUT_PADDING_TOP: number = 8;
export const COMMENT_INPUT_PADDING_BOTTOM: number = 8;

export function commentKeyboardToggleIcon(showEmojiKeyboard: boolean): string {
  return showEmojiKeyboard ? 'keyboard' : 'face-smile';
}

export function commentInputHeightForLineHeights(lineHeights: number[]): number {
  let contentHeight: number = 0;
  for (let index: number = 0; index < lineHeights.length; index++) {
    contentHeight += lineHeights[index];
  }
  const measuredHeight: number = contentHeight + COMMENT_INPUT_PADDING_TOP + COMMENT_INPUT_PADDING_BOTTOM;
  return Math.max(COMMENT_INPUT_SINGLE_LINE_HEIGHT, Math.min(COMMENT_INPUT_MAX_HEIGHT, measuredHeight));
}

export function shouldShowCommentInputPlaceholder(serializedText: string): boolean {
  return serializedText.length === 0;
}
