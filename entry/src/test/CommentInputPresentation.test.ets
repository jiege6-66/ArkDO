import { describe, it, expect } from '@ohos/hypium';
import {
  COMMENT_INPUT_EMOJI_SIZE,
  COMMENT_INPUT_EMOJI_VERTICAL_MARGIN,
  COMMENT_INPUT_HALF_LEADING,
  COMMENT_INPUT_LINE_HEIGHT,
  COMMENT_INPUT_PADDING_BOTTOM,
  COMMENT_INPUT_PADDING_TOP,
  COMMENT_INPUT_SINGLE_LINE_HEIGHT,
  commentKeyboardToggleIcon,
  commentInputHeightForLineHeights,
  shouldShowCommentInputPlaceholder
} from '../main/ets/views/components/CommentInputPresentation';

export default function commentInputPresentationTest() {
  describe('commentInputPresentationTest', () => {
    it('usesKeyboardIconWhileEmojiPanelIsVisible', 0, () => {
      expect(commentKeyboardToggleIcon(false)).assertEqual('face-smile');
      expect(commentKeyboardToggleIcon(true)).assertEqual('keyboard');
    });

    it('centersOneLineContentInCompactInput', 0, () => {
      expect(COMMENT_INPUT_SINGLE_LINE_HEIGHT).assertEqual(40);
      expect(COMMENT_INPUT_LINE_HEIGHT).assertEqual(24);
      expect(COMMENT_INPUT_HALF_LEADING).assertTrue();
      expect(COMMENT_INPUT_PADDING_TOP).assertEqual(8);
      expect(COMMENT_INPUT_PADDING_BOTTOM).assertEqual(8);
      expect(COMMENT_INPUT_LINE_HEIGHT + COMMENT_INPUT_PADDING_TOP + COMMENT_INPUT_PADDING_BOTTOM)
        .assertEqual(COMMENT_INPUT_SINGLE_LINE_HEIGHT);
    });

    it('keepsEmojiLineBoxStableWhenTextIsAdded', 0, () => {
      expect(COMMENT_INPUT_EMOJI_SIZE).assertEqual(22);
      expect(COMMENT_INPUT_EMOJI_VERTICAL_MARGIN).assertEqual(1);
      expect(COMMENT_INPUT_EMOJI_SIZE + COMMENT_INPUT_EMOJI_VERTICAL_MARGIN * 2)
        .assertEqual(COMMENT_INPUT_LINE_HEIGHT);
    });

    it('growsInputHeightAfterContentWraps', 0, () => {
      expect(commentInputHeightForLineHeights([])).assertEqual(40);
      expect(commentInputHeightForLineHeights([24])).assertEqual(40);
      expect(commentInputHeightForLineHeights([24, 24])).assertEqual(64);
      expect(commentInputHeightForLineHeights([24, 24, 24, 24, 24])).assertEqual(120);
    });

    it('showsPlaceholderOnlyWhileEditorIsEmpty', 0, () => {
      expect(shouldShowCommentInputPlaceholder('')).assertTrue();
      expect(shouldShowCommentInputPlaceholder('回复内容')).assertFalse();
      expect(shouldShowCommentInputPlaceholder(':heart:')).assertFalse();
    });
  });
}
