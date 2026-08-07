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
 * 折叠屏展开态「近方形」上限(长边 / 短边)。展开态那条兜底之所以敢不看长宽比,前提是内屏
 * 接近正方形(如 741×832,比值 1.12)——竖着拿也有足够横向空间。阔折叠(Pura X Max 展开态
 * 939×664,比值 1.41)不满足这个前提:竖持后是 664×939,形状已接近平板竖屏,再走兜底就会
 * 出现「同样 664vp 宽,平板判单栏、阔折叠判双栏」的自相矛盾,且左右各 332vp 反而挤了阅读。
 * 取 1.2 卡在 1.12 与 1.41 之间:竖折叠内屏照旧双栏,阔折叠竖持回落单栏(横持仍由
 * WIDE_THRESHOLD_VP 那条判成双栏,939 ≥ 840)。
 */
export const UNFOLDED_SQUARE_RATIO_MAX: number = 1.2;

/**
 * AppStorage 中「双栏左列表栏宽度(vp)」的 key。仅 Split 生效,单栏下忽略。
 * 与 appIsWide 同源同帧算出(见 applySize),避免两个值各自更新导致中间态。
 */
export const APP_SPLIT_NAV_BAR_WIDTH_STORAGE_KEY: string = 'appSplitNavBarWidth';

/** 双栏左列表栏占窗口宽的比例。对半分,分割线正好落在折叠屏内屏的折痕上。 */
export const SPLIT_NAV_BAR_RATIO: number = 0.5;

/** 左栏下限须 ≥ 分区抽屉宽度(288),否则抽屉滑出会溢进右详情栏,留点余量取 320。 */
export const SPLIT_NAV_BAR_MIN_WIDTH: number = 320;

/**
 * 左栏上限(vp),**只对非折叠设备生效**。平板横屏 1440vp 对半是 720,右栏读正文用不了这么宽的
 * 目录,封到 420(与改造前写死的值一致)。
 *
 * 折叠屏展开态豁免这条上限:内屏是对折出来的,折痕必在几何中线,左栏取满一半分割线才压在折痕上——
 * 内屏 741vp 时算出 370,本来就没触顶;阔折叠(Pura X Max 展开横持 939vp)对半是 470,会被 420
 * 夹住,分割线偏离折痕约 50vp,正是这条豁免要救的场景。
 *
 * 已知不足:三折叠 G 态横持 1107vp 有两条折痕(369 / 738),对半的 553 哪条都不压。要对准得改用
 * display.getCurrentFoldCreaseRegion() 读真实折痕,复杂度不划算,暂留不对齐。
 */
export const SPLIT_NAV_BAR_MAX_WIDTH: number = 420;

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
    // 左栏宽先播种为上限(平板横屏的取值):首帧尺寸还没进来时用它,避免闪一下窄栏。
    if (AppStorage.get<number>(APP_SPLIT_NAV_BAR_WIDTH_STORAGE_KEY) === undefined) {
      AppStorage.setOrCreate(APP_SPLIT_NAV_BAR_WIDTH_STORAGE_KEY, SPLIT_NAV_BAR_MAX_WIDTH);
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
   * 由布局回调喂入当前窗口尺寸(vp),折算宽屏标志与双栏左栏宽,仅在变化时写回,避免无谓刷新。
   *
   * 两个值都在这里算,是因为它们同吃「是否展开态」这个输入:折叠/展开时窗口尺寸与折叠状态未必
   * 同一帧到达,若左栏宽留在 onAreaChange 里各算各的,先到的尺寸会用过期的折叠状态算出 420 并
   * 就此定死(foldStatusChange 的重算够不着它)。放一起后 reapply 一次把两个都刷新。
   *
   * 判定规则见 isWideLayout / splitNavBarWidth。
   */
  static applySize(widthVp: number, heightVp: number): void {
    BreakpointManager.lastWidthVp = widthVp;
    BreakpointManager.lastHeightVp = heightVp;
    const unfolded: boolean = BreakpointManager.isUnfolded();
    const wide: boolean = BreakpointManager.isWideLayout(widthVp, heightVp, unfolded);
    if (AppStorage.get<boolean>(APP_IS_WIDE_STORAGE_KEY) !== wide) {
      AppStorage.setOrCreate(APP_IS_WIDE_STORAGE_KEY, wide);
    }
    const navBarWidth: number = BreakpointManager.splitNavBarWidth(widthVp, unfolded);
    if (AppStorage.get<number>(APP_SPLIT_NAV_BAR_WIDTH_STORAGE_KEY) !== navBarWidth) {
      AppStorage.setOrCreate(APP_SPLIT_NAV_BAR_WIDTH_STORAGE_KEY, navBarWidth);
    }
  }

  /**
   * 纯函数版左栏宽:窗口宽的一半,夹进 [320, 420];折叠屏展开态不封上限,让分割线压在折痕上。
   * 理由与已知不足见 SPLIT_NAV_BAR_MAX_WIDTH。
   */
  static splitNavBarWidth(widthVp: number, unfolded: boolean): number {
    const half: number = Math.max(Math.round(widthVp * SPLIT_NAV_BAR_RATIO), SPLIT_NAV_BAR_MIN_WIDTH);
    return unfolded ? half : Math.min(half, SPLIT_NAV_BAR_MAX_WIDTH);
  }

  /**
   * 纯函数版判定:给定窗口尺寸(vp)与折叠屏是否展开,算「当前窗口是否适合双栏」。
   * 不碰 display / AppStorage,便于单测覆盖各机型形态。
   *
   * 两条路任一成立即双栏:
   *   ① 够宽(≥840)**且**横着(宽 > 高)——平板横屏、阔折叠展开横持(939×664)。只看宽度不够:
   *      大屏平板竖屏宽度就有 965vp,光凭阈值同样会被判成宽屏、竖屏照样分栏(单纯抬高阈值又会
   *      误伤窄的平板横屏),加上长宽比这一刀,「竖屏一律单栏」才与设备无关地成立;左右分屏
   *      (半宽)也自然落回单栏。
   *   ② 折叠屏展开、宽度 ≥600 **且**内屏近方形——竖折叠内屏(741×832)竖着拿也该双栏,①的
   *      长宽比这一刀对它不适用;近方形这个限制是为了把阔折叠竖持挡在外面,见
   *      UNFOLDED_SQUARE_RATIO_MAX。
   */
  static isWideLayout(widthVp: number, heightVp: number, unfolded: boolean): boolean {
    const landscapeWide: boolean = widthVp >= WIDE_THRESHOLD_VP && widthVp > heightVp;
    const unfoldedWide: boolean = unfolded && widthVp >= UNFOLDED_WIDE_THRESHOLD_VP &&
      BreakpointManager.isNearSquare(widthVp, heightVp);
    return landscapeWide || unfoldedWide;
  }

  /** 长边 / 短边是否落在近方形范围内。尺寸非法(≤0)时判否,顺带避开除零。 */
  private static isNearSquare(widthVp: number, heightVp: number): boolean {
    const shortSide: number = Math.min(widthVp, heightVp);
    const longSide: number = Math.max(widthVp, heightVp);
    if (shortSide <= 0) {
      return false;
    }
    return longSide / shortSide <= UNFOLDED_SQUARE_RATIO_MAX;
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
