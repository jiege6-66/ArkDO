import { BRAND_BLUE } from '../../common/theme/Palette';

export interface AnimatedDigitColumn {
  previous: string;
  current: string;
  changed: boolean;
}

export function shouldShowIncomingTopicsPrompt(count: number): boolean {
  return Number.isFinite(count) && count > 0;
}

export function incomingTopicsPromptText(count: number): string {
  const safeCount: number = Math.max(0, Math.floor(count));
  if (safeCount <= 0) {
    return '';
  }
  return `查看 ${safeCount} 个新的或更新的话题`;
}

export function incomingTopicsPromptAccessibilityText(count: number, loading: boolean): string {
  const safeCount: number = Math.max(0, Math.floor(count));
  if (safeCount <= 0) {
    return '';
  }
  return loading
    ? `正在加载 ${safeCount} 个新的或更新的话题`
    : incomingTopicsPromptText(safeCount);
}

export function incomingTopicDigitColumns(previousCount: number, currentCount: number): AnimatedDigitColumn[] {
  const previous: string = Math.max(0, Math.floor(previousCount)).toString();
  const current: string = Math.max(0, Math.floor(currentCount)).toString();
  const width: number = Math.max(previous.length, current.length);
  const paddedPrevious: string = previous.padStart(width, '0');
  const paddedCurrent: string = current.padStart(width, '0');
  const out: AnimatedDigitColumn[] = [];
  for (let index: number = 0; index < width; index++) {
    const previousDigit: string = paddedPrevious.charAt(index);
    const currentDigit: string = paddedCurrent.charAt(index);
    out.push({
      previous: previousDigit,
      current: currentDigit,
      changed: previousDigit !== currentDigit
    });
  }
  return out;
}

export function incomingHighlightRemainingMs(deadline: number, now: number): number {
  return Math.max(0, Math.floor(deadline - now));
}

// 渐隐终点保留与起点相同的 RGB，仅把 alpha 置零，避免蓝色向透明黑插值时经过灰色。
export function incomingTopicHighlightBackground(active: boolean, dark: boolean): string {
  if (dark) {
    return active ? '#13202D' : '#0013202D';
  }
  return active ? '#E8F1FE' : '#00E8F1FE';
}

const PROMPT_HEIGHT: number = 44;
const PROMPT_FONT_SIZE: number = 14;
const DIGIT_HEIGHT: number = 18;
const DIGIT_WIDTH: number = 9;
const NUMBER_ANIMATION_MS: number = 260;

@Component
export struct HomeIncomingTopicsPrompt {
  @Prop @Watch('onCountChanged') count: number = 0;
  @Prop loading: boolean = false;
  onPromptClick: () => void = () => {};

  @State private previousCount: number = 0;
  @State private visibleCount: number = 0;
  @State private digitProgress: number = 1;

  aboutToAppear(): void {
    this.previousCount = this.count;
    this.visibleCount = this.count;
    this.digitProgress = 1;
  }

  private onCountChanged(): void {
    if (this.count === this.visibleCount) {
      return;
    }
    this.previousCount = this.visibleCount;
    this.visibleCount = this.count;
    this.digitProgress = 0;
    this.getUIContext().animateTo({ duration: NUMBER_ANIMATION_MS, curve: Curve.EaseOut }, () => {
      this.digitProgress = 1;
    });
  }

  build() {
    Row() {
      Row() {
        Text('查看')
          .fontSize(PROMPT_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(BRAND_BLUE)

        Row({ space: 0 }) {
          ForEach(incomingTopicDigitColumns(this.previousCount, this.visibleCount),
            (column: AnimatedDigitColumn, index: number) => {
              this.DigitColumn(column, index);
            },
            (column: AnimatedDigitColumn, index: number) =>
              `${index}_${column.previous}_${column.current}_${this.visibleCount}`)
        }
        .height(DIGIT_HEIGHT)
        .clip(true)
        .margin({ left: 4, right: 4 })

        Text('个新的或更新的话题')
          .fontSize(PROMPT_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(BRAND_BLUE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.loading) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(BRAND_BLUE)
            .margin({ left: 8 })
        }
      }
      .height(PROMPT_HEIGHT)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .height(PROMPT_HEIGHT)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.info_soft_bg'))
    .border({
      width: { bottom: 1 },
      color: $r('app.color.border')
    })
    .padding(0)
    .opacity(1)
    .onClick(() => {
      if (!this.loading) {
        this.onPromptClick();
      }
    })
    .accessibilityText(incomingTopicsPromptAccessibilityText(this.visibleCount, this.loading))
  }

  @Builder
  private DigitColumn(column: AnimatedDigitColumn, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (column.changed) {
        Text(column.previous)
          .fontSize(PROMPT_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(BRAND_BLUE)
          .translate({ y: -DIGIT_HEIGHT * this.digitProgress })
          .opacity(1 - this.digitProgress)

        Text(column.current)
          .fontSize(PROMPT_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(BRAND_BLUE)
          .translate({ y: DIGIT_HEIGHT * (1 - this.digitProgress) })
          .opacity(this.digitProgress)
      } else {
        Text(column.current)
          .fontSize(PROMPT_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(BRAND_BLUE)
      }
    }
    .width(DIGIT_WIDTH)
    .height(DIGIT_HEIGHT)
  }
}
