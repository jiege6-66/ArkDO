import { ImagePreview, PreviewDirection } from '@rv/image-preview';
import { componentUtils } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { ON_DARK_FG } from '../../common/theme/Palette';
import { FaIconView, getFaIcon, FaIconDefinition } from './FaIcon';
import { ImageShareService } from '../../services/content/ImageShareService';
import { showToast } from '../../common/utils/Toast';

/**
 * 一张待浏览的图片：url 为首选（原图 href，高清），优化图作为兜底。
 * fallbackUrl 为优化图 src（与贴子内联同源、多已缓存），原图加载失败时回退。
 * heroId 为列表里该图源节点挂的 .id()，供 hero 转场按它现查源节点几何；
 * 缺省（来源组件没挂）时该图自动降级为淡入淡出。
 */
export interface ViewerImage {
  url: string;
  fallbackUrl: string;
  heroId?: string;
}

// hero 飞行矩形，单位 vp，坐标系为窗口（见 sourceRect 注释）
interface HeroRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

// 预览可见态镜像 + 系统返回键信号:浮层不进 Navigation 栈,返回键由 Index @Entry 拦截并
// bump 计数,经 RootTabPage 以 @Param 传入本组件消费(非首图翻回上一张,首图才关闭)。

const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;
const DOUBLE_TAP_SCALE: number = 2.5;

// 拖动关闭：竖直位移绝对值超过该阈值即关闭，否则回弹（上/下拖同等）
const DISMISS_THRESHOLD: number = 120;
// 缩放估计值高于该值即视为「已放大」，此时禁用拖动关闭（让位给库的图片平移）
const ZOOM_EPSILON: number = 1.05;

// hero 飞入/飞回时长；无 hero 可用时退化成的淡入淡出时长
const HERO_IN_MS: number = 280;
const HERO_OUT_MS: number = 260;
const FADE_MS: number = 220;
// 无 hero 时淡入淡出附带的轻微缩放起点，纯粹为了不那么生硬
const FADE_SCALE: number = 0.94;
// 源节点可见面积占自身面积低于此比例即视作「已滚出视野」：此时不飞回去
// （会看到图片甩向屏幕外），改为淡出。
const HERO_MIN_VISIBLE_RATIO: number = 0.25;
// 预览根容器 id：hero 起飞前靠它量一次视口尺寸（= 整窗），算落位矩形。
const VIEWER_ROOT_ID: string = 'arkdo-image-viewer-root';
// 顶栏按钮尺寸（左上关闭 / 右上分享共用）
const TOP_BUTTON_SIZE: number = 40;
// 分享面板上给这张图的标题
const SHARE_TITLE: string = '分享图片';

/**
 * 全屏图片浏览器：Swiper 管多图翻页，每页用三方库 @rv/image-preview 的 ImagePreview
 * 承载缩放/平移/双击。direction=Horizontal：水平平移到边界让给横向 Swiper 翻页（多图切换的必需项）。
 * 注意这是库的取舍——Horizontal 不夹竖直（放大后可把图拖出屏外），Vertical 虽夹竖直却会吃掉水平、翻页失效，
 * 二者不可兼得；多图翻页优先，故用 Horizontal，竖直越界是库限制暂无法外部修正。
 * 需在页面级渲染（放页面根 Stack 顶层），不能塞进 bindContentCover——其内容不随状态刷新。
 *
 * hero 转场自己接管（库只有缩放/平移配置，不提供任何转场或顶栏能力）：
 * 独立一层绝对定位的 Image，打开时从源节点矩形飞到整窗，关闭时飞回「当前这张」的源节点矩形。
 * 起止两端都是 ImageFit.Contain：源缩略图本身也是 Contain，故两端画面与静态时逐像素一致，
 * 落位后把 hero 换成真正的 Swiper 内容看不出接缝。
 */
@ComponentV2
export struct ImageViewer {
  @Param images: ViewerImage[] = [];
  @Param startIndex: number = 0;
  @Param onClose: () => void = () => {};
  // 系统返回键信号计数(Index 拦截后 bump):非首图翻回上一张,首图关闭预览。
  @Param backTick: number = 0;

