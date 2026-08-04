import { display } from '@kit.ArkUI';

/**
 * AppStorage 中「当前是否宽屏布局」的布尔 key,供 UI 通过 @StorageProp 响应式绑定。
 * true 表示当前窗口适合双栏(平板横屏 / 折叠屏展开 / 大屏),此时:
 *   - RootTabPage 的 Navigation 切成双栏 Split(左列表右详情);
 *   - 富文本图片启用宽屏规则(居中 + 宽度封顶 + 按屏高限高)。
 * false(手机、平板竖屏、折叠屏折叠态)保持单栏 Stack 与手机端原有渲染,行为完全不变。
 */
export const APP_IS_WIDE_STORAGE_KEY: string = 'appIsWide';

/**
 * 横屏双栏阈值(vp)。取 840:
 *   - 手机(≈360,横屏也极少超 840)→ 非宽屏,单栏,和现状一致;
 *   - 平板横屏(1138 ~ 1440)→ 宽屏,双栏。
 * 注:Navigation 默认 Auto 在 520vp 就分栏,会把平板竖屏也切成双栏;这里用更高的
 * 840 阈值显式驱动 mode,才能做到「竖屏单栏 / 横屏双栏」。
 */
export const WIDE_THRESHOLD_VP: number = 840;

/**
 * 折叠屏展开态的双栏阈值(vp)。内屏近似方形(如 741×832),竖着拿也要双栏,故不看长宽比,
 * 只用宽度兜底:直板折叠(Flip)展开后仍是 ≈360 的窄屏,低于此值,不会被误判成双栏。
 */
export const UNFOLDED_WIDE_THRESHOLD_VP: number = 600;

/**
 * 响应式断点。判定「当前窗口是否适合双栏」并写入 AppStorage 供各页 @StorageProp('appIsWide') 读取。
 *
 * 实测宽度不用 mediaquery(在 onCreate 阶段窗口未就绪、且 `(width>=Nvp)` 语法不稳),
 * 改由 RootTabPage 根 Stack 的 onAreaChange 把实际布局尺寸(vp)喂进 applySize——
 * 布局驱动,首帧与旋转/分屏/折叠都会触发,最可靠。
 */
export class BreakpointManager {
  // 最近一次布局尺寸(vp)。折叠状态变化时用它重算,不必等下一次 onAreaChange。
  private static lastWidthVp: number = 0;
  private static lastHeightVp: number = 0;
  // 是否折叠屏设备。开机问一次即可,不会变。
  private static foldable: boolean = false;

  /** 应用启动时调用一次:先把 key 播种为 false(非宽屏),保证首帧渲染前 AppStorage 有值。 */
  static init(): void {
    if (AppStorage.get<boolean>(APP_IS_WIDE_STORAGE_KEY) === undefined) {
      AppStorage.setOrCreate(APP_IS_WIDE_STORAGE_KEY, false);
    }
    try {
      BreakpointManager.foldable = display.isFoldable();
      if (BreakpointManager.foldable) {
        // 展开/折叠时窗口尺寸与折叠状态未必同一帧到达,两个信号都重算一次,谁后到谁生效。
        display.on('foldStatusChange', () => {
          BreakpointManager.reapply();
        });
      }
    } catch (err) {
      // 取不到就当普通直板机:后面只走「够宽且横着」这一条,不影响手机与平板。
      BreakpointManager.foldable = false;
    }
  }

  /**
   * 由布局回调喂入当前窗口尺寸(vp),折算宽屏标志,仅在变化时写回,避免无谓刷新。
   *
   * 两条路任一成立即双栏:
   *   ① 够宽(≥840)**且**横着(宽 > 高)——平板横屏。只看宽度不够:大屏平板竖屏宽度就有
   *      965vp,光凭阈值同样会被判成宽屏、竖屏照样分栏(单纯抬高阈值又会误伤窄的平板横屏),
   *      加上长宽比这一刀,「竖屏一律单栏」才与设备无关地成立;左右分屏(半宽)也自然落回单栏。
   *   ② 折叠屏展开且宽度 ≥600——内屏近似方形,竖着拿也该双栏,长宽比这一刀对它不适用。
   */
  static applySize(widthVp: number, heightVp: number): void {
    BreakpointManager.lastWidthVp = widthVp;
    BreakpointManager.lastHeightVp = heightVp;
    const landscapeWide: boolean = widthVp >= WIDE_THRESHOLD_VP && widthVp > heightVp;
    const unfoldedWide: boolean = BreakpointManager.isUnfolded() && widthVp >= UNFOLDED_WIDE_THRESHOLD_VP;
    const wide: boolean = landscapeWide || unfoldedWide;
    if (AppStorage.get<boolean>(APP_IS_WIDE_STORAGE_KEY) !== wide) {
      AppStorage.setOrCreate(APP_IS_WIDE_STORAGE_KEY, wide);
    }
  }

  /** 折叠状态变化后按最近一次尺寸重算。首帧之前(尺寸还没喂进来)不做事。 */
  private static reapply(): void {
    if (BreakpointManager.lastWidthVp > 0) {
      BreakpointManager.applySize(BreakpointManager.lastWidthVp, BreakpointManager.lastHeightVp);
    }
  }

  /** 折叠屏是否处于展开态(半折的书本形态同样是内屏,按展开算)。非折叠屏恒 false。 */
  private static isUnfolded(): boolean {
    if (!BreakpointManager.foldable) {
      return false;
    }
    try {
      const status: display.FoldStatus = display.getFoldStatus();
      return status !== display.FoldStatus.FOLD_STATUS_FOLDED &&
        status !== display.FoldStatus.FOLD_STATUS_UNKNOWN;
    } catch (err) {
      return false;
    }
  }
}
