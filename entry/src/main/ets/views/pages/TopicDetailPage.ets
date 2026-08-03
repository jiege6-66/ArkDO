import {
  ActionBarButton,
  ActionBarStyle,
  HdsActionBar,
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit';
import { ColorMetrics, LengthMetrics } from '@ohos.arkui.node';
import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { Log } from '../../services/logging/Log';
import { common } from '@kit.AbilityKit';
import { TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { PendingPost, Poll, PollVoteResult, PostBoost, ReactionUser, SharedIssueResult, TopicDetail, TopicPost } from '../../models/TopicDetail';
import { TopicCategory, TopicTag } from '../../models/Topic';
import { User } from '../../models/User';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { LoginGate } from '../../services/session/LoginGate';
import { TopicReadController } from '../../services/reading/TopicReadController';
import { CreateReplyOutcome, TopicService } from '../../services/topic/TopicService';
import { extractCreatedPostId, MessageBusEvent, MessageBusEventBus } from '../../services/message/MessageBusEventBus';
import { REALTIME_POSTS_ENABLED_STORAGE_KEY } from '../../services/realtime/RealtimePostsPrefs';
import { TopicPresenceService } from '../../services/presence/TopicPresenceService';
import { DraftService } from '../../services/draft/DraftService';
import { DraftEventBus } from '../../services/draft/DraftEventBus';
import { ChallengeShortcutEventBus } from '../../services/challenge/ChallengeShortcutEventBus';
import { ChallengeShortcutPrefs } from '../../services/challenge/ChallengeShortcutPrefs';
import { BookmarkToggleResult, PostActions } from '../../services/topic/PostActions';
import { PostDataSource } from '../../services/topic/PostDataSource';
import { PostStreamPager } from '../../services/topic/PostStreamPager';
import { ReactionUsersPager } from '../../services/topic/ReactionUsersPager';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { LOTTERY_TIP_ENABLED_STORAGE_KEY } from '../../services/topic/LotteryTipPrefs';
import {
  LOTTERY_REPLY_HINT,
  LOTTERY_REPLY_PLACEHOLDER,
  LOTTERY_RULES_TOPIC_URL,
  shouldShowLotteryNotice
} from '../../services/topic/LotteryTopicRule';
import { LoadStateView } from '../components/LoadStateView';
import { TopicDetailHeader } from '../components/TopicDetailHeader';
import { TopicSummaryCard } from '../components/TopicSummaryCard';
import { LotteryNoticeCard } from '../components/LotteryNoticeCard';
import { PendingPostCard } from '../components/PendingPostCard';
import { TopicPostItem } from '../components/TopicPostItem';
import { REPLYING_PRESENCE_BAR_HEIGHT, ReplyingPresenceBar } from '../components/ReplyingPresenceBar';
import { ViewerImage } from '../components/ImageViewer';
import { CommentInputBar, NO_MAX_CHARS, REPLY_BLUE } from '../components/CommentInputBar';
import { ComposerPage, COMPOSER_ANIM_MS } from './ComposerPage';
import { COMPOSER_OVERLAY_BACK_TICK_KEY, COMPOSER_OVERLAY_VISIBLE_KEY } from '../../common/constants/StorageKeys';
import { TopicScrubber } from '../components/TopicScrubber';
import { ReactionUsersSheet } from '../components/ReactionUsersSheet';
import { SYS_BOTTOM_INSET_KEY, SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { floatingActionBottomMargin } from '../../common/ui/FloatingActionLayout';
import { showToast as promptToast } from '../../common/utils/Toast';
import { SHADOW_SOFT } from '../../common/theme/Palette';
import {
  immersiveTitleBarBottomOffset,
  immersiveTitleBarContentTopSpacer
} from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';
import {
  buildImmersiveFloatingActionButtonModifier,
  IMMERSIVE_ACTION_BAR_BLUR_DISABLED
} from '../../common/ui/ImmersiveActionBarStyle';
import { FAB_GLASS_ENABLED_STORAGE_KEY } from '../../common/ui/FabGlassPrefs';
import {
  SMART_REACH_ANIMATION_DURATION,
  SMART_REACH_LEFT_HAND_STORAGE_KEY,
  smartReachBottomAlignRules
} from '../../common/ui/SmartReachLayout';

const LOG_TAG: string = '[ArkDO][TopicDetail]';
const POSTS_PAGE_SIZE: number = 20;
// 楼层预创建数(视口外上下各 N 条)，平衡快滑白块与内存占用。
const POSTS_CACHED_COUNT: number = 4;
// 向上预取阈值(posts 下标):离已加载区间顶部还剩这么多楼就开始"拉数据"——只入 pendingEarlier 缓存,
// 不碰数据源。拉取纯后台、不动画面,故提前量给足,让数据在视口进入插入安全窗之前就备好。
const EARLIER_PREFETCH_INDEX: number = 25;
// 顶部"正在加载更早的回复"悬浮胶囊开关:向上补楼是后台预取、用户没发起过动作,
// 弹提示反而打扰,故默认隐藏(产品观感待定,置 true 即恢复)。
// 注意:跳楼/回顶定位(isRewindowing)不受此开关管——那是用户主动点击触发的,
// 必须给反馈,否则点了没动静会以为没点上(实测在百楼外点标题回顶要等一会儿)。
const SHOW_LOADING_CAPSULE: boolean = false;
// 提交成功的 toast 延后到浮层完全收场(遮罩淡出 220ms、键盘收起约 270ms)之后再弹,
// 否则 toast 存活期横跨键盘收起的布局变化,会被重新锚定而在屏幕上跳一下。
const SUCCESS_TOAST_DELAY_MS: number = 350;
// boost 正文上限:服务端 16 字,超一个字就是不带原因的 422({"failed":"FAILED"}),故在客户端先拦。
const BOOST_MAX_CHARS: number = 16;
// 回帖草稿自动存防抖:停止输入这么久才真发一次(与发新主题同节奏)。
const REPLY_DRAFT_SAVE_DEBOUNCE_MS: number = 2000;
// 末尾加载行已有 54vp；再补这段空白与底部安全区，让最后一楼操作区完全越过 52vp 悬浮回复按钮。
const POST_LIST_BOTTOM_SPACER: number = 28;
// 实时新楼(MessageBus /topic created)去抖窗口:合并 ~400ms 内连着来的多条 created,一次批量拉。
const INCOMING_POST_DEBOUNCE_MS: number = 400;
// "N 条新回复"提示条高度。必须写死而非由 padding 撑开:它要与 52vp 悬浮回复按钮垂直居中对齐,
// 对齐算式需要确切的半高;交给内容撑高就只能用百分比锚点,而那条路已经证明会把胶囊顶出屏幕。
const INCOMING_BANNER_HEIGHT: number = 34;
// 提示条在"与悬浮回复按钮垂直居中"这个基准位之上再抬高多少。抬高的理由不是观感而是占位:
// 底部那一行要留给后续的「正在回复」头像区(它会与回复按钮垂直对齐),提示条得让开、浮在其上方。
// 实测值——基准位(抬高 0)确认过就是与按钮正中对齐,这 24 是在其上额外让出的余量。
const INCOMING_BANNER_LIFT: number = 24;
// 离开详情页后延迟这么久再去长轮询循环里删掉本帖频道。该操作要经 ArkWeb 桥 runJavaScript,
// 压在 pop 那一帧上会掉帧;推迟到转场动画结束之后再做。与 TopicReadController 的 DETACH_DEFER_MS 同理。
const CHANNEL_UNSUBSCRIBE_DEFER_MS: number = 600;

@Component({ freezeWhenInactive: true })
export struct TopicDetailPage {
  // 窗口常驻全屏布局:主内容列自行避让状态栏(padding 在带背景的列上,背景填满状态栏条);
  // 评论浮层/遮罩留在根 Stack 层不加避让,天然盖满整屏。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  @StorageProp(SYS_BOTTOM_INSET_KEY) private sysBottomInset: number = 0;
  @StorageProp(SMART_REACH_LEFT_HAND_STORAGE_KEY) @Watch('onSmartReachSideChanged')
  private smartReachLeftHanded: boolean = false;
  // 「悬浮按钮玻璃效果」开关(设置页-外观):开⇒模糊材质背板;关⇒当前透明样式。默认关。
  @StorageProp(FAB_GLASS_ENABLED_STORAGE_KEY) private fabGlassEnabled: boolean = false;
  @State private replyFabAlignRules: AlignRuleOption = smartReachBottomAlignRules(false);
  @State @Watch('syncTopicBookmarkFromDetail') private detail: TopicDetail | undefined = undefined;
  // 标题书签图标的独立驱动态:detail 是 interface 的 @State,改字段不触发重渲染,故用基元 @State 镜像。
  // detail 整体加载/替换时经 @Watch 从 detail.bookmarked 同步;楼层 toggle 收藏后由回调直接改写实现即时联动。
  @State private topicBookmarked: boolean = false;
  // 反应用户弹层状态由页面持有，避免 LazyForEach 的楼层项回收后丢失分页进度。
  @State private showReactionUsersSheet: boolean = false;
  @State private reactionUsersPost: TopicPost | undefined = undefined;
  @State private reactionUsers: ReactionUser[] = [];
  @State private reactionUsersTotal: number = 0;
  @State private selectedReactionUserFilter: string = '';
  @State private reactionUsersLoading: boolean = false;
  @State private reactionUsersHasMore: boolean = false;
  @State private reactionUsersInitialError: string = '';
  @State private reactionUsersLoadMoreError: string = '';
  private reactionUsersPager: ReactionUsersPager = new ReactionUsersPager();
  private reactionUsersNextPage: number = 0;
  private reactionUsersEpoch: number = 0;
  // 楼层真源:LazyForEach 数据源,增删经精准通知(maintainVisibleContentPosition 依赖)。
  // postCount 镜像总数驱动条件 UI(@State 观测不到 dataSource 内部变化),变更后须手动同步。
  private dataSource: PostDataSource = new PostDataSource();
  @State private postCount: number = 0;
  @State private isLoading: boolean = false;
  @State private message: string = '正在准备 ArkWeb 请求环境';
  @State private requiresChallenge: boolean = false;
  @State private categories: TopicCategory[] = [];
  // 当前用户在本主题下的待审核回复。detail 是 interface 的 @State,改其字段不触发重渲染,
  // 故这里持一份独立数组作真源:详情加载时从 detail.pendingPosts 灌入,发帖被扣审时乐观追加,
  // 撤回成功后就地移除。仅本人可见,不占楼号,不进 dataSource。
  @State private pendingPosts: PendingPost[] = [];
  @State private isLoadingMore: boolean = false;
  @State private hasMorePosts: boolean = false;
  @State private loadMoreMessage: string = '上拉加载更多';
  // 窗口式加载(从任意楼号进入)的向上分页:已加载区间之前是否还有更早楼层/是否正在补。
  @State private hasEarlier: boolean = false;
  @State private isLoadingEarlier: boolean = false;
  // 已拉到手但尚未插入的更早楼层。统一经 tryFlushEarlierPosts 精准头插，交给 List 的
  // maintainVisibleContentPosition 保持当前内容位置，避免额外滚动命令与 HDS 覆盖层坐标冲突。
  private pendingEarlier: TopicPost[] = [];
  // 窗口纪元:换窗/重载须作废在途预取与缓存——旧窗口的楼层插进新窗口是楼号错乱。
  private earlierEpoch: number = 0;
  // 首帧定位的 List 下标(目标楼 + summary 占位偏移)。List 创建时读取一次,无需 @State。
  private initialListIndex: number = 0;
  // 带目标楼进入时由 List 首次布局直接预留 HDS 标题栏高度，避免 initialIndex 后再二次滚动。
  // 滚回列表顶部后会归零，并由摘要内部 Blank 等量接管顶部空间；需为 @State 才能同步刷新
  // List.contentStartOffset 与 HDS 模糊阈值。普通首屏从一开始就是 0。
  @State private initialListStartOffset: number = 0;
  // "上次访问"红线:进入时快照的已读水位(只取一次,页内重开窗口/本次阅读推高水位都不重取,
  // 否则线会消失);锚楼 = 快照后第一条已加载未读楼的 post.id,楼层创建前确定,不再变化。
  private lastVisitedSnapshot: number = 0;
  private lastVisitedAnchorPostId: number = 0;
  // 落地高亮的目标楼 post.id(通知/引用跳转):@State 经 @Prop 下发给各楼,已在组件树上的楼
  // 靠 @Watch 就地起播(已加载路径的楼内跳转)。短暂生效后清零,避免楼层销毁重建时重播。
  @State private flashTargetPostId: number = 0;
  private flashClearTimerId: number = -1;
  // 当前视口首/末项的 List 下标(onScrollIndex 持续更新):用于预取判断、已读统计，
  // 以及跳楼时判断目标楼是否已在屏内(在屏内则不滚动)。
  private currentStartListIndex: number = 0;
  private currentEndListIndex: number = 0;
  // 跳未加载楼的重开窗口请求进行中(防重入 + 顶部悬浮胶囊提示)。请求期间旧列表原样保留,不白屏。
  @State private isRewindowing: boolean = false;
  // 本次换窗是不是「回一楼」(点顶栏标题):只影响加载胶囊的文案。
  @State private rewindowingToTop: boolean = false;
  // 阅读时 timings 被 CF 拦下:right-top 亮过盾快捷入口(还需用户在设置里开了开关)。
  @State private challengeBlocked: boolean = false;
  private unsubscribeChallengeShortcut?: () => void = undefined;
  // List 重建开关:翻转值使 build 里的 if/else 换分支,同一帧销毁旧 List、全新重建
  // (新 List 挂新 PostDataSource 实例 + initialIndex 生效)。这是原地换窗不经过加载页的关键。
  @State private listEpochEven: boolean = true;
  // 顶部摘要(标题/分类/标签)是否可见:滑出视口后,头部由"帖子详情"切换为显示帖子标题与分类标签行。
  @State private summaryVisible: boolean = true;
  // 当前视口首楼的楼号:驱动右缘 scrubber 的滑块位置(onScrollIndex 持续更新)。
  @State private currentPostNumber: number = 1;
  // 视口是否可滚动(摘要与末尾项同时可见 = 一屏放得下):不可滚动时隐藏 scrubber(滑块位置无意义,
  // 顺带解决"只有两楼滑块该放哪"的歧义)。
  @State private listScrollable: boolean = true;
  // "钉到底"闩:真正滚到话题结尾(onReachEnd 且无更多可加载=末楼已加载)时置位,让 scrubber 到底,
  // 补上短楼场景下"首楼映射够不到底"的末段行程;末尾项滚出视口即撤销。用 onReachEnd 而非"末楼可见"
  // 作触发——后者末楼冒出 1px 就误判到底,超长末楼会翻车;onReachEnd 是与楼高无关的真·触底信号。
  @State private atListEnd: boolean = false;
  // 评论输入浮层是否展开(点右下角悬浮回复按钮打开)。窗口常驻全屏布局(ImmersiveWindow),
  // 浮层遮罩经 expandSafeArea 天然盖住状态栏,不再需要临时切窗口模式与背景补偿。
  @State private showComposer: boolean = false;
  // 定向回复目标楼号:0 = 回复整个话题(顶层);>0 = 回复该楼(带 reply_to_post_number)。
  @State private replyTargetPostNumber: number = 0;
  // 草稿续写:本次进入是否已自动弹过回复框(防重载再弹)。
  private draftComposerOpened: boolean = false;
  // 本主题未发出的回复内容(页面级暂存)。内联条/全屏编辑器都往这写,关掉再打开据此回填——
  // 这是「关了输入框内容就没了」的直接兜底,纯内存、不依赖网络。
  @State private pendingReplyText: string = '';
  // 未发出的 boost 内容,**按楼(post id)分开存**——给 A 楼打的 boost 不能串到 B 楼去。
  // boost 不是 Discourse 草稿(服务端无此概念),所以只做内存暂存,不落服务端。
  private pendingBoostByPostId: Map<number, string> = new Map();
  // 回帖草稿(服务端)运行态。draft_key 固定 topic_<id>,故同一主题只有一条。
  private replyDraftSequence: number = 0;
  private replyDraftTimer: number = -1;
  private replyDraftSaving: boolean = false;
  // 快速发表时可能还没落过服务端草稿；仅实际存在时删除并递减角标。
  private replyDraftPersisted: boolean = false;
  // 输入框占位文字:回复话题「回复当前话题」/回复某楼「回复<昵称>」/发 boost「发一个 boost…」。
  @State private composerPlaceholder: string = '回复当前话题';
  // boost 输入目标楼 id:0 = 当前浮层是普通回复;>0 = 当前浮层是给该楼发 boost。
  @State private boostTargetPostId: number = 0;
  // 正在编辑的楼层 id(0=不在编辑态)。与 boostTargetPostId 一样,输入浮层靠它区分本次提交走哪条链路。
  @State private editingPostId: number = 0;
  // 打开编辑框时服务端给的那份 raw。保存时原样回传作 original_text —— 服务端拿它跟当前 raw 比,
  // 不一致就 409,从而挡下「编辑期间这楼被别处改过」的覆盖。别拿用户改后的文本充数,那等于自己关掉了这道闸。
  private editingOriginalRaw: string = '';
  // 正在为哪一楼取原文(0=没有)。取原文要走网络,期间在该楼铅笔处转圈,并挡住连点。
  @State private editLoadingPostId: number = 0;
  // 编辑框里改到一半的正文。与 pendingReplyText 分开:两者共用同一个 draft_key,混用会互相污染。
  private pendingEditText: string = '';
  private editDraftTimer: number = -1;
  // 帖子列表滚动控制器:供「回复别人」指示器 / 被回复列表「跳到帖子」按 postNumber 定位楼层。
  private scroller: Scroller = new Scroller();
  param: TopicDetailRouteParam = {
    topicId: 0,
    title: ''
  };
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  // 楼层动作胶水(表情/投票/拷链/书签):乐观回滚与 toast 闭环全在服务类里,页面只接线。
  // bridge 必须经闭包惰性读取:字段初始化此刻父组件注入的 bridge prop 还没覆盖默认值,
  // 按值传会捕获未连接宿主的空壳实例(所有请求被拒,表情/书签全挂,实测翻车)。
  private postActions: PostActions = new PostActions(
    (): ArkWebNetworkBridge => this.bridge,
    (message: string, duration: number): void => this.showComposerToast(message, duration),
    (): number => this.detail?.id ?? 0,
    (): string | undefined => this.detail?.slug
  );
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  // 待审帖卡片的作者信息来源(服务端不下发待审帖作者——只有本人看得到自己的待审帖)。
  @Prop currentUser: User = { id: 0, username: '' };
  onBack: () => void = () => {};
  // 打开 CF 过盾页(顶栏快捷入口触发)。导航栈与弹层都在宿主 RootTabPage 手里,故上抛。
  onOpenChallenge: () => void = () => {};
  // 图片预览上抛给根组件渲染:双栏(平板横屏)下须盖满整窗而非仅右详情栏,故提到 RootTabPage 根级。
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  // 正文链接 / onebox 卡片点击上抛给根导航:站内帖子链接跳原生详情,其余打开通用 WebView。
  onOpenLink: (url: string) => void = () => {};
  // 点楼层作者头像/昵称上抛给根导航,进他人主页。
  onOpenUser: (user: User) => void = () => {};
  // 全屏 Markdown 编辑器浮层:内联挂在本页根 Stack(不走 Navigation),点内联输入条「展开」时
  // 由 animateTo 从输入条几何生长铺满全屏(一镜到底)。
  @State private showFullComposer: boolean = false;
  // 全屏编辑器带入的初始正文(内联浮层已输入内容);顶栏标题/占位随定向回复目标而定。
  @State private composerInitialText: string = '';
  @State private composerHeaderTitle: string = '回复';
  @State private composerFullPlaceholder: string = '写下你的回复…';
  // 展开瞬间的键盘高度(vp),传给全屏编辑器做初值,首帧即按「有键盘」布局,消除「回缩一下」。
  @State private composerInitialKb: number = 0;
  // 返回键 tick 监听:RootTabPage 在详情页 NavDestination.onBackPressed 里 bump 此值,本页据此关浮层。
  @StorageProp(COMPOSER_OVERLAY_BACK_TICK_KEY) @Watch('onComposerBackTick') private composerBackTick: number = 0;
  private categoryIndex: CategoryIndex = new CategoryIndex();
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;
  private unsubscribeLoginState?: () => void = undefined;
  // 实时新楼(MessageBus /topic/<id> 的 created 事件)。总线退订句柄 + 频道订阅在 detail 就位后发起。
  private unsubscribeMessageBus?: () => void = undefined;
  // created 只带 post id，无 cooked：收集待拉 id，去抖后一次 loadMorePosts 批量拉。
  private pendingCreatedPostIds: number[] = [];
  private createdFetchTimer: number = -1;
  // "N 条新回复"提示条：用户不在列表底部时累计，点按跳到首条新楼；在底部则直接追加不计数。
  @State private incomingNewPostCount: number = 0;
  private incomingFirstNewPostNumber: number = 0;
  // 「帖子内新回复提醒」开关(默认关)。关⇒不订阅 /topic 频道、不处理 created；运行中翻转由 @Watch 即时启停。
  @StorageProp(REALTIME_POSTS_ENABLED_STORAGE_KEY) @Watch('onRealtimePostsToggled')
  private realtimePostsEnabled: boolean = false;
  // 「抽奖帖提醒」开关(默认开)。关⇒摘要下方的提醒卡与回复浮层的提醒行都不出现。
  @StorageProp(LOTTERY_TIP_ENABLED_STORAGE_KEY) private lotteryTipEnabled: boolean = true;
  // 块 2(下行、只读)：真实"正在回复"用户,由 TopicPresenceService 维护后回调写入。
  @State private presenceUsers: User[] = [];
  // Presence 下行服务。bridge 走闭包惰性读取(字段初始化时父注入的 bridge 尚未覆盖默认空壳)。
  private presence: TopicPresenceService = new TopicPresenceService(
    (): ArkWebNetworkBridge => this.bridge,
    (): number => this.currentUser.id,
    (users: User[]): void => {
      this.presenceUsers = users;
    });
  // 已读追踪控制器:计时上报、已读水位、错峰翻已读、离开时回传列表页,全部由它托管。
  // 用闭包读取 detail 与数据源当前楼层数组(分页后数组会变,不能捕获快照)。
  private readController: TopicReadController = new TopicReadController(
    (): TopicDetail | undefined => this.detail,
    (): TopicPost[] => this.dataSource.getAll()
  );

  aboutToAppear(): void {
    this.replyFabAlignRules = smartReachBottomAlignRules(this.smartReachLeftHanded);
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }

    // 详情已加载后才登录(首装/登出后在本页触发登录)时,startReadingTrackerIfNeeded 的一次性调用
    // 已错过。登录态翻真时补启一次(startIfNeeded 内有 started 幂等守卫,已启动则空转);此信号严格
    // 对齐 setLoggedIn 写入,回调里 isLoggedIn 必为 true,不同于早于写入的 SessionEventBus。
    if (!this.unsubscribeLoginState) {
      this.unsubscribeLoginState = LoginGate.subscribeBecameLoggedIn(() => {
        this.startReadingTrackerIfNeeded();
      });
    }

    // 过盾快捷入口:每次进入新详情先清掉上一个帖子的运行态,只响应本次 timings 的撞盾结果。
    // 这样旧帖曾被盾拦下不会让新帖首帧错误显示图标,且本次失败仍会通过订阅重新亮起。
    ChallengeShortcutPrefs.load(this.getUIContext().getHostContext() as common.Context);
    ChallengeShortcutEventBus.reset();
    this.challengeBlocked = false;
    if (!this.unsubscribeChallengeShortcut) {
      this.unsubscribeChallengeShortcut = ChallengeShortcutEventBus.subscribe((blocked: boolean) => {
        this.challengeBlocked = blocked;
      });
    }

    this.readController.attach();

    // 实时新楼：订阅全局 MessageBus 总线（按 channel 过滤本帖）。频道订阅本身在 detail 就位后
    // (loadTopicDetail 成功)才发起——那时才有 topicId 与 message_bus_last_id。
    if (!this.unsubscribeMessageBus) {
      this.unsubscribeMessageBus = MessageBusEventBus.subscribe((event: MessageBusEvent) => {
        this.handleMessageBusEvent(event);
      });
    }

    if (this.isArkWebReady && !this.detail) {
      this.loadSiteMetadataIfNeeded();
      this.loadTopicDetail();
    }
  }

  private onSmartReachSideChanged(): void {
    this.getUIContext().animateTo({
      duration: SMART_REACH_ANIMATION_DURATION,
      curve: Curve.EaseInOut
    }, () => {
      this.replyFabAlignRules = smartReachBottomAlignRules(this.smartReachLeftHanded);
    });
  }

  aboutToDisappear(): void {
    // 停表 + 清定时器/订阅;已读回传与最后一次 timings 上报由它自己推迟到转场之后(见 TopicReadController)。
    this.readController.detach();

    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }

    if (this.unsubscribeChallengeShortcut) {
      this.unsubscribeChallengeShortcut();
      this.unsubscribeChallengeShortcut = undefined;
    }

    if (this.unsubscribeLoginState) {
      this.unsubscribeLoginState();
      this.unsubscribeLoginState = undefined;
    }

    // 退订实时新楼：总线退订 + 从长轮询循环里删掉本帖频道 + 清掉去抖计时器。
    // 总线退订必须同步做(留着会让已销毁的页面继续收事件);删频道那步要经 ArkWeb 桥 runJavaScript,
    // 与已读上报同理推迟到转场之后——期间最多多收几条本帖消息,而总线已退订,不会有人处理。
    if (this.unsubscribeMessageBus) {
      this.unsubscribeMessageBus();
      this.unsubscribeMessageBus = undefined;
    }
    if (this.detail) {
      const topicId: number = this.detail.id;
      const bridge: ArkWebNetworkBridge = this.bridge;
      setTimeout(() => {
        bridge.unsubscribeTopicChannel(topicId);
        // Presence 退订同理经桥 runJavaScript，一并推迟到转场之后。总线已同步退订，此前不会有人处理增量。
        this.presence.stop();
      }, CHANNEL_UNSUBSCRIBE_DEFER_MS);
    } else {
      this.presence.stop();
    }
    if (this.createdFetchTimer !== -1) {
      clearTimeout(this.createdFetchTimer);
      this.createdFetchTimer = -1;
    }

    if (this.flashClearTimerId >= 0) {
      clearTimeout(this.flashClearTimerId);
      this.flashClearTimerId = -1;
    }
  }

  // 楼层列表区。抽成 Builder 是为了原地换窗:build 里用 listEpochEven 翻转 if/else 分支,
  // 同一帧销毁旧 List、按当前 dataSource/initialListIndex 全新重建。
  @Builder
  private PostListSection() {
    List({ scroller: this.scroller, initialIndex: this.initialListIndex }) {
      ListItem() {
        Column() {
          Blank()
            .height(Math.max(0,
              immersiveTitleBarContentTopSpacer(this.sysTopInset) - this.initialListStartOffset))

          TopicSummaryCard({
            title: this.getTitle(),
            category: CategoryIndex.find(this.categories, this.detail?.categoryId),
            parentCategory: CategoryIndex.findParent(this.categories, this.detail?.categoryId),
            tags: this.getTags(),
            metaText: this.getTopicMetaText(),
            solved: (this.detail?.acceptedAnswers?.length ?? 0) > 0,
            bookmarked: this.topicBookmarked
          })

          // 抽奖帖提醒:挂在摘要与一楼之间,跟着列表滚走。刻意塞进这个已存在的 ListItem 而不新开
          // 一项——详情页多处硬依赖「index 0 是摘要、楼层从 index 1 起」的下标算术(已读上报、
          // 顶栏双层标题切换、向上预取阈值、跳楼定位),多一项就得让这些偏移量随卡片在不在而变。
          if (this.showsLotteryNotice()) {
            LotteryNoticeCard({
              onOpenAnnouncement: () => {
                // 走站内链接路由:LinkRouter 认得这个形状的 URL,直接开原生详情页而非 WebView。
                this.onOpenLink(LOTTERY_RULES_TOPIC_URL);
              }
            })
          }
        }
        .width('100%')
      }

      LazyForEach(this.dataSource, (post: TopicPost) => {
        TopicPostItem({
          post: post,
          topicCreatedById: this.detail?.createdById ?? -1,
          lastReadPostNumber: this.detail?.lastReadPostNumber ?? -1,
          showLastVisitedLine: post.id === this.lastVisitedAnchorPostId && this.lastVisitedAnchorPostId > 0,
          flashTargetPostId: this.flashTargetPostId,
          // 采纳答案面板只挂一楼:非一楼下发空数组,免得每个 item 都持有整份数据。
          acceptedAnswers: post.postNumber === 1 ? (this.detail?.acceptedAnswers ?? []) : [],
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.onOpenImages(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.onOpenLink(url);
          },
          onJumpToQuote: (topicId: number, postNumber: number, fallbackUrl: string) => {
            this.jumpToQuote(topicId, postNumber, fallbackUrl);
          },
          onResolveQuotedPost: (topicId: number, postNumber: number): Promise<string> => {
            return this.resolveQuotedPost(topicId, postNumber);
          },
          onResolveMedia: (url: string): Promise<string> => {
            return this.bridge.downloadMedia(url);
          },
          onToggleReaction: (targetPost: TopicPost, reaction: string): Promise<boolean> => {
            return this.postActions.toggleReaction(targetPost, reaction);
          },
          onOpenReactionUsers: (targetPost: TopicPost) => {
            this.openReactionUsers(targetPost);
          },
          onReply: (targetPost: TopicPost) => {
            this.openComposerForPost(targetPost);
          },
          onEdit: (targetPost: TopicPost) => {
            this.openComposerForEdit(targetPost);
          },
          editLoading: this.editLoadingPostId === post.id,
          onAddBoost: (targetPost: TopicPost) => {
            this.openComposerForBoost(targetPost);
          },
          // 删除自己发的 boost。currentUserId 下发给楼层判断「这条是不是我的」(未登录为 0,谁的都不是)。
          currentUserId: this.currentUser.id,
          onDeleteBoost: (targetPost: TopicPost, boost: PostBoost): Promise<boolean> => {
            return this.deleteBoost(targetPost, boost);
          },
          onOpenUser: (user: User) => {
            this.onOpenUser(user);
          },
          onJumpToPost: (postNumber: number): Promise<void> => {
            return this.jumpToPostNumber(postNumber);
          },
          onLoadReplies: (targetPost: TopicPost) => {
            return this.loadPostReplies(targetPost);
          },
          onVote: (targetPost: TopicPost, poll: Poll, optionIds: string[]) => {
            return this.postActions.vote(targetPost, poll, optionIds);
          },
          onRemoveVote: (targetPost: TopicPost, poll: Poll) => {
            return this.postActions.removeVote(targetPost, poll);
          },
          onCopyPostLink: (targetPost: TopicPost) => {
            this.postActions.copyPostLink(targetPost);
          },
          onToggleBookmark: (targetPost: TopicPost) => {
            return this.postActions.toggleBookmark(targetPost).then((result: BookmarkToggleResult) => {
              // 主题级态确定时(加书签必 true;取消取接口 topic_bookmarked),即时联动标题书签图标。
              if (result.topicBookmarked !== undefined) {
                this.topicBookmarked = result.topicBookmarked;
                if (this.detail !== undefined) {
                  this.detail.bookmarked = result.topicBookmarked;
                }
              }
              return result;
            });
          },
          // "俺也一样"(shared issue):话题级功能,只对 shared_issue_visible 的一楼下发有效值,其余楼不渲染。
          sharedIssueVisible: post.postNumber === 1 && (this.detail?.sharedIssueVisible ?? false),
          sharedIssueCanCreate: this.detail?.canCreateSharedIssue ?? false,
          sharedIssueCount: post.postNumber === 1 ? (this.detail?.sharedIssueCount ?? 0) : 0,
          sharedIssueCreated: post.postNumber === 1 ? (this.detail?.userCreatedSharedIssue ?? false) : false,
          onToggleSharedIssue: (): Promise<SharedIssueResult | null> => {
            return this.toggleSharedIssue();
          }
        })
      }, (post: TopicPost) => post.id.toString())

      // 待审核区:对齐官方 templates/topic.gjs——铺在整个楼层流最底部,且只有楼层全部加载完
      // (官方的 loadedAllPosts,我们即 !hasMorePosts)才渲染。停在第 3 楼时不该看见它。
      // 用 ForEach 而非 LazyForEach:待审帖是当前用户在本主题下的未过审回复,现实中就一两条。
      if (!this.hasMorePosts && this.pendingPosts.length > 0) {
        ListItem() {
          Column() {
            ForEach(this.pendingPosts, (pending: PendingPost) => {
              PendingPostCard({
                pending: pending,
                currentUser: this.currentUser,
                onDelete: (target: PendingPost) => {
                  this.confirmDeletePending(target);
                }
              })
            }, (pending: PendingPost) => pending.id.toString())
          }
          .width('100%')
          // 不加 top border:每个楼层自己底边就带 1px 发丝线(TopicPostItem 的 border.bottom),
          // 这里再加一条顶线会和末楼底线贴在一起变成 2px,肉眼就是"待审区的线比楼间线粗一倍"。
        }
      }

      if (this.postCount > 0) {
        ListItem() {
          Column() {
            Row() {
              if (this.isLoadingMore) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color($r('app.color.brand'))
                  .margin({ right: 8 })
              }

              Text(this.loadMoreMessage)
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .height(54)
            .justifyContent(FlexAlign.Center)

            // List 铺进底部系统区域，需把导航指示条高度一并计入可滚动尾距。
            Blank()
              .height(POST_LIST_BOTTOM_SPACER + this.sysBottomInset)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .height('100%')
    .contentStartOffset(this.initialListStartOffset)
    // 关掉系统默认滚动条:右缘已有楼层 scrubber,两者并存会视觉打架。
    .scrollBar(BarState.Off)
    // 左右留白下放到各 item 内部(楼层高亮背景要通栏),List 不再统一内缩。
    // 头部插入更早楼层时保持可视内容不动。重要:只在"List 创建后从未吃过 onDataReloaded"时可靠
    // ——对活 List 做 reset 会让后续补偿全部失效(实测),原地换窗必须走 epoch 翻转重建。
    .maintainVisibleContentPosition(true)
    // 楼层含富文本/图片偏重,预创建数平衡快滑白块与内存(与向上预取阈值联动,见常量注释)。
    .cachedCount(POSTS_CACHED_COUNT)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onScrollIndex((start: number, end: number) => {
      this.currentStartListIndex = start;
      this.currentEndListIndex = end;
      if (start === 0) {
        this.normalizeTargetListStartOffsetAtTop();
      }
      // List 的 index 0 是 TopicSummary,楼层从 index 1 起 → 换算成 posts 下标再交给已读控制器。
      this.readController.onVisibleRange(start - 1, end - 1);
      // 摘要 ListItem 固定为 index 0:仍在视口内(start===0)显示"帖子详情",滑出后显示帖子标题与分类标签。
      this.summaryVisible = start === 0;
      // 右缘 scrubber:维护可滚动性、钉底闩、当前楼号(见 updateScrubberFromScroll)。
      this.updateScrubberFromScroll(start, end);
      // 先插入已备好的更早楼层，再按阈值预取下一页。头插只发精准 ADD 通知，由 List 自己保持
      // 可见内容；HDS 标题栏是覆盖层，不能拿 start 当“标题栏下方首项”再手动滚动。
      this.tryFlushEarlierPosts(start);
      if (this.hasEarlier && start - 1 <= EARLIER_PREFETCH_INDEX) {
        this.prefetchEarlierPosts();
      }
    })
    .onReachStart(() => {
      // 兜底:飞速甩到顶时立即并入已预取楼层，并继续拉取上一页。
      this.tryFlushEarlierPosts(this.currentStartListIndex);
      this.prefetchEarlierPosts();
    })
    .onReachEnd(() => {
      this.loadMorePosts();
      // 真正滚到话题结尾(无更多可加载 → 末楼已加载)才钉滑块到底;loadMorePosts 在 !hasMorePosts 时
      // 自身 no-op,故此处同步判定即当前状态。有更多待加载时不钉,交给分页继续拉。
      if (!this.hasMorePosts) {
        this.atListEnd = true;
        this.currentPostNumber = this.getHighestPostNumber();
        // 滚到底即已看到新楼：清掉"N 条新回复"提示条。
        this.clearIncomingBanner();
      }
    })
  }

  @Builder
  private DetailTitleBarContent() {
    TopicDetailHeader({
      summaryVisible: this.summaryVisible,
      title: this.getTitle(),
      showBadges: this.hasBadges(),
      category: CategoryIndex.find(this.categories, this.detail?.categoryId),
      parentCategory: CategoryIndex.findParent(this.categories, this.detail?.categoryId),
      tags: this.getTags(),
      solved: (this.detail?.acceptedAnswers?.length ?? 0) > 0,
      bookmarked: this.topicBookmarked,
      onTitleClick: () => {
        this.jumpToFirstPost();
      },
      // 与 HdsNavigation.menu 使用同一条件，仅用于给右侧原生按钮预留标题空间。
      showChallengeShortcut: this.shouldShowChallengeShortcut()
    })
  }

  @Builder
  private DetailMainContent() {
    if (this.detail) {
      // 相同的两个分支:翻转 listEpochEven 强制销毁重建 List(原地换窗用),平时恒走其一。
      if (this.listEpochEven) {
        this.PostListSection()
      } else {
        this.PostListSection()
      }
    } else {
      Column() {
        LoadStateView({
          isLoading: this.isLoading,
          message: this.message,
          requiresChallenge: this.requiresChallenge,
          showRetry: !this.isLoading && this.isArkWebReady,
          onRetry: () => {
            this.loadTopicDetail();
          }
        })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  private ReactionUsersSheetBuilder() {
    ReactionUsersSheet({
      reactions: this.reactionUsersPost?.reactions ?? [],
      totalRows: this.reactionUsersTotal,
      users: this.reactionUsers,
      selectedReaction: this.selectedReactionUserFilter,
      isInitialLoading: this.reactionUsersLoading && this.reactionUsers.length === 0,
      isLoadingMore: this.reactionUsersLoading && this.reactionUsers.length > 0,
      hasMore: this.reactionUsersHasMore,
      initialError: this.reactionUsersInitialError,
      loadMoreError: this.reactionUsersLoadMoreError,
      onSelectReaction: (reaction: string) => {
        this.selectedReactionUserFilter = reaction;
      },
      onLoadMore: () => {
        this.loadMoreReactionUsers();
      },
      onRetryInitial: () => {
        this.loadReactionUsersPage(true);
      },
      onRetryLoadMore: () => {
        this.loadMoreReactionUsers();
      },
      onOpenUser: (user: ReactionUser) => {
        this.showReactionUsersSheet = false;
        this.onOpenUser(user);
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.DetailMainContent()

      HdsNavigation() {
        Column()
          .width('100%')
          .height('100%')
      }
      .titleBar({
        avoidLayoutSafeArea: requiresHdsLayoutSafeAreaAvoidance(ImmersiveLightArea.TITLE_BAR),
        enableComponentSafeArea: requiresHdsComponentSafeArea(ImmersiveLightArea.TITLE_BAR),
        // 通知/未读入口用 contentStartOffset 把目标楼首帧放在标题栏下方；List 此时的初始
        // 滚动偏移是负的标题栏高度。阈值同步左移同一偏移后，内容刚进入标题栏覆盖区就开始
        // 过渡；滚回顶部归零后恢复公共样式的 0..8vp 区间。
        style: buildImmersiveTitleBarStyle({
          blurEffectiveStartOffset: LengthMetrics.vp(-this.initialListStartOffset),
          blurEffectiveEndOffset: LengthMetrics.vp(8 - this.initialListStartOffset)
        }),
        content: {
          backIcon: {
            icon: $r('sys.symbol.chevron_left'),
            label: '返回',
            action: () => {
              this.onBack();
            }
          },
          menu: {
            value: this.shouldShowChallengeShortcut() ? [{
              content: {
                icon: $r('sys.symbol.lock_shield'),
                label: '手动验证',
                isEnabled: true,
                action: () => {
                  this.onOpenChallenge();
                }
              }
            }] : []
          },
          stackBuilder: () => {
            this.DetailTitleBarContent();
          }
        }
      })
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      // 只当标题栏容器用,不参与分栏(分栏由 RootTabPage 根 Navigation 负责)。默认 Auto 会在
      // 宽度 ≥600vp 时自切 Split——平板横屏右详情栏就会多出一条可拖的分割线,菜单也被挤到线左边。
      .mode(NavigationMode.Stack)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Transparent)
      .bindSheet(this.showReactionUsersSheet, this.ReactionUsersSheetBuilder, {
        // 初始半屏，长列表可上拉扩展到全屏高度。
        height: SheetSize.MEDIUM,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: false,
        maskColor: '#66000000',
        onDisappear: () => {
          this.showReactionUsersSheet = false;
        }
      })

    // 右缘楼层 scrubber:话题够长(最高楼 > 1)且浮层未展开时挂载,拖动直接跳楼。
    // 覆盖层自身透明、只在右缘 Slider 处拦截触摸,不影响正文滚动。
    if (this.detail && this.getHighestPostNumber() > 1 && this.listScrollable
      && !this.showComposer) {
      TopicScrubber({
        currentPostNumber: this.currentPostNumber,
        highestPostNumber: this.getHighestPostNumber(),
        onJump: (postNumber: number): Promise<void> => {
          return this.jumpToPostNumber(postNumber);
        }
      })
    }

    // 右下角悬浮回复按钮:仅在帖子已加载且浮层未展开时显示。
    // 窗口常驻全屏布局后不再有临时切换,按钮锚点全程稳定,无需再绑全屏标志防"闪回"。
    if (this.detail && !this.showComposer) {
      RelativeContainer() {
        // 玻璃材质与光边都做在 primaryButton 上(见 replyFabButton 的 buttonModifier),外层 ActionBar 只
        // 承载位置/阴影/交互,背景模糊始终 DISABLE,避免与按钮材质叠成双层磨砂。
        HdsActionBar({
          primaryButton: this.replyFabButton(),
          actionBarStyle: this.replyFabStyle(),
          blurStrategy: IMMERSIVE_ACTION_BAR_BLUR_DISABLED
        })
          .id('smartReachReplyFab')
          .alignRules(this.replyFabAlignRules)
          .width(52)
          .height(52)
          .margin({
            left: 16,
            right: 16,
            bottom: floatingActionBottomMargin(this.sysBottomInset)
          })
          // 不对称过渡:出现(关闭浮层后)淡入;消失(打开浮层时)立即移除,被同时淡入的遮罩盖住,毫无痕迹。
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }),
            TransitionEffect.IDENTITY
          ))
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }

    // 向上补楼 / 跳楼定位的加载指示:悬浮小胶囊,不参与 List 布局(头插时列表零跳动的前提)。
    if (this.isRewindowing || (SHOW_LOADING_CAPSULE && this.isLoadingEarlier)) {
      Row() {
        LoadingProgress()
          .width(14)
          .height(14)
          .color($r('app.color.brand'))
          .margin({ right: 6 })
        Text(this.isRewindowing ? (this.rewindowingToTop ? '正在回到一楼' : '正在定位楼层') : '正在加载更早的回复')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface_card'))
      .borderRadius(15)
      .shadow({ radius: 6, color: SHADOW_SOFT, offsetX: 0, offsetY: 1 })
      .position({ x: '50%', y: 72 })
      .markAnchor({ x: '50%', y: 0 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
    }

    // 实时新楼提示条：用户不在底部时新楼到达累计，点按跳到首条新楼。悬浮在底部中央、不参与布局，
    // 与向上加载胶囊同一套"悬浮小胶囊"长相。在底部时不显示(那时直接追加，见 flushCreatedPosts)。
    //
    // 定位方式与右下角悬浮回复按钮保持一致(满屏容器 + 底距)，不要改回
    // position('100%') + markAnchor('50%') + offset 那一套：算式上两者中心该重合，实测胶囊却沉到
    // 屏幕外只露出顶部一条——百分比锚点作用在由内容撑开的组件上并不可靠。
    // 底距 = FAB 底距 + FAB 半高 26 − 胶囊半高（此式即与按钮垂直居中，已实测确认）再加让位余量。
    if (this.incomingNewPostCount > 0 && !this.showComposer) {
      Column() {
        Row() {
          Text('↓')
            .fontSize(13)
            .fontColor($r('app.color.brand'))
            .margin({ right: 6 })
          Text(`${this.incomingNewPostCount} 条新回复`)
            .fontSize(13)
            .fontColor($r('app.color.brand'))
        }
        .height(INCOMING_BANNER_HEIGHT)
        .padding({ left: 14, right: 14 })
        // 与"正在回复"胶囊 / 悬浮回复按钮同一套玻璃磨砂(强磨砂 + 通透)，不再用实色底。
        .backgroundEffect({
          radius: 28,
          color: $r('app.color.hds_floating_action_bg'),
          saturation: 1.2
        })
        .borderRadius(INCOMING_BANNER_HEIGHT / 2)
        .shadow({ radius: 8, color: SHADOW_SOFT, offsetX: 0, offsetY: 2 })
        .onClick(() => {
          this.openIncomingPosts();
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .padding({
        bottom: floatingActionBottomMargin(this.sysBottomInset) + 26 - INCOMING_BANNER_HEIGHT / 2
          + INCOMING_BANNER_LIFT
      })
      // 满屏容器只为定位，不能吃掉正文的滚动与点击。
      .hitTestBehavior(HitTestMode.Transparent)
      .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
    }

    // 底部"正在回复"悬浮条：真实 Presence 数据驱动。定位与"N 条新回复"一致(满屏容器 + 底距)，
    // 与右下角悬浮回复按钮垂直居中。
    if (this.detail && this.presenceUsers.length > 0 && !this.showComposer) {
      Column() {
        ReplyingPresenceBar({ users: this.presenceUsers })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .padding({
        // 与右下角回复按钮垂直居中(FAB 底距 + FAB 半高 26 − 胶囊半高)；FAB 走 HdsActionBar 内部已处理
        // 底部安全区，本条是普通 Column 会把安全区多算一次，故再扣掉 sysBottomInset。
        bottom: floatingActionBottomMargin(this.sysBottomInset) - this.sysBottomInset
          + 26 - REPLYING_PRESENCE_BAR_HEIGHT / 2
      })
      .hitTestBehavior(HitTestMode.Transparent)
      .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
    }

    // 评论输入浮层:内联挂在根 Stack 顶层(而非 contentCover),这样组件 getLastWindow 拿到主窗口、
    // 能稳定收到键盘高度事件把输入条顶到键盘上方;窗口常驻全屏布局,遮罩经 expandSafeArea 盖住状态栏。
    if (this.showComposer) {
      CommentInputBar({
        placeholder: this.composerPlaceholder,
        // 抽奖帖:输入条上方压一行规则提醒(空串则整行不渲染)。只提示不拦截。
        hintText: this.lotteryReplyHint(),
        // boost 是「起飞」「感谢佬」这类短文本,放开最短字数下限;普通回复仍用默认 16。
        // 编辑时不设最短字数:原文本来就可能很短,拿新回复的 16 字下限去卡编辑会让人改不动。
        minChars: this.boostTargetPostId > 0 || this.editingPostId > 0 ? 1 : 16,
        // boost 服务端上限 16 字,超了只回 {"failed":"FAILED"} 的 422;回复不限(NO_MAX_CHARS)。
        maxChars: this.boostTargetPostId > 0 ? BOOST_MAX_CHARS : NO_MAX_CHARS,
        // 普通回复与 Boost 都在底部输入条直接显示表情图片 Span，并按一个字符计数。
        // 展开后的全屏编辑器仍接收序列化短码，继续使用现有 TextArea Markdown 编辑模式。
        richEmojiMode: true,
        spaceBeforeSelectedEmoji: this.boostTargetPostId > 0,
        // 带回上次未发出的内容。boost 与回复各自独立;boost 还要再按楼区分。
        initialText: this.editingPostId > 0
          ? this.editingOriginalRaw
          : (this.boostTargetPostId > 0
            ? (this.pendingBoostByPostId.get(this.boostTargetPostId) ?? '')
            : this.pendingReplyText),
        onTextChange: (text: string) => {
          // 编辑态存的是**编辑草稿**(action='edit'),不能倒进「未发出的回复」那个抽屉 ——
          // 两者共用同一个 draft_key,混写会让下次点回复冒出某楼的旧原文。
          if (this.editingPostId > 0) {
            this.pendingEditText = text;
            this.scheduleEditDraftSave();
            return;
          }
          // 内联条一关就卸载,内容只存在于它的 @State,必须实时同步到页面级暂存。
          if (this.boostTargetPostId > 0) {
            // boost:按楼存,不落服务端草稿。
            this.pendingBoostByPostId.set(this.boostTargetPostId, text);
          } else {
            this.pendingReplyText = text;
            this.scheduleReplyDraftSave();
          }
        },
        onClose: () => {
          AppStorage.setOrCreate(COMPOSER_OVERLAY_VISIBLE_KEY, false);
          this.showComposer = false;
          this.resetComposerModes();
        },
        // 展开按钮:仅普通回复显示(boost 短文本无需全屏编辑)。编辑态同样放行 —— 要改的往往是长文。
        showExpand: this.boostTargetPostId <= 0,
        // 一镜到底展开:把已输入文本带进全屏编辑器,由 openFullComposer 在同一 animateTo 里
        // 关内联条、开全屏面板(几何配对生长)。保留 replyTargetPostNumber 供全屏提交读。
        onExpand: (currentText: string, keyboardHeight: number) => {
          this.openFullComposer(currentText, keyboardHeight);
        },
        onSubmit: (text: string, typingMs: number, composerMs: number): Promise<boolean> => {
          // 三条链路:编辑走 updatePost,boost 走 createBoost,其余是普通回复。
          if (this.editingPostId > 0) {
            return this.submitEdit(text);
          }
          if (this.boostTargetPostId > 0) {
            return this.submitBoost(text);
          }
          return this.submitReply(text, typingMs, composerMs);
        }
      })
    }

    // 全屏 Markdown 编辑器浮层:从内联输入条一镜到底生长而来(geometryTransition)。
    // onSubmit 复用 submitReply(成功即 appendPosts 追加新楼);提交成功置 submitted 标志,
    // 关闭时据此淡出彻底关,取消则几何回落到内联输入条。
    if (this.showFullComposer) {
      ComposerPage({
        bridge: this.bridge,
        isArkWebReady: this.isArkWebReady,
        headerTitle: this.composerHeaderTitle,
        placeholder: this.composerFullPlaceholder,
        initialText: this.composerInitialText,
        initialKeyboardHeight: this.composerInitialKb,
        minChars: this.editingPostId > 0 ? 1 : 16,
        // 全屏编辑器的正文同样同步到页面暂存 + 服务端草稿(关掉不丢)。编辑态除外,理由同内联条。
        onTextChange: (text: string) => {
          if (this.editingPostId > 0) {
            this.pendingEditText = text;
            this.scheduleEditDraftSave();
            return;
          }
          this.pendingReplyText = text;
          this.scheduleReplyDraftSave();
        },
        onBack: () => {
          // 提交成功(ComposerPage 内部 ok 后自调 onBack)与主动取消/返回,统一走淡出关闭。
          this.closeFullComposer();
        },
        onSubmit: (raw: string, typingMs: number, composerMs: number): Promise<boolean> => {
          // 从编辑态展开成全屏后,提交仍必须走编辑链路 —— 漏了这一分支就会把改动发成一条新回复。
          if (this.editingPostId > 0) {
            return this.submitEdit(raw);
          }
          // 复用内联回复链路:成功即 appendPosts 追加新楼,返回 true 由 ComposerPage 触发关闭。
          return this.submitReply(raw, typingMs, composerMs);
        }
      })
    }

    }
    .width('100%')
    .height('100%')
    // 楼层与摘要主体保持透明，统一透出详情页专用背景；浅色使用系统通用背景
    // #F2F3F5，暗色资源仍保持原来的 #17191D，便于单独验证浅色视觉效果。
    .backgroundColor($r('app.color.topic_detail_page_bg'))
  }

  // 点 FAB:回复整个话题(顶层回复)。
  private openComposerForTopic(): void {
    // 未登录:拦截并弹登录页,不打开输入浮层(回复/评论)。
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    this.resetComposerModes();
    // 抽奖帖的顶层回复就是「参与抽奖」的那一条,占位文字直接问到点子上;定向回复某楼不改
    // (那是聊天不是参与,「回复<昵称>」更有用)。
    this.composerPlaceholder = this.showsLotteryNotice() ? LOTTERY_REPLY_PLACEHOLDER : '回复当前话题';
    AppStorage.setOrCreate(COMPOSER_OVERLAY_VISIBLE_KEY, true);
    this.showComposer = true;
  }

  // 点某楼回复按钮:定向回复该楼,占位文字「回复<作者昵称>」。
  private openComposerForPost(post: TopicPost): void {
    // 未登录:拦截并弹登录页,不打开输入浮层(定向回复)。
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    this.resetComposerModes();
    this.replyTargetPostNumber = post.postNumber;
    this.composerPlaceholder = `回复${this.resolveAuthorName(post)}`;
    AppStorage.setOrCreate(COMPOSER_OVERLAY_VISIBLE_KEY, true);
    this.showComposer = true;
  }

  /**
   * 点铅笔:编辑该楼。
   *
   * 列表接口只回 cooked HTML 不回 Markdown 原文,所以必须先 GET /posts/{id}.json 取 raw
   * 才能把编辑框填上 —— 拿 cooked 反推 Markdown 是不可能做对的。这一趟顺带取到的也是最新原文,
   * 正好作为乐观并发的基线存进 editingOriginalRaw。
   *
   * 取原文期间不先把浮层开起来:开一个空框再异步填字,用户会以为内容丢了。
   */
  /**
   * 点铅笔:取原文 → 直接展开全屏编辑器。
   *
   * 不走底部单行输入条:要改的往往是整段正文,单行条既看不全也不好定位光标;而且编辑必然是
   * 「已有一整段文字」的场景,和回复那种「从空白起手随手写两句」的姿势不一样。
   *
   * 列表接口只回 cooked HTML 不回 Markdown 原文,所以必须先 GET /posts/{id}.json —— 拿 cooked
   * 反推 Markdown 是做不对的。这一趟要走网络,故先转圈:不给反馈的话用户会以为点了没反应而连点。
   */
  private async openComposerForEdit(post: TopicPost): Promise<void> {
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    if (this.editLoadingPostId > 0) {
      return;
    }
    this.editLoadingPostId = post.id;
    const result: NetworkResult<string> = await new TopicService(this.bridge).getPostRaw(post.id);
    this.editLoadingPostId = 0;
    if (!result.success || result.data === undefined) {
      this.showComposerToast('读取原文失败,请稍后重试', 2000);
      return;
    }
    this.resetComposerModes();
    this.editingPostId = post.id;
    this.editingOriginalRaw = result.data;
    this.composerHeaderTitle = '编辑';
    this.composerFullPlaceholder = '编辑这条回复';
    this.composerInitialText = result.data;
    this.pendingEditText = result.data;
    // 没有内联条可作几何配对的起点(编辑是直接开全屏),键盘起始高度按 0 走普通淡入。
    this.composerInitialKb = 0;
    AppStorage.setOrCreate(COMPOSER_OVERLAY_VISIBLE_KEY, true);
    this.showFullComposer = true;
  }

  /**
   * 保存编辑。成功后就地把新的 cooked/raw 写回该楼,不整页重载 —— 重载会把用户滚动位置冲掉。
   * 409 是编辑冲突(这楼在你打开编辑框之后被改过),要单独说清楚,不能混进「保存失败」里:
   * 前者要用户重新打开编辑看最新内容,后者重试即可。
   */
  private async submitEdit(text: string): Promise<boolean> {
    const postId: number = this.editingPostId;
    const topicId: number = this.detail?.id ?? 0;
    if (postId <= 0 || topicId <= 0) {
      return false;
    }
    const result: NetworkResult<TopicPost> =
      await new TopicService(this.bridge).updatePost(postId, topicId, text, this.editingOriginalRaw);
    if (result.success && result.data) {
      this.applyEditedPost(result.data);
      // 已经存进服务端的编辑草稿要删掉,否则改完发出去了草稿列表里还挂着一条。
      if (this.editDraftTimer !== -1) {
        clearTimeout(this.editDraftTimer);
        this.editDraftTimer = -1;
      }
      if (this.replyDraftPersisted) {
        await this.deleteReplyDraft();
      }
      this.pendingEditText = '';
      this.editingPostId = 0;
      this.editingOriginalRaw = '';
      this.showToastAfterComposerClose('已保存', 2000);
      return true;
    }
    if (result.statusCode === 409) {
      this.showComposerToast('这条回复已被改动,请重新打开编辑', 2500);
      return false;
    }
    this.showComposerToast('保存失败,请稍后重试', 2000);
    return false;
  }

  // 把编辑后的楼层写回列表。TopicPost 是 @Observed,改字段即由 @ObjectLink 精准重渲染那一行,
  // 不必动 DataSource(换实例反而会让整列重建)。
  private applyEditedPost(updated: TopicPost): void {
    const posts: TopicPost[] = this.dataSource.getAll();
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      if (post.id !== updated.id) {
        continue;
      }
      post.cookedHtml = updated.cookedHtml;
      post.plainText = updated.plainText;
      post.updatedAt = updated.updatedAt;
      post.canEdit = updated.canEdit;
      return;
    }
  }

  // 点火箭:给该楼发 boost,占位文字「发一个 boost…」。
  private openComposerForBoost(post: TopicPost): void {
    // 未登录:拦截并弹登录页,不打开输入浮层(boost)。
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    this.resetComposerModes();
    this.boostTargetPostId = post.id;
    this.composerPlaceholder = '发一个 boost…';
    AppStorage.setOrCreate(COMPOSER_OVERLAY_VISIBLE_KEY, true);
    this.showComposer = true;
  }

  /**
   * 输入浮层的三种模式(普通回复 / boost / 编辑)互斥。每个入口先调它清干净再设自己那一个,
   * 每个出口也统一调它。
   *
   * 之所以要集中:模式是三个独立字段散在五个开关处,谁漏一处就串台 —— 加编辑这一模式时就漏过,
   * 表现是编辑完关掉、再点右下角回复,浮层仍停在编辑态并带出被编辑楼的原文。
   */
  private resetComposerModes(): void {
    this.replyTargetPostNumber = 0;
    this.boostTargetPostId = 0;
    this.editingPostId = 0;
    this.editingOriginalRaw = '';
    this.pendingEditText = '';
    this.composerHeaderTitle = '回复';
  }

  // 作者昵称:displayName(来自 API name)优先,回退 username,再回退占位。
  private resolveAuthorName(post: TopicPost): string {
    const displayName: string | undefined = post.author?.displayName;
    if (displayName && displayName.length > 0) {
      return displayName;
    }
    const username: string | undefined = post.author?.username;
    if (username && username.length > 0) {
      return username;
    }
    return '该用户';
  }

  // 点内联输入条「展开」:一镜到底把内联输入条几何生长为全屏编辑器。放进同一 animateTo,
  // 内联输入条(showComposer)与全屏面板(showFullComposer)同 geometryTransition id 才能配对插值。
  // 保留 replyTargetPostNumber(全屏提交仍走 submitReply 读它);boost 不展开(showExpand=false)。
  // 回帖草稿自动存:停止输入 2 秒后发一次(与发新主题同节奏)。draft_key = topic_<主题id>,
  // 同一主题只有一条草稿,不会越存越多。
  /**
   * 编辑草稿自动保存。与回帖草稿同一个 draft_key(topic_<id>)——这是官方行为,
   * 代价是同主题下编辑草稿会顶掉回帖草稿,好处是与网页版互通。
   *
   * 复用 replyDraftSequence 这一个序号,正因为两者是同一条草稿:各存各的序号,
   * 交替保存时必有一方拿着过期序号被服务端拒。
   */
  private scheduleEditDraftSave(): void {
    if (this.editDraftTimer !== -1) {
      clearTimeout(this.editDraftTimer);
    }
    this.editDraftTimer = setTimeout(() => {
      this.editDraftTimer = -1;
      this.saveEditDraftNow();
    }, REPLY_DRAFT_SAVE_DEBOUNCE_MS);
  }

  private async saveEditDraftNow(): Promise<void> {
    if (!this.detail || this.replyDraftSaving || this.editingPostId <= 0) {
      return;
    }
    // 没改动就别存:一进编辑框就存一条内容等于原文的草稿,会平白顶掉用户的回帖草稿。
    if (this.pendingEditText === this.editingOriginalRaw || this.pendingEditText.trim().length === 0) {
      return;
    }
    this.replyDraftSaving = true;
    const result: NetworkResult<number> = await new DraftService(this.bridge).saveEditDraft({
      draftKey: `topic_${this.detail.id}`,
      sequence: this.replyDraftSequence,
      categoryId: this.detail.categoryId !== undefined ? this.detail.categoryId : -1,
      reply: this.pendingEditText,
      postId: this.editingPostId,
      originalText: this.editingOriginalRaw,
      composerTimeMs: 0,
      typingTimeMs: 0
    });
    this.replyDraftSaving = false;
    if (result.success && result.data !== undefined) {
      this.replyDraftSequence = result.data;
      this.replyDraftPersisted = true;
    }
  }

  private scheduleReplyDraftSave(): void {
    if (this.replyDraftTimer !== -1) {
      clearTimeout(this.replyDraftTimer);
    }
    this.replyDraftTimer = setTimeout(() => {
      this.replyDraftTimer = -1;
      this.saveReplyDraftNow();
    }, REPLY_DRAFT_SAVE_DEBOUNCE_MS);
  }

  private async saveReplyDraftNow(): Promise<void> {
    if (!this.detail || this.replyDraftSaving) {
      return;
    }
    if (this.pendingReplyText.trim().length === 0) {
      return;
    }
    this.replyDraftSaving = true;
    const result: NetworkResult<number> = await new DraftService(this.bridge).saveReplyDraft({
      draftKey: `topic_${this.detail.id}`,
      sequence: this.replyDraftSequence,
      categoryId: this.detail.categoryId !== undefined ? this.detail.categoryId : -1,
      reply: this.pendingReplyText,
      composerTimeMs: 0,
      typingTimeMs: 0,
      replyToPostNumber: this.replyTargetPostNumber > 0 ? this.replyTargetPostNumber : undefined
    });
    this.replyDraftSaving = false;
    if (result.success && result.data !== undefined) {
      // 服务端回的是下次该带的序号,不存回去下次会因序号过期被拒。
      this.replyDraftSequence = result.data;
      this.replyDraftPersisted = true;
    }
  }

  // 删掉本主题的回帖草稿(topic_<id>)。发表成功后调用。
  private async deleteReplyDraft(): Promise<void> {
    if (!this.detail) {
      return;
    }
    const draftKey: string = `topic_${this.detail.id}`;
    const result: NetworkResult<boolean> =
      await new DraftService(this.bridge).deleteDraft(draftKey, this.replyDraftSequence);
    if (result.success && this.replyDraftPersisted) {
      this.replyDraftPersisted = false;
      DraftEventBus.notifyDeleted(draftKey);
    }
    this.replyDraftSequence = 0;
  }

  // 续写来的草稿在发表成功后删除。只删一次(删完清空 key,防重复发表路径重复删)。
  // 注意:回帖草稿的 key 本就是 topic_<主题id>,与 deleteReplyDraft 删的是同一条——那条已用
  // 最新序号删过,这里必须跳过,否则会拿路由里的旧序号重复删一次(失败无害但会留假错误日志)。
  private async deleteResumedDraftIfAny(): Promise<void> {
    const key: string | undefined = this.param.draftKey;
    if (key === undefined || key.length === 0) {
      return;
    }
    this.param.draftKey = '';
    if (this.detail && key === `topic_${this.detail.id}`) {
      return;
    }
    const sequence: number = this.param.draftSequence ?? 0;
    const result: NetworkResult<boolean> = await new DraftService(this.bridge).deleteDraft(key, sequence);
    if (result.success) {
      DraftEventBus.notifyDeleted(key);
    }
  }

  // 草稿续写:详情加载完后自动弹回复框(仅当路由带了草稿正文,且本次进入还没弹过)。
  private maybeOpenDraftComposer(): void {
    const draftReply: string | undefined = this.param.draftReply;
    if (this.draftComposerOpened || draftReply === undefined || draftReply.length === 0) {
      return;
    }
    this.draftComposerOpened = true;
    // 编辑草稿要开成编辑态。它和回帖草稿共用 topic_<id> 这个 key、正文字段也一样,
    // 唯一的区别就是路由带没带 postId + 原文基线 —— 判在回帖之前,漏判的后果是把某楼的旧原文
    // 当成新回复发出去。两者缺一就当普通草稿处理,宁可退化也不开半残的编辑态。
    const editPostId: number | undefined = this.param.draftEditPostId;
    const editOriginal: string | undefined = this.param.draftEditOriginalText;
    if (editPostId !== undefined && editPostId > 0 && editOriginal !== undefined) {
      this.resetComposerModes();
      this.editingPostId = editPostId;
      this.editingOriginalRaw = editOriginal;
      this.composerHeaderTitle = '编辑';
      this.composerFullPlaceholder = '编辑这条回复';
      this.replyDraftSequence = this.param.draftSequence ?? 0;
      this.replyDraftPersisted = this.detail !== undefined && this.param.draftKey === `topic_${this.detail.id}`;
      this.openFullComposer(draftReply, 0);
      return;
    }
    // 灌进页面暂存:全屏关掉后再点内联条也能带回这段内容。
    this.pendingReplyText = draftReply;
    // 沿用草稿原序号继续自动存,不然首次保存会因序号过期被拒。
    this.replyDraftSequence = this.param.draftSequence ?? 0;
    this.replyDraftPersisted = this.detail !== undefined && this.param.draftKey === `topic_${this.detail.id}`;
    this.openFullComposer(draftReply, 0);
  }

  private openFullComposer(currentText: string, keyboardHeight: number): void {
    this.composerInitialText = currentText;
    this.composerInitialKb = keyboardHeight;
    const replyTo: number = this.replyTargetPostNumber;
    // 编辑态展开时不能套用回复文案 —— 标题得留住「编辑」,否则用户以为自己在发新回复。
    if (this.editingPostId <= 0) {
      this.composerHeaderTitle = replyTo > 0 ? `回复 #${replyTo} 楼` : '回复';
      this.composerFullPlaceholder = replyTo > 0 ? `回复 #${replyTo} 楼…` : '写下你的回复…';
    }
    AppStorage.setOrCreate(COMPOSER_OVERLAY_VISIBLE_KEY, true);
    this.getUIContext().animateTo({ duration: COMPOSER_ANIM_MS, curve: Curve.Friction }, () => {
      this.showComposer = false;
      this.showFullComposer = true;
    });
  }

  // 关闭全屏编辑器:统一淡出回到帖子(提交成功新楼已在列表;取消即放弃)。不重现内联输入条——
  // 否则它 aboutToAppear 又自动弹键盘、按键盘高度上移,观感是"回复条跑到上面";键盘由
  // ComposerPage 卸载时主动收起,避免详情页被 OFFSET 顶起。
  private closeFullComposer(): void {
    AppStorage.setOrCreate(COMPOSER_OVERLAY_VISIBLE_KEY, false);
    this.getUIContext().animateTo({ duration: COMPOSER_ANIM_MS, curve: Curve.Friction }, () => {
      this.showFullComposer = false;
      this.showComposer = false;
      this.resetComposerModes();
    });
  }

  // 系统返回键(RootTabPage 在详情页 NavDestination.onBackPressed 里 bump tick):浮层开着就关。
  private onComposerBackTick(): void {
    if (this.showFullComposer) {
      this.closeFullComposer();
    }
  }

  // 发表评论:POST /posts。成功后把新楼层追加到列表底部,返回 true 令浮层关闭。
  // replyTargetPostNumber>0 时定向回复该楼(带 reply_to_post_number),否则回复整个话题。
  private async submitReply(text: string, typingMs: number, composerMs: number): Promise<boolean> {
    if (!this.detail) {
      return false;
    }
    const topicId: number = this.detail.id;
    const categoryId: number | undefined = this.detail.categoryId;
    const replyToPostNumber: number | undefined =
      this.replyTargetPostNumber > 0 ? this.replyTargetPostNumber : undefined;
    const result: NetworkResult<CreateReplyOutcome> = await new TopicService(this.bridge)
      .createReply(topicId, categoryId, text, typingMs, composerMs, replyToPostNumber);

    if (result.success && result.data) {
      this.replyTargetPostNumber = 0;
      if (result.data.pending) {
        // 进入审核队列:不会成为楼层,但服务端把待审帖快照(id/raw/created_at)随响应回带了,
        // 直接乐观追加到底部待审区,不等下次刷新 topic.json。老站点/异常响应没这个快照时只提示。
        if (result.data.pendingPost) {
          this.pendingPosts = this.pendingPosts.concat([result.data.pendingPost]);
        }
        this.showToastAfterComposerClose('评论已提交，等待审核', 2000);
      } else if (result.data.post) {
        // 直接发布:追加到楼层末尾(数据源精准通知,列表只新建这一条)。
        this.dataSource.appendPosts([result.data.post]);
        this.postCount = this.dataSource.totalCount();
        this.showToastAfterComposerClose('评论已发表', 1500);
      }
      // 发表成功:清掉未发出内容的暂存 + 停掉待发的草稿保存,再删服务端草稿——
      // 否则已发出的回帖还会以草稿身份留在草稿列表里。
      this.pendingReplyText = '';
      if (this.replyDraftTimer !== -1) {
        clearTimeout(this.replyDraftTimer);
        this.replyDraftTimer = -1;
      }
      await this.deleteReplyDraft();
      // 若本次是从草稿页续写进来的,顺带删掉那条(key 可能与本主题草稿不同,如带楼号的旧草稿)。
      await this.deleteResumedDraftIfAny();
      return true;
    }

    const reason: string = result.error ? result.error.message : '发表失败，请稍后重试。';
    this.showComposerToast(reason, 2000);
    return false;
  }

  // 发送 boost:POST /discourse-boosts/posts/{id}/boosts。成功后把返回的 boost 乐观追加到该楼,
  // 返回 true 令浮层关闭;失败保留输入内容(返回 false)。
  private async submitBoost(text: string): Promise<boolean> {
    if (!this.detail || this.boostTargetPostId <= 0) {
      return false;
    }
    const postId: number = this.boostTargetPostId;
    const topicId: number = this.detail.id;
    const result: NetworkResult<PostBoost> = await new TopicService(this.bridge).createBoost(postId, topicId, text);

    if (result.success && result.data) {
      const target: TopicPost | undefined = PostStreamPager.findById(this.dataSource.getAll(), postId);
      if (target) {
        // 用新数组赋值触发 @ObjectLink 精准重渲染(直接 push 现有数组不会被观测)。
        const next: PostBoost[] = target.boosts ? target.boosts.slice() : [];
        next.push(result.data);
        target.boosts = next;
        // 一个人对一楼只能 boost 一次:提交后本地即置 canBoost=false,火箭立即对我隐藏
        // (与服务端重新返回 can_boost=false 一致,无需退出重进)。
        target.canBoost = false;
      }
      // 已发出:清掉这一楼的 boost 暂存(否则下次点这楼的火箭还会带出已发送的内容)。
      this.pendingBoostByPostId.delete(postId);
      this.boostTargetPostId = 0;
      this.showToastAfterComposerClose('Boost 已发送', 1500);
      return true;
    }

    const reason: string = result.error ? result.error.message : 'Boost 发送失败，请稍后重试。';
    this.showComposerToast(reason, 2000);
    return false;
  }

  // 删除自己发的 boost:DELETE /discourse-boosts/boosts/{id}(204 无响应体)。
  // 不做乐观移除——删失败还得把气泡按原顺序塞回去,不值当;等服务端确认再摘,失败则原样留着(同待审帖删除)。
  // 与 submitBoost 对称:成功后把该条从这一楼摘掉,并把 canBoost 放回 true——
  // 一人一楼只能 boost 一次,删掉自己那条后服务端就会重新允许,火箭即时回来,无需退出重进。
  private async deleteBoost(post: TopicPost, boost: PostBoost): Promise<boolean> {
    if (!this.detail || !LoginGate.ensureLoggedIn()) {
      return false;
    }
    const result: NetworkResult<boolean> =
      await new TopicService(this.bridge).deleteBoost(boost.id, this.detail.id);
    if (!result.success) {
      Log.i(`${LOG_TAG} deleteBoost failed id=${boost.id} status=${result.statusCode}`);
      this.showComposerToast(result.error ? result.error.message : 'Boost 删除失败，请稍后重试', 2000);
      return false;
    }

    const target: TopicPost | undefined = PostStreamPager.findById(this.dataSource.getAll(), post.id);
    if (target) {
      // 用新数组赋值触发 @ObjectLink 精准重渲染(就地改现有数组不会被观测),同 submitBoost。
      const next: PostBoost[] = (target.boosts ? target.boosts : [])
        .filter((item: PostBoost) => item.id !== boost.id);
      target.boosts = next;
      target.canBoost = true;
    }
    this.showComposerToast('Boost 已删除', 1500);
    return true;
  }

  // ===== 实时新楼(MessageBus /topic/<id> 的 created 事件) =====

  // detail 就位后向长轮询循环订阅本帖频道；循环重启(config-ready)时也会重新订阅。
  private subscribeTopicChannel(): void {
    if (!this.detail || !this.realtimePostsEnabled) {
      return;
    }
    const position: number = this.detail.messageBusLastId !== undefined ? this.detail.messageBusLastId : -1;
    this.bridge.subscribeTopicChannel(this.detail.id, position);
  }

  // 「帖子内新回复提醒」开关运行中翻转：开⇒订阅本帖频道 + 启动 Presence；关⇒退订、停 Presence、清提示条。
  private onRealtimePostsToggled(): void {
    if (this.realtimePostsEnabled) {
      this.subscribeTopicChannel();
      if (this.detail) {
        this.presence.start(this.detail.id);
      }
    } else if (this.detail) {
      this.bridge.unsubscribeTopicChannel(this.detail.id);
      this.presence.stop();
      this.pendingCreatedPostIds = [];
      if (this.createdFetchTimer !== -1) {
        clearTimeout(this.createdFetchTimer);
        this.createdFetchTimer = -1;
      }
      this.clearIncomingBanner();
    }
  }

  // 总线事件入口。只处理本帖 /topic/<id> 上的 created(MVP)；循环重启时补订阅。
  private handleMessageBusEvent(event: MessageBusEvent): void {
    // 循环重启(host 重载/前后台切换)后 state 重建，补订本帖频道 + 重同步 Presence。
    if (event.type === 'status' && event.stage === 'config-ready') {
      this.subscribeTopicChannel();
      this.presence.resync();
      return;
    }
    // Presence 增量：独立于下面 /topic 新楼的门控(服务内部按 started/频道自守卫)。
    this.presence.handleBusEvent(event);
    if (!this.realtimePostsEnabled || event.type !== 'message' || this.detail === undefined) {
      return;
    }
    if (event.channel !== `/topic/${this.detail.id}`) {
      return;
    }
    // 只在"已加载到话题结尾"时接新楼：否则新楼在已加载窗口之外，原地追加会造成楼号跳断。
    // hasMorePosts 时忽略(与无实时时行为一致，用户翻到末页/重进即可见)。
    if (this.hasMorePosts) {
      return;
    }
    const postId: number | undefined = extractCreatedPostId(event);
    if (postId === undefined) {
      return; // 非 created(revised/deleted/无 type 整帖刷新等)MVP 不处理
    }
    // 已加载 / 已在待拉队列的跳过(含用户自己刚发、已本地追加的楼)。
    if (PostStreamPager.findById(this.dataSource.getAll(), postId) !== undefined ||
      this.pendingCreatedPostIds.indexOf(postId) >= 0) {
      return;
    }
    this.pendingCreatedPostIds.push(postId);
    if (this.createdFetchTimer !== -1) {
      return; // 去抖：已排定一次批量拉，合并本次
    }
    this.createdFetchTimer = setTimeout(() => {
      this.createdFetchTimer = -1;
      this.flushCreatedPosts();
    }, INCOMING_POST_DEBOUNCE_MS);
  }

  // 去抖到点：批量拉收集到的新楼，追加到列表尾；在底部则滚动揭示，否则累计提示条。
  private async flushCreatedPosts(): Promise<void> {
    const topicId: number | undefined = this.detail?.id;
    const ids: number[] = this.pendingCreatedPostIds.filter((id: number) =>
      PostStreamPager.findById(this.dataSource.getAll(), id) === undefined);
    this.pendingCreatedPostIds = [];
    if (topicId === undefined || ids.length === 0 || this.hasMorePosts) {
      return;
    }
    const result: NetworkResult<TopicPost[]> = await new TopicService(this.bridge).loadMorePosts(topicId, ids);
    // 拉取期间可能发生换窗(rewindowToPost 跳到中段)：此时 hasMorePosts 变真，末尾追加会造成楼号跳断，
    // 或 detail/topic 已切换——一律放弃本次追加。
    if (!result.success || !result.data || result.data.length === 0 ||
      !this.detail || this.detail.id !== topicId || this.hasMorePosts) {
      return;
    }
    const before: number = this.dataSource.totalCount();
    const added: number = this.dataSource.appendPosts(result.data);
    if (added <= 0) {
      return; // 全被去重(期间已由其它路径插入)
    }
    this.postCount = this.dataSource.totalCount();
    const firstNewPostNumber: number = this.dataSource.getData(before).postNumber;
    Log.i(`${LOG_TAG} realtime created topicId=${topicId} ids=${ids.length} added=${added} atEnd=${this.atListEnd}`);
    if (this.atListEnd) {
      // 在底部：只追加，不发滚动命令。新楼正好补进末尾"加载态行 + 底部留白"腾出的那段位置
      // (54 + POST_LIST_BOTTOM_SPACER + 底部安全区 ≈ 116vp)，顶部自然露出来就够提示了；
      // maintainVisibleContentPosition 保证已经在屏上的楼层原地不动。
      // 此前这里发 scrollEdge(Edge.Bottom)，无动画瞬跳，正在读的内容会被整块顶走。
      // 注意：追加后末项被挤出视口，onScrollIndex 会把 atListEnd 置回 false——人确实不在
      // 真正的底部了，所以再来的新楼改走下面的提示条分支，这是预期行为。
      this.clearIncomingBanner();
    } else {
      // 不在底部：累计提示条，记住首条新楼楼号供点按跳转。
      if (this.incomingNewPostCount === 0) {
        this.incomingFirstNewPostNumber = firstNewPostNumber;
      }
      this.incomingNewPostCount += added;
    }
  }

  private clearIncomingBanner(): void {
    this.incomingNewPostCount = 0;
    this.incomingFirstNewPostNumber = 0;
  }

  // 点"N 条新回复"提示条：跳到首条新楼(已在列表中，走 jumpToPostNumber 的已加载滚动+落地高亮分支)。
  private openIncomingPosts(): void {
    const target: number = this.incomingFirstNewPostNumber;
    this.clearIncomingBanner();
    if (target > 0) {
      this.jumpToPostNumber(target);
    }
  }

  // 按 postNumber 滚动定位到对应楼层。List index 0 是 TopicSummary,楼层从 index 1 起 → 目标 index = 楼序 + 1。
  // 已加载直接平滑滚动;未加载原地重开窗口(先卸载 List 再以新窗口重建,见 rewindowToPost)。
  private async jumpToPostNumber(postNumber: number): Promise<void> {
    const index: number = this.dataSource.findIndexByPostNumber(postNumber);
    Log.i(`${LOG_TAG} jump request post=${postNumber} loadedIndex=${index}`);
    if (index >= 0) {
      // 已加载:落地高亮(与重开窗口路径观感一致)。
      const targetListIndex: number = index + 1;
      this.armTargetFlash(this.dataSource.getData(index).id);
      // 目标楼已在视口范围内:用 AUTO 对齐——完全可见就原地不动(不把它无谓拽到屏顶,仅靠高亮提示),
      // 只在顶/底被裁只露一半时,按最短距离滑动把它完整带进视口。
      if (targetListIndex >= this.currentStartListIndex && targetListIndex <= this.currentEndListIndex) {
        this.scroller.scrollToIndex(targetListIndex, true, ScrollAlign.AUTO);
        return;
      }
      // 完全在屏外:对齐到视口顶部(导航栏下)定位。
      this.scrollToListIndexBelowTitleBar(targetListIndex, true);
      return;
    }
    await this.rewindowToPost(postNumber);
  }

  // 点顶栏标题回到一楼。与 jumpToPostNumber 的区别:不做落地高亮——回顶是导航动作,
  // 闪一下反而突兀(高亮是给「跳到某条具体楼层」用的,要提示「就是这条」)。
  // 一楼已在当前窗口内则直接滚到列表顶(含摘要卡);翻页翻远了导致一楼已不在窗口,
  // 走 rewindowToPost 重新以一楼为中心拉一屏(即你说的「在最后面也能直接加载 1 楼数据」)。
  private async jumpToFirstPost(): Promise<void> {
    if (!this.detail || this.isRewindowing) {
      return;
    }
    const index: number = this.dataSource.findIndexByPostNumber(1);
    if (index >= 0) {
      // 滚到 0 而非 index+1:0 是摘要卡,回顶应该连标题/分类一起露出来。
      this.scroller.scrollToIndex(0, true);
      return;
    }
    // 一楼已不在当前窗口(翻页翻远了):以一楼为锚重拉一窗,asTop 让它落到摘要卡且不闪高亮。
    await this.rewindowToPost(1, true);
  }

  // 引用卡 arrow-up:被引用楼在本帖 → 滚动定位;跨帖 → 走 fallbackUrl 开详情(经 LinkRouter)。
  private jumpToQuote(topicId: number, postNumber: number, fallbackUrl: string): void {
    if (topicId === this.param.topicId && postNumber > 0) {
      this.jumpToPostNumber(postNumber);
      return;
    }
    if (fallbackUrl.length > 0) {
      this.onOpenLink(fallbackUrl);
    }
  }

  // 引用卡取被引用楼层全文:先遍历已加载楼层(本帖),没有再按需 GET /posts/by_number/{topicId}/{postNumber}。
  // 拉不到返回 ''(→ 引用卡隐藏展开、只显示预览)。
  private async resolveQuotedPost(topicId: number, postNumber: number): Promise<string> {
    if (topicId <= 0 || postNumber <= 0) {
      return '';
    }
    // 1. 已加载楼层直接取(仅本帖流里有)。
    if (topicId === this.param.topicId) {
      const index: number = this.dataSource.findIndexByPostNumber(postNumber);
      if (index >= 0) {
        const html: string = this.dataSource.getData(index).cookedHtml;
        if (html.length > 0) {
          return html;
        }
      }
    }
    // 2. 未加载:按需拉取单楼 cooked。
    const result: NetworkResult<string> = await new TopicService(this.bridge).getPostByNumber(topicId, postNumber);
    if (result.success && result.data !== undefined) {
      return result.data;
    }
    return '';
  }

  // 目标楼未加载:以该楼为锚重新拉一窗详情,原地换窗。
  // 网络期间旧列表原样保留(不白屏,顶部胶囊提示"正在定位");数据就位后换一个全新的
  // PostDataSource 实例并翻转 listEpochEven,同一帧销毁旧 List、按 initialIndex 全新重建。
  // 绝不对活 List 发 onDataReloaded——那会让 maintainVisibleContentPosition 的头插补偿
  // 永久失效(实测),这正是"新建 List 没问题、原地 reset 有问题"的根因;旧 List 至死只持有
  // 旧数据源实例,新数据源的任何通知都到不了它。
  // asTop=true:回顶语义(点顶栏标题)。首帧落到摘要卡而非目标楼、且不武装落地高亮——
  // 高亮是「跳到某条具体楼层」的提示,回顶闪一下只会突兀。必须在本方法内区分:
  // initialListIndex 由 listEpochEven 翻转触发的 List 重建当帧消费,调用方在 await 之后再改就晚了。
  private async rewindowToPost(postNumber: number, asTop: boolean = false): Promise<void> {
    if (!this.detail || this.isRewindowing) {
      return;
    }
    this.isRewindowing = true;
    this.rewindowingToTop = asTop;
    const topicId: number = this.detail.id;
    const slug: string | undefined = this.detail.slug ?? this.param.slug;

    const result: NetworkResult<TopicDetail> =
      await new TopicService(this.bridge).getTopicDetail(topicId, slug, postNumber);
    this.isRewindowing = false;
    this.rewindowingToTop = false;

    if (!result.success || !result.data || result.data.posts.length === 0) {
      // 失败:旧列表还在原位,只提示。
      Log.i(`${LOG_TAG} rewindow failed post=${postNumber} status=${result.statusCode}`);
      this.showComposerToast('楼层定位失败，请稍后重试', 1500);
      return;
    }

    const stream: number[] = result.data.stream ?? [];
    const nextSource: PostDataSource = new PostDataSource();
    nextSource.reset(result.data.posts);
    this.invalidateEarlierPrefetch();
    this.dataSource = nextSource;
    this.postCount = nextSource.totalCount();
    this.hasEarlier = PostStreamPager.countEarlier(stream, nextSource.getAll()) > 0;
    this.hasMorePosts = PostStreamPager.countLater(stream, nextSource.getAll()) > 0;
    this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
    this.updateLastVisitedAnchor();

    const targetIndex: number = Math.max(0, nextSource.findIndexAtOrAfterPostNumber(postNumber));
    // 回顶:落到 0(摘要卡,标题/分类一并露出)且不高亮;跳楼层:落到该楼并高亮提示「就是这条」。
    this.initialListIndex = asTop ? 0 : targetIndex + 1;
    this.initialListStartOffset = asTop ? 0 : immersiveTitleBarBottomOffset(this.sysTopInset);
    if (!asTop) {
      this.armTargetFlash(nextSource.getData(targetIndex).id);
    }
    this.detail = result.data;
    // 翻转分支 → 旧 List 销毁、新 List 以新数据源 + initialIndex 重建,同帧完成,无加载页。
    this.listEpochEven = !this.listEpochEven;
    const posts: TopicPost[] = nextSource.getAll();
    Log.i(`${LOG_TAG} rewindow ok post=${postNumber} targetIndex=${targetIndex} stream=${stream.length} window=[${posts[0]?.postNumber}..${posts[posts.length - 1]?.postNumber}] hasEarlier=${this.hasEarlier} hasMore=${this.hasMorePosts}`);
  }

  // 武装目标楼落地高亮:短暂生效后清零,免得该楼被 LazyForEach 销毁重建时重播。
  private armTargetFlash(postId: number): void {
    this.flashTargetPostId = postId;
    if (this.flashClearTimerId >= 0) {
      clearTimeout(this.flashClearTimerId);
    }
    this.flashClearTimerId = setTimeout(() => {
      this.flashTargetPostId = 0;
      this.flashClearTimerId = -1;
    }, 3000);
  }

  // HDS 标题栏是覆盖层，List 的 START 是物理屏幕顶部。负 extraOffset 让目标项少向前滚
  // 一个标题栏高度，最终正好停在标题栏下方；用户随后手势滚动仍可正常进入标题栏区域。
  private scrollToListIndexBelowTitleBar(listIndex: number, smooth: boolean): void {
    const remainingOffset: number = Math.max(0,
      immersiveTitleBarBottomOffset(this.sysTopInset) - this.initialListStartOffset);
    this.scroller.scrollToIndex(listIndex, smooth, ScrollAlign.START, {
      extraOffset: LengthMetrics.vp(-remainingOffset)
    });
  }

  // contentStartOffset 只用于“带目标楼首帧定位”，不应成为这一个 List 永久的滚动坐标系。
  // 用户回到顶部时将它归零；摘要项 Blank 的高度公式是 contentSpacer - startOffset，
  // 因此同一帧会等量增高，总顶部空间保持不变，不会产生视觉跳动。归零后 HDS 的 0..8vp
  // 模糊区间与普通从一楼进入时完全一致，避免再次要求内容滚到物理屏幕外才触发模糊。
  private normalizeTargetListStartOffsetAtTop(): void {
    if (this.initialListStartOffset <= 0) {
      return;
    }
    this.initialListStartOffset = 0;
  }

  // 加载某楼的「被回复」列表(供 TopicPostItem 展开时调用)。成功返回楼层数组;失败弹 toast 并返回 null。
  private async loadPostReplies(post: TopicPost): Promise<TopicPost[] | null> {
    const result: NetworkResult<TopicPost[]> = await new TopicService(this.bridge).getPostReplies(post.id);
    if (result.success && result.data) {
      return result.data;
    }
    const reason: string = result.error ? result.error.message : '加载回复失败，请稍后重试。';
    this.showComposerToast(reason, 2000);
    return null;
  }

  // 打开时立刻以帖子详情中的汇总数渲染分类栏，明细由分页接口异步补齐。
  private openReactionUsers(post: TopicPost): void {
    const total: number = Math.max(0, post.reactionUsersCount ?? 0);
    if (total === 0) {
      return;
    }
    this.reactionUsersEpoch++;
    this.reactionUsersPost = post;
    this.reactionUsersPager.reset();
    this.reactionUsers = [];
    this.reactionUsersTotal = total;
    this.reactionUsersNextPage = 0;
    this.reactionUsersHasMore = true;
    this.reactionUsersInitialError = '';
    this.reactionUsersLoadMoreError = '';
    this.reactionUsersLoading = false;
    this.selectedReactionUserFilter = '';
    this.showReactionUsersSheet = true;
    this.loadReactionUsersPage(true);
  }

  private loadMoreReactionUsers(): void {
    if (!this.reactionUsersHasMore) {
      return;
    }
    this.loadReactionUsersPage(false);
  }

  private async loadReactionUsersPage(reset: boolean): Promise<void> {
    const post: TopicPost | undefined = this.reactionUsersPost;
    if (!post || this.reactionUsersLoading || (!reset && !this.reactionUsersHasMore)) {
      return;
    }
    const epoch: number = this.reactionUsersEpoch;
    const page: number = reset ? 0 : this.reactionUsersNextPage;
    this.reactionUsersLoading = true;
    if (reset) {
      this.reactionUsersInitialError = '';
    } else {
      this.reactionUsersLoadMoreError = '';
    }

    const result = await new TopicService(this.bridge).getReactionUsers(post.id, page);
    if (epoch !== this.reactionUsersEpoch) {
      return;
    }
    this.reactionUsersLoading = false;
    if (result.success && result.data) {
      if (reset) {
        this.reactionUsersPager.reset();
      }
      this.reactionUsersPager.append(result.data);
      this.reactionUsers = this.reactionUsersPager.allUsers();
      this.reactionUsersNextPage = page + 1;
      // 空页时强制停止，避免服务端 total_rows 与分页数据短暂不一致时无限触底请求。
      this.reactionUsersHasMore = result.data.users.length > 0 && this.reactionUsersPager.hasMore();
      return;
    }

    const message: string = result.error?.message ? result.error.message : '加载表情回应失败，请稍后重试。';
    if (reset) {
      this.reactionUsersInitialError = message;
    } else {
      this.reactionUsersLoadMoreError = message;
    }
  }

  // "俺也一样"(shared issue)toggle:发网络并把服务端返回的权威新态回写到 this.detail(持久化计数/已点态),
  // 免得一楼 item 被 LazyForEach 回收重建后 aboutToAppear 又从旧值初始化、把刚点的"抹回去"。
  // 返回 { created, count } 给按钮做本地校正;null=失败(按钮回滚)。
  private async toggleSharedIssue(): Promise<SharedIssueResult | null> {
    const topicId: number = this.detail?.id ?? 0;
    if (topicId <= 0) {
      return null;
    }
    const result: SharedIssueResult | null = await this.postActions.toggleSharedIssue(topicId);
    if (result !== null && this.detail) {
      this.detail.userCreatedSharedIssue = result.created;
      this.detail.sharedIssueCount = result.count;
    }
    return result;
  }

  private showComposerToast(message: string, duration: number): void {
    promptToast(this.getUIContext(), message, duration);
  }

  // 提交成功后浮层随即关闭(键盘收起),提示延后到收场结束再弹,避免 toast 被重新锚定而跳动。
  // 失败提示不延迟:浮层保持展开、键盘不收,不存在布局变化。
  private showToastAfterComposerClose(message: string, duration: number): void {
    setTimeout(() => {
      this.showComposerToast(message, duration);
    }, SUCCESS_TOAST_DELAY_MS);
  }

  // 撤回待审帖:不可逆(审核队列里删掉就没了,原文只在这张卡片上),故先二次确认。
  private confirmDeletePending(pending: PendingPost): void {
    this.getUIContext().showAlertDialog({
      title: '删除待审核内容',
      message: '删除后这条内容不会再进入审核，也无法恢复。确定删除吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.ld_danger'),
        action: () => {
          this.deletePending(pending);
        }
      }
    });
  }

  // DELETE /review/{id}。待审帖本质是 ReviewableQueuedPost,走审核端点而非 /posts/{id}。
  // 这里不做乐观移除:删失败还得把卡片塞回原位,不值当——等服务端确认再移除,失败则原样留着。
  private async deletePending(pending: PendingPost): Promise<void> {
    if (!this.detail || !LoginGate.ensureLoggedIn()) {
      return;
    }
    const result: NetworkResult<boolean> =
      await new TopicService(this.bridge).deletePendingPost(pending.id, this.detail.id);
    if (!result.success) {
      Log.i(`${LOG_TAG} deletePending failed id=${pending.id} status=${result.statusCode}`);
      this.showComposerToast('删除失败，请稍后重试', 2000);
      return;
    }
    this.pendingPosts = this.pendingPosts.filter((item: PendingPost) => item.id !== pending.id);
    this.showComposerToast('已删除', 1500);
  }

  private replyFabButton(): ActionBarButton {
    return new ActionBarButton({
      width: LengthMetrics.vp(52),
      // 背景恒透明:玻璃态的磨砂底由 buttonModifier 里的 backgroundBlurStyle 组件材质提供,与首页 FAB 统一。
      backgroundColor: ColorMetrics.resourceColor(Color.Transparent),
      // 始终挂载 modifier(内部按开关施加/复位),避免关闭时材质/描边残留。
      buttonModifier: buildImmersiveFloatingActionButtonModifier(this.fabGlassEnabled),
      iconSize: LengthMetrics.vp(22),
      // 品牌蓝仅用于图标，仍能明确表达“回复”这个主操作。
      iconFillColor: ColorMetrics.resourceColor(REPLY_BLUE),
      baseIconSymbolGlyphModifier: this.replyFabSymbolModifier(),
      accessibilityText: '回复当前话题',
      onClick: () => {
        this.openComposerForTopic();
      }
    });
  }

  private replyFabStyle(): ActionBarStyle {
    // 外层容器恒透明、不加背景模糊(磨砂交给按钮层的组件材质)。
    return new ActionBarStyle({
      height: LengthMetrics.vp(52),
      backgroundBlurStyle: BlurStyle.NONE,
      backgroundColor: ColorMetrics.resourceColor(Color.Transparent),
      innerSpace: LengthMetrics.vp(0),
      startSpace: LengthMetrics.vp(0),
      endSpace: LengthMetrics.vp(0),
      isHorizontal: true
    });
  }

  private replyFabSymbolModifier(): SymbolGlyphModifier {
    const modifier: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.message_fill'));
    modifier.fontSize(22);
    modifier.fontColor([REPLY_BLUE]);
    return modifier;
  }

  // 列表末项下标。项序:0 = 摘要卡 → 1..postCount = 楼层 → 待审区(条件渲染) → 底部加载态行(有楼层时)。
  // 待审区那一项必须算进来:漏掉它时 lastIndex 指向的是待审区而非真正的末项,于是待审区一进视口
  // 就判成"已到底"——钉底闩提前落下,实时新楼也会误判成"人在底部"。只有本人在本帖有未过审回复时才撞上。
  private lastListIndex(): number {
    const pendingSection: number = (!this.hasMorePosts && this.pendingPosts.length > 0) ? 1 : 0;
    const tailRow: number = this.postCount > 0 ? 1 : 0;
    return this.postCount + pendingSection + tailRow;
  }

  // 依据视口首/末项下标维护 scrubber 状态:可滚动性、钉底闩、当前楼号。
  private updateScrubberFromScroll(start: number, end: number): void {
    const lastIndex: number = this.lastListIndex();
    // 摘要(index 0)与末尾项同时可见 = 整屏放得下、不可滚动 → 隐藏 scrubber。
    this.listScrollable = !(start === 0 && end >= lastIndex);
    // 末尾项滚出视口即离开底部,撤销钉底(短楼:滑块回落到首楼映射;长末楼:首楼本就是 max,无影响)。
    if (this.atListEnd && end < lastIndex) {
      this.atListEnd = false;
    }
    // 钉底优先 → 顶部(摘要可见)记 1 楼 → 否则取视口首楼楼号。
    if (this.atListEnd) {
      this.currentPostNumber = this.getHighestPostNumber();
      return;
    }
    if (start === 0) {
      this.currentPostNumber = 1;
      return;
    }
    const firstPostIndex: number = start - 1;
    if (firstPostIndex >= 0 && firstPostIndex < this.dataSource.totalCount()) {
      this.currentPostNumber = this.dataSource.getData(firstPostIndex).postNumber;
    }
  }

  // scrubber 上限:优先话题最高楼号;缺失时回退到已加载末楼 / 楼层数。
  private getHighestPostNumber(): number {
    const highest: number = this.detail?.highestPostNumber ?? 0;
    if (highest > 0) {
      return highest;
    }
    const posts: TopicPost[] = this.dataSource.getAll();
    if (posts.length > 0) {
      return posts[posts.length - 1].postNumber;
    }
    return this.postCount;
  }

  private async loadTopicDetail(): Promise<void> {
    if (!this.isArkWebReady) {
      this.message = '正在准备 ArkWeb 请求环境';
      return;
    }

    if (this.isLoading) {
      return;
    }

    if (this.param.topicId <= 0) {
      this.message = '帖子参数无效';
      return;
    }

    this.isLoading = true;
    this.requiresChallenge = false;
    this.message = '正在加载帖子详情';
    this.loadSiteMetadataIfNeeded();
    Log.i(`${LOG_TAG} load detail start topicId=${this.param.topicId} slug=${this.getSlugLabel()}`);

    const result: NetworkResult<TopicDetail> =
      await new TopicService(this.bridge).getTopicDetail(this.param.topicId, this.param.slug, this.param.targetPostNumber);

    this.isLoading = false;
    if (result.success && result.data) {
      const stream: number[] = result.data.stream ?? [];
      this.detail = result.data;
      this.invalidateEarlierPrefetch();
      this.dataSource.reset(result.data.posts);
      this.postCount = this.dataSource.totalCount();
      // 待审区以服务端为准整体替换:重新加载详情即对齐真值,过审的条目自然消失(它已变成正式楼层)。
      this.pendingPosts = result.data.pendingPosts ?? [];
      this.message = this.postCount > 0 ? '' : '暂无帖子内容';
      this.hasEarlier = PostStreamPager.countEarlier(stream, this.dataSource.getAll()) > 0;
      this.hasMorePosts = PostStreamPager.countLater(stream, this.dataSource.getAll()) > 0;
      this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
      this.initialListIndex = 0;
      this.initialListStartOffset = 0;
      // 带目标楼进入:List 尚未创建(detail 刚就位),首帧直接定位到目标楼(+1 为 summary 占位)。
      const target: number | undefined = this.param.targetPostNumber;
      if (target !== undefined && target > 1 && this.postCount > 0) {
        const targetIndex: number = Math.max(0, this.dataSource.findIndexAtOrAfterPostNumber(target));
        this.initialListIndex = targetIndex + 1;
        this.initialListStartOffset = immersiveTitleBarBottomOffset(this.sysTopInset);
        if (this.param.highlightTarget === true) {
          this.armTargetFlash(this.dataSource.getData(targetIndex).id);
        }
      }
      // "上次访问"红线只属于"未读徽标跳转"入口:带目标楼号且不高亮(通知=带楼号+高亮、
      // 普通打开=无楼号,都不画线;官网是所有入口都画,这里按产品偏好收窄)。
      // 从草稿页续写回帖:详情就位后自动弹全屏回复框并回填草稿正文。
      // 放这里(而非 aboutToAppear)是因为 submitReply 依赖 detail,提前弹会得到一个提交必失败的框。
      // 一次进入只弹一次:重载/刷新不该再弹。
      this.maybeOpenDraftComposer();
      const isUnreadBadgeEntry: boolean =
        this.param.targetPostNumber !== undefined && this.param.highlightTarget !== true;
      // 水位只在首次加载快照;已读完(水位>=最高楼)或匿名(无水位)不设线。
      if (isUnreadBadgeEntry && this.lastVisitedSnapshot === 0) {
        const watermark: number = result.data.lastReadPostNumber ?? 0;
        const highest: number = result.data.highestPostNumber ?? 0;
        if (watermark > 0 && watermark < highest) {
          this.lastVisitedSnapshot = watermark;
        }
      }
      this.updateLastVisitedAnchor();
      // 定位与红线对齐:红线锚楼取自详情接口的真实水位(result.data.lastReadPostNumber → lastVisitedSnapshot),
      // 而入口楼号 param.targetPostNumber 来自列表页水位(可能陈旧/估算,见 HomePage.openTopic),两者不一致
      // 会造成"定位到 50 楼、红线却画在 43 楼"。锚楼一旦确定,改用真实水位把首帧落点重算成第一条真实未读楼
      // (锚楼的下一楼),与红线严格对齐。
      if (isUnreadBadgeEntry && this.lastVisitedAnchorPostId > 0) {
        const firstUnreadIndex: number = Math.max(0, this.dataSource.findIndexAtOrAfterPostNumber(this.lastVisitedSnapshot + 1));
        this.initialListIndex = firstUnreadIndex + 1;
        this.initialListStartOffset = immersiveTitleBarBottomOffset(this.sysTopInset);
      }
      Log.i(`${LOG_TAG} load detail success topicId=${result.data.id} posts=${result.data.posts.length} stream=${result.data.stream ? result.data.stream.length : 0}`);
      this.startReadingTrackerIfNeeded();
      // detail 就位：订阅 /topic/<id> 实时新楼（起点游标取 message_bus_last_id，缺失回落 -1）。
      this.subscribeTopicChannel();
      // 块 2：启动"正在回复"下行(仅当开关开；服务内部再走 /presence/get + 订阅增量)。
      if (this.realtimePostsEnabled) {
        this.presence.start(this.detail.id);
      }
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.message = result.error?.message ? result.error.message : '帖子详情加载失败';
    Log.i(`${LOG_TAG} load detail failed topicId=${this.param.topicId} status=${result.statusCode}`);
  }

  private async loadMorePosts(): Promise<void> {
    if (!this.detail || this.isLoadingMore || !this.hasMorePosts) {
      return;
    }
    const stream: number[] = this.detail.stream ? this.detail.stream : [];
    const nextIds: number[] = PostStreamPager.collectNextIds(stream, this.dataSource.getAll(), POSTS_PAGE_SIZE);
    if (nextIds.length === 0) {
      this.hasMorePosts = false;
      this.loadMoreMessage = '没有更多了';
      return;
    }

    this.isLoadingMore = true;
    this.loadMoreMessage = '正在加载更多';
    const topicId: number = this.detail.id;
    const result: NetworkResult<TopicPost[]> = await new TopicService(this.bridge).loadMorePosts(topicId, nextIds);
    this.isLoadingMore = false;

    if (result.success && result.data) {
      const added: number = this.dataSource.appendPosts(result.data);
      this.postCount = this.dataSource.totalCount();
      this.hasMorePosts = PostStreamPager.countLater(stream, this.dataSource.getAll()) > 0;
      this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
      this.updateLastVisitedAnchor();
      Log.i(`${LOG_TAG} load more topicId=${topicId} added=${added} total=${this.postCount}`);
      return;
    }

    this.loadMoreMessage = result.error?.message ? `${result.error.message}，上拉重试` : '加载更多失败，上拉重试';
  }

  // 确定"上次访问"红线锚楼:快照水位后第一条未读楼的**上一楼**(最后一条已读)。
  // 红线画在锚楼底边,替代该处灰色分割线 → 楼间只此一条,恰是"已读|未读"边界。
  // 上一楼须已加载(index>0)才能锚;首条已加载楼即未读时,已读侧还在未加载区,留待 prepend 补楼后重试。
  // 锚一旦确定不再变化。
  private updateLastVisitedAnchor(): void {
    if (this.lastVisitedSnapshot <= 0 || this.lastVisitedAnchorPostId > 0 || !this.detail) {
      return;
    }
    const posts: TopicPost[] = this.dataSource.getAll();
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].postNumber <= this.lastVisitedSnapshot) {
        continue;
      }
      if (index > 0) {
        this.lastVisitedAnchorPostId = posts[index - 1].id;
      }
      return;
    }
  }

  // 换窗/重载时调用:纪元 +1 让在途预取的响应自行丢弃,并清掉已缓存的旧窗口楼层。
  private invalidateEarlierPrefetch(): void {
    this.earlierEpoch += 1;
    this.pendingEarlier = [];
  }

  // 向上补更早楼层(窗口式进入后往回看)的第一步:取已加载区间之前的一页 id 拉回来存进 pendingEarlier,
  // 不碰数据源、不动画面。何时真正插入由 tryFlushEarlierPosts 决定。
  // pending 未清空时不再重复拉:prevIds 按 dataSource 已加载区间算,pending 尚未并入,再拉就是同一批。
  private async prefetchEarlierPosts(): Promise<void> {
    if (!this.detail || this.isLoadingEarlier || !this.hasEarlier || this.pendingEarlier.length > 0) {
      return;
    }
    const stream: number[] = this.detail.stream ? this.detail.stream : [];
    const loaded: TopicPost[] = this.dataSource.getAll();
    const prevIds: number[] = PostStreamPager.collectPrevIds(stream, loaded, POSTS_PAGE_SIZE);
    Log.i(`${LOG_TAG} prefetchEarlier begin stream=${stream.length} loaded=${loaded.length} window=[${loaded[0]?.postNumber}..${loaded[loaded.length - 1]?.postNumber}] prevIds=${prevIds.length}`);
    if (prevIds.length === 0) {
      this.hasEarlier = false;
      return;
    }

    this.isLoadingEarlier = true;
    const topicId: number = this.detail.id;
    const epoch: number = this.earlierEpoch;
    const result: NetworkResult<TopicPost[]> = await new TopicService(this.bridge).loadMorePosts(topicId, prevIds);
    this.isLoadingEarlier = false;
    // 等待期间换过窗:这批楼层属于旧窗口,插进去就是楼号错乱,直接丢弃。
    if (epoch !== this.earlierEpoch) {
      Log.i(`${LOG_TAG} prefetchEarlier stale drop epoch=${epoch} now=${this.earlierEpoch}`);
      return;
    }

    if (result.success && result.data) {
      this.pendingEarlier = result.data;
      Log.i(`${LOG_TAG} prefetchEarlier ok cached=${this.pendingEarlier.length}`);
      // 响应回来时滑动可能已停,onScrollIndex 不再回调 → 主动试插一次,否则数据一直躺在缓存里。
      this.tryFlushEarlierPosts(this.currentStartListIndex);
      return;
    }

    Log.i(`${LOG_TAG} prefetchEarlier failed topicId=${topicId} status=${result.statusCode} err=${result.error?.message ?? ''}`);
    this.showComposerToast(result.error?.message ? result.error.message : '加载更早楼层失败', 1500);
  }

  // 第二步:把预取好的更早楼层头插进数据源。响应到达时立即插入，保证用户第一次回看前
  // 上一批楼层已经存在。prependPosts 会发精准 ADD@0，List 据此自动保持当前可见内容。
  // 这里禁止再调用 scrollToIndex：HDS 标题栏覆盖在 List 上方，onScrollIndex 的 start 是
  // 物理屏幕顶部可见项，可能正是藏在标题栏下面的上一楼；手动对齐会把它错误地拉到标题栏底部。
  private tryFlushEarlierPosts(start: number): void {
    if (this.pendingEarlier.length === 0) {
      return;
    }
    const batch: TopicPost[] = this.pendingEarlier;
    this.pendingEarlier = [];
    const added: number = this.dataSource.prependPosts(batch);
    this.postCount = this.dataSource.totalCount();
    const stream: number[] = this.detail && this.detail.stream ? this.detail.stream : [];
    this.hasEarlier = PostStreamPager.countEarlier(stream, this.dataSource.getAll()) > 0;
    this.updateLastVisitedAnchor();
    Log.i(`${LOG_TAG} flushEarlier maintained start=${start} added=${added} total=${this.postCount} hasEarlier=${this.hasEarlier}`);
  }

  private startReadingTrackerIfNeeded(): void {
    const service: TopicService = new TopicService(this.bridge);
    this.readController.startIfNeeded(
      (id: number, timings: Map<number, number>, topicTime: number) => service.reportTimings(id, timings, topicTime),
      LOG_TAG
    );
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady && !this.detail && !this.isLoading) {
      this.loadSiteMetadataIfNeeded();
      this.loadTopicDetail();
    }
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    if (!this.detail && !this.isLoading) {
      this.message = '会话已更新，正在重试';
      this.loadTopicDetail();
    }
  }

  private getTitle(): string {
    const title: string | undefined = this.detail?.title;
    if (title && title.length > 0) {
      return title;
    }
    return this.param.title;
  }

  // 过盾入口只在用户主动开启快捷入口且本次阅读确实命中验证时交给 HDS menu 渲染。
  private shouldShowChallengeShortcut(): boolean {
    return ChallengeShortcutPrefs.isEnabled() && this.challengeBlocked;
  }

  // detail 整体加载/替换时,把主题级书签态同步到独立驱动的 topicBookmarked(标题书签图标的真源)。
  private syncTopicBookmarkFromDetail(): void {
    this.topicBookmarked = this.detail?.bookmarked === true;
  }

  private getTopicMetaText(): string {
    if (!this.detail) {
      return `Topic ID：${this.param.topicId}`;
    }

    const postsCount: number = this.detail.postsCount ? this.detail.postsCount : this.postCount;
    const replyCount: number = this.detail.replyCount ? this.detail.replyCount : 0;
    const likeCount: number = this.detail.likeCount ? this.detail.likeCount : 0;
    const viewCount: number = this.detail.viewCount ? this.detail.viewCount : 0;
    return `${postsCount} 帖 · ${replyCount} 回复 · ${likeCount} 赞 · ${viewCount} 浏览`;
  }

  private async loadSiteMetadataIfNeeded(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  private hasBadges(): boolean {
    return CategoryIndex.find(this.categories, this.detail?.categoryId) !== undefined || this.getTags().length > 0;
  }

  private getTags(): TopicTag[] {
    return this.detail?.tags ? this.detail.tags : [];
  }

  // 本帖是否该出抽奖提醒:总开关 + 帖子本身的判定(见 LotteryTopicRule,含「高级推广」排除、
  // 已关闭/已归档、楼主是自己这几条)。详情未到手时先不显示,免得标签还没解析出来先闪一下。
  private showsLotteryNotice(): boolean {
    if (!this.lotteryTipEnabled || this.detail === undefined) {
      return false;
    }
    return shouldShowLotteryNotice({
      tags: this.getTags(),
      closed: this.detail.closed === true,
      archived: this.detail.archived === true,
      createdById: this.detail.createdById ?? 0,
      currentUserId: this.currentUser.id
    });
  }

  // 回复浮层顶上那行提醒:只给普通回复,boost(短文本,规则管不着)与编辑(改的是已发出的内容)不给。
  private lotteryReplyHint(): string {
    if (this.boostTargetPostId > 0 || this.editingPostId > 0) {
      return '';
    }
    return this.showsLotteryNotice() ? LOTTERY_REPLY_HINT : '';
  }

  private getSlugLabel(): string {
    if (!this.param.slug || this.param.slug.length === 0) {
      return '无';
    }
    return this.param.slug;
  }
}