  @Local currentIndex: number = 0;
  @Local failedIndexes: number[] = [];
  // 高清原图已加载完成的页下标（隐藏该页 loading 指示）
  @Local loadedIndexes: number[] = [];
  // 顶部状态栏高度，用于让关闭按钮避让状态栏
  @Local topInset: number = 0;
  // 拖动关闭的实时竖直位移（>0 向下、<0 向上拖动中）
  @Local dragOffsetY: number = 0;
  // 缩放估计值：库不暴露真实 scale，靠并行的双击/双指手势自维护，仅用于判断「是否已放大」。
  // 未放大(≈1)才放行拖动关闭；放大后禁用，把竖直拖动让给库的图片平移。
  @Local scaleGuess: number = 1;
  // hero 图层：挂载后常驻（只切透明度），使关闭时飞行的起点是早已提交过的矩形，
  // 不存在「同一帧刚赋值就动画」导致从 0,0 起飞的问题。
  @Local heroMounted: boolean = false;
  @Local heroOpacity: number = 0;
  @Local heroRect: HeroRect = { x: 0, y: 0, w: 0, h: 0 };
  // Swiper 及各浮层（页码、转圈、按钮）的整体透明度/缩放：hero 飞行期间藏起来，落位瞬间显形。
  @Local contentOpacity: number = 1;
  @Local contentScale: number = 1;
  // 黑底不透明度：打开时 0→1，关闭时 →0（拖动消隐另算，见 backdropColor）
  @Local backdropAlpha: number = 1;
  // 分享进行中（下载 + 拉面板）：按钮换转圈并拒绝重复点击。
  @Local sharing: boolean = false;
  private pinchBase: number = 1;
  // 视口尺寸（vp）：hero 落位矩形 = 整窗，onAppear 量一次，旋转时随 onAreaChange 更新。
  private viewW: number = 0;
  private viewH: number = 0;
  // 关闭动画进行中：拦截重复触发，并让飞入动画的 onFinish 不再回写状态。
  private closing: boolean = false;
  // 返回键翻页用控制器:showPrevious 带切换动画并触发 onChange(直接改 .index 无动画)。
  private swiperController: SwiperController = new SwiperController();

  // 返回键:非首图翻回上一张(动画翻页,onChange 会同步 currentIndex 并重置缩放估计),首图关闭。
  @Monitor('backTick')
  onBackTick(): void {
    if (this.currentIndex > 0) {
      this.swiperController.showPrevious();
      return;
    }
    this.requestClose();
  }

