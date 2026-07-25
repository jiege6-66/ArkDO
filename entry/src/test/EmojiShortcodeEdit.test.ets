import { describe, it, expect } from '@ohos/hypium';
import { EmojiDeleteResult, EmojiShortcodeEdit } from '../main/ets/utils/EmojiShortcodeEdit';

function isKnownEmoji(name: string): boolean {
  return name === 'heart' || name === 'smile';
}

export default function emojiShortcodeEditTest() {
  describe('emojiShortcodeEditTest', () => {
    it('deletesWholeKnownShortcodeBackward', 0, () => {
      const result: EmojiDeleteResult | undefined =
        EmojiShortcodeEdit.deleteBackward('回复 :heart:', 10, isKnownEmoji);
      expect(result?.text).assertEqual('回复 ');
      expect(result?.caret).assertEqual(3);
    });

    it('deletesWholeKnownShortcodeForward', 0, () => {
      const result: EmojiDeleteResult | undefined =
        EmojiShortcodeEdit.deleteForward('前:smile:后', 1, isKnownEmoji);
      expect(result?.text).assertEqual('前后');
      expect(result?.caret).assertEqual(1);
    });

    it('deletesOnlyEmojiNextToAnotherShortcode', 0, () => {
      const text: string = ':heart::smile:';
      const result: EmojiDeleteResult | undefined =
        EmojiShortcodeEdit.deleteBackward(text, text.length, isKnownEmoji);
      expect(result?.text).assertEqual(':heart:');
      expect(result?.caret).assertEqual(7);
    });

    it('doesNotAtomizeUnknownOrPartialShortcodes', 0, () => {
      expect(EmojiShortcodeEdit.deleteBackward(':unknown:', 9, isKnownEmoji)).assertUndefined();
      expect(EmojiShortcodeEdit.deleteBackward(':heart', 6, isKnownEmoji)).assertUndefined();
      expect(EmojiShortcodeEdit.deleteForward('text:', 4, isKnownEmoji)).assertUndefined();
    });

    it('deletesPreviousUnicodeCodePointForEmojiKeyboardBackspace', 0, () => {
      const text: string = 'A😀B';
      const result: EmojiDeleteResult | undefined =
        EmojiShortcodeEdit.deletePreviousCharacter(text, 3);
      expect(result?.text).assertEqual('AB');
      expect(result?.caret).assertEqual(1);
    });
  });
}
