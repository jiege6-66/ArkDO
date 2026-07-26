import { describe, it, expect } from '@ohos/hypium';
import {
  AnimatedDigitColumn,
  incomingHighlightRemainingMs,
  incomingTopicHighlightBackground,
  incomingTopicDigitColumns,
  incomingTopicsPromptAccessibilityText,
  incomingTopicsPromptText,
  shouldShowIncomingTopicsPrompt
} from '../main/ets/views/components/HomeIncomingTopicsPrompt';

export default function homeIncomingTopicsPromptTest() {
  describe('homeIncomingTopicsPromptTest', () => {
    it('hidesPromptWhenThereAreNoIncomingTopics', 0, () => {
      expect(shouldShowIncomingTopicsPrompt(0)).assertFalse();
      expect(shouldShowIncomingTopicsPrompt(-1)).assertFalse();
    });

    it('formatsIncomingTopicPromptText', 0, () => {
      expect(incomingTopicsPromptText(375)).assertEqual('查看 375 个新的或更新的话题');
      expect(incomingTopicsPromptText(0)).assertEqual('');
      expect(incomingTopicsPromptAccessibilityText(375, true))
        .assertEqual('正在加载 375 个新的或更新的话题');
    });

    it('marksOnlyChangedDigitsForIncrementAnimation', 0, () => {
      const columns: AnimatedDigitColumn[] = incomingTopicDigitColumns(375, 376);

      expect(columns.length).assertEqual(3);
      expect(columns[0].changed).assertFalse();
      expect(columns[1].changed).assertFalse();
      expect(columns[2].previous).assertEqual('5');
      expect(columns[2].current).assertEqual('6');
      expect(columns[2].changed).assertTrue();
    });

    it('padsDigitsWhenCountWidthGrows', 0, () => {
      const columns: AnimatedDigitColumn[] = incomingTopicDigitColumns(99, 100);

      expect(columns.length).assertEqual(3);
      expect(columns[0].previous).assertEqual('0');
      expect(columns[0].current).assertEqual('1');
      expect(columns[1].previous).assertEqual('9');
      expect(columns[1].current).assertEqual('0');
      expect(columns[2].previous).assertEqual('9');
      expect(columns[2].current).assertEqual('0');
    });

    it('doesNotReplayExpiredIncomingHighlight', 0, () => {
      expect(incomingHighlightRemainingMs(3500, 1000)).assertEqual(2500);
      expect(incomingHighlightRemainingMs(3500, 3500)).assertEqual(0);
      expect(incomingHighlightRemainingMs(3500, 4000)).assertEqual(0);
    });

    it('fadesIncomingHighlightToTransparentSameHue', 0, () => {
      expect(incomingTopicHighlightBackground(true, false)).assertEqual('#E8F1FE');
      expect(incomingTopicHighlightBackground(false, false)).assertEqual('#00E8F1FE');
      expect(incomingTopicHighlightBackground(true, true)).assertEqual('#13202D');
      expect(incomingTopicHighlightBackground(false, true)).assertEqual('#0013202D');
    });

  });
}
