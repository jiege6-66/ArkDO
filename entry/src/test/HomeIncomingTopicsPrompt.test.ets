import { describe, it, expect } from '@ohos/hypium';
import {
  AnimatedDigitColumn,
  incomingDigitColumnWidth,
  incomingHighlightRemainingMs,
  incomingInsertOpacity,
  incomingInsertTranslateY,
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
      expect(columns[0].kind).assertEqual('stable');
      expect(columns[1].kind).assertEqual('stable');
      expect(columns[0].changed).assertFalse();
      expect(columns[1].changed).assertFalse();
      expect(columns[2].previous).assertEqual('5');
      expect(columns[2].current).assertEqual('6');
      expect(columns[2].kind).assertEqual('roll');
      expect(columns[2].changed).assertTrue();
    });

    it('entersLeadingColumnWhenCountWidthGrows', 0, () => {
      const columns: AnimatedDigitColumn[] = incomingTopicDigitColumns(99, 100);

      expect(columns.length).assertEqual(3);
      // 增位：新前导列是 enter(previous 空)，其余两列滚动 9→0。
      expect(columns[0].previous).assertEqual('');
      expect(columns[0].current).assertEqual('1');
      expect(columns[0].kind).assertEqual('enter');
      expect(columns[1].kind).assertEqual('roll');
      expect(columns[1].previous).assertEqual('9');
      expect(columns[1].current).assertEqual('0');
      expect(columns[2].kind).assertEqual('roll');
    });

    it('exitsLeadingColumnWhenCountWidthShrinks', 0, () => {
      const columns: AnimatedDigitColumn[] = incomingTopicDigitColumns(10, 1);

      expect(columns.length).assertEqual(2);
      // 退位：离开的前导列是 exit(current 空)，不滚成假「0」；个位滚动 0→1。
      expect(columns[0].previous).assertEqual('1');
      expect(columns[0].current).assertEqual('');
      expect(columns[0].kind).assertEqual('exit');
      expect(columns[1].previous).assertEqual('0');
      expect(columns[1].current).assertEqual('1');
      expect(columns[1].kind).assertEqual('roll');
    });

    it('opensAndClosesDigitColumnWidthByKind', 0, () => {
      expect(incomingDigitColumnWidth('enter', 0, 9)).assertEqual(0);
      expect(incomingDigitColumnWidth('enter', 1, 9)).assertEqual(9);
      expect(incomingDigitColumnWidth('exit', 0, 9)).assertEqual(9);
      expect(incomingDigitColumnWidth('exit', 1, 9)).assertEqual(0);
      expect(incomingDigitColumnWidth('stable', 0.5, 9)).assertEqual(9);
      expect(incomingDigitColumnWidth('roll', 0.5, 9)).assertEqual(9);
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

    it('movesIncomingListOnlyDownwardDuringReveal', 0, () => {
      expect(incomingInsertTranslateY(0, 96)).assertEqual(-96);
      expect(incomingInsertTranslateY(0.5, 96)).assertEqual(-48);
      expect(incomingInsertTranslateY(1, 96)).assertEqual(0);
      expect(incomingInsertTranslateY(2, 96)).assertEqual(0);
    });

    it('fadesOnlyIncomingRowsIntoTheReveal', 0, () => {
      expect(incomingInsertOpacity(0, true)).assertEqual(0);
      expect(incomingInsertOpacity(0.5, true)).assertEqual(0.5);
      expect(incomingInsertOpacity(1, true)).assertEqual(1);
      expect(incomingInsertOpacity(0, false)).assertEqual(1);
    });

  });
}
