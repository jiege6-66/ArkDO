import { BRAND_BLUE } from '../../common/theme/Palette';

// kind 取值：'stable'(静态) / 'roll'(滚动换字) / 'enter'(增位新前导列) / 'exit'(减位要离开的前导列)。
export interface AnimatedDigitColumn {
  previous: string;
  current: string;
  changed: boolean;
  kind: string;
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
  const out: AnimatedDigitColumn[] = [];
  for (let index: number = 0; index < width; index++) {
    // 个位右对齐：越界(短侧缺失的前导位)记为空串，而非补零——空串区分「进位/退位」列。
    const previousIndex: number = index - (width - previous.length);
    const currentIndex: number = index - (width - current.length);
    const previousDigit: string = previousIndex >= 0 ? previous.charAt(previousIndex) : '';
    const currentDigit: string = currentIndex >= 0 ? current.charAt(currentIndex) : '';
    let kind: string;
    if (previousDigit === '') {
      kind = 'enter';
    } else if (currentDigit === '') {
      kind = 'exit';
    } else if (previousDigit !== currentDigit) {
      kind = 'roll';
    } else {
      kind = 'stable';
    }
    out.push({
      previous: previousDigit,
      current: currentDigit,
      changed: previousDigit !== currentDigit,
      kind
    });
  }
  return out;
}

export function incomingHighlightRemainingMs(deadline: number, now: number): number {
  return Math.max(0, Math.floor(deadline - now));
}

function clampAnimationProgress(progress: number): number {
  return Math.max(0, Math.min(1, progress));
}

export function incomingInsertTranslateY(progress: number, distance: number): number {
  const safeDistance: number = Math.max(0, distance);
  return -safeDistance * (1 - clampAnimationProgress(progress));
}

export function incomingInsertOpacity(progress: number, fadeIn: boolean): number {
  return fadeIn ? clampAnimationProgress(progress) : 1;
}

// 数字列宽随进度开合：enter 从 0 展开到满宽，exit 从满宽合拢到 0，其余恒为满宽。
// 配合列内旧字上滑淡出，让「退位」列平滑滑走并让空间闭合，而非结束时整列突塌。
export function incomingDigitColumnWidth(kind: string, progress: number, fullWidth: number): number {
  const clamped: number = clampAnimationProgress(progress);
  if (kind === 'enter') {
    return fullWidth * clamped;
  }
  if (kind === 'exit') {
    return fullWidth * (1 - clamped);
  }
  return fullWidth;
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
  // 数字滚动动画序号：仅最新一次动画的 onFinish 允许对齐位数，避免被更早的回调误改宽度。
  private numberAnimationEpoch: number = 0;

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
    const epoch: number = ++this.numberAnimationEpoch;
    this.getUIContext().animateTo({
      duration: NUMBER_ANIMATION_MS,
      curve: Curve.EaseOut,
      // 滚动结束把 previous 对齐 current，位数回落到当前值本身，避免收缩(如 10→1)后残留前导零"01"。
      onFinish: () => {
        if (epoch !== this.numberAnimationEpoch) {
          return;
        }
        this.previousCount = this.visibleCount;
      }
    }, () => {
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
              `${index}_${column.kind}_${column.previous}_${column.current}_${this.visibleCount}`)
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
      if (column.kind === 'stable') {
        Text(column.current)
          .fontSize(PROMPT_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(BRAND_BLUE)
      } else {
        // roll / exit：旧字上滑淡出。
        if (column.previous !== '') {
          Text(column.previous)
            .fontSize(PROMPT_FONT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(BRAND_BLUE)
            .translate({ y: -DIGIT_HEIGHT * this.digitProgress })
            .opacity(1 - this.digitProgress)
        }
        // roll / enter：新字自下滑入。
        if (column.current !== '') {
          Text(column.current)
            .fontSize(PROMPT_FONT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(BRAND_BLUE)
            .translate({ y: DIGIT_HEIGHT * (1 - this.digitProgress) })
            .opacity(this.digitProgress)
        }
      }
    }
    // enter/exit 列宽随进度开合，让水平空间平滑闭合/展开；clip 让字形随宽度收拢被裁。
    .width(incomingDigitColumnWidth(column.kind, this.digitProgress, DIGIT_WIDTH))
    .height(DIGIT_HEIGHT)
    .clip(true)
  }
}
