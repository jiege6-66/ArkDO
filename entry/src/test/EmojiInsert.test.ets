import { describe, it, expect } from '@ohos/hypium';
import { EditState, insertText } from '../main/ets/utils/markdownInsert';

export default function emojiInsertTest() {
  describe('emojiInsertTest', () => {
    it('insertsShortcodeAtCaret', 0, () => {
      const result: EditState = insertText({
        text: '感谢佬',
        selectionStart: 2,
        selectionEnd: 2
      }, ':heart:');

      expect(result.text).assertEqual('感谢:heart:佬');
      expect(result.selectionStart).assertEqual(9);
      expect(result.selectionEnd).assertEqual(9);
    });

    it('replacesSelectionWithShortcode', 0, () => {
      const result: EditState = insertText({
        text: '感谢大佬',
        selectionStart: 2,
        selectionEnd: 3
      }, ':bili_001:');

      expect(result.text).assertEqual('感谢:bili_001:佬');
      expect(result.selectionStart).assertEqual(12);
      expect(result.selectionEnd).assertEqual(12);
    });
  });
}
