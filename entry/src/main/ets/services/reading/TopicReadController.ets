import { Log } from '../logging/Log';
import { TopicDetail, TopicPost } from '../../models/TopicDetail';
import { AppStateEventBus } from '../session/AppStateEventBus';
import { TopicReadState, TopicReadStateEventBus } from '../session/TopicReadStateEventBus';
import { ReadingTracker, ReportTimingsFn } from './ReadingTracker';
import { LoginGate } from '../session/LoginGate';

// 相邻楼层错峰翻已读的间隔:让蓝点淡出动画自上而下依次开始,对齐官网的级联观感。
const READ_STAGGER_STEP_MS: number = 80;
// 离开详情页后,延迟这么久再做"回传已读状态 + 最后一次 timings 上报"。
// 目的是让这两件事落在 Navigation 转场动画结束之后:回传会触发列表页 item 重渲染,上报要经
// ArkWeb 桥 runJavaScript 发请求,压在 pop 那一帧上会掉帧。二者都是"发出去就不管"的收尾,
// 晚这么一会儿对语义没有任何影响。取值略大于系统转场时长(~350ms)。
const DETACH_DEFER_MS: number = 600;

export type DetailProvider = () => TopicDetail | undefined;
export type PostsProvider = () => TopicPost[];

// 详情页已读追踪控制器:托管 ReadingTracker 的启停/焦点胶水、"已读到哪"的水位计算、
// 错峰翻已读动画,以及离开页面时把已读状态回传列表页(消蓝点、更新未读徽标)。
// 通过 provider 闭包读取页面 @State 的 detail/posts(posts 分页后会换新数组,不能在启动时捕获快照);
// 翻已读直接对 @Observed 的 TopicPost 赋值,由 @ObjectLink 精准重渲染,不经过页面。
export class TopicReadController {
  private getDetail: DetailProvider;
  private getPosts: PostsProvider;
  private tracker: ReadingTracker = new ReadingTracker();
  private started: boolean = false;
  private unsubscribeAppState?: () => void = undefined;
  private staggerTimers: number[] = [];
  // 本次浏览进入过视口的最高楼号:作为"已读到哪"的水位,用于返回时算真实剩余未读。
  // 比依赖停留时长的 post.read 更贴合"我看过了就算读了"的预期,避免徽标卡住不更新。
  private maxSeenPostNumber: number = 0;

  constructor(getDetail: DetailProvider, getPosts: PostsProvider) {
    this.getDetail = getDetail;
    this.getPosts = getPosts;
  }

  // 页面挂载:订阅 App 前后台切换,驱动阅读计时的焦点(对齐 Discourse session.hasFocus)。
  attach(): void {
    if (!this.unsubscribeAppState) {
      this.unsubscribeAppState = AppStateEventBus.subscribe((isForeground: boolean) => {
        this.tracker.setFocus(isForeground);
      });
    }
  }

  // 页面离开。同步只做必须立刻做的部分:停表结算(晚停会把用户离开后的时间也算进阅读时长)、
  // 清掉未触发的错峰定时器与前后台订阅。把"回传已读状态给列表页"和"最后一次 timings 上报"
  // 推迟 DETACH_DEFER_MS 再做,让它们落在转场动画之后——见该常量的注释。
  //
  // 注意:延迟回调执行时详情页组件已销毁,provider 闭包(getDetail/getPosts)不能再碰。
  // 所以回传载荷在这里同步算好(两趟数组遍历,很便宜)再捕获进闭包。
  detach(): void {
    const payload: TopicReadState | undefined = this.buildReadStatePayload();
    const wasRunning: boolean = this.tracker.stopTiming();
    this.started = false;

    for (let index: number = 0; index < this.staggerTimers.length; index++) {
      clearTimeout(this.staggerTimers[index]);
    }
    this.staggerTimers = [];

    if (this.unsubscribeAppState) {
      this.unsubscribeAppState();
      this.unsubscribeAppState = undefined;
    }

    const tracker: ReadingTracker = this.tracker;
    setTimeout(() => {
      if (payload) {
        TopicReadStateEventBus.publish(payload);
      }
      if (wasRunning) {
        tracker.flushPending();
      }
    }, DETACH_DEFER_MS);
  }

  // 详情加载成功后启动计时上报。未登录一律不启动:匿名 POST /topics/timings 会被后端拒,
  // 且 Discourse 匿名话题响应里 post 仍带 read(boolean),不能靠"响应是否含已读字段"推断登录态,
  // 必须以全局登录闸门为准(避免未登录时定时器不停发 timings 报错)。
  startIfNeeded(reportFn: ReportTimingsFn, logTag: string): void {
    const detail: TopicDetail | undefined = this.getDetail();
    if (this.started || !detail) {
      return;
    }
    if (!LoginGate.isLoggedIn()) {
      return;
    }
    if (!this.hasServerReadState()) {
      return;
    }

    this.tracker.setFocus(AppStateEventBus.isForeground());
    this.tracker.start(
      detail.id,
      reportFn,
      (postNumbers: number[]) => this.markPostsRead(postNumbers),
      (postNumbers: number[], reporting: boolean) => this.markPostsReporting(postNumbers, reporting)
    );
    this.tracker.seedRead(this.collectAlreadyReadPostNumbers());
    this.started = true;
    Log.i(`${logTag} reading tracker started topicId=${detail.id}`);
  }

