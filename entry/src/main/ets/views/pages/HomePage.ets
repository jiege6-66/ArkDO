import { Log } from '../../services/logging/Log';
import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { User } from '../../models/User';
import { Topic, TopicCategory, TopicTag } from '../../models/Topic';
import { TopicListItem } from '../components/TopicListItem';
import { UserAvatar } from '../components/UserAvatar';
import { NotificationBell } from '../components/NotificationBell';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { LoadStateView } from '../components/LoadStateView';
import { TopicReadState, TopicReadStateEventBus } from '../../services/session/TopicReadStateEventBus';
import { NotificationEventBus, NotificationSnapshot } from '../../services/notification/NotificationEventBus';
import {
  extractMessageBusCategoryId,
  extractMessageBusTopicId,
  MessageBusEvent,
  MessageBusEventBus
} from '../../services/message/MessageBusEventBus';
import { TopicPage, TopicService } from '../../services/topic/TopicService';
import { TopicDataSource } from '../../services/topic/TopicDataSource';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { FeedKey } from '../../services/site/FeedPrefs';
import {
  cloneTopicListQuery,
  createDefaultTopicListQuery,
  hasTopicListSummary,
  isDefaultTopicListQuery,
  sameTopicListQuery,
  topicListPrimaryTitle,
  topicListSummaryLead,
  topicListSummaryTag,
  TopicListQuery
} from '../../services/topic/TopicListQuery';
import { SiteDef, SitePrefs } from '../../services/site/SitePrefs';
import { CategoryDrawer } from '../components/CategoryDrawer';
import { HomeFab } from '../components/HomeFab';
import {
  HomeIncomingTopicsPrompt,
  shouldShowIncomingTopicsPrompt
} from '../components/HomeIncomingTopicsPrompt';
import {
  addIncomingTopicMessage,
  clearHomeIncomingTopics,
  createHomeIncomingTopicsState,
  HomeIncomingTopicsState,
  homeIncomingTopicsCount,
  incomingTopicMatchesCategory,
  removeIncomingTopicsSnapshot,
  snapshotHomeIncomingTopics
} from '../../services/home/HomeIncomingTopicsController';
import { ComposerPage } from './ComposerPage';
import { LoginGate } from '../../services/session/LoginGate';
import { REALTIME_TOPICS_ENABLED_STORAGE_KEY } from '../../services/realtime/RealtimeTopicsPrefs';
import { BADGE_FILTER_ENABLED_STORAGE_KEY } from '../../services/home/BadgeFilterPrefs';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { SEARCH_ICON_GEOMETRY_ID } from '../components/SearchOverlay';
import { SEARCH_OVERLAY_VISIBLE_KEY } from '../../common/constants/StorageKeys';
import { SYS_BOTTOM_INSET_KEY, SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { PostRichContent } from '../components/PostRichContent';
import {
  getCategoryColor,
  getCategoryIcon,
  getCategoryLogo,
  getTagColor,
  getTagIcon,
  resolveBadgeAssetUrl
} from '../components/TopicBadgeUtils';
import { VersionAnnouncement, VersionAnnouncementService } from '../../services/announce/VersionAnnouncement';
import { bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { FrameCallback } from '@kit.ArkUI';
import { showToast as promptToast } from '../../common/utils/Toast';
import { submitNewTopic } from '../../services/topic/CreateTopicFlow';
import { HOME_COMPOSER_BACK_TICK_KEY, HOME_COMPOSER_VISIBLE_KEY } from '../../common/constants/StorageKeys';
import { SCRIM } from '../../common/theme/Palette';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  HDS_TITLE_BAR_MASK_EXTRA_HEIGHT,
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';
import {
  SMART_REACH_ANIMATION_DURATION,
  SMART_REACH_LEFT_HAND_STORAGE_KEY,
  smartReachBottomAlignRules
} from '../../common/ui/SmartReachLayout';

const LOG_TAG: string = '[ArkDO][Home]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
// 侧边抽屉宽度(关闭时向左平移此距离移出屏幕)。
const DRAWER_WIDTH: number = 288;
// ===== 从左边缘右滑跟手拉出版块抽屉 =====
// 起手区宽度(vp):按下点距屏幕左边小于它,右滑才认作「拉抽屉」,否则中屏随手右滑就把抽屉带出来了。
// 别再往小调:实测「贴着边缘滑」的按下点落在 30~45,而不是贴着 0——最靠边的那几毫米被系统侧滑
// 返回的热区吃掉,触点根本派发不进来。留出这段够不着的余量,起手区才有实际可用宽度。
// (391vp 屏宽下约占 14%,而中屏右滑实测 downX≈245,离得很远,不会误触。)
const DRAWER_EDGE_WIDTH: number = 56;
// 松手判定阈值:拉出/推回超过抽屉宽度这个比例即补完动作,否则回弹。开与关同一比例,两向手感对称。
const DRAWER_COMMIT_RATIO: number = 0.4;
// 松手判定阈值:横向甩速(vp/s)超过即直接补完,不看距离。
const DRAWER_COMMIT_VELOCITY: number = 800;
// ↓↓↓ 手感就调这三个:补完时长、回弹时长、收尾曲线。与个人中心左滑那套(RootTabPage)取值一致。 ↓↓↓
const DRAWER_COMMIT_MS: number = 280;
const DRAWER_REBOUND_MS: number = 220;
const DRAWER_SETTLE_CURVE: Curve = Curve.Friction;
// 版本公告弹窗:true=每次启动都弹(调试用);false=同一版本只弹一次(上线值)。
const ANNOUNCE_ALWAYS_SHOW: boolean = false;
// 诊断关键字:hilog / DevEco Log 里搜 ANNOUNCE_DIAG 看公告全链路日志。
const ANNOUNCE_DIAG: string = '[ArkDO][ANNOUNCE_DIAG]';
// 记「已弹过的 versionCode」的偏好 key(全项目共用 'app_settings' 库)。
const ANNOUNCE_PREFS_NAME: string = 'app_settings';
const ANNOUNCE_SHOWN_CODE_KEY: string = 'announce_shown_version_code';
// 右下角悬浮按钮换成「回到顶部」的滚动阈值,单位=视口高的倍数。
// 浮现/收起取不同值形成滞回区:轻微滑动不该把发帖入口换掉(1.5 屏才浮现),
// 也不能让用户停在临界点时图标反复 morph(退回 1.2 屏才变回发帖)。
const FAB_TOP_SHOW_RATIO: number = 1.5;
const FAB_TOP_HIDE_RATIO: number = 1.2;
// 首页发帖浮层可见态镜像 + 返回键信号:浮层内联挂在首页根 Stack,不进 Navigation 栈。
// 首页坐在 navBar(非 NavDestination),系统返回键须由 @Entry(Index)的 onBackPress 拦截——
// 可见时 bump BACK_TICK,首页监听后关闭。与详情页回帖浮层各用一套 key,互不干扰。
// 回顶动画:只有最后一屏走动画,这是那一屏的时长。
const SCROLL_TOP_MS: number = 460;
// 瞬移落地的重试上限:惯性未停时 scrollTo 可能被"顶回去",逐帧再钉;超过则放弃动画直接到顶,
// 宁可生硬也不能卡在半路。
const SCROLL_TOP_MAX_RETRY: number = 3;
const INCOMING_HIGHLIGHT_MS: number = 1500;
const INCOMING_PROMPT_HEIGHT: number = 44;
const INCOMING_PROMPT_ENTER_MS: number = 240;
const INCOMING_PROMPT_EXIT_MS: number = 180;
const INCOMING_INSERT_MS: number = 360;
// 单条增量行的兜底高度(含分割线)。真机测到实际高度前先用它算揭示距离，避免第一帧跳变。
const INCOMING_INSERT_ROW_ESTIMATE: number = 96;
// 顶栏主标题(版块/标签名)的字号区间:装得下用大的,长名字自适应往下缩,缩到下限还装不下才截断。
// ArkDO 那个默认标题不走这套(它长度固定),仍是 26。
// 独占一行时给足 21;要带副行时收到 19,和 13 的副行拉开层次但不至于一大一小失衡。
const TITLE_MAX_FONT_SIZE: number = 21;
const TITLE_MIN_FONT_SIZE: number = 15;
const TITLE_WITH_SUMMARY_MAX_FONT_SIZE: number = 19;
const TITLE_WITH_SUMMARY_MIN_FONT_SIZE: number = 14;
// 副行胶囊:高度压到 20 是为了两行合计仍落在 MINI 顶栏高度内(标题 19 + 间距 1 + 胶囊 20)。
// 实机若发现被裁,优先动这三个数。
const SUMMARY_FONT_SIZE: number = 12;
const SUMMARY_CHIP_HEIGHT: number = 20;
const SUMMARY_CHIP_ICON_SIZE: number = 10;
const TITLE_ICON_SIZE: number = 17;

// 顶栏副行里一枚条件胶囊的入参。
interface QueryChipParams {
  label: string;
  // 无图标时传 undefined(排序胶囊就没有图标)。
  icon?: FaIconDefinition;
  // 十六进制色;空串 = 跟随文字色。
  iconColor: string;
}

// 把比例夹到 0~1。跟手手势里到处要用:手指可以拖过头,进度不能。
function clampUnit(value: number): number {
  return Math.min(1, Math.max(0, value));
}

// 下一帧回调。setTimeout(0) 只是"下一个宏任务",跟"上一帧已渲染"没有任何保证关系,
// 用它串瞬移→动画会时灵时不灵;postFrameCallback 才是真正的帧边界。
class NextFrameTask extends FrameCallback {
  private readonly run: () => void;

  constructor(run: () => void) {
    super();
    this.run = run;
  }

  onFrame(_frameTimeInNano: number): void {
    this.run();
  }
}

@Component({ freezeWhenInactive: true })
export struct HomePage {
  @State private topics: Topic[] = [];
  // 完整刷新会替换整批 Topic 实例。版本变化后重建 TopicListItem，避免 @ObjectLink 仍绑定旧实例。
  @State private topicListVersion: number = 0;
  private topicDataSource: TopicDataSource = new TopicDataSource();
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private currentPage: number = 0;
  @State private listMessage: string = '正在准备 ArkWeb 请求环境';
  @State private footerMessage: string = '上拉加载更多';
  @State private requiresChallenge: boolean = false;
  @State private loadFailed: boolean = false;
  @State private categories: TopicCategory[] = [];
  // 侧边版块抽屉开关。
  @State private showSideBar: boolean = false;
  // 抽屉内容是否挂载。与 showSideBar 分开:开抽屉时先于动画置真,关抽屉时等滑出动画播完才置假,
  // 保证内容的挂载/卸载都发生在屏幕左外、看不见的位置。见 build 里抽屉那段的注释。
  @State private drawerMounted: boolean = false;
  // 版块树的展开态。放在本页而非抽屉内部:抽屉内容会随开合挂载/卸载,状态留在里面会被一起丢掉。
  @State private drawerExpandedIds: number[] = [];
  // 抽屉展开进度 0~1(0=完全在屏外,1=完全展开)。同时驱动抽屉位移与遮罩浓度,拖拽期间直接跟手,
  // 开合动画期间由 animateTo 插值。位移 = (progress - 1) * DRAWER_WIDTH。
  @State private drawerProgress: number = 0;
  // 本轮左滑是否已被接管:onActionStart 里判定一次,后续 update/end 据此放行。
  private swipeTracking: boolean = false;
  // 本轮边缘右滑(拉抽屉)是否已被接管。与 swipeTracking 同由 onActionStart 二选一置真。
  private drawerSwiping: boolean = false;
  // 最近一次按下的横坐标(vp,即距屏幕左边的距离)。判「是否从左边缘起手」用。-1 = 还没按下过。
  private touchDownX: number = -1;
  // 当前生效的列表条件:过滤器 × 版块 × 标签三个维度正交(不是互斥的单选),拼装规则见 TopicListQuery。
  @State private listQuery: TopicListQuery = createDefaultTopicListQuery();
  // 抽屉里正在编辑的那份草稿。放在本页而非抽屉内部:抽屉内容随开合挂载/卸载,状态留在里面会被一起丢掉
  // (与 drawerExpandedIds 同理)。开抽屉时从 listQuery 拷一份,点「查看结果」才提交回 listQuery。
  @State private draftQuery: TopicListQuery = createDefaultTopicListQuery();
  // 抽屉「我的站点」区:入口开关 + 要展示的站点(打开抽屉时刷新)。
  @State private sitesEntryEnabled: boolean = true;
  @State private drawerSites: SiteDef[] = [];
  // 头像铃铛未读数:由 NotificationEventBus 广播驱动(NotificationService 前台轮询产出)。
  @State private unreadNotifications: number = 0;
  private unsubscribeNotifications?: () => void = undefined;
  private unsubscribeMessageBus?: () => void = undefined;
  private categoryIndex: CategoryIndex = new CategoryIndex();
  // 帖子列表的 Scroller:回顶按钮要用它跳回顶部,滚动阈值判定也靠它读当前偏移。
  private listScroller: Scroller = new Scroller();
  // 右下角悬浮按钮当前身份:false=发帖,true=回到顶部。由滚动位置驱动。
  @State private showBackToTopFab: boolean = false;
  // MessageBus 接入后写入 topicId；当前长按 FAB 注入模拟 topicId 验证去重计数链路。
  @State private incomingTopicsState: HomeIncomingTopicsState = createHomeIncomingTopicsState();
  @State private isLoadingIncoming: boolean = false;
  @State private incomingHighlightedTopicIds: number[] = [];
  @State private incomingHighlightDeadline: number = 0;
  @State private incomingPromptHeight: number = 0;
  @State private incomingPromptOpacity: number = 0;
  @State private incomingInsertActive: boolean = false;
  @State private incomingInsertProgress: number = 1;
  @State private incomingInsertingTopicIds: number[] = [];
  // 揭示距离 = 本次插入块的总高度。所有非新增行统一按它上移再滑回，方向与幅度都对齐真实布局。
  @State private incomingInsertRevealDistance: number = 0;
  private incomingRequestEpoch: number = 0;
  private incomingHighlightEpoch: number = 0;
  private incomingInsertEpoch: number = 0;
  private incomingInsertTimerId: number = -1;
  // 起播前累计新增行实测高度；起播后冻结，避免中途改距离造成跳变。
  private incomingInsertMeasuredIds: number[] = [];
  private incomingInsertMeasuredHeight: number = 0;
  private incomingInsertPlayed: boolean = false;
  // 「实时更新话题」开关。关闭(默认)时忽略事件、隐藏提示；运行中翻转由 @Watch 中和残留态。
  @StorageProp(REALTIME_TOPICS_ENABLED_STORAGE_KEY) @Watch('onRealtimeTopicsEnabledChanged')
  private realtimeTopicsEnabled: boolean = false;
  // 「点分类/标签快速筛选」开关(实验性功能页,默认关)。开着时帖子行上的徽章可点。
  @StorageProp(BADGE_FILTER_ENABLED_STORAGE_KEY) private badgeFilterEnabled: boolean = false;
  // 传感器只发布明确的左右手结果；本页把结果转成 RelativeContainer 约束，保证换边可平滑插值。
  @StorageProp(SMART_REACH_LEFT_HAND_STORAGE_KEY) @Watch('onSmartReachSideChanged')
  private smartReachLeftHanded: boolean = false;
  @State private fabAlignRules: AlignRuleOption = smartReachBottomAlignRules(false);
  // 列表视口实测高度(vp):把滚动偏移换算成"滑过几屏"的分母,onAreaChange 量得。
  @State private listViewportH: number = 0;
  // 发帖浮层开关。
  @State private showComposer: boolean = false;
  // 返回键信号镜像:Index.onBackPress 在浮层可见时 bump,本页 @Watch 接住关闭。
  @StorageProp(HOME_COMPOSER_BACK_TICK_KEY) @Watch('onComposerBackTick') private composerBackTick: number = 0;
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  // 宿主真就绪信号:宿主每次真正就绪(onPageEnd,executor 已挂)时宿主自增此计数。
  // 冷启动若越过看门狗才就绪,isArkWebReady 早被失败路径置真、@Watch 不再触发,列表会卡在失败态;
  // 接住此信号在真就绪时补拉一次,把「卡死+手点重试」变成自动自愈。
  @Prop @Watch('handleHostReadyEpoch') hostReadyEpoch: number = 0;
  @Prop accountUser: User = { id: 0, username: '' };
  @Prop isLoggedIn: boolean = false;
  @Prop isCheckingSession: boolean = false;
  @Prop hasCheckedSession: boolean = false;
  onAccountClick: () => void = () => {};
  // 左滑拉出个人中心:手势在本页,导航栈在宿主(RootTabPage)手里,故三个阶段全部上抛。
  onProfileSwipeStart: () => void = () => {};
  onProfileSwipeUpdate: (progress: number) => void = () => {};
  onProfileSwipeEnd: (progress: number, velocity: number) => void = () => {};
  // 主体实测宽度(vp):把手指位移换算成 0~1 进度的分母。
  @State private swipeAreaWidth: number = 0;
  // 下拉刷新时通知宿主补查会话:上次会话检查被 CF 拦截时,右上角状态可能不真实。
  onSessionRecheck: () => void = () => {};
  onOpenNotifications: () => void = () => {};
  onOpenSearch: () => void = () => {};
  // 搜索 Flow 可见态镜像:一镜到底期间隐藏顶栏源图标,把几何交给搜索页里的目标图标(geometryTransition)。
  @StorageProp(SEARCH_OVERLAY_VISIBLE_KEY) private searchOverlayVisible: boolean = false;
  // 窗口常驻全屏布局:主体内容自行避让状态栏(padding 加在带背景的主体列,背景填满状态栏条);
  // 遮罩与抽屉不加,天然盖满整屏。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  // 列表区 Stack 铺进了底部安全区(expandSafeArea BOTTOM),悬浮按钮得自己躲开手势条,
  // 否则 16vp 的底边距会把它压在导航指示条上。
  @StorageProp(SYS_BOTTOM_INSET_KEY) private sysBottomInset: number = 0;
  onTopicClick: (topic: Topic) => void = () => {};
  // 按帖子 ID 直接跳转详情(通用入口,不依赖完整 Topic 对象)。
  onOpenTopicById: (topicId: number) => void = () => {};
  // 点未读徽标:带目标楼号打开详情,直接定位到第一条未读楼。
  onOpenTopicAtPost: (topic: Topic, postNumber: number) => void = () => {};
  // 抽屉「我的站点」标题行:打开站点管理页。
  onOpenSites: () => void = () => {};
  // 抽屉站点行:打开该站点(走通用 WebView 页)。siteId 用于缓存该站 favicon。
  onOpenSite: (url: string, title: string, siteId: string) => void = () => {};
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;
  private unsubscribeTopicReadState?: () => void = undefined;
  // 会话变化撞上在途列表请求时先记账，请求结束后再按最新 Cookie 补拉首页。
  private pendingSessionRefresh: boolean = false;
  // 用户点 incoming 提示时若列表请求在途，等当前请求结束再做增量加载；成功前不丢 topic ID。
  @State private pendingIncomingRefresh: boolean = false;
  // 调试用:输入帖子 ID 直接跳转详情(有些帖子已从最新列表里翻走,无法在列表中找到)。
  private jumpDialogController: CustomDialogController = new CustomDialogController({
    builder: TopicJumpDialog({
      onConfirm: (topicId: number) => {
        this.jumpToTopic(topicId);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });
  // 版本公告弹层:命中当前 versionCode 的回复后展示其正文。
  @State private announceVisible: boolean = false;
  @State private announceCooked: string = '';
  // 本次页面挂载是否已发起过公告检查(每次冷启动只查一次,不随下拉刷新/切源重复)。
  private announceChecked: boolean = false;

  aboutToAppear(): void {
    // 页面可能在左手状态已生效后才重新挂载，首帧直接使用当前侧，避免先从右侧飞入。
    this.fabAlignRules = smartReachBottomAlignRules(this.smartReachLeftHanded);
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }
    if (!this.unsubscribeTopicReadState) {
      // 从详情页返回时同步该主题的已读状态(消蓝点、更新未读徽标)。
      this.unsubscribeTopicReadState = TopicReadStateEventBus.subscribe((state: TopicReadState) => {
        this.handleTopicReadStateChanged(state);
      });
    }
    if (!this.unsubscribeNotifications) {
      // 先取当前已知值(避免首帧空窗),再订阅后续变化。
      this.unreadNotifications = NotificationEventBus.current().unread;
      this.unsubscribeNotifications = NotificationEventBus.subscribe((snapshot: NotificationSnapshot) => {
        this.unreadNotifications = snapshot.unread;
      });
    }
    if (!this.unsubscribeMessageBus) {
      this.unsubscribeMessageBus = MessageBusEventBus.subscribe((event: MessageBusEvent) => {
        this.handleMessageBusEvent(event);
      });
    }
    this.refreshDrawerPrefs();
    this.syncSessionVersion();
    if (this.isArkWebReady && this.topics.length === 0) {
      this.loadSiteMetadataIfNeeded();
      this.refreshLatestTopics();
    }
    this.checkVersionAnnouncement();
  }

  private onSmartReachSideChanged(): void {
    this.getUIContext().animateTo({
      duration: SMART_REACH_ANIMATION_DURATION,
      curve: Curve.EaseInOut
    }, () => {
      this.fabAlignRules = smartReachBottomAlignRules(this.smartReachLeftHanded);
    });
  }

  aboutToDisappear(): void {
    this.incomingInsertEpoch++;
    if (this.incomingInsertTimerId >= 0) {
      clearTimeout(this.incomingInsertTimerId);
      this.incomingInsertTimerId = -1;
    }
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
    if (this.unsubscribeTopicReadState) {
      this.unsubscribeTopicReadState();
      this.unsubscribeTopicReadState = undefined;
    }
    if (this.unsubscribeNotifications) {
      this.unsubscribeNotifications();
      this.unsubscribeNotifications = undefined;
    }
    if (this.unsubscribeMessageBus) {
      this.unsubscribeMessageBus();
      this.unsubscribeMessageBus = undefined;
    }
  }

  // 按当前滚动偏移决定右下角按钮的身份。滞回:滑过 1.5 屏才换成回顶,退回 1.2 屏内才变回发帖。
  private updateFabMode(): void {
    if (this.listViewportH <= 0) {
      return;
    }
    const y: number = this.listScroller.currentOffset().yOffset;
    if (!this.showBackToTopFab && y > this.listViewportH * FAB_TOP_SHOW_RATIO) {
      this.showBackToTopFab = true;
    } else if (this.showBackToTopFab && y < this.listViewportH * FAB_TOP_HIDE_RATIO) {
      this.showBackToTopFab = false;
    }
  }

  // 回到顶部。两难:列表可能已翻几十页,真把几万 vp 滚完既慢又晕;直接跳又太生硬——
  // 人眼没有位移可跟,只看到画面瞬变。故两段式:先无动画瞬移到离顶一屏的"起跑线"
  // (这段本来滚起来也只是一片糊,看不清等于没损失),再把最后一屏用动画滑完,
  // 给出一个跟得住的"到站"过程。观感上花的是一屏的钱,买的是全程动画的感觉。
  private scrollToTop(): void {
    // 立刻换回发帖态:morph 与这段滚动同时进行,按钮和列表一起"到站"。
    this.showBackToTopFab = false;
    const runway: number = this.listViewportH;
    if (runway <= 0) {
      // 视口没量到就别耍花活,老老实实到顶。
      this.listScroller.scrollEdge(Edge.Top);
      return;
    }
    if (this.listScroller.currentOffset().yOffset <= runway) {
      // 本来就在一屏内,直接动画滑完。
      this.animateScrollToTop();
      return;
    }
    this.teleportThenAnimate(runway, 0);
  }

  // 瞬移到起跑线,并在下一帧确认它真的落地了再起动画。
  // 之所以要"确认":点击时列表可能还在惯性滑行,惯性会把瞬移顶回去,
  // 动画段于是又从几万 vp 外起跑——这正是回顶时灵时不灵的来源。
  // 首页改为 LazyForEach 后,长距离按绝对 yOffset 跳转会触发懒列表估算/补建大量中间项；
  // 改按 index 直接跳到首个帖子项,再动画补完顶部 spacer,成本稳定。
  private teleportThenAnimate(runway: number, attempt: number): void {
    this.listScroller.scrollToIndex(1, false);
    this.getUIContext().postFrameCallback(new NextFrameTask(() => {
      // 1vp 容差:像素取整/浮点误差,不必较真。
      if (this.listScroller.currentOffset().yOffset <= runway + 1) {
        this.animateScrollToTop();
        return;
      }
      if (attempt + 1 < SCROLL_TOP_MAX_RETRY) {
        this.teleportThenAnimate(runway, attempt + 1);
      } else {
        // 惯性太顽固,放弃动画:生硬到顶也好过卡在半路。
        this.listScroller.scrollEdge(Edge.Top);
      }
    }));
  }

  private animateScrollToTop(): void {
    this.listScroller.scrollTo({
      xOffset: 0,
      yOffset: 0,
      animation: { duration: SCROLL_TOP_MS, curve: Curve.EaseOut }
    });
  }

  private openComposer(): void {
    // 未登录先拦:LoginGate 弹登录页,登录后用户再自行点发帖(不自动续开,避免登录流程里突兀弹编辑器)。
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    AppStorage.setOrCreate(HOME_COMPOSER_VISIBLE_KEY, true);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showComposer = true;
    });
  }

  private closeComposer(): void {
    AppStorage.setOrCreate(HOME_COMPOSER_VISIBLE_KEY, false);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showComposer = false;
    });
  }

  // 系统返回键(Index.onBackPress 在浮层可见时 bump tick):浮层开着就关。
  private onComposerBackTick(): void {
    if (this.showComposer) {
      this.closeComposer();
    }
  }

  // 发新主题:POST /posts。成功后跳进新帖详情;进审核队列则只提示。返回 true 令浮层关闭。
  private async submitNewTopic(title: string, categoryId: number, raw: string, tags: string[], typingMs: number, composerMs: number): Promise<boolean> {
    return submitNewTopic(
      this.bridge,
      (message: string, duration: number) => promptToast(this.getUIContext(), message, duration),
      title, categoryId, raw, tags, typingMs, composerMs,
      (topicId: number) => this.onOpenTopicById(topicId));
  }

  // 手指位移(向左为负)换算成 0~1 进度,夹在区间内。
  private swipeProgressOf(offsetX: number): number {
    if (this.swipeAreaWidth <= 0) {
      return 0;
    }
    return clampUnit(-offsetX / this.swipeAreaWidth);
  }

  build() {
    // 自绘抽屉:Stack 底层为主体,上层为遮罩 + 侧边抽屉(靠 translate 滑入/滑出)。
    // 不用 SideBarContainer——其 overlay 遮罩不拦截点击、内滚也不灵。
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        this.HomeMainContent()
      }
      .titleBar({
        avoidLayoutSafeArea: requiresHdsLayoutSafeAreaAvoidance(ImmersiveLightArea.TITLE_BAR),
        enableComponentSafeArea: requiresHdsComponentSafeArea(ImmersiveLightArea.TITLE_BAR),
        style: buildImmersiveTitleBarStyle({ enableRefreshOffsetChange: true }),
        content: {
          stackBuilder: () => {
            this.HomeTitleBarContent();
          }
        }
      })
      .bindToScrollable([this.listScroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'))

      // 遮罩:抽屉在场时铺满,拦截并点击关闭,防止点穿到帖子列表。
      // 挂载条件跟抽屉内容同一个闸(drawerMounted)而非 showSideBar:边缘拖拽期间抽屉只出来一半,
      // 遮罩得同步跟着浓起来;浓度直接绑 drawerProgress,跟手与开合动画共用同一个源。
      if (this.drawerMounted) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(SCRIM)
          .opacity(this.drawerProgress)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onClick(() => {
            this.closeDrawer();
          })
      }

      // 侧边抽屉。外壳常驻、内容按需挂载:
      //  · 外壳(这个 Column)一直在,承载宽度/位移/拖拽手势。滑入滑出动画作用在它身上,
      //    所以 animateTo 永远拿得到动画起点——若把带 translate 的节点本身做成条件渲染,
      //    挂载与翻转 showSideBar 落在同一帧,动画起点缺失,抽屉会直接闪现在最终位置。
      //  · 内容(CategoryDrawer)只在抽屉真正用到时才挂:它内部是 Scroll + 四层嵌套 ForEach
      //    (入口/站点/顶级版块/子版块),全量构建无回收,几十个节点。常驻的话每次返回首页的
      //    转场里这些节点都要参与绘制,而转场期间两个页面同屏、每帧预算本来就紧张。
      //    挂载与卸载都发生在外壳位于屏幕左外(translate=-DRAWER_WIDTH)时,看不到内容突现/突消。
      Column() {
        if (this.drawerMounted) {
          CategoryDrawer({
            bridge: this.bridge,
            isArkWebReady: this.isArkWebReady,
            categories: this.categories,
            isLoggedIn: this.isLoggedIn,
            sitesEntryEnabled: this.sitesEntryEnabled,
            sites: this.drawerSites,
            // 草稿与生效值都提到本页持有:抽屉内容按需卸载后,编辑中的选择不能跟着一起丢。
            draft: this.draftQuery,
            applied: this.listQuery,
            expandedIds: this.drawerExpandedIds,
            onToggleExpand: (categoryId: number) => {
              this.handleDrawerToggleExpand(categoryId);
            },
            onDraftChange: (next: TopicListQuery) => {
              this.draftQuery = next;
            },
            onApply: () => {
              this.handleApplyDraftQuery();
            },
            onClose: () => {
              this.closeDrawer();
            },
            onNotice: (message: string) => {
              this.showToast(message);
            },
            onRequireLogin: () => {
              this.handleDrawerRequireLogin();
            },
            onOpenSites: () => {
              this.closeDrawer();
              this.onOpenSites();
            },
            onOpenSite: (url: string, title: string, siteId: string) => {
              this.closeDrawer();
              this.onOpenSite(url, title, siteId);
            }
          })
        }
      }
      .width(DRAWER_WIDTH)
      .height('100%')
      // 进度 0 时整体在屏幕左外,1 时贴左边缘归位;中间值即跟手位置。
      .translate({ x: (this.drawerProgress - 1) * DRAWER_WIDTH })
      .gesture(
        // 横向拖:向左拖动抽屉,过阈值即关闭,否则弹回。仅横向,不干扰内部竖向滚动。
        // 这条只管「已展开后往回推」:边缘拉出走的是主体那条 pan(起手时抽屉还在屏外,命中不到这里)。
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionUpdate((event: GestureEvent) => {
            if (this.showSideBar) {
              this.drawerProgress = clampUnit(1 + event.offsetX / DRAWER_WIDTH);
            }
          })
          .onActionEnd((event: GestureEvent) => {
            this.handleDrawerPanEnd(event.velocityX);
          })
          .onActionCancel(() => {
            // 被系统打断:按零速松手处理(照阈值判开/关),别把抽屉卡在半开。
            this.handleDrawerPanEnd(0);
          })
      )

      // 发帖浮层:挂在根 Stack 最顶层,盖住顶栏/列表/抽屉。不进 Navigation 栈,返回键由 Index 拦截。
      // 淡入淡出(无一镜到底源可配对——首页没有内联输入条,不像详情页从回复条生长)。
      if (this.showComposer) {
        ComposerPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          headerTitle: '发帖',
          placeholder: '正文（支持 Markdown）',
          minChars: 1,
          composeTopic: true,
          categories: this.categories,
          onBack: () => {
            this.closeComposer();
          },
          onSubmitTopic: (title: string, categoryId: number, raw: string, tags: string[], typingMs: number, composerMs: number): Promise<boolean> => {
            return this.submitNewTopic(title, categoryId, raw, tags, typingMs, composerMs);
          }
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet(this.announceVisible, this.AnnouncementSheet(), {
      height: SheetSize.FIT_CONTENT,
      // 顶部拖拽条:下滑即可关闭弹层(内容可滚动时也不冲突,拖拽条是独立手柄)。
      dragBar: true,
      showClose: true,
      onDisappear: () => {
        this.announceVisible = false;
      }
    })
  }

  @Builder
  private HomeMainContent() {
    // BottomEnd 供右下角悬浮按钮定位;Refresh 与空态列都是 100%×100%,不受对齐方式影响。
    Stack({ alignContent: Alignment.BottomEnd }) {
      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List({ scroller: this.listScroller }) {
          ListItem() {
            Column() {
              Blank()
                .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))
            }
            .width('100%')
          }

          ListItem() {
            this.IncomingTopicsPrompt()
          }
          .height(this.incomingPromptHeight)
          .opacity(this.incomingPromptOpacity)
          .clip(true)

          LazyForEach(this.topicDataSource, (topic: Topic) => {
            TopicListItem({
              topic: topic,
              category: CategoryIndex.find(this.categories, topic.categoryId),
              parentCategory: CategoryIndex.findParent(this.categories, topic.categoryId),
              contentHorizontalPadding: 12,
              incomingHighlightUntil: this.incomingTopicHighlightDeadline(topic.id),
              incomingInsertProgress: this.incomingInsertProgress,
              incomingInsertDistance: this.incomingInsertActive &&
                this.incomingInsertingTopicIds.indexOf(topic.id) < 0 ? this.incomingInsertRevealDistance : 0,
              incomingInsertFadeIn: this.incomingInsertActive &&
                this.incomingInsertingTopicIds.indexOf(topic.id) >= 0,
              onIncomingInsertMeasured: (topicId: number, height: number) => {
                this.handleIncomingInsertMeasured(topicId, height);
              },
              badgesTappable: this.badgeFilterEnabled,
              onTagClick: (tag: TopicTag) => {
                this.handleTagClick(tag);
              },
              onCategoryClick: (category: TopicCategory) => {
                this.handleCategoryClick(category);
              },
              onTopicClick: (selectedTopic: Topic) => {
                // 点击即清除蓝点(乐观已读);未读徽标待返回时由详情页结算的真实未读数同步。
                selectedTopic.unseen = false;
                this.onTopicClick(selectedTopic);
              },
              onUnreadBadgeClick: (selectedTopic: Topic) => {
                this.handleUnreadBadgeClick(selectedTopic);
              }
            })
            // 完整刷新会 new 一批 Topic，版本入 key 后强制重绑 @ObjectLink；同实例上的收藏变化仍靠
            // bookmarked 重建，已读状态则继续走 @Observed 精准更新，不必重建整行。
          }, (topic: Topic) =>
            `${this.topicListVersion}_${topic.id}_${topic.bookmarked === true ? 1 : 0}_` +
              `${this.incomingTopicRenderToken(topic.id)}`)

          if (this.topics.length > 0) {
            ListItem() {
              Row() {
                if (this.isLoadingMore) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color($r('app.color.brand'))
                    .margin({ right: 8 })
                }

                Text(this.footerMessage)
                  .fontSize(13)
                  .fontColor(this.requiresChallenge ? $r('app.color.warning') : $r('app.color.text_secondary'))
              }
              .width('100%')
              .height(54)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width('100%')
        .height(`calc(100% + ${immersiveTitleBarContentTopSpacer(this.sysTopInset)}vp)`)
        .position({ x: 0, y: -immersiveTitleBarContentTopSpacer(this.sysTopInset) })
        .clip(false)
        .scrollBar(BarState.Off)
        .enableScrollInteraction(!this.incomingInsertActive)
        .padding({ bottom: 0 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onReachEnd(() => {
          this.loadMoreTopics();
        })
        .onDidScroll(() => {
          this.updateFabMode();
        })
      }
      .width('100%')
      .height('100%')
      .clip(false)
      // Refresh 会把子 List 裁剪到自身边界;List 与 Refresh 都放开裁剪后内容才能进入标题栏下方。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .pullToRefresh(true)
      .refreshOffset(64)
      .onRefreshing(() => {
        this.handleManualRefresh();
      })

      ScrollBar({
        scroller: this.listScroller,
        direction: ScrollBarDirection.Vertical,
        state: BarState.Auto
      })
        .height(`calc(100% - ${HDS_TITLE_BAR_MASK_EXTRA_HEIGHT}vp)`)
        .margin({ top: HDS_TITLE_BAR_MASK_EXTRA_HEIGHT })
        .align(Alignment.TopEnd)

      if (this.topics.length === 0) {
        Column() {
          // 门卫看「桥能否真发请求」而非 UI 解锁标志:看门狗/失败路径会把 isArkWebReady 置真但 executor
          // 仍为空,那一刻发请求必被跳过。冷启动空窗统一显示品牌化「准备环境中」加载态,等宿主真就绪
          // (hostReadyEpoch)再进 LoadStateView——此时要么已有数据、要么是真失败(CF/服务端)给重试,
          // 从而不再硬闪「加载失败」。
          if (!this.bridge.canFetch()) {
            Image($r('app.media.linuxdo_logo'))
              .width(64)
              .height(64)
              .margin({ bottom: 16 })

            Text('准备环境中...')
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
          } else {
            // 加载/失败/CF 挑战三态统一走共享组件:挑战态由组件接管全局恢复状态,
            // 静默过验中转圈、数秒后放出"手动验证",终态直接给手动入口。二级页复用同一份,不再各写一套。
            LoadStateView({
              isLoading: this.isInitialLoading,
              message: this.listMessage,
              requiresChallenge: this.requiresChallenge,
              showRetry: this.loadFailed && !this.isInitialLoading,
              onRetry: () => {
                this.refreshLatestTopics();
              }
            })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 悬浮按钮:发帖 / 回到顶部同占一个坑位,按滚动位置换身份(详见 HomeFab)。
      // 列表为空时(加载中/失败/CF 挑战)不出现——既无从回顶,空态下也不该冒出主动作。
      if (this.topics.length > 0) {
        RelativeContainer() {
          Row() {
            this.HomeFloatingButton()
          }
            .id('smartReachHomeFabCluster')
            .alignRules(this.fabAlignRules)
            .margin({ left: 16, right: 16, bottom: 16 + this.sysBottomInset })
            .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
        // 覆盖层空白区域继续把列表滚动手势传下去，只有按钮本身响应点击。
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 同时记录列表视口和手势宽度,避免同一组件挂两个 onAreaChange 时后者覆盖前者。
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.listViewportH = Number(newArea.height);
      this.swipeAreaWidth = newArea.width as number;
    })
    // 记录每次按下的横坐标。判「是不是从左边缘起手」只能靠按下点,而手势回调里拿不到可靠的按下点:
    // PanGesture 的 onActionStart 已经是走完识别阈值之后,fingerList 也不保证有值。onTouch 的
    // Down 事件则必定带着触点、且拿到的就是真正的按下位置,不用拿位移反推。
    // 与主体这条 pan 挂在同一个节点上,坐标系天然一致(根 Stack 铺满窗口,windowX 即本地 X)。
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && event.touches.length > 0) {
        this.touchDownX = event.touches[0].windowX;
      }
    })
    // 主体上的横向跟手手势,一条 pan 兼管两个方向:
    //   · 向左  → 拉出个人中心(位移换算成 0~1 进度上抛,由宿主驱动 Navigation 的交互式转场)
    //   · 按下点落在左边缘、向右 → 拉出版块抽屉(本页自绘,进度直接驱动 drawerProgress)
    // 两件事合在一条 pan 上,而不是给抽屉单挂一条:识别器落在哪个节点上能被派发到,是要碰运气的
    // (给边缘窄条单挂一条 PanGesture 实测就没被识别,右滑无人接管,反而漏成了点开帖子);
    // 而这条 pan 挂在主体根节点上、左滑拉个人中心一直好用,是已经验证过能收到横向拖动的位置。
    // 方向归属在起手时一锤定音,后续 update/end 照它走,中途不改判。起手 10vp 才认,与 List 的
    // 竖向滚动靠方向隔离。
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
        .onActionStart((event: GestureEvent) => {
          this.swipeTracking = false;
          this.drawerSwiping = false;
          // 抽屉开着/正拉出时不归这里(往回推是抽屉自己那条 pan 的事),发帖浮层盖着时同理,不抢。
          if (this.showSideBar || this.drawerMounted || this.showComposer || this.swipeAreaWidth <= 0) {
            return;
          }
          if (event.offsetX < 0) {
            this.swipeTracking = true;
            this.onProfileSwipeStart();
            return;
          }
          if (this.isEdgeTouchDown()) {
            this.drawerSwiping = true;
            // 内容先挂上(此刻抽屉整体还在屏外,看不见),之后每帧直接改 drawerProgress 跟手。
            this.prepareDrawerContent();
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.swipeTracking) {
            this.onProfileSwipeUpdate(this.swipeProgressOf(event.offsetX));
          } else if (this.drawerSwiping) {
            this.drawerProgress = clampUnit(event.offsetX / DRAWER_WIDTH);
          }
        })
        .onActionEnd((event: GestureEvent) => {
          if (this.swipeTracking) {
            this.swipeTracking = false;
            // velocityX 向左为负,取反换成「向左甩得多快」。
            this.onProfileSwipeEnd(this.swipeProgressOf(event.offsetX), -event.velocityX);
          } else if (this.drawerSwiping) {
            this.drawerSwiping = false;
            this.endDrawerSwipe(event.velocityX);
          }
        })
        .onActionCancel(() => {
          // 手势被系统打断:两边都当回弹处理,别把转场/抽屉悬在半路。
          if (this.swipeTracking) {
            this.swipeTracking = false;
            this.onProfileSwipeEnd(0, 0);
          } else if (this.drawerSwiping) {
            this.drawerSwiping = false;
            this.settleDrawer(false);
          }
        })
    )
  }

  // 按下点是否落在左边缘起手区。用 onTouch 记下的真实按下点,不拿手势位移反推——
  // 反推(当前位置 - 累计位移)会算出负数,判定恒假,抽屉永远拉不出来。
  private isEdgeTouchDown(): boolean {
    return this.touchDownX >= 0 && this.touchDownX <= DRAWER_EDGE_WIDTH;
  }

  @Builder
  private HomeFloatingButton() {
    HomeFab({
      showBackToTop: this.showBackToTopFab,
      onCompose: () => {
        this.openComposer();
      },
      onBackToTop: () => {
        this.scrollToTop();
      }
    })
      .id('smartReachHomeFab')
  }

  @Builder
  private IncomingTopicsPrompt() {
    if (shouldShowIncomingTopicsPrompt(this.incomingTopicsPromptCount())) {
      HomeIncomingTopicsPrompt({
        count: this.incomingTopicsPromptCount(),
        loading: this.isLoadingIncoming || this.pendingIncomingRefresh,
        onPromptClick: () => {
          this.handleIncomingTopicsPromptClick();
        }
      })
    }
  }

  private incomingTopicsPromptCount(): number {
    return homeIncomingTopicsCount(this.incomingTopicsState);
  }

  @Builder
  private HomeTitleBarContent() {
    Row() {
      // 环境未就绪("准备环境中...")时抽屉尚无意义,隐藏汉堡入口(标题左移填满,就绪后再出现)。
      if (this.isArkWebReady) {
        this.MenuButton()
      }

      this.FeedTitle()

      // 搜索入口:环境就绪后常驻(搜索匿名可用,不随登录态隐藏)。
      if (this.isArkWebReady) {
        this.SearchButton()
      }

      // 仅在会话已确认且已登录时显示铃铛(未登录/未确认不出现)。
      if (this.hasCheckedSession && this.isLoggedIn) {
        NotificationBell({
          unreadCount: this.unreadNotifications,
          onBellClick: () => {
            // 打开通知页(进页会发 recent=true 让服务端 bump seen);本地先乐观清零红点。
            this.unreadNotifications = 0;
            this.onOpenNotifications();
          }
        })
      }

      this.AccountEntry()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 版本公告弹层:标题 + 命中回复的完整富文本正文(含 [vXXXX] 版本号,超长可滚动)。
  @Builder
  private AnnouncementSheet() {
    Column() {
      Text('本次更新')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 16 })

      Scroll() {
        Column() {
          PostRichContent({
            cookedHtml: this.announceCooked,
            fallbackText: '',
            polls: []
          })
            .width('100%')
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      // 内容滚到顶再下拉时把手势交还弹层,让「按住内容区域下滑」也能关闭(否则 Scroll 独吞垂直手势)。
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 24 })
  }

  // 顶栏标题区。全默认(全站 · 最新 · 不限标签)时与改造前完全一致——单行大标题,「ArkDO」末尾的 O
  // 换成 linux.do 三色圆 logo(内联 ImageSpan 保持基线对齐;logo 为固定色 SVG,深色模式下不翻转以保留品牌配色)。
  //
  // 一旦有筛选条件就长出第二行条件摘要,主标题相应收一号(26 → 19),两行合计仍落在 MINI 顶栏高度内。
  // 默认态零视觉负担、有条件时才占位,这样"清爽"和"看得见当前在筛什么"才能同时成立。
  @Builder
  private FeedTitle() {
    Column({ space: 1 }) {
      if (isDefaultTopicListQuery(this.listQuery)) {
        Text() {
          Span(AppConstants.APP_NAME.slice(0, -1))
          ImageSpan($r('app.media.linuxdo_logo'))
            .width(24)
            .height(24)
            .verticalAlign(ImageSpanAlignment.CENTER)
            .margin({ bottom: 2 })
        }
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      } else {
        Row() {
          this.QueryTitleIcon()
          Text(this.currentFeedTitle())
            // 版块名可以很长(「积分乐园, Lv1」这种带后缀的),而顶栏右边还站着搜索/铃铛/头像,
            // 留给标题的宽度本就不多。宁可自适应缩字号也别直接截成「积分乐园, …」——
            // 截断丢的是尾部的区分信息(Lv1),缩字号只是小一点,还认得出是哪个版块。
            // MAX_LINES_FIRST = 优先保住 maxLines(1),为此可以一路缩到 minFontSize。
            .fontSize(this.titleMaxFontSize())
            .minFontSize(this.titleMinFontSize())
            .maxFontSize(this.titleMaxFontSize())
            .heightAdaptivePolicy(TextHeightAdaptivePolicy.MAX_LINES_FIRST)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (hasTopicListSummary(this.listQuery)) {
          this.QuerySummaryRow()
        }
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
  }

  // 主标题的前导图标:与帖子卡片上的徽章同一套视觉——版块走「专属图标 → 上传 logo → 兜底色点」,
  // 标签走「专属图标 → 通用小标签图标」。只按过滤器筛(未读/热门)时没有可画的东西,整个图标位不占。
  @Builder
  private QueryTitleIcon() {
    if (this.listQuery.category !== undefined) {
      Row() {
        if (this.titleCategoryIcon() !== undefined) {
          FaIconView({
            icon: this.titleCategoryIcon() as FaIconDefinition,
            color: getCategoryColor(this.listQuery.category as TopicCategory),
            iconSize: this.titleIconSize()
          })
        } else if (this.titleCategoryLogo().length > 0) {
          Image(resolveBadgeAssetUrl(this.titleCategoryLogo()))
            .width(this.titleIconSize())
            .height(this.titleIconSize())
            .objectFit(ImageFit.Contain)
        } else {
          Circle()
            .width(this.titleIconSize() - 5)
            .height(this.titleIconSize() - 5)
            .fill(getCategoryColor(this.listQuery.category as TopicCategory))
        }
      }
      .width(this.titleIconSize() + 5)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 7 })
    } else if (this.listQuery.tag !== undefined) {
      Row() {
        FaIconView({
          icon: this.tagIcon((this.listQuery.tag as TopicTag).name),
          color: getTagColor((this.listQuery.tag as TopicTag).name),
          iconSize: this.titleIconSize() - 1
        })
      }
      .width(this.titleIconSize() + 5)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 7 })
    }
  }

  // 前导图标不随副行有无变化:标题字号只差两号,图标跟着跳反而显得晃。
  private titleIconSize(): number {
    return TITLE_ICON_SIZE;
  }

  private titleMaxFontSize(): number {
    return hasTopicListSummary(this.listQuery) ? TITLE_WITH_SUMMARY_MAX_FONT_SIZE : TITLE_MAX_FONT_SIZE;
  }

  private titleMinFontSize(): number {
    return hasTopicListSummary(this.listQuery) ? TITLE_WITH_SUMMARY_MIN_FONT_SIZE : TITLE_MIN_FONT_SIZE;
  }

  // 副行的一枚小胶囊。@Builder 的参数必须打包成单个对象:多个/基本类型参数是按值传递,
  // 捕获一次就不再重算,条件变了胶囊不会跟着刷新。
  @Builder
  private QueryChip(p: QueryChipParams) {
    Row({ space: 4 }) {
      if (p.icon !== undefined) {
        FaIconView({
          icon: p.icon as FaIconDefinition,
          color: p.iconColor.length > 0 ? p.iconColor : $r('app.color.text_secondary'),
          iconSize: SUMMARY_CHIP_ICON_SIZE
        })
      }
      Text(p.label)
        .fontSize(SUMMARY_FONT_SIZE)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(SUMMARY_CHIP_HEIGHT)
    // 带图标时左内边距收一点:图标本身已经贡献了视觉留白。
    .padding({ left: p.icon !== undefined ? 6 : 8, right: 8 })
    .constraintSize({ maxWidth: '60%' })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(SUMMARY_CHIP_HEIGHT / 2)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 副行:主标题下面那一行,每个条件各占一枚小胶囊。
   *
   * 做成胶囊而不是裸文字,是因为「未读」这种两个字的副标题裸着挂在标题下面会显得是"没写完";
   * 套上边界之后同样的内容读起来就是"这一行有一枚标记",观感完全不同。顺带还有两个好处:
   * 胶囊边界自己就是分隔,不再需要那个中点;以后要加第四个维度,多一枚胶囊即可。
   *
   * 点整行回抽屉接着改(省得去够左上角的汉堡)。胶囊本身暂不单独响应——
   * 「点某一枚只改那一维」是个合理期待,但那要先想清楚点了是清空还是进对应 Tab,留到后面再说。
   */
  @Builder
  private QuerySummaryRow() {
    Row({ space: 6 }) {
      if (topicListSummaryLead(this.listQuery).length > 0) {
        this.QueryChip({
          label: topicListSummaryLead(this.listQuery),
          icon: undefined,
          iconColor: ''
        })
      }

      if (topicListSummaryTag(this.listQuery) !== undefined) {
        this.QueryChip({
          label: (topicListSummaryTag(this.listQuery) as TopicTag).name,
          icon: this.tagIcon((topicListSummaryTag(this.listQuery) as TopicTag).name),
          iconColor: this.tagIconColor((topicListSummaryTag(this.listQuery) as TopicTag).name)
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openDrawer();
    })
  }

  // 版块图标要带上父版块做兜底(子版块自己常常没图标,得回退到父版块那一套)。
  private titleCategoryIcon(): FaIconDefinition | undefined {
    const category: TopicCategory | undefined = this.listQuery.category;
    if (category === undefined) {
      return undefined;
    }
    return getCategoryIcon(category, CategoryIndex.findParent(this.categories, category.id));
  }

  private titleCategoryLogo(): string {
    const category: TopicCategory | undefined = this.listQuery.category;
    if (category === undefined) {
      return '';
    }
    return getCategoryLogo(category, CategoryIndex.findParent(this.categories, category.id));
  }

  // 没有专属图标时回空串,让通用小标签图标跟着胶囊的文字色走——固定的灰在深色模式下会比文字暗一档。
  private tagIconColor(name: string): string {
    return getTagIcon(name) !== undefined ? getTagColor(name) : '';
  }

  // 没登记过专属图标的标签退回通用小标签图标,图标位始终有东西,标题不会一会儿缩进一会儿不缩。
  private tagIcon(name: string): FaIconDefinition {
    const own: FaIconDefinition | undefined = getTagIcon(name);
    if (own !== undefined) {
      return own;
    }
    const fallback: FaIconDefinition | undefined = getFaIcon('tag');
    return fallback ? fallback : { id: 'tag', rawfilePath: 'fa_icons/tag.svg' };
  }

  // 左上角汉堡入口:打开版块抽屉(三条发丝线,无需依赖 sys.symbol 资源)。
  @Builder
  private MenuButton() {
    Button() {
      Column({ space: 4 }) {
        Divider().width(18).strokeWidth(2).color($r('app.color.text_primary'))
        Divider().width(18).strokeWidth(2).color($r('app.color.text_primary'))
        Divider().width(18).strokeWidth(2).color($r('app.color.text_primary'))
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(42)
    .height(42)
    .borderRadius(21)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .margin({ right: 10 })
    .onClick(() => {
      this.openDrawer();
    })
  }

  // 顶栏搜索入口:放大镜图标,点击一镜到底打开 SearchFlow 根覆盖层。
  // SearchFlow 可见时把源图标 if 掉(几何交给搜索页前导图标),二者同 geometryTransition id、由同一 animateTo 驱动插值。
  @Builder
  private SearchButton() {
    Button() {
      if (!this.searchOverlayVisible) {
        FaIconView({ icon: this.searchIcon(), color: $r('app.color.text_primary'), iconSize: 20 })
          .geometryTransition(SEARCH_ICON_GEOMETRY_ID, { follow: true })
          .transition(TransitionEffect.OPACITY)
      }
    }
    .width(42)
    .height(42)
    .borderRadius(21)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .margin({ right: 4 })
    .onClick(() => {
      this.onOpenSearch();
    })
  }

  private searchIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('magnifying-glass');
    return def ? def : { id: 'magnifying-glass', rawfilePath: 'fa_icons/magnifying-glass.svg' };
  }

  private jumpToTopic(topicId: number): void {
    Log.i(`${LOG_TAG} debug jump to topic topicId=${topicId}`);
    this.onOpenTopicById(topicId);
  }

  // 入口无条件可点:环境未就绪/会话检查中只换图标,不禁用也不留空白。
  // 网络不通时这里是够到 DoH 配置的唯一通路,一旦拦下用户就被关在门外只能干等超时。
  @Builder
  private AccountEntry() {
    Button() {
      Stack() {
        if (this.isCheckingSession) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color($r('app.color.brand'))
        } else if (this.isLoggedIn) {
          UserAvatar({
            user: this.accountUser,
            avatarSize: 34
          })
        } else {
          SymbolGlyph($r('sys.symbol.person'))
            .fontSize(28)
            .fontColor([$r('app.color.brand')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
      }
      .width(38)
      .height(38)
      .alignContent(Alignment.Center)
    }
    .width(42)
    .height(42)
    .borderRadius(21)
    .backgroundColor(Color.Transparent)
    .padding(0)
    // 放行溢出:头像光圈会扩散到 42 之外,默认圆角裁剪会切掉,需关闭裁剪。
    .clip(false)
    .onClick(() => {
      this.onAccountClick();
    })
    // 长按头像:弹出输入框填帖子 ID,直接跳转到指定帖子详情。
    // Button 自带点击识别器会抢占触摸,须用 priorityGesture 让长按优先于内置手势。
    .priorityGesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.jumpDialogController.open();
        })
    )
  }

  // 打开抽屉前刷新一次抽屉配置(设置页/站点管理页可能刚改过),挂载内容,带滑入动画。
  private openDrawer(): void {
    this.prepareDrawerContent();
    this.animateDrawer(true);
  }

  // 抽屉登场前的准备:重读配置 + 草稿对齐当前条件 + 同步展开态 + 挂载内容。点汉堡和边缘拖拽共用。
  // 内容此刻还在屏幕左外(drawerProgress 仍为 0),挂载过程看不见。
  private prepareDrawerContent(): void {
    this.refreshDrawerPrefs();
    // 每次开抽屉都从生效条件重新拷一份草稿:上次没点确认就滑走的那些改动就此丢弃(等同「取消」)。
    this.draftQuery = cloneTopicListQuery(this.listQuery);
    this.syncDrawerAutoExpand();
    this.drawerProgress = 0;
    this.drawerMounted = true;
  }

  // 左边缘右滑松手:拉出过阈值、或向右甩得够快,就补完展开;否则滑回屏外收场。
  private endDrawerSwipe(velocityX: number): void {
    const commit: boolean = this.drawerProgress >= DRAWER_COMMIT_RATIO || velocityX >= DRAWER_COMMIT_VELOCITY;
    this.settleDrawer(commit);
  }

  // 跟手结束后的收尾:把进度补到 0 或 1。补完/回弹各用一套时长,曲线同个人中心那套。
  private settleDrawer(open: boolean): void {
    this.animateDrawer(open, open ? DRAWER_COMMIT_MS : DRAWER_REBOUND_MS, DRAWER_SETTLE_CURVE);
  }

  // 若当前看的是某个子版块,自动展开它的父版块,让选中项在树里可见。
  // 原先写在 CategoryDrawer.aboutToAppear 里,而抽屉是随首页一起构建的、那时还没有任何选中版块,
  // 等于从没生效过;改为按需挂载后放在这里,每次开抽屉判定一次,才真正起到"让选中项可见"的作用。
  private syncDrawerAutoExpand(): void {
    const selected: TopicCategory | undefined = this.listQuery.category;
    if (!selected || selected.parentCategoryId === undefined) {
      return;
    }
    const parentId: number = selected.parentCategoryId;
    if (this.drawerExpandedIds.indexOf(parentId) >= 0) {
      return;
    }
    const next: number[] = this.drawerExpandedIds.slice();
    next.push(parentId);
    this.drawerExpandedIds = next;
  }

  // 抽屉里点展开箭头:展开态由本页持有,这里做增删。
  private handleDrawerToggleExpand(categoryId: number): void {
    const next: number[] = this.drawerExpandedIds.slice();
    const index: number = next.indexOf(categoryId);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(categoryId);
    }
    this.drawerExpandedIds = next;
  }

  // 抽屉配置统一重读:站点入口开关 + 要展示的站点。
  // 子页改完 pop 回来不会重建本页,靠每次开抽屉重读 preferences 拿最新值(无需 AppStorage tick)。
  private refreshDrawerPrefs(): void {
    this.sitesEntryEnabled = SitePrefs.isEntryEnabled(getContext(this));
    this.drawerSites = SitePrefs.drawerSites(getContext(this));
  }

  private closeDrawer(): void {
    this.animateDrawer(false);
  }

  // 抽屉开合动画:在 animateTo 里把 drawerProgress 推到 0/1,抽屉平移、遮罩浓淡都跟着走;
  // showSideBar 同步翻转,供遮罩点击、主体手势闸判定「抽屉是否已展开」。
  // 关闭动画播完才卸载抽屉内容——否则内容会在滑出途中凭空消失。onFinish 里以当时的 showSideBar
  // 为准而非捕获的 show:关闭动画未播完就被重新打开时,不能把刚挂上的内容又卸掉。
  private animateDrawer(show: boolean, duration: number = 220, curve: Curve = Curve.EaseOut): void {
    this.getUIContext().animateTo({
      duration: duration,
      curve: curve,
      onFinish: () => {
        if (!this.showSideBar) {
          this.drawerMounted = false;
        }
      }
    }, () => {
      this.showSideBar = show;
      this.drawerProgress = show ? 1 : 0;
    });
  }

  // 展开后往回推的松手判定:推回过阈值、或向左甩得够快则关闭,否则弹回展开态。
  private handleDrawerPanEnd(velocityX: number): void {
    if (!this.showSideBar) {
      return;
    }
    if (this.drawerProgress <= 1 - DRAWER_COMMIT_RATIO || velocityX <= -DRAWER_COMMIT_VELOCITY) {
      this.settleDrawer(false);
      return;
    }
    this.settleDrawer(true);
  }

  // 抽屉点「查看结果」:提交草稿、关抽屉、整列重载。与当前条件无差异时抽屉侧就不会走到这里。
  private handleApplyDraftQuery(): void {
    this.closeDrawer();
    if (sameTopicListQuery(this.draftQuery, this.listQuery)) {
      return;
    }
    this.listQuery = cloneTopicListQuery(this.draftQuery);
    this.resetAndReload();
  }

  /**
   * 点帖子行上的分类/标签徽章 = 把它加进当前条件,等同于在抽屉里选中它再点「查看结果」。
   * 只改被点的那一维,其余原样保留(在「未读」里点分类,得到的是「该分类的未读」)。
   *
   * 已经在按它筛选时静默忽略:列表不会有任何变化,重发一次请求纯属浪费,
   * 弹个「已经在看了」的提示反而像是出了错。
   *
   * 保留其它维度是可证明安全的:被点的这条帖子本身就同时满足新旧两个条件,
   * 所以叠加后的列表至少包含它,不会筛出个空列表。
   */
  private handleTagClick(tag: TopicTag): void {
    if (this.listQuery.tag !== undefined && this.listQuery.tag.name === tag.name) {
      return;
    }
    const next: TopicListQuery = cloneTopicListQuery(this.listQuery);
    next.tag = tag;
    this.listQuery = next;
    // 顶栏此刻多半已随滚动收起,副行看不见,所以给一句 toast 交代刚发生了什么。
    this.showToast(`已按标签「${tag.name}」筛选`);
    this.resetAndReload();
  }

  // 徽章上写的是帖子自己的(叶子)分类,所以在看父版块时点子版块的徽章就是收窄到子版块 ——
  // 徽章写着「福利羊毛」点了却没反应,只会显得坏掉。
  private handleCategoryClick(category: TopicCategory): void {
    if (this.listQuery.category !== undefined && this.listQuery.category.id === category.id) {
      return;
    }
    const next: TopicListQuery = cloneTopicListQuery(this.listQuery);
    next.category = category;
    this.listQuery = next;
    this.showToast(`已按分类「${category.name}」筛选`);
    this.resetAndReload();
  }

  // 点了受限版块/需登录入口:关抽屉并提示登录(账号入口在右上角头像)。
  private handleDrawerRequireLogin(): void {
    this.closeDrawer();
    this.showToast('登录后可查看该版块');
  }

  // 中和所有 incoming / highlight / insert 运行态并清空提示计数(bump 各 epoch、清定时器、
  // 复位插入与高亮字段、清 incomingTopicsState)。提示条的收起方式由调用方决定：换源整列重建走
  // 瞬时归零；下拉刷新 / 关闭实时开关走动画收起。供 resetAndReload / handleManualRefresh /
  // onRealtimeTopicsEnabledChanged 三处共用。
  private clearIncomingTopicsState(): void {
    this.incomingRequestEpoch++;
    this.incomingHighlightEpoch++;
    this.incomingInsertEpoch++;
    if (this.incomingInsertTimerId >= 0) {
      clearTimeout(this.incomingInsertTimerId);
      this.incomingInsertTimerId = -1;
    }
    this.isLoadingIncoming = false;
    this.pendingIncomingRefresh = false;
    this.incomingHighlightedTopicIds = [];
    this.incomingHighlightDeadline = 0;
    this.incomingInsertActive = false;
    this.incomingInsertProgress = 1;
    this.incomingInsertingTopicIds = [];
    this.incomingInsertRevealDistance = 0;
    this.incomingTopicsState = clearHomeIncomingTopics(this.incomingTopicsState);
  }

  private resetAndReload(): void {
    this.clearIncomingTopicsState();
    this.incomingPromptHeight = 0;
    this.incomingPromptOpacity = 0;
    this.topics = [];
    this.topicDataSource.reset([]);
    this.currentPage = 0;
    this.hasMore = true;
    this.loadFailed = false;
    this.showBackToTopFab = false;
    this.refreshLatestTopics();
  }

  private handleIncomingTopicsPromptClick(): void {
    this.pendingIncomingRefresh = true;
    this.runPendingIncomingRefresh();
  }

  // 实时开关翻转:关⇒中和所有 incoming 运行态并动画收起提示条(轮询由 ArkWebHost 侧停掉);
  // 开⇒无需动作,事件恢复流入后按既有逻辑自然展示提示。
  private onRealtimeTopicsEnabledChanged(): void {
    if (!this.realtimeTopicsEnabled) {
      this.clearIncomingTopicsState();
      this.collapseIncomingTopicsPrompt();
    }
  }

  private handleMessageBusEvent(event: MessageBusEvent): void {
    // 实时开关关闭时忽略一切事件(防御性：轮询循环此时也已停，订阅仍常驻)。
    if (!this.realtimeTopicsEnabled) {
      return;
    }
    if (event.channel !== '/latest' || !this.acceptsIncomingTopics()) {
      return;
    }
    const topicId: number | undefined = extractMessageBusTopicId(event);
    if (topicId === undefined) {
      return;
    }
    // 频道是全局的,推来的可能是任何版块的帖子;限定了版块就得按 payload 自己比一次。
    if (!incomingTopicMatchesCategory(
      this.categories, this.listQuery.category, extractMessageBusCategoryId(event))) {
      return;
    }
    const previousCount: number = this.incomingTopicsPromptCount();
    this.incomingTopicsState = addIncomingTopicMessage(
      this.incomingTopicsState,
      topicId,
      event.messageId === undefined ? 0 : event.messageId
    );
    if (previousCount === 0 && this.incomingTopicsPromptCount() > 0) {
      this.expandIncomingTopicsPrompt();
    }
  }

  /**
   * 当前条件下要不要接 /latest 的实时提示。两条限制都来自「我们只订了 /latest 这一个频道」:
   *  · 排序必须是「最新」—— 未读/新主题各有自己的频道(/unread/{user_id}、/new),没订就没数据
   *  · 不能限定标签 —— payload 只给 tag id,而我们手上的标签常常只有名字(列表接口不回 id),
   *    比不了。宁可停掉提示,也别拿名字去猜。
   * 版块维度能过:payload 带 category_id,见 incomingTopicMatchesCategory。
   */
  private acceptsIncomingTopics(): boolean {
    return this.listQuery.filter === FeedKey.LATEST && this.listQuery.tag === undefined;
  }

  private expandIncomingTopicsPrompt(): void {
    this.getUIContext().animateTo({ duration: INCOMING_PROMPT_ENTER_MS, curve: Curve.EaseOut }, () => {
      this.incomingPromptHeight = INCOMING_PROMPT_HEIGHT;
      this.incomingPromptOpacity = 1;
    });
  }

  private collapseIncomingTopicsPrompt(): void {
    this.getUIContext().animateTo({ duration: INCOMING_PROMPT_EXIT_MS, curve: Curve.EaseIn }, () => {
      this.incomingPromptHeight = 0;
      this.incomingPromptOpacity = 0;
    });
  }

  private handleManualRefresh(): void {
    // 下拉刷新代表用户主动查看最新列表。先丢弃这一刻之前的提示；刷新期间的新消息会写入新状态。
    this.clearIncomingTopicsState();
    this.collapseIncomingTopicsPrompt();
    this.refreshLatestTopics();
  }

  // 按当前条件取一页。四种 scope 组合共用一个入口,路径拼装全在 TopicListQuery 里。
  private fetchTopicPage(page: number): Promise<NetworkResult<TopicPage>> {
    return new TopicService(this.bridge).getQueryPage(this.listQuery, page);
  }

  // 顶栏主标题:版块名 → #标签名 → 过滤器名;全默认时显示应用名 ArkDO(FeedTitle 据此换 logo 版式)。
  private currentFeedTitle(): string {
    const title: string = topicListPrimaryTitle(this.listQuery);
    return title.length > 0 ? title : AppConstants.APP_NAME;
  }


  private showToast(message: string): void {
    promptToast(this.getUIContext(), message);
  }

  private async refreshLatestTopics(): Promise<boolean> {
    // 门卫看「桥能否真发请求」(executor 已挂),而非 UI 解锁标志 isArkWebReady:
    // 看门狗/失败路径会把 isArkWebReady 置真但 executor 仍为空,此时若照发请求必被跳过、硬闪「加载失败」。
    // 冷启动空窗里停在「连接中」软状态,等宿主真就绪(hostReadyEpoch)再自动补拉,避免错误闪屏。
    if (!this.bridge.canFetch()) {
      this.listMessage = '正在连接服务器…';
      return false;
    }

    this.loadSiteMetadataIfNeeded();
    // 顺带补查会话状态:上次 current.json 被 CF 拦截时右上角可能误显示为未登录。
    this.onSessionRecheck();

    if (this.isRefreshing || this.isLoadingMore || this.isInitialLoading || this.isLoadingIncoming) {
      return false;
    }

    const isFirstLoad: boolean = this.topics.length === 0;
    this.isInitialLoading = isFirstLoad;
    this.isRefreshing = !isFirstLoad;
    this.requiresChallenge = false;
    this.loadFailed = false;
    this.listMessage = `正在加载${this.currentFeedTitle()}`;
    this.footerMessage = '上拉加载更多';

    if (isFirstLoad) {
      // 计时锚点②:首页帖子列表开始拉取。与应用启动日志配对,测量冷启动到首屏拉取的耗时。
      Log.i(`${LOG_TAG} stage=firstLatestFetchStart ts=${Date.now()}`);
    }
    const result: NetworkResult<TopicPage> = await this.fetchTopicPage(0);
    this.isRefreshing = false;
    this.isInitialLoading = false;

    if (result.success && result.data) {
      this.topics = result.data.topics;
      this.topicDataSource.reset(this.topics);
      this.topicListVersion++;
      this.currentPage = 0;
      this.hasMore = result.data.hasMore;
      this.listMessage = result.data.topics.length > 0 ? '' : '暂无帖子数据';
      this.footerMessage = this.hasMore ? '上拉加载更多' : '没有更多了';
      this.runPendingSessionRefresh();
      this.runPendingIncomingRefresh();
      return true;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    const friendlyMessage: string = this.requiresChallenge
      ? '内容加载遇到访问验证,请稍后重试'
      : '加载失败,请检查网络后重试';
    if (this.topics.length === 0) {
      this.loadFailed = true;
      this.listMessage = friendlyMessage;
      // 诊断:这块全屏"访问验证/加载失败"提示在什么情形下弹出。它只在列表为空时出现,
      // 关键要靠时间戳配合前后的既有日志(冷启动标志/前后台切换/上一笔 latest.json 是否返回空列表)还原
      // "使用中列表怎么变空的"。这里记本次失败的指纹:是 CF 拦截还是普通网络失败、状态码、错误信息。
      Log.i(`${DIAG_TAG} stage=homeEmptyPromptShown requiresChallenge=${this.requiresChallenge} status=${result.statusCode} isLoggedIn=${this.isLoggedIn} errCode=${result.error?.code ?? ''} errMsg=${result.error?.message ?? ''}`);
    } else {
      this.footerMessage = '刷新失败,请重试';
    }
    this.runPendingSessionRefresh();
    this.runPendingIncomingRefresh();
    return false;
  }

  private async loadMoreTopics(): Promise<void> {
    // 门卫与 refreshLatestTopics 保持一致:看 bridge.canFetch()(executor 已挂)而非 UI 解锁标志
    // isArkWebReady。看门狗/失败路径会把 isArkWebReady 置真但 executor 仍为空,此时照发请求必被跳过。
    if (!this.bridge.canFetch()) {
      this.footerMessage = '正在准备 ArkWeb 请求环境';
      return;
    }

    this.loadSiteMetadataIfNeeded();

    if (this.isRefreshing || this.isLoadingMore || this.isLoadingIncoming ||
      !this.hasMore || this.topics.length === 0) {
      return;
    }

    this.isLoadingMore = true;
    this.requiresChallenge = false;
    this.footerMessage = '正在加载更多';

    const nextPage: number = this.currentPage + 1;
    const result: NetworkResult<TopicPage> = await this.fetchTopicPage(nextPage);
    this.isLoadingMore = false;

    if (result.success && result.data) {
      this.topicDataSource.appendUnique(result.data.topics);
      this.topics = this.topicDataSource.getAll();
      this.currentPage = nextPage;
      this.hasMore = result.data.hasMore && result.data.topics.length > 0;
      this.footerMessage = this.hasMore ? '上拉加载更多' : '没有更多了';
      this.runPendingSessionRefresh();
      this.runPendingIncomingRefresh();
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.footerMessage = result.error?.message ? `${result.error.message}，上拉重试` : '加载失败，上拉重试';
    this.runPendingSessionRefresh();
    this.runPendingIncomingRefresh();
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    Log.i(`${LOG_TAG} session changed version=${version}, refresh latest topics`);
    this.footerMessage = '会话已更新，正在刷新';
    if (!this.bridge.canFetch() || this.isRefreshing || this.isLoadingMore || this.isInitialLoading ||
      this.isLoadingIncoming) {
      this.pendingSessionRefresh = true;
      Log.i(`${LOG_TAG} session refresh queued version=${version}`);
      return;
    }
    this.refreshLatestTopics();
  }

  private runPendingSessionRefresh(): void {
    if (!this.pendingSessionRefresh || !this.bridge.canFetch() ||
      this.isRefreshing || this.isLoadingMore || this.isInitialLoading || this.isLoadingIncoming) {
      return;
    }
    this.pendingSessionRefresh = false;
    Log.i(`${LOG_TAG} run queued session refresh`);
    this.refreshLatestTopics();
  }

  private runPendingIncomingRefresh(): void {
    if (!this.pendingIncomingRefresh || !this.bridge.canFetch() || this.isRefreshing ||
      this.isLoadingMore || this.isInitialLoading || this.isLoadingIncoming) {
      return;
    }
    const snapshot: HomeIncomingTopicsState = snapshotHomeIncomingTopics(this.incomingTopicsState);
    if (snapshot.topicIds.length === 0) {
      this.pendingIncomingRefresh = false;
      return;
    }
    this.pendingIncomingRefresh = false;
    this.loadIncomingTopics(snapshot);
  }

  private async loadIncomingTopics(snapshot: HomeIncomingTopicsState): Promise<void> {
    this.isLoadingIncoming = true;
    const requestEpoch: number = ++this.incomingRequestEpoch;
    Log.i(`${LOG_TAG} incoming topics fetch started count=${snapshot.topicIds.length}`);
    const result: NetworkResult<Topic[]> =
      await new TopicService(this.bridge).getLatestTopicsByIds(snapshot.topicIds);
    if (requestEpoch !== this.incomingRequestEpoch) {
      return;
    }

    if (result.success && result.data) {
      const incomingTopics: Topic[] = result.data;
      if (incomingTopics.length === 0) {
        this.isLoadingIncoming = false;
        Log.i(`${LOG_TAG} incoming topics fetch returned empty requested=${snapshot.topicIds.length}`);
        this.showToast('暂未获取到新话题，请稍后重试');
        this.runPendingSessionRefresh();
        return;
      }
      this.stageIncomingTopicsInsert(snapshot, incomingTopics);
      return;
    }

    this.isLoadingIncoming = false;
    Log.i(`${LOG_TAG} incoming topics fetch failed status=${result.statusCode} ` +
      `error=${result.error?.message ?? ''}`);
    this.showToast('加载新话题失败，请重试');
    this.runPendingSessionRefresh();
  }

  private stageIncomingTopicsInsert(snapshot: HomeIncomingTopicsState, incomingTopics: Topic[]): void {
    const insertTopicIds: number[] = [];
    for (let index: number = 0; index < incomingTopics.length; index++) {
      if (insertTopicIds.indexOf(incomingTopics[index].id) < 0) {
        insertTopicIds.push(incomingTopics[index].id);
      }
    }
    const insertEpoch: number = ++this.incomingInsertEpoch;
    this.incomingInsertingTopicIds = insertTopicIds;
    this.incomingInsertMeasuredIds = [];
    this.incomingInsertMeasuredHeight = 0;
    this.incomingInsertPlayed = false;
    // 兜底距离先按条数估算；下一帧起播前若测到真实高度会替换它，两种情况都不跳。
    this.incomingInsertRevealDistance = insertTopicIds.length * INCOMING_INSERT_ROW_ESTIMATE;
    this.incomingInsertActive = true;
    this.incomingInsertProgress = 0;
    this.topicDataSource.prependOrReplace(incomingTopics);
    this.topics = this.topicDataSource.getAll();

    // 先让“新布局 + 负偏移”完整落一帧，下一帧再收提示并归零偏移，方向才稳定为向下。
    this.getUIContext().postFrameCallback(new NextFrameTask(() => {
      if (insertEpoch !== this.incomingInsertEpoch) {
        return;
      }
      this.playIncomingTopicsInsert(snapshot, incomingTopics, insertEpoch);
    }));
  }

  private playIncomingTopicsInsert(
    snapshot: HomeIncomingTopicsState,
    incomingTopics: Topic[],
    insertEpoch: number
  ): void {
    // 冻结揭示距离：起播后再来的测量回调不得改值，否则动画中途会瞬移。
    this.incomingInsertPlayed = true;
    this.getUIContext().animateTo({ duration: INCOMING_INSERT_MS, curve: Curve.EaseOut }, () => {
      this.incomingInsertProgress = 1;
      this.incomingTopicsState = removeIncomingTopicsSnapshot(this.incomingTopicsState, snapshot);
      if (this.incomingTopicsPromptCount() === 0) {
        this.incomingPromptHeight = 0;
        this.incomingPromptOpacity = 0;
      }
    });
    this.incomingInsertTimerId = setTimeout(() => {
      if (insertEpoch !== this.incomingInsertEpoch) {
        return;
      }
      this.incomingInsertTimerId = -1;
      this.startIncomingHighlight(incomingTopics);
      this.incomingInsertActive = false;
      this.incomingInsertingTopicIds = [];
      this.incomingInsertRevealDistance = 0;
      this.isLoadingIncoming = false;
      Log.i(`${LOG_TAG} incoming topics fetch completed requested=${snapshot.topicIds.length} ` +
        `received=${incomingTopics.length} remaining=${this.incomingTopicsPromptCount()}`);
      this.runPendingSessionRefresh();
      this.runPendingIncomingRefresh();
    }, INCOMING_INSERT_MS);
  }

  // 新增行 onAreaChange 上报自身高度。累计到全部到齐即用实测总高度覆盖兜底估算，让旧行整块下滑不留缝。
  private handleIncomingInsertMeasured(topicId: number, height: number): void {
    if (!this.incomingInsertActive || this.incomingInsertPlayed) {
      return;
    }
    if (this.incomingInsertingTopicIds.indexOf(topicId) < 0) {
      return;
    }
    if (this.incomingInsertMeasuredIds.indexOf(topicId) >= 0) {
      return;
    }
    const measured: number = Number(height);
    if (!(measured > 0)) {
      return;
    }
    this.incomingInsertMeasuredIds.push(topicId);
    this.incomingInsertMeasuredHeight += measured;
    if (this.incomingInsertMeasuredIds.length >= this.incomingInsertingTopicIds.length) {
      this.incomingInsertRevealDistance = this.incomingInsertMeasuredHeight;
    }
  }

  private startIncomingHighlight(topics: Topic[]): void {
    const topicIds: number[] = [];
    for (let index: number = 0; index < topics.length; index++) {
      if (topicIds.indexOf(topics[index].id) < 0) {
        topicIds.push(topics[index].id);
      }
    }
    if (topicIds.length === 0) {
      return;
    }

    const highlightEpoch: number = ++this.incomingHighlightEpoch;
    this.incomingHighlightedTopicIds = topicIds;
    this.incomingHighlightDeadline = Date.now() + INCOMING_HIGHLIGHT_MS;
    setTimeout(() => {
      if (highlightEpoch !== this.incomingHighlightEpoch) {
        return;
      }
      this.incomingHighlightedTopicIds = [];
      this.incomingHighlightDeadline = 0;
    }, INCOMING_HIGHLIGHT_MS);
  }

  private incomingTopicHighlightDeadline(topicId: number): number {
    return this.incomingHighlightedTopicIds.indexOf(topicId) >= 0 ? this.incomingHighlightDeadline : 0;
  }

  private incomingTopicRenderToken(topicId: number): string {
    if (this.incomingInsertingTopicIds.indexOf(topicId) >= 0) {
      return `insert_${this.incomingInsertEpoch}`;
    }
    return `highlight_${this.incomingTopicHighlightDeadline(topicId)}`;
  }

  private handleTopicReadStateChanged(state: TopicReadState): void {
    for (let index: number = 0; index < this.topics.length; index++) {
      const topic: Topic = this.topics[index];
      if (topic.id === state.topicId) {
        // @Observed 实例赋值 → 对应 TopicListItem(@ObjectLink)精准重渲染。
        topic.unseen = state.unseen;
        topic.unreadPosts = state.unreadPosts;
        // 同步已读水位(最高楼 − 剩余未读):再点未读徽标时跳转目标才是最新的第一条未读楼。
        if (topic.highestPostNumber !== undefined && topic.highestPostNumber > 0) {
          topic.lastReadPostNumber = Math.max(0, topic.highestPostNumber - state.unreadPosts);
        }
        Log.i(`${LOG_TAG} topic read state synced topicId=${state.topicId} unreadPosts=${state.unreadPosts}`);
        return;
      }
    }
  }

  // 点未读徽标:目标楼 = 已读水位 + 1(封顶最高楼)。字段缺失(匿名/异常数据)退化为普通打开。
  private handleUnreadBadgeClick(topic: Topic): void {
    topic.unseen = false;
    const lastRead: number = topic.lastReadPostNumber ?? 0;
    if (lastRead <= 0) {
      this.onTopicClick(topic);
      return;
    }
    let target: number = lastRead + 1;
    const highest: number = topic.highestPostNumber ?? 0;
    if (highest > 0 && target > highest) {
      target = highest;
    }
    this.onOpenTopicAtPost(topic, target);
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady && this.topics.length === 0) {
      this.loadSiteMetadataIfNeeded();
      this.refreshLatestTopics();
    }
    this.checkVersionAnnouncement();
  }

  // 宿主真就绪(executor 已挂):若列表此刻还空/还停在失败态,补拉一次。
  // 这是冷启动越过看门狗场景的自愈点——失败路径先画了「加载失败」,真就绪后由此自动重拉,
  // 无需用户手点重试。列表已有数据则不打扰。refreshLatestTopics 自带在途去重,重复触发无副作用。
  private handleHostReadyEpoch(): void {
    if (this.hostReadyEpoch <= 0) {
      return;
    }
    if (this.pendingSessionRefresh) {
      this.loadSiteMetadataIfNeeded();
      this.runPendingSessionRefresh();
    } else if (this.topics.length === 0 || this.loadFailed) {
      this.loadSiteMetadataIfNeeded();
      this.refreshLatestTopics();
    }
    this.runPendingIncomingRefresh();
    this.checkVersionAnnouncement();
  }

  // 首页就绪后拉版本公告:用当前 versionCode 从公告帖末尾往前匹配 [v<code>] 那条回复弹出。
  // 冷启动只查一次;桥是父组件注入的 @Prop,服务必须在此惰性创建(字段初始化器会捕获空壳默认 bridge)。
  private async checkVersionAnnouncement(): Promise<void> {
    Log.i(`${ANNOUNCE_DIAG} 触发检查 isArkWebReady=${this.isArkWebReady} 本次挂载已查过=${this.announceChecked}`);
    if (this.announceChecked || !this.isArkWebReady) {
      return;
    }
    this.announceChecked = true;

    const versionCode: number = this.readVersionCode();
    Log.i(`${ANNOUNCE_DIAG} 当前 versionCode=${versionCode} ALWAYS_SHOW=${ANNOUNCE_ALWAYS_SHOW}`);
    if (versionCode <= 0) {
      Log.w(`${ANNOUNCE_DIAG} versionCode 读取失败,跳过`);
      return;
    }
    if (!ANNOUNCE_ALWAYS_SHOW && this.announceAlreadyShown(versionCode)) {
      Log.i(`${ANNOUNCE_DIAG} 该版本已弹过,跳过(改 ALWAYS_SHOW=true 可强制弹)`);
      return;
    }

    const service: VersionAnnouncementService = new VersionAnnouncementService(this.bridge);
    const announcement: VersionAnnouncement | null = await service.fetchForVersion(versionCode);
    if (!announcement) {
      Log.i(`${ANNOUNCE_DIAG} 无匹配公告,不弹窗`);
      return;
    }
    Log.i(`${ANNOUNCE_DIAG} 弹出公告 楼号=${announcement.postNumber}`);
    this.announceCooked = announcement.cookedHtml;
    this.announceVisible = true;
    if (!ANNOUNCE_ALWAYS_SHOW) {
      this.markAnnounceShown(versionCode);
    }
  }

  private readVersionCode(): number {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionCode;
    } catch (error) {
      Log.w(`${LOG_TAG} 读取 versionCode 失败: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  private announceAlreadyShown(versionCode: number): boolean {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(getContext(this), { name: ANNOUNCE_PREFS_NAME });
      return (store.getSync(ANNOUNCE_SHOWN_CODE_KEY, 0) as number) === versionCode;
    } catch (error) {
      return false;
    }
  }

  private markAnnounceShown(versionCode: number): void {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(getContext(this), { name: ANNOUNCE_PREFS_NAME });
      store.putSync(ANNOUNCE_SHOWN_CODE_KEY, versionCode);
      store.flush();
    } catch (error) {
      Log.w(`${LOG_TAG} 记录已弹版本失败: ${JSON.stringify(error)}`);
    }
  }

  private syncSessionVersion(): void {
    this.handleSessionChanged(SessionEventBus.getCurrentVersion());
  }

  private async loadSiteMetadataIfNeeded(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

}

// 调试用输入框:填帖子 ID 直接跳转详情。
@CustomDialog
struct TopicJumpDialog {
  controller: CustomDialogController;
  onConfirm: (topicId: number) => void = () => {};
  @State private idText: string = '';

  build() {
    Column() {
      Text('跳转到帖子')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })

      TextInput({ placeholder: '输入帖子 ID' })
        .type(InputType.Number)
        .defaultFocus(true)
        .fontSize(16)
        .height(46)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(10)
        .onChange((value: string) => {
          this.idText = value;
        })
        .onSubmit(() => {
          this.confirm();
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_muted'))
          .onClick(() => {
            this.controller.close();
          })

        Button('跳转')
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand'))
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
      .margin({ top: 20 })
    }
    .width('80%')
    .padding(20)
    .backgroundColor($r('app.color.page_bg'))
    .borderRadius(16)
  }

  private confirm(): void {
    const topicId: number = parseInt(this.idText.trim(), 10);
    if (isNaN(topicId) || topicId <= 0) {
      return;
    }
    this.controller.close();
    this.onConfirm(topicId);
  }
}