  aboutToAppear(): void {
    this.currentIndex = this.clampIndex(this.startIndex);
    // 状态栏高度读全局插图(ImmersiveWindow 维护):预览打开时状态栏可能已被隐藏,
    // 此刻查 getWindowAvoidArea 会得 0,关闭按钮就会顶进挖孔/刘海区;AppStorage 里是冻结的真实高度。
    this.topInset = (AppStorage.get(SYS_TOP_INSET_KEY) as number | undefined) ?? 0;
    // hero 起点必须在首帧之前就位（首帧渲染成源节点大小），onAppear 里才有东西可动画。
    // 源节点在底层页面里,此刻已完成布局,查得到几何;本组件自己的几何要等 onAppear。
    const src: HeroRect | undefined = this.sourceRect(this.currentIndex);
    if (src !== undefined) {
      this.heroRect = src;
      this.heroMounted = true;
      this.heroOpacity = 1;
      this.contentOpacity = 0;
      this.backdropAlpha = 0;
      return;
    }
    // 拿不到源节点几何：退化为淡入
    this.contentOpacity = 0;
    this.contentScale = FADE_SCALE;
    this.backdropAlpha = 0;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Swiper(this.swiperController) {
        Repeat<ViewerImage>(this.images).each((ri: RepeatItem<ViewerImage>) => {
          ImagePreview({
            config: {
              minScale: MIN_SCALE,
              maxScale: MAX_SCALE,
              doubleClickDefaultScale: DOUBLE_TAP_SCALE,
              // Horizontal：水平到边界让给横向 Swiper 翻页（多图切换必需）。
              // 换 Vertical 会夹住竖直但吃掉水平、导致翻页失效，故保持 Horizontal。
              direction: PreviewDirection.Horizontal,
              onClick: () => {
                this.requestClose();
              }
            }
          }) {
            // 渐进加载：底层优化图（已缓存、秒显占位，避免高清图未回来时纯黑），
            // 顶层高清原图加载完成后覆盖；高清失败则回退优化图。
            Stack() {
              Image(this.placeholderUrl(ri.index))
                .objectFit(ImageFit.Contain)
                .width('100%')
                .height('100%')
                .draggable(false)

              Image(this.resolveUrl(ri.index))
                .objectFit(ImageFit.Contain)
                .width('100%')
                .height('100%')
                .draggable(false)
                .onComplete(() => {
                  this.markLoaded(ri.index);
                })
                .onError(() => {
                  this.markFailed(ri.index);
                  // 回退到优化图后也算「已就绪」，隐藏 loading
                  this.markLoaded(ri.index);
                })
            }
            .width('100%')
            .height('100%')
          }
        })
      }
      .index(this.currentIndex)
      .loop(false)
      .indicator(false)
      .width('100%')
      .height('100%')
      // 让图片视口也扩展到状态栏/导航条区域，放大后能铺满全屏
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      // 拖动关闭时整页内容随手指上/下移
      .translate({ y: this.dragOffsetY })
      .scale({ x: this.contentScale, y: this.contentScale })
      .opacity(this.contentOpacity)
      .onChange((index: number) => {
        this.currentIndex = index;
        // 翻页后库会重置该页缩放，同步重置估计值，让新页可下滑关闭
        this.scaleGuess = 1;
        this.dragOffsetY = 0;
      })

      // 高清原图加载中的转圈（当前页未就绪且未失败时显示；优化图已垫底，仅提示高清在路上）
      if (!this.isLoaded(this.currentIndex) && this.failedIndexes.indexOf(this.currentIndex) < 0) {
        Column() {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(ON_DARK_FG)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .opacity(this.contentOpacity)
        .hitTestBehavior(HitTestMode.None)
      }

      // 页码指示（多图时显示），透传点击不拦截手势
      if (this.images.length > 1) {
        Column() {
          Text(`${this.currentIndex + 1} / ${this.images.length}`)
            .fontSize(14)
            .fontColor(ON_DARK_FG)
            .backgroundColor('#00000080')
            .borderRadius(14)
            .padding({ left: 14, right: 14, top: 5, bottom: 5 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: 44 })
        .opacity(this.contentOpacity)
        .hitTestBehavior(HitTestMode.None)
      }

      // 关闭按钮（下移 topInset 避让状态栏）
      Text('✕')
        .fontSize(20)
        .fontColor(ON_DARK_FG)
        .width(TOP_BUTTON_SIZE)
        .height(TOP_BUTTON_SIZE)
        .textAlign(TextAlign.Center)
        .borderRadius(TOP_BUTTON_SIZE / 2)
        .backgroundColor('#00000066')
        .margin({ top: this.topInset + 12, left: 12 })
        .opacity(this.contentOpacity)
        .onClick(() => {
          this.requestClose();
        })

      // 分享按钮：与关闭按钮同一条顶栏,靠右。外层 Row 只是把它推到右边,
      // hitTestBehavior 设 Transparent,让顶栏空白处的点击照旧落到下面的图上（= 关闭）。
      Row() {
        Stack() {
          if (this.sharing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(ON_DARK_FG)
          } else {
            FaIconView({ icon: this.faIcon('share-nodes'), color: ON_DARK_FG, iconSize: 18 })
          }
        }
        .width(TOP_BUTTON_SIZE)
        .height(TOP_BUTTON_SIZE)
        .borderRadius(TOP_BUTTON_SIZE / 2)
        .backgroundColor('#00000066')
        .onClick(() => {
          this.shareCurrent();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12 })
      .margin({ top: this.topInset + 12 })
      .opacity(this.contentOpacity)
      .hitTestBehavior(HitTestMode.Transparent)

      // hero 图层：坐标为窗口坐标（本组件是根 Stack 直挂的全窗浮层，原点即窗口原点）。
      // y 恒加上 dragOffsetY——关闭动画里 dragOffsetY 与 heroRect 一起收敛，
      // 拖到一半松手也能从手指所在处接着飞回原位。
      if (this.heroMounted) {
        Image(this.heroUrl(this.currentIndex))
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .width(this.heroRect.w)
          .height(this.heroRect.h)
          .position({ x: this.heroRect.x, y: this.heroRect.y + this.dragOffsetY })
          .opacity(this.heroOpacity)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .id(VIEWER_ROOT_ID)
    .width('100%')
    .height('100%')
    // 黑底：下滑关闭时随位移渐透，露出身后页面（iOS 风格拖拽消隐）
    .backgroundColor(this.backdropColor())
    // 铺满顶部状态栏 + 底部导航条安全区，黑底沉浸式，避免露白
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAppear(() => {
      this.startEnter();
    })
    // 旋转/分屏改变视口：hero 空闲时把它的落位矩形同步成新整窗，避免之后按旧尺寸起飞。
    .onAreaChange((_: Area, area: Area) => {
      this.viewW = Number(area.width);
      this.viewH = Number(area.height);
      if (this.heroMounted && this.heroOpacity === 0 && !this.closing) {
        this.heroRect = { x: 0, y: 0, w: this.viewW, h: this.viewH };
      }
    })
    // 并行手势：与库内手势共存。双击/双指仅用于自维护缩放估计；竖直 Pan 做「未放大时上/下拖关闭」。
    .parallelGesture(
      GestureGroup(GestureMode.Parallel,
        TapGesture({ count: 2 })
          .onAction(() => {
            this.scaleGuess = this.scaleGuess > ZOOM_EPSILON ? MIN_SCALE : DOUBLE_TAP_SCALE;
          }),
        PinchGesture()
          .onActionStart(() => {
            this.pinchBase = this.scaleGuess;
          })
          .onActionUpdate((event: GestureEvent) => {
            const next: number = this.pinchBase * event.scale;
            this.scaleGuess = next < MIN_SCALE ? MIN_SCALE : (next > MAX_SCALE ? MAX_SCALE : next);
          }),
        PanGesture({ direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => {
            // 已放大 → 让位给库的图片平移；未放大时上/下拖均可关闭
            if (this.scaleGuess > ZOOM_EPSILON) {
              this.dragOffsetY = 0;
              return;
            }
            this.dragOffsetY = event.offsetY;
          })
          .onActionEnd(() => {
            if (this.scaleGuess > ZOOM_EPSILON) {
              return;
            }
            if (Math.abs(this.dragOffsetY) > DISMISS_THRESHOLD) {
              this.requestClose();
              return;
            }
            this.springBack();
          })
          .onActionCancel(() => {
            this.springBack();
          })
      )
    )
  }

  // 入场：首帧已把 hero 渲染成源节点大小（aboutToAppear 里定的），这里才起飞到整窗。
  // 分两帧是必须的——同一帧里赋值再动画，起点会取不到刚写入的值。
  private startEnter(): void {
    this.measureViewport();
    if (this.heroMounted && this.viewW > 0 && this.viewH > 0) {
      this.getUIContext().animateTo({
        duration: HERO_IN_MS,
        curve: Curve.Friction,
        onFinish: () => {
          // 已在关闭中就不要回写了，否则会把关闭动画的状态覆盖掉
          if (this.closing) {
            return;
          }
          // 落位矩形与 Swiper 里那张图逐像素重合，直接对调看不出接缝
          this.contentOpacity = 1;
          this.heroOpacity = 0;
        }
      }, () => {
        this.heroRect = { x: 0, y: 0, w: this.viewW, h: this.viewH };
        this.backdropAlpha = 1;
      });
      return;
    }
    // 没有 hero（或视口没量到）：退化为淡入
    this.heroMounted = false;
    this.getUIContext().animateTo({ duration: FADE_MS, curve: Curve.EaseOut }, () => {
      this.contentOpacity = 1;
      this.contentScale = 1;
      this.backdropAlpha = 1;
    });
  }

  /**
   * 统一的关闭入口（✕ / 单击 / 首图返回键 / 拖动过阈值都走这里）。
   * 关键点：源节点按「当前这张」现查，不是打开时那张——多图左右翻过之后关闭，
   * 缩回去的是当前这张自己的原位。查不到（没挂 heroId / 已滚出视野）或当前处于放大态时
   * 退化为淡出：放大态下库内的 matrix 外部拿不到，飞回去必然错位。
   */
  private requestClose(): void {
    if (this.closing) {
      return;
    }
    this.closing = true;
    const zoomed: boolean = this.scaleGuess > ZOOM_EPSILON;
    const src: HeroRect | undefined = zoomed ? undefined : this.sourceRect(this.currentIndex);
    if (this.heroMounted && src !== undefined) {
      // 起点是早已提交过的整窗矩形（入场落位时写入），可以直接动画到源矩形。
      // 与 Swiper 的对调放在动画外，同帧生效，两者位置重合故看不出切换。
      this.heroOpacity = 1;
      this.contentOpacity = 0;
      this.getUIContext().animateTo({
        duration: HERO_OUT_MS,
        curve: Curve.Friction,
        onFinish: () => {
          this.onClose();
        }
      }, () => {
        this.heroRect = src;
        this.dragOffsetY = 0;
        this.backdropAlpha = 0;
      });
      return;
    }
    this.getUIContext().animateTo({
      duration: FADE_MS,
      curve: Curve.EaseIn,
      onFinish: () => {
        this.onClose();
      }
    }, () => {
      this.heroOpacity = 0;
      this.contentOpacity = 0;
      this.contentScale = FADE_SCALE;
      this.backdropAlpha = 0;
    });
  }

  /**
   * 分享当前这张图：先下到沙箱再交系统分享面板——面板认 uri 不认 https 链接,
   * 直接塞链接只会被当成一条文本分享出去。分享的是高清原图（原图失败过就是回退后的那张,
   * 与屏上所见一致）。下载期间按钮转圈,预览层不关闭,分享完仍停在原图上。
   */
  private shareCurrent(): void {
    if (this.sharing || this.closing) {
      return;
    }
    const url: string = this.resolveUrl(this.currentIndex);
    if (url.length === 0) {
      return;
    }
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return;
    }
    this.sharing = true;
    ImageShareService.share(context, url, SHARE_TITLE).then((ok: boolean) => {
      this.sharing = false;
      if (!ok) {
        showToast(this.getUIContext(), '分享失败,请稍后重试');
      }
    }).catch(() => {
      this.sharing = false;
      showToast(this.getUIContext(), '分享失败,请稍后重试');
    });
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }

  // 量视口（= 整窗）：hero 的落位矩形。onAreaChange 也会写，这里保证入场时一定有值。
  private measureViewport(): void {
    if (this.viewW > 0 && this.viewH > 0) {
      return;
    }
    try {
      const info: componentUtils.ComponentInfo =
        this.getUIContext().getComponentUtils().getRectangleById(VIEWER_ROOT_ID);
      this.viewW = px2vp(info.size.width);
      this.viewH = px2vp(info.size.height);
    } catch (err) {
      this.viewW = 0;
      this.viewH = 0;
    }
  }

  /**
   * 取第 index 张图在底层页面里的源节点矩形（窗口坐标，vp）。
   * 预览是浮层、底层页面并未卸载，所以源节点全程还在，几何随时可查。
   * 返回 undefined 的三种情况：没挂 heroId / 查不到节点 / 已滚出视野。
   */
  private sourceRect(index: number): HeroRect | undefined {
    if (index < 0 || index >= this.images.length) {
      return undefined;
    }
    const heroId: string | undefined = this.images[index].heroId;
    if (heroId === undefined || heroId.length === 0) {
      return undefined;
    }
    try {
      const info: componentUtils.ComponentInfo =
        this.getUIContext().getComponentUtils().getRectangleById(heroId);
      const rect: HeroRect = {
        x: px2vp(info.windowOffset.x),
        y: px2vp(info.windowOffset.y),
        w: px2vp(info.size.width),
        h: px2vp(info.size.height)
      };
      if (rect.w <= 0 || rect.h <= 0) {
        return undefined;
      }
      if (!this.isMostlyVisible(rect)) {
        return undefined;
      }
      return rect;
    } catch (err) {
      return undefined;
    }
  }

  // 源节点与视口的交叠面积是否够大。视口还没量到（入场首帧）时一律放行——
  // 那一刻的源节点就是用户刚点的那张，必然在视野里。
  private isMostlyVisible(rect: HeroRect): boolean {
    if (this.viewW <= 0 || this.viewH <= 0) {
      return true;
    }
    const left: number = Math.max(rect.x, 0);
    const top: number = Math.max(rect.y, 0);
    const right: number = Math.min(rect.x + rect.w, this.viewW);
    const bottom: number = Math.min(rect.y + rect.h, this.viewH);
    if (right <= left || bottom <= top) {
      return false;
    }
    const visible: number = (right - left) * (bottom - top);
    return visible / (rect.w * rect.h) >= HERO_MIN_VISIBLE_RATIO;
  }

  // hero 图层用哪张：高清已就位就用高清（关闭时与屏上画面一致，无画质回跳），
  // 否则用优化图（多已缓存，起飞瞬间就有内容，不会是块空白）。
  private heroUrl(index: number): string {
    if (this.isLoaded(index)) {
      return this.resolveUrl(index);
    }
    return this.placeholderUrl(index);
  }

  // 回弹到原位（拖动未过阈值）
  private springBack(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.dragOffsetY = 0;
    });
  }

  // 黑底透明度随拖动位移（上/下同等）递减，最低留 25% 黑（保证内容仍可辨）；
  // 再乘上开关场的整体不透明度 backdropAlpha。
  private backdropColor(): string {
    const fade: number = Math.abs(this.dragOffsetY) / 300;
    const clamped: number = fade > 0.75 ? 0.75 : fade;
    const alpha: number = Math.round((1 - clamped) * this.backdropAlpha * 255);
    let hex: string = alpha.toString(16);
    if (hex.length < 2) {
      hex = `0${hex}`;
    }
    return `#${hex}000000`;
  }

  // 占位图：优先用优化图（帖子内联同源、多已缓存，秒显）；没有则退回高清图本身
  private placeholderUrl(index: number): string {
    const item: ViewerImage = this.images[index];
    if (item.fallbackUrl.length > 0) {
      return item.fallbackUrl;
    }
    return item.url;
  }

  private resolveUrl(index: number): string {
    const item: ViewerImage = this.images[index];
    const failed: boolean = this.failedIndexes.indexOf(index) >= 0;
    if (failed && item.fallbackUrl.length > 0) {
      return item.fallbackUrl;
    }
    if (item.url.length > 0) {
      return item.url;
    }
    return item.fallbackUrl;
  }

  private isLoaded(index: number): boolean {
    return this.loadedIndexes.indexOf(index) >= 0;
  }

  private markLoaded(index: number): void {
    if (this.loadedIndexes.indexOf(index) >= 0) {
      return;
    }
    this.loadedIndexes = this.loadedIndexes.concat([index]);
  }

  private markFailed(index: number): void {
    const item: ViewerImage = this.images[index];
    if (item.fallbackUrl.length === 0 || item.fallbackUrl === item.url) {
      return;
    }
    if (this.failedIndexes.indexOf(index) >= 0) {
      return;
    }
    this.failedIndexes = this.failedIndexes.concat([index]);
  }

  private clampIndex(index: number): number {
    if (index < 0) {
      return 0;
    }
    if (index >= this.images.length) {
      return this.images.length > 0 ? this.images.length - 1 : 0;
    }
    return index;
  }
}