  // 可见楼层范围变化(入参为 posts 数组下标,列表头部占位的换算由页面完成):
  // 记录"看到过"的最高楼号水位、同步在屏楼层给计时器、刷新防挂机的滚动时间戳。
  // postEndIndex 可能落在底部"加载更多"占位上,超界则夹到最后一楼。
  onVisibleRange(postStartIndex: number, postEndIndex: number): void {
    const posts: TopicPost[] = this.getPosts();

    let seenIndex: number = postEndIndex;
    if (seenIndex >= posts.length) {
      seenIndex = posts.length - 1;
    }
    if (seenIndex >= 0) {
      const postNumber: number = posts[seenIndex].postNumber;
      if (postNumber > this.maxSeenPostNumber) {
        this.maxSeenPostNumber = postNumber;
      }
    }

    if (this.started) {
      const postNumbers: number[] = [];
      for (let index: number = postStartIndex; index <= postEndIndex; index++) {
        if (index >= 0 && index < posts.length) {
          postNumbers.push(posts[index].postNumber);
        }
      }
      this.tracker.setOnscreen(postNumbers);
    }

    this.tracker.scrolled();
  }

  // 算出要回传给列表页的已读状态:蓝点消失(unseen=false),未读徽标 = 最高楼号 − 已读到的最高楼号
  // (可能只加载了部分楼层,但 highestPostNumber/stream 在首屏就给了全量总数,所以未读数依然准确)。
  // 只负责算、不负责发:发的时机由 detach 推迟到转场之后。返回 undefined 表示这次不该回传。
  private buildReadStatePayload(): TopicReadState | undefined {
    const detail: TopicDetail | undefined = this.getDetail();
    if (!detail) {
      return undefined;
    }
    // 匿名或响应无已读态时不上报,避免把服务端真实状态误清。
    if (!this.hasServerReadState()) {
      return undefined;
    }

    const highest: number = this.highestKnownPostNumber();
    const highestRead: number = this.highestReadPostNumber();
    const unread: number = Math.max(0, highest - highestRead);
    return {
      topicId: detail.id,
      unseen: false,
      unreadPosts: unread
    };
  }

  private highestKnownPostNumber(): number {
    const posts: TopicPost[] = this.getPosts();
    let highest: number = this.getDetail()?.highestPostNumber ?? 0;
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].postNumber > highest) {
        highest = posts[index].postNumber;
      }
    }
    return highest;
  }

  private highestReadPostNumber(): number {
    // 三个信号取最高:服务端加载时的旧水位、本次浏览到的最高楼号、已翻真的 read 楼号。
    const posts: TopicPost[] = this.getPosts();
    let watermark: number = this.getDetail()?.lastReadPostNumber ?? 0;
    if (this.maxSeenPostNumber > watermark) {
      watermark = this.maxSeenPostNumber;
    }
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      if (post.read === true && post.postNumber > watermark) {
        watermark = post.postNumber;
      }
    }
    return watermark;
  }

  private hasServerReadState(): boolean {
    const detail: TopicDetail | undefined = this.getDetail();
    if (detail && detail.lastReadPostNumber !== undefined) {
      return true;
    }
    const posts: TopicPost[] = this.getPosts();
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].read !== undefined) {
        return true;
      }
    }
    return false;
  }

  private collectAlreadyReadPostNumbers(): number[] {
    const posts: TopicPost[] = this.getPosts();
    const watermark: number = this.getDetail()?.lastReadPostNumber ?? -1;
    const out: number[] = [];
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      const read: boolean = post.read === true ||
        (post.read === undefined && watermark >= 0 && post.postNumber <= watermark);
      if (read) {
        out.push(post.postNumber);
      }
    }
    return out;
  }

  // 上报进行中:把本批楼层标记为 reporting,让蓝点进入"呼吸"态;结束(成功/失败)时清除。
  // 已翻已读的楼层跳过(它们已淡出,呼吸无意义)。直接改 @Observed 字段驱动 @ObjectLink 重渲染。
  private markPostsReporting(postNumbers: number[], reporting: boolean): void {
    const posts: TopicPost[] = this.getPosts();
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      if (postNumbers.indexOf(post.postNumber) < 0) {
        continue;
      }
      if (reporting && post.read === true) {
        continue;
      }
      post.reporting = reporting;
    }
  }

  private markPostsRead(postNumbers: number[]): void {
    // 收集本批需新标已读的楼层,按楼号升序错峰(自上而下)翻已读。
    const posts: TopicPost[] = this.getPosts();
    const pending: TopicPost[] = [];
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      if (post.read !== true && postNumbers.indexOf(post.postNumber) >= 0) {
        pending.push(post);
      }
    }
    if (pending.length === 0) {
      return;
    }

    pending.sort((a: TopicPost, b: TopicPost) => a.postNumber - b.postNumber);
    for (let order: number = 0; order < pending.length; order++) {
      const post: TopicPost = pending[order];
      // @Observed 实例赋值 → TopicPostItem(@ObjectLink)重渲染 → 蓝点淡出。
      const timerId: number = setTimeout(() => {
        post.read = true;
      }, order * READ_STAGGER_STEP_MS);
      this.staggerTimers.push(timerId);
    }
  }
}
