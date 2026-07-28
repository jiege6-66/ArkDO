import { describe, it, expect } from '@ohos/hypium';
import { BoostEditDocument, BoostEditToken, BoostTokenType } from '../main/ets/models/BoostEditDocument';

function isKnownEmoji(name: string): boolean {
  return name === 'heart' || name === 'slightly_smiling_face' || name === 'bili_001' || name === 'piñata';
}

export default function boostEditDocumentTest() {
  describe('boostEditDocumentTest', () => {
    it('parsesAndSerializesKnownEmojiShortcodes', 0, () => {
      const raw: string = '谢谢:slightly_smiling_face:佬:bili_001:';
      const tokens: BoostEditToken[] = BoostEditDocument.parse(raw, isKnownEmoji);

      expect(tokens.length).assertEqual(4);
      expect(tokens[1].type).assertEqual(BoostTokenType.EMOJI);
      expect(tokens[1].value).assertEqual('slightly_smiling_face');
      expect(BoostEditDocument.serialize(tokens)).assertEqual(raw);
      expect(BoostEditDocument.logicalLength(tokens)).assertEqual(5);
      expect(BoostEditDocument.serialize(BoostEditDocument.parse(':piñata:', isKnownEmoji))).assertEqual(':piñata:');
    });

    it('keepsUnknownShortcodesAsText', 0, () => {
      const raw: string = 'a:not_registered:b';
      const tokens: BoostEditToken[] = BoostEditDocument.parse(raw, isKnownEmoji);

      expect(tokens.length).assertEqual(1);
      expect(tokens[0].type).assertEqual(BoostTokenType.TEXT);
      expect(BoostEditDocument.serialize(tokens)).assertEqual(raw);
    });

    it('countsSelectedEmojiAsOneCharacter', 0, () => {
      expect(BoostEditDocument.logicalLengthOfRaw(':slightly_smiling_face:', isKnownEmoji)).assertEqual(1);
      expect(BoostEditDocument.logicalLengthOfRaw('A😀:heart:', isKnownEmoji)).assertEqual(3);
      expect(BoostEditDocument.logicalLengthTrimmed([
        { type: BoostTokenType.TEXT, value: '  A😀' },
        { type: BoostTokenType.EMOJI, value: 'heart' },
        { type: BoostTokenType.TEXT, value: '  ' }
      ])).assertEqual(3);
    });

    it('addsSeparatorBeforePickerEmojiOnlyAfterNonWhitespaceContent', 0, () => {
      expect(BoostEditDocument.needsSpaceBeforeEmoji([])).assertFalse();
      expect(BoostEditDocument.needsSpaceBeforeEmoji([
        { type: BoostTokenType.TEXT, value: '我核对一下' }
      ])).assertTrue();
      expect(BoostEditDocument.needsSpaceBeforeEmoji([
        { type: BoostTokenType.TEXT, value: '我核对一下 ' }
      ])).assertFalse();
      expect(BoostEditDocument.needsSpaceBeforeEmoji([
        { type: BoostTokenType.EMOJI, value: 'heart' }
      ])).assertTrue();
    });
  });
}
