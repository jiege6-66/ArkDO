// "正在回复"三点跳动指示器。仿 Discourse 打字指示：三点依次抬起→落下，成一道波浪，然后停约 0.5s 再来一轮。
// 不用 .animation(iterations:-1) 连续交替(那样没停顿、太急)；改用 setTimeout 自循环 + 有限 .animation 逐次翻转，
// alive 闸 + clearTimeout 在卸载时可靠停止(对齐项目对无限动画"停不干净"的规避范式)。
const DOT_MOVE_MS: number = 240;    // 单个圆点抬起/落下的时长
const DOT_STAGGER_MS: number = 110; // 相邻圆点的错峰延迟，形成波浪
const DOT_REST_MS: number = 500;    // 一轮波浪结束后的停顿(≈0.5s)

@Component
export struct TypingDots {
  // 圆点颜色，默认次要文字色（Discourse 是灰点）。
  dotColor: ResourceColor = $r('app.color.text_secondary');
  private readonly dotSize: number = 2;
  // 上跳幅度（vp）。对齐 Discourse 的 translateY(-0.2em) 观感。
  private readonly bounce: number = 3;
  // 起伏状态：true=抬起。每轮由 runWave 翻转，.animation 负责把变化演成过渡。
  @State private raised: boolean = false;
  // 组件在场闸：卸载后置 false，配合 clearTimeout 让自循环干净停止，不残留计时器。
  private alive: boolean = false;
  private riseTimer: number = -1;
  private loopTimer: number = -1;

  aboutToDisappear(): void {
    this.alive = false;
    if (this.riseTimer !== -1) {
      clearTimeout(this.riseTimer);
      this.riseTimer = -1;
    }
    if (this.loopTimer !== -1) {
      clearTimeout(this.loopTimer);
      this.loopTimer = -1;
    }
  }

  // 一轮波浪：抬起(错峰) → 落下(错峰) → 停顿 → 递归下一轮。
  private runWave(): void {
    if (!this.alive) {
      return;
    }
    this.raised = true;
    // 所有点抬到位所需时长：最后一个点的错峰延迟 + 单点时长。落下同理。
    const phaseMs: number = DOT_STAGGER_MS * 2 + DOT_MOVE_MS;
    this.riseTimer = setTimeout(() => {
      this.riseTimer = -1;
      this.raised = false;
      // 落下完成(再一个 phaseMs)后停 DOT_REST_MS，再起下一轮。
      this.loopTimer = setTimeout(() => {
        this.loopTimer = -1;
        this.runWave();
      }, phaseMs + DOT_REST_MS);
    }, phaseMs);
  }

  @Builder
  private Dot(delayMs: number) {
    Circle()
      .width(this.dotSize)
      .height(this.dotSize)
      .fill(this.dotColor)
      .translate({ y: this.raised ? -this.bounce : 0 })
      .animation({
        duration: DOT_MOVE_MS,
        curve: Curve.EaseInOut,
        delay: delayMs
      })
  }

  build() {
    Row({ space: 3 }) {
      this.Dot(0)
      this.Dot(DOT_STAGGER_MS)
      this.Dot(DOT_STAGGER_MS * 2)
    }
    .alignItems(VerticalAlign.Center)
    // 首帧布局后再起循环：初值 raised=false，首次抬起才有过渡可动；也避免 aboutToAppear 早于布局。
    .onAppear(() => {
      if (!this.alive) {
        this.alive = true;
        this.runWave();
      }
    })
  }
}
