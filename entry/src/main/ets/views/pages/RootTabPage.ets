import { Log } from '../../services/logging/Log';
import { AppConstants, LinuxDoConstants } from '../../common/constants/AppConstants';
import { APP_IS_WIDE_STORAGE_KEY, APP_SPLIT_NAV_BAR_WIDTH_STORAGE_KEY, BreakpointManager,
  SPLIT_NAV_BAR_MAX_WIDTH } from '../../common/utils/BreakpointManager';
import { ActivityRouteParam, AppRouteName, BadgesRouteParam, BookmarksRouteParam, buildActivityRouteParam, buildBadgesRouteParam, buildBookmarksRouteParam, buildDraftsRouteParam, buildDohSettingsRouteParam, buildPushSettingsRouteParam, buildNetworkSettingsRouteParam, buildLabSettingsRouteParam, buildDiagnosticsSettingsRouteParam, buildTopicListStyleSettingsRouteParam, buildLevelProgressRouteParam, buildNotificationsRouteParam, buildProfileRouteParam, buildReadTopicsRouteParam, buildSettingsRouteParam, buildForumsRouteParam, buildSitesRouteParam, buildSolvedRouteParam, buildTopicDetailRouteParam, buildTopicDetailDraftRouteParam, buildTopicDetailEditDraftRouteParam, buildUserProfileRouteParam, buildWebRouteParam, isActivityRouteParam, isBadgesRouteParam, isBookmarksRouteParam, isDraftsRouteParam, DraftsRouteParam, isSolvedRouteParam, isTopicDetailRouteParam, isUserProfileRouteParam, isWebRouteParam, LevelProgressRouteParam, SolvedRouteParam, TopicDetailRouteParam, UserProfileRouteParam, WebRouteParam } from '../../navigation/AppRoutes';
import { LinkRouter, LinkTarget, LinkTargetKind } from '../../services/content/LinkRouter';
import { DownloadService } from '../../services/content/DownloadService';
import { DownloadEventBus, DownloadResult } from '../../services/content/DownloadEventBus';
import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import window from '@ohos.window';
import { APP_IS_DARK_STORAGE_KEY } from '../../common/theme/ThemeManager';
import { ImmersiveWindow } from '../../common/utils/ImmersiveWindow';
import { Topic } from '../../models/Topic';
import { SidebarTag, User } from '../../models/User';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../../services/challenge/ChallengeEventBus';
import { ChallengeRecoveryCoordinator } from '../../services/challenge/ChallengeRecoveryCoordinator';
import { ChallengeRecoveryEventBus } from '../../services/challenge/ChallengeRecoveryEventBus';
import { ChallengeShortcutEventBus } from '../../services/challenge/ChallengeShortcutEventBus';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationService } from '../../services/notification/NotificationService';
import { NotificationEventBus } from '../../services/notification/NotificationEventBus';
import { HarmonyPushTokenProvider } from '../../services/push/HarmonyPushTokenProvider';
import { PushNotificationPermissionResult, PushNotificationPermissionService } from '../../services/push/PushNotificationPermissionService';
import { HttpPushRelayClient } from '../../services/push/PushRelayClient';
import { PushRegistrationResult, PushRelayRegistration, PushRelayUser, PushStatusResult, PushSubscriptionService } from '../../services/push/PushSubscriptionService';
import { PushSubscriptionStore, StoredPushSubscription } from '../../services/push/PushSubscriptionStore';
import { describePushNotificationRoute, PushNotificationRoute } from '../../services/push/PushNotificationNavigation';
import { PushNotificationNavigationEventBus } from '../../services/push/PushNotificationNavigationEventBus';
import { PushTokenUpdateEventBus } from '../../services/push/PushTokenUpdateEventBus';
import { isPushRelayConfigured, PushRelayConfig, resolvePushRelayConfig } from '../../services/push/PushRelayConfig';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { AvatarImageCache } from '../../services/network/AvatarImageCache';
import { ContentImageCache } from '../../services/network/ContentImageCache';
import { SiteIconStore } from '../../services/site/SiteIconStore';
import { image } from '@kit.ImageKit';
import { DohManager, DohResolveMode } from '../../services/network/DohManager';
import { NetworkResult, NetworkErrorCode, ChallengeState } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { CurrentUserEventBus } from '../../services/session/CurrentUserEventBus';
import { LoginGate } from '../../services/session/LoginGate';
import { WebSessionManager } from '../../services/web/WebSessionManager';
import { ArkWebHost } from '../components/ArkWebHost';
import { MathRenderHost } from '../components/MathRenderHost';
import { ImageViewer, ViewerImage } from '../components/ImageViewer';
import { SearchFlow } from '../components/SearchFlow';
import { ensureFaIconsLoaded } from '../components/FaIcon';
import { ensureTagIconsLoaded } from '../components/TagIconRegistry';
import { CfChallengePage } from './CfChallengePage';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { NotificationPage } from './NotificationPage';
import { ProfilePage } from './ProfilePage';
import { SettingsPage } from './SettingsPage';
import { DohSettingsPage } from './DohSettingsPage';
import { PushSettingsPage } from './PushSettingsPage';
import { NetworkSettingsPage } from './NetworkSettingsPage';
import { ExperimentalSettingsPage } from './ExperimentalSettingsPage';
import { TopicListStyleSettingsPage } from './TopicListStyleSettingsPage';
import { DiagnosticsSettingsPage } from './DiagnosticsSettingsPage';
import { CurrentSite } from '../../services/site/CurrentSite';
import { ForumsPage } from './ForumsPage';
import { SiteSwitchCoordinator } from '../../services/site/SiteSwitchCoordinator';
import { ForumDef, ForumPrefs } from '../../services/site/ForumPrefs';
import { SiteUrl } from '../../services/site/SiteUrl';
import { SitesPage } from './SitesPage';
import { LevelProgressPage } from './LevelProgressPage';
import { LdcCreditPage } from './LdcCreditPage';
import { isLdcCreditRouteParam, LdcCreditRouteParam } from '../../navigation/AppRoutes';
import { BookmarksPage } from './BookmarksPage';
import { DraftsPage } from './DraftsPage';
import { ActivityListPage } from './ActivityListPage';
import { ReadTopicsPage } from './ReadTopicsPage';
import { BadgesPage } from './BadgesPage';
import { UserProfilePage } from './UserProfilePage';
import { SolvedPostsPage } from './SolvedPostsPage';
import { TopicDetailPage } from './TopicDetailPage';
import { bumpTick, COMPOSER_OVERLAY_BACK_TICK_KEY, COMPOSER_OVERLAY_VISIBLE_KEY, DRAFTS_COMPOSER_BACK_TICK_KEY,
  DRAFTS_COMPOSER_VISIBLE_KEY, DRAFTS_REFRESH_TICK_KEY, IMAGE_VIEWER_BACK_TICK_KEY, IMAGE_VIEWER_VISIBLE_KEY,
  PROFILE_DRAFT_COUNT_KEY, SEARCH_OVERLAY_BACK_TICK_KEY, SEARCH_OVERLAY_VISIBLE_KEY, SETTINGS_DOH_TICK,
  SITES_TICK } from '../../common/constants/StorageKeys';
import { DraftEventBus } from '../../services/draft/DraftEventBus';
import { WebViewPage } from './WebViewPage';
import { showToast as promptToast } from '../../common/utils/Toast';
import { MATH_HOST_ACTIVE_KEY } from '../../services/content/MathRenderService';
import { PushCoordinator } from '../../services/push/PushCoordinator';
import { SCRIM } from '../../common/theme/Palette';

const LOG_TAG: string = '[ArkDO][Root]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
// 网络恢复触发宿主重载的冷却窗口:地铁出隧道等场景网络会短时间内反复抖动/多次上报,
// 冷却避免每次抖动都重载一次宿主(重载较重)。只在宿主此前确实加载失败时才会触发。
const NET_RECOVERY_RELOAD_COOLDOWN_MS: number = 15000;
// ===== 首页左滑跟手拉出个人中心 =====
// 松手判定阈值:滑过屏宽这个比例即补完,否则回弹。
const SWIPE_COMMIT_RATIO: number = 0.4;
// 松手判定阈值:横向甩速(vp/s)超过即直接补完,不看距离。
const SWIPE_COMMIT_VELOCITY: number = 800;
// ↓↓↓ 手感就调这三个:补完时长、回弹时长、收尾曲线。 ↓↓↓
const SWIPE_COMMIT_MS: number = 280;
const SWIPE_REBOUND_MS: number = 220;
const SWIPE_SETTLE_CURVE: Curve = Curve.Friction;
// 首页视差(对齐系统默认转场的观感):个人中心滑到底时,首页左移自身宽度的这个比例。
// 与个人中心的位移共用同一个 progress,天然同步。0 即关掉视差。
const SWIPE_PARALLAX_RATIO: number = 0.25;
enum RootSheet {
  NONE = 0,
  LOGIN = 1,
  CHALLENGE = 2
}

@Component
export struct RootTabPage {
  // 单一 bindSheet:同一组件链多个 bindSheet 只有最后一个生效,会导致登录 sheet 不显示。
  @State private isSheetVisible: boolean = false;
  @State private activeSheet: RootSheet = RootSheet.NONE;
  // 公式离屏引擎挂载门控:由 MathRenderService.retain/release 经 AppStorage 翻转。
  @StorageProp(MATH_HOST_ACTIVE_KEY) private mathHostActive: boolean = false;
  // 宽屏标志(平板横屏 / 大屏):驱动 Navigation 双栏 Split;手机、平板竖屏恒为 false 走单栏 Stack。
  // @Watch 在宽<->窄切换(旋转)时同步右栏空占位:进宽屏且空栈时垫占位,回窄屏时移除占位。
  @StorageProp(APP_IS_WIDE_STORAGE_KEY) @Watch('onWideChanged') private appIsWide: boolean = false;
  // 双栏左列表栏宽度(vp)。与 appIsWide 同源:BreakpointManager.applySize 按窗口宽度 + 折叠状态
  // 算好写进 AppStorage,这里只读。首帧尺寸还没进来时是 init 播种的上限值,避免闪一下窄栏。
  @StorageProp(APP_SPLIT_NAV_BAR_WIDTH_STORAGE_KEY) private splitNavBarWidth: number = SPLIT_NAV_BAR_MAX_WIDTH;
  // 图片浏览器提到根级渲染:双栏下必须盖满整窗(否则只占右详情栏),旋转时随根 Stack 重排。
  // 由详情页经 onOpenImages 回调冒泡上来触发,统一在这里开关。
  @State private showImageViewer: boolean = false;
  @State private viewerImages: ViewerImage[] = [];
  @State private viewerStartIndex: number = 0;
  // 预览返回键信号:Index @Entry 拦截后 bump,经 @Param 透传给 ImageViewer(翻回上一张/首图关闭)。
  @StorageProp(IMAGE_VIEWER_BACK_TICK_KEY) private viewerBackTick: number = 0;
  // 主窗口引用:图片预览期间隐藏/恢复状态栏用(打开时获取,关闭后释放)。
  // 窗口常驻全屏布局(ImmersiveWindow):状态栏避让下沉到各页面的顶层内容容器
  // (padding 加在带页面背景色的容器上,背景自然填满状态栏条且颜色逐页正确);
  // 页面内遮罩/浮层留在未加 padding 的层级,天然盖满物理屏。此处 Navigation 不加任何避让。
  private viewerWindow?: window.Window = undefined;
  // 预览期间是否已隐藏状态栏。隐藏/恢复卡在浮层盖满屏的窗口内做(见 openImageViewer 注释),
  // 入场动效没放完就被关掉时压根没隐藏过,靠这个标志决定要不要恢复。
  private viewerBarHidden: boolean = false;
  // 搜索 Flow:根 Stack 覆盖层负责一镜到底;内部自带 Navigation 负责搜索结果 -> 详情 -> Web -> 原路返回。
  @State private searchFlowMounted: boolean = false;
  @State private showSearchFlow: boolean = false;
  // 系统返回键信号:SearchFlow 不进主 Navigation 栈,由 Index @Entry 拦截后 bump,SearchFlow 自己处理。
  @StorageProp(SEARCH_OVERLAY_BACK_TICK_KEY) private searchBackTick: number = 0;
  @State private isArkWebReady: boolean = false;
  // 宿主真就绪信号:仅在 onReady(onPageEnd,executor 已挂)时自增。isArkWebReady 会被看门狗/失败路径
  // 提前置真且烧掉 false→true 跳变,导致真就绪时首页的 @Watch(isArkWebReady) 不再触发、列表卡在失败态;
  // 用这个独立单调计数专门驱动「真就绪后重拉列表」,与 UI 解锁标志解耦。
  @State private hostReadyEpoch: number = 0;
  @State private currentUser?: User = undefined;
  // 侧栏自选的标签与版块(current_user.sidebar_tags / sidebar_category_ids),首页筛选抽屉用。
  // 独立于 currentUser 持有,不是图省事:它有两个更新源——会话检查(权威,会改登录态)与通知轮询
  // 的静默快照(绝不能碰登录态)。单独存这两份,轮询那条路就不必去复制/合并整个 User,
  // 也就没有「哪天 User 加了字段忘了同步」的坑。
  @State private sidebarTags: SidebarTag[] = [];
  @State private sidebarCategoryIds: number[] = [];
  @State private isCheckingSession: boolean = false;
  @State private hasCheckedSession: boolean = false;
  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private notificationService: NotificationService = new NotificationService(this.bridge);
  // 推送协调器。三个依赖走闭包:this.bridge 是父注入 prop,字段初始化器里是空壳;
  // context 要 UI 就绪后才取得到。
  private pushCoordinator: PushCoordinator = new PushCoordinator(
    () => this.getUIContext().getHostContext() as common.UIAbilityContext | undefined,
    () => this.currentUser,
    () => this.bridge);
  private navPathStack: NavPathStack = new NavPathStack();
  private levelProgressScroller: Scroller = new Scroller();
  // LINUX DO Credit 页的滚动容器:HDS 宿主标题栏必须绑定页面滚动容器才能联动,故在此持有并注入。
  private ldcCreditScroller: Scroller = new Scroller();
  // 手势激活闸:仅此为 true 时 customNavContentTransition 才接管 PROFILE 的 push;
  // 点头像那条路照走系统默认转场,互不干扰。
  @State private profileSwipeActive: boolean = false;
  // 跟手进度 0~1:同时驱动 ProfilePage 的 translate、首页视差、proxy.updateTransition,三者共用一个源。
  @State private profileSwipeProgress: number = 0;
  private profileSwipeProxy?: NavigationTransitionProxy = undefined;
  // 收尾动画进行中:此间不许 onTransitionEnd 重置 active,否则位移表达式短路成 0、页面瞬移归位,
  // 收尾动画等于白播(表现为"一松手就唰一下到位")。
  private profileSwipeSettling: boolean = false;
  private sessionCheckSequence: number = 0;
  // 会话检查进行中又收到登录成功/会话变化时,不能丢掉这次新检查请求。
  // 旧请求返回后会自动启动最新一轮,避免旧的「未登录」结果覆盖刚登录状态。
  private sessionCheckQueued: boolean = false;
  // 上次会话检查是否失败(CF 盾/网络原因,状态可能不真实),下拉刷新时据此补查。
  private lastSessionCheckFailed: boolean = false;
  // 网络层自愈闸:长时间后台回前台后宿主 webview 连接/DNS 可能僵死(status=0 且非 CF 盾),
  // 首次遇到时重载一次宿主拿新连接并重查;每段失败只自愈一次,成功后复位,避免重载死循环。
  private hasSelfHealedNetwork: boolean = false;
  // 宿主 webview 是否处于「加载失败」态。isArkWebReady 在失败路径也会被置真(为解锁 UI),不可作此判据;
  // 用这个独立闸精确标记:onLoadFailed 置真、真就绪(onReady)复位。仅此态下网络恢复才重载宿主。
  private hostLoadFailed: boolean = false;
  // 网络恢复重载的上一次触发时刻,配合 NET_RECOVERY_RELOAD_COOLDOWN_MS 做冷却去抖。
  private lastNetRecoveryReloadTs: number = 0;
  // 网络状态监听:冷启动即离线时,宿主首屏加载失败后无任何自动重连入口(自愈仅一次、下拉刷新在
  // 桥未就绪时提前返回)。监听网络恢复,失败态下重载一次宿主,把 MessageBus 与全站数据一起救回来。
  private netConnection?: connection.NetConnection = undefined;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private handledChallengeVersion: number = ChallengeEventBus.getCurrentVersion();
  private unsubscribeChallengeRequired?: () => void = undefined;
  private unsubscribeSessionChanged?: () => void = undefined;
  private unsubscribeDownload?: () => void = undefined;
  private unsubscribeDraftDeleted?: () => void = undefined;
  private unsubscribeRequireLogin?: () => void = undefined;
  private unsubscribeManualChallenge?: () => void = undefined;
  private unsubscribePushNavigation?: () => void = undefined;
  private unsubscribePushTokenUpdate?: () => void = undefined;
  private unsubscribeCurrentUser?: () => void = undefined;
  // 切站订阅:本页持有 bridge 与导航栈,是唯一能编排「重载宿主 + 清栈 + 刷列表」的地方。
  private unsubscribeSiteChanged?: () => void = undefined;
  // 挑战恢复协调器:优先后台静默过盾,失败才弹窗。惰性创建(需闭包引用本组件方法)。
  private challengeRecovery?: ChallengeRecoveryCoordinator = undefined;

  // 宿主 Context 收口。getContext(this) 已废弃,统一从 UIContext 取,免得每个调用点各写一遍 cast。
  private hostContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  aboutToAppear(): void {
    this.ensureIconSymbolsLoaded();
    // 冷启动即在宽屏(平板横屏)时,给空的右详情栏垫上占位(@Watch 只在切换时触发,首值需手动同步)。
    this.syncWidePlaceholder();
    // 头像缓存单例注入 host bridge:UserAvatar 深层嵌套拿不到 bridge,统一经它取图(过 SNI 封锁)。
    AvatarImageCache.getInstance().attachBridge(this.bridge);
    // 正文图缓存同理:原生 Image 直载失败时由它经 host webview 兜底取图(DoH 只对 ArkWeb 内核生效)。
    ContentImageCache.getInstance().attachBridge(this.bridge);
    if (!this.challengeRecovery) {
      this.challengeRecovery = new ChallengeRecoveryCoordinator(
        this.bridge,
        () => {
          // 恢复成功:广播会话刷新——重载 host、复查登录态、刷新列表。
          SessionEventBus.notifySessionChanged();
        },
        () => {
          this.openChallengeSheet();
        },
        () => {
          // 过盾窗口开始:临时借用 AUTO,让 challenges.cloudflare.com 回退系统 DNS 解出来(不落盘)。
          DohManager.applyTransientMode(this.hostContext(), DohResolveMode.AUTO);
        },
        () => {
          // 过盾结束:还原用户持久化的 DoH 设置(通常 SECURE_ONLY),不让 AUTO 泄漏到正常浏览。
          DohManager.applyActive(this.hostContext());
        }
      );
    }
    if (!this.unsubscribeChallengeRequired) {
      this.unsubscribeChallengeRequired = ChallengeEventBus.subscribe((event: ChallengeRequiredEvent) => {
        this.handleChallengeRequired(event);
      });
    }
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }
    if (!this.unsubscribeSiteChanged) {
      this.unsubscribeSiteChanged = CurrentSite.subscribe(() => {
        this.handleSiteChanged();
      });
    }
    if (!this.unsubscribeDownload) {
      this.unsubscribeDownload = DownloadEventBus.subscribe((result: DownloadResult) => {
        this.handleDownloadResult(result);
      });
    }
    if (!this.unsubscribeDraftDeleted) {
      this.unsubscribeDraftDeleted = DraftEventBus.subscribeDeleted((draftKey: string) => {
        this.handleDraftDeleted(draftKey);
      });
    }
    // 深层页面/楼层动作在未登录时点写操作,经 LoginGate 请求登录,统一在此弹出登录页。
    if (!this.unsubscribeRequireLogin) {
      this.unsubscribeRequireLogin = LoginGate.subscribe(() => {
        this.openLoginPage();
      });
    }
    // 首页"手动验证"按钮:停后台静默恢复并直接弹可见验证页。
    if (!this.unsubscribeManualChallenge) {
      this.unsubscribeManualChallenge = ChallengeRecoveryEventBus.subscribeManual(() => {
        this.challengeRecovery?.forceEscalate();
      });
    }
    if (!this.unsubscribePushNavigation) {
      this.unsubscribePushNavigation = PushNotificationNavigationEventBus.subscribe((route: PushNotificationRoute) => {
        this.handlePushNotificationRoute(route);
      });
    }
    const pendingPushRoute: PushNotificationRoute | undefined = PushNotificationNavigationEventBus.takePending();
    if (pendingPushRoute) {
      this.handlePushNotificationRoute(pendingPushRoute);
    }
    // 设备 token 轮换:中继里的旧 token 已投不到本机,须重新登记(force 绕开账号去重)。
    if (!this.unsubscribePushTokenUpdate) {
      this.unsubscribePushTokenUpdate = PushTokenUpdateEventBus.subscribe(() => {
        PushTokenUpdateEventBus.clearPending();
        this.pushCoordinator.reconcile(true);
      });
    }
    if (PushTokenUpdateEventBus.takePending()) {
      this.pushCoordinator.reconcile(true);
    }
    // 通知轮询顺路带回来的 current_user 快照。
    if (!this.unsubscribeCurrentUser) {
      this.unsubscribeCurrentUser = CurrentUserEventBus.subscribe((user: User) => {
        this.applyCurrentUserSnapshot(user);
      });
    }
    this.startNetworkRecoveryWatch();
  }

  aboutToDisappear(): void {
    this.notificationService.stop();
    this.stopNetworkRecoveryWatch();
    this.challengeRecovery?.dispose();
    if (this.unsubscribeChallengeRequired) {
      this.unsubscribeChallengeRequired();
      this.unsubscribeChallengeRequired = undefined;
    }
    if (this.unsubscribeCurrentUser) {
      this.unsubscribeCurrentUser();
      this.unsubscribeCurrentUser = undefined;
    }
    if (this.unsubscribeSiteChanged) {
      this.unsubscribeSiteChanged();
      this.unsubscribeSiteChanged = undefined;
    }
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
    if (this.unsubscribeDownload) {
      this.unsubscribeDownload();
      this.unsubscribeDownload = undefined;
    }
    if (this.unsubscribeDraftDeleted) {
      this.unsubscribeDraftDeleted();
      this.unsubscribeDraftDeleted = undefined;
    }
    if (this.unsubscribeRequireLogin) {
      this.unsubscribeRequireLogin();
      this.unsubscribeRequireLogin = undefined;
    }
    if (this.unsubscribeManualChallenge) {
      this.unsubscribeManualChallenge();
      this.unsubscribeManualChallenge = undefined;
    }
    if (this.unsubscribePushNavigation) {
      this.unsubscribePushNavigation();
      this.unsubscribePushNavigation = undefined;
    }
    if (this.unsubscribePushTokenUpdate) {
      this.unsubscribePushTokenUpdate();
      this.unsubscribePushTokenUpdate = undefined;
    }
  }

  build() {
    Stack() {
      ArkWebHost({
        bridge: this.bridge,
        onReady: () => {
          this.handleArkWebReady();
        },
        onLoadFailed: () => {
          this.handleArkWebLoadFailed();
        }
      })
      // 公式离屏引擎:仅在有含数学公式的帖子打开时(refCount>0)才挂载,离开后空闲销毁。
      if (this.mathHostActive) {
        MathRenderHost()
      }
      this.RootNavigation()

      // 搜索 Flow:根级覆盖层负责首页 -> 搜索的一镜到底;内部 Navigation 负责搜索结果 -> 详情 -> Web。
      if (this.searchFlowMounted) {
        SearchFlow({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          currentUser: this.currentUser ?? this.getAnonymousUser(),
          backTick: this.searchBackTick,
          onClose: () => {
            this.closeSearch();
          },
          onOpenChallenge: () => {
            this.challengeRecovery?.forceEscalate();
            this.openChallengeSheet();
          },
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.openImageViewer(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.handleOpenLink(url);
          },
          onOpenUser: (user: User) => {
            this.openUserProfileFor(user);
          }
        })
          .opacity(this.showSearchFlow ? 1 : 0)
          .hitTestBehavior(this.showSearchFlow ? HitTestMode.Default : HitTestMode.None)
          .transition(
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
          )
      }

      // 图片浏览器:根 Stack 顶层,越过 Navigation 分栏盖满整窗(双栏下也全屏,旋转随根重排)。
      if (this.showImageViewer) {
        ImageViewer({
          images: this.viewerImages,
          startIndex: this.viewerStartIndex,
          backTick: this.viewerBackTick,
          onCovered: () => {
            this.onImageViewerCovered();
          },
          onRevealing: () => {
            this.onImageViewerRevealing();
          },
          onClose: () => {
            this.closeImageViewer();
          }
        })
        // 挂载/卸载不带任何 transition:开关场动效(hero 飞入飞回,或降级的淡入淡出)
        // 全部由 ImageViewer 自己在内部跑完——外层再套一层 opacity 会把飞行中的图一起淡掉。
        // 相应地 onClose 是「动效已播完」的信号,收到就能直接卸载。
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 根 Stack 铺满整窗,其实测尺寸即窗口尺寸:布局驱动断点,首帧与旋转/分屏/折叠都会触发。
    // 判定规则见 BreakpointManager.applySize(平板横屏 / 折叠屏展开 → 双栏,并一并算好左栏宽)。
    // 比 mediaquery 更可靠。
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      BreakpointManager.applySize(newValue.width as number, newValue.height as number);
    })
    .bindSheet($$this.isSheetVisible, this.RootSheetBuilder, {
      // CF 交互式挑战需要尽量完整的视口(半屏+圆角+露底会被 Turnstile 视作可疑),且过盾中途
      // 不该被误滑关,故 CHALLENGE 用满高全屏、去拖动条。登录 sheet 同样用满高,给登录网页
      // (CF Turnstile / 第三方 SSO 跳转)尽量完整的视口。
      height: '100%',
      dragBar: this.activeSheet !== RootSheet.CHALLENGE,
      // CF 验证弹窗自带「关闭」按钮,隐藏原生右上角 X 避免出现两个关闭入口;其余 sheet 保留原生 X。
      showClose: this.activeSheet !== RootSheet.CHALLENGE,
      maskColor: SCRIM,
      backgroundColor: $r('app.color.surface_card'),
      // bindSheet API 23 尚无 HDS systemMaterialEffect 字段;登录页使用 ArkUI 官方 blur,
      // Cloudflare 验证页保持无 blur,避免材质覆盖影响交互验证。
      blurStyle: this.rootSheetBlurStyle(),
      preferType: SheetType.BOTTOM,
      enableOutsideInteractive: false,
      onDisappear: () => {
        this.activeSheet = RootSheet.NONE;
        // 弹窗以任意方式关闭(X/下滑/关闭按钮),若仍在等待兜底则让协调器复位;已解决则无副作用。
        this.challengeRecovery?.notifySheetDismissed();
      }
    })
  }

  @Builder
  private RootNavigation() {
    Navigation(this.navPathStack) {
      this.HomeRoot()
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    // 显式驱动分栏:仅宽屏(平板横屏)双栏 Split,手机 / 平板竖屏单栏 Stack。
    // 不用默认 Auto——其 520vp 阈值会把平板竖屏也切成双栏。手机恒 Stack,与现状一致。
    .mode(this.appIsWide ? NavigationMode.Split : NavigationMode.Stack)
    // 左列表栏宽(仅 Split 生效,Stack/手机下忽略):由 BreakpointManager.splitNavBarWidth 按窗口宽度
    // + 折叠状态算好,经 AppStorage 读进来。
    //
    // 这里刻意只设 navBarWidth 一个属性,navBarWidthRange / minContentWidth / enableDragBar
    // 一个都不能加——设了其中任一个,分割线就变成可拖的(enableDragBar 只多给一个可见把手,
    // 不是拖拽的总开关)。而拖拽改宽度走的是「只改宽度、跳过重排」的路径
    //   (HiLog: Text Relayout: No relayout required → generatePaintRegion: paragraph is not formatted),
    // 左栏里的 Text 会留在未重排状态,之后一转屏,绘制阶段拿过期 paragraph 调
    // SPText::ParagraphImpl::GeneratePaintRegion 直接 SIGTRAP 崩溃(四次崩溃栈完全一致)。
    // 这是系统文字引擎的缺陷,ArkTS 侧没有干净的规避手段(拿不到拖拽回调,也无法手动触发重排)。
    // 右栏最小宽度由比例自己保证(左栏最多占一半,折叠屏展开态取满一半时右栏同样有一半),
    // 不必再靠 minContentWidth。
    // 要可调宽度就走设置项 + 状态驱动 navBarWidth 的正常 measure 路径。
    .navBarWidth(this.splitNavBarWidth)
    .navDestination(this.NavDestinationBuilder)
    // 只接管「手势闸打开 + PUSH + 目标是 PROFILE」这一种;其余一律返回 undefined 走系统默认,
    // 不影响其他页面的转场。搜索 Flow 不进主 Navigation,不在这里处理。
    .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
      return this.buildProfileSwipeTransition(to, operation);
    })
  }

  private buildProfileSwipeTransition(to: NavContentInfo, operation: NavigationOperation): NavigationAnimatedTransition | undefined {
    if (!this.profileSwipeActive || operation !== NavigationOperation.PUSH || to.name !== AppRouteName.PROFILE) {
      return undefined;
    }
    return {
      // 不开这个,updateTransition / cancelTransition 全是空操作(API 12 起)。
      isInteractive: true,
      // 兜底:手势异常中断没人收尾时超时自动结束,避免转场悬着——挂起期间 Navigation 吞掉所有输入。
      timeout: 3000,
      transition: (proxy: NavigationTransitionProxy) => {
        this.profileSwipeProxy = proxy;
        proxy.updateTransition?.(0);
      },
      // 注:实测每次转场此回调会触发两遍(系统行为),故这里必须保持幂等,别塞非幂等副作用。
      onTransitionEnd: (success: boolean) => {
        this.profileSwipeProxy = undefined;
        // 收尾动画还在播时不要重置——留给动画的 onFinish 收,否则页面当场瞬移。
        if (!this.profileSwipeSettling) {
          this.profileSwipeActive = false;
          this.profileSwipeProgress = 0;
        }
      }
    };
  }

  // 手指按下即 push:跟手要求目标页当场在场,晚了就跟不上手指(实测 push 到转场就绪 ≈15~20ms,一帧内)。
  private handleProfileSwipeStart(): void {
    // 宽屏(平板横屏)是 Split 双栏:首页常驻左栏、个人中心出现在右栏,
    // "把页面从右边拖进来"这个隐喻不成立,视差还会把左栏整个推走。宽屏只留点头像入口。
    if (this.appIsWide || this.profileSwipeActive || this.profileSwipeSettling) {
      return;
    }
    this.profileSwipeActive = true;
    this.profileSwipeProgress = 0;
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.PROFILE, buildProfileRouteParam('homeSwipe')));
  }

  private handleProfileSwipeUpdate(progress: number): void {
    if (!this.profileSwipeActive) {
      return;
    }
    this.profileSwipeProgress = progress;
    this.profileSwipeProxy?.updateTransition?.(progress);
  }

  // 松手:过阈值或甩速够快就补完,否则回弹。两条路的收尾动画都由自绘 translate 播,
  // 时长/曲线见顶部三个常量。
  private handleProfileSwipeEnd(progress: number, velocity: number): void {
    if (!this.profileSwipeActive || this.profileSwipeSettling) {
      return;
    }
    const commit: boolean = progress >= SWIPE_COMMIT_RATIO || velocity >= SWIPE_COMMIT_VELOCITY;
    this.profileSwipeSettling = true;
    if (commit) {
      // 先自绘把页面推到满屏,推到位了再 finish。
      // 不能一松手就 finish——系统当场判定转场结束并撤掉 NavBar,而自绘动画还要再播 SWIPE_COMMIT_MS,
      // 这期间页面尚未盖满,露出的那条缝背后首页已经没了(表现为"背后首页突然消失")。
      this.settleProfileSwipe(1, SWIPE_COMMIT_MS, () => {
        this.profileSwipeProxy?.finishTransition();
      });
    } else {
      // 回弹走 finish+pop,不走 cancelTransition:
      //   cancelTransition 虽然能把栈回滚干净(栈深归 0),但会把 NavBar 的 eventHub 永久留在禁用态
      //   ——此后首页命中测试恒为空,上下滑/左滑/点击全死,只有渲染还在动(GIF 照转),极难察觉。
      //   系统日志实锤:"NavBar/12 eventHub not enabled" + "Touch test result is empty."
      //   而正常 POP 流程会把 eventHub 收拾干净,故绕道:让 push 落地再补一次 pop。
      // 顺序上先自绘把页面滑回屏外,滑到看不见了再 finish+pop——
      // finish 那一下页面会瞬间归位,把它藏在屏幕外,眼睛看到的全程才是平滑的。
      this.settleProfileSwipe(0, SWIPE_REBOUND_MS, () => {
        this.profileSwipeProxy?.finishTransition();
        this.navPathStack.pop(false);
      });
    }
  }

  // 把进度动画到 target,播完执行 after 并复位。
  // 注意:target 与当前进度相等时 animateTo 无状态变化,onFinish 不会触发——
  // 必须走同步分支,否则 active 永久卡 true、转场悬着不落地(下一次左滑直接失灵)。
  private settleProfileSwipe(target: number, duration: number, after: () => void): void {
    const finishUp: () => void = () => {
      after();
      this.profileSwipeSettling = false;
      this.profileSwipeActive = false;
      this.profileSwipeProgress = 0;
    };
    if (Math.abs(this.profileSwipeProgress - target) < 0.001) {
      finishUp();
      return;
    }
    this.getUIContext().animateTo({
      duration: duration,
      curve: SWIPE_SETTLE_CURVE,
      onFinish: finishUp
    }, () => {
      this.profileSwipeProgress = target;
    });
  }

  @Builder
  private NavDestinationBuilder(name: string, param: Object | undefined) {
    if (name === AppRouteName.TOPIC_DETAIL && isTopicDetailRouteParam(param)) {
      NavDestination() {
        TopicDetailPage({
          param: param as TopicDetailRouteParam,
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          // 待审帖卡片的作者信息:待审帖只有本人可见,服务端不下发作者字段,故用当前登录用户画头像昵称。
          currentUser: this.currentUser ?? this.getAnonymousUser(),
          onBack: () => {
            this.popNavigation();
          },
          // 顶栏过盾快捷入口:直接开验证页,并让恢复协调器停掉后台静默重试、把弹窗交给用户接管
          // (与首页空态「手动验证」同一路径),否则协调器可能正处于 DISMISSED 保持期而把弹窗吞掉。
          onOpenChallenge: () => {
            this.challengeRecovery?.forceEscalate();
            this.openChallengeSheet();
          },
          // 图片预览上抛到根级渲染:双栏下才能盖满整窗、旋转正常。
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.openImageViewer(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.handleOpenLink(url);
          },
          onOpenUser: (user: User) => {
            this.openUserProfileFor(user);
          }
        })
      }
      .hideTitleBar(true)
      // 详情页返回键优先消费本页内联浮层:全屏编辑器 > 图片预览。二者都从详情页打开、
      // Navigation 栈非空,返回键先到栈顶 NavDestination(轮不到 Index @Entry),不拦会直接弹掉详情页。
      .onBackPressed(() => this.consumeTopicDetailBack())
      // NavDestination 自身会铺满含状态栏区域，必须与详情页根背景使用同一专用资源；
      // 否则页面转场期间会短暂露出默认 page_bg，浅色下形成白色闪边。
      .backgroundColor($r('app.color.topic_detail_page_bg'))
    } else if (name === AppRouteName.WEB && isWebRouteParam(param)) {
      NavDestination() {
        WebViewPage({
          url: (param as WebRouteParam).url,
          pageTitle: (param as WebRouteParam).title ?? '',
          onBack: () => {
            this.popNavigation();
          },
          // 只有「我的站点」打开的页面才留 favicon(带 siteId);帖子外链的图标直接丢弃。
          onFaviconReceived: (favicon: image.PixelMap) => {
            this.cacheSiteFavicon((param as WebRouteParam).siteId, favicon);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.NOTIFICATIONS) {
      NavDestination() {
        NotificationPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, slug: string | undefined, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, slug, title, postNumber, postNumber !== undefined);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.PROFILE) {
      NavDestination() {
        ProfilePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          accountUser: this.currentUser ?? this.getAnonymousUser(),
          isLoggedIn: this.currentUser !== undefined,
          isCheckingSession: this.isCheckingSession,
          hasCheckedSession: this.hasCheckedSession,
          onLoginClick: () => {
            this.openLoginPage();
          },
          onOpenWeb: (url: string, title?: string) => {
            this.openWebPage(url, title);
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          },
          onOpenReadTopics: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.READ_TOPICS, buildReadTopicsRouteParam('profile')));
          },
          onOpenBookmarks: (username: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.BOOKMARKS, buildBookmarksRouteParam(username)));
          },
          onOpenDrafts: (username: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.DRAFTS, buildDraftsRouteParam(username)));
          },
          onLogoutCleanup: () => {
            return this.pushCoordinator.disableForLogout();
          },
          onLoggedOut: () => {
            this.applyLoggedOut();
          },
          onOpenActivity: (username: string, filter: string, title: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.ACTIVITY, buildActivityRouteParam(username, filter, title)));
          },
          onOpenBadges: (username: string, badgeCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.BADGES, buildBadgesRouteParam(username, badgeCount)));
          },
          onOpenSettings: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.SETTINGS, buildSettingsRouteParam('profile')));
          },
          onOpenLevelProgress: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.LEVEL_PROGRESS,
              buildLevelProgressRouteParam(this.currentUser !== undefined)));
          },
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
      // 左滑跟手时本页的位移。百分比相对自身宽度,不必测屏宽:progress=0 整页停在右侧屏外,=1 归位。
      // 手势闸关闭时恒 0,点头像那条路(系统默认转场)不受影响。
      .translate({ x: this.profileSwipeActive ? `${(1 - this.profileSwipeProgress) * 100}%` : 0 })
    } else if (name === AppRouteName.LEVEL_PROGRESS) {
      NavDestination() {
        LevelProgressPage({
          isLoggedIn: (param as LevelProgressRouteParam).isLoggedIn,
          useHostTitleBar: true,
          scroller: this.levelProgressScroller,
          onBack: () => {
            this.popNavigation();
          },
          onOpenWeb: (url: string, title?: string) => {
            this.openWebPage(url, title);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.SETTINGS) {
      NavDestination() {
        SettingsPage({
          onBack: () => {
            this.popNavigation();
          },
          onOpenUser: (username: string, displayName: string) => {
            this.openUserProfile(username, displayName, '', 0);
          },
          onOpenFeedback: () => {
            // 标题留空:详情页拉到帖子后自会填真实标题,不必在此硬编码一份易过期的副本。
            this.openTopicDetailById(LinuxDoConstants.FEEDBACK_TOPIC_ID);
          },
          onOpenForums: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.FORUMS, buildForumsRouteParam('settings')));
          },
          onOpenPush: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.PUSH_SETTINGS, buildPushSettingsRouteParam('settings')));
          },
          onOpenNetwork: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.NETWORK_SETTINGS, buildNetworkSettingsRouteParam('settings')));
          },
          onOpenExperimental: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.LAB_SETTINGS, buildLabSettingsRouteParam('settings')));
          },
          onOpenTopicListStyle: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.TOPIC_LIST_STYLE_SETTINGS,
              buildTopicListStyleSettingsRouteParam('settings')));
          },
          onOpenDiagnostics: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.DIAGNOSTICS_SETTINGS, buildDiagnosticsSettingsRouteParam('settings')));
          },
          // 与抽屉那条入口进的是同一个页面,只是来源标成 settings。
          // 站点页里的「在侧边栏显示入口」开关能把抽屉那条藏掉,所以这条路必须存在。
          onOpenSites: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.SITES, buildSitesRouteParam('settings')));
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.PUSH_SETTINGS) {
      NavDestination() {
        PushSettingsPage({
          currentUser: this.currentUser ?? this.getAnonymousUser(),
          isLoggedIn: this.currentUser !== undefined,
          onBack: () => {
            this.popNavigation();
          },
          onEnablePush: () => {
            return this.pushCoordinator.enable();
          },
          onDisablePush: () => {
            return this.pushCoordinator.disable();
          },
          onRefreshPush: () => {
            return this.pushCoordinator.refreshStatus();
          },
          onSendTestPush: () => {
            return this.pushCoordinator.sendTest();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.NETWORK_SETTINGS) {
      NavDestination() {
        NetworkSettingsPage({
          onBack: () => {
            this.popNavigation();
          },
          onOpenDoh: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.DOH_SETTINGS, buildDohSettingsRouteParam('settings')));
          },
          onActiveChallenge: () => {
            // 主动过盾:直接打开交互式 CF 验证 sheet(绕过协调器静默阶段),过盾后刷新会话。
            this.openChallengeSheet();
          }
        })
      }
      .hideTitleBar(true)
      // 从 DoH 配置页 pop 回来时本页重新可见,自增 AppStorage 计数,让网络页 @StorageProp 重读
      // DoH 摘要(此刻本页已在前台,变更能可靠触发重渲染;单纯 @Prop 不会流入 NavDestination 子树)。
      .onShown(() => {
        bumpTick(SETTINGS_DOH_TICK);
      })
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.LAB_SETTINGS) {
      NavDestination() {
        ExperimentalSettingsPage({
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.TOPIC_LIST_STYLE_SETTINGS) {
      NavDestination() {
        TopicListStyleSettingsPage({
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.DIAGNOSTICS_SETTINGS) {
      NavDestination() {
        DiagnosticsSettingsPage({
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.DOH_SETTINGS) {
      NavDestination() {
        DohSettingsPage({
          onBack: () => {
            this.popNavigation();
          },
          onDohApplied: () => {
            this.reloadHostForDoh();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.SITES) {
      NavDestination() {
        SitesPage({
          onBack: () => {
            this.popNavigation();
          },
          onOpenSite: (url: string, title: string, siteId: string) => {
            this.openWebPage(url, title, siteId);
          }
        })
      }
      .hideTitleBar(true)
      // 从站点的 WEB 页 pop 回来时本页重新可见,自增计数让站点页重读——favicon 此刻可能刚落盘。
      .onShown(() => {
        bumpTick(SITES_TICK);
      })
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.FORUMS) {
      NavDestination() {
        ForumsPage({
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.ACTIVITY && isActivityRouteParam(param)) {
      NavDestination() {
        ActivityListPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as ActivityRouteParam).username,
          filter: (param as ActivityRouteParam).filter,
          pageTitle: (param as ActivityRouteParam).title,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.READ_TOPICS) {
      NavDestination() {
        ReadTopicsPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onBack: () => {
            this.popNavigation();
          },
          onTopicClick: (topic: Topic) => {
            this.openTopicDetail(topic);
          },
          onOpenTopicAtPost: (topic: Topic, postNumber: number) => {
            this.openTopicDetailById(topic.id, topic.slug, topic.title, postNumber);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.BOOKMARKS && isBookmarksRouteParam(param)) {
      NavDestination() {
        BookmarksPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as BookmarksRouteParam).username,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.DRAFTS && isDraftsRouteParam(param)) {
      NavDestination() {
        DraftsPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as DraftsRouteParam).username,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string) => {
            this.openTopicDetailById(topicId, undefined, title, undefined, false);
          },
          onOpenTopicWithDraft: (topicId: number, title: string, draftReply: string, draftKey: string, sequence: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.TOPIC_DETAIL,
              buildTopicDetailDraftRouteParam(topicId, title, draftReply, draftKey, sequence)));
          },
          onOpenTopicWithEditDraft: (topicId: number, title: string, draftReply: string, draftKey: string,
            sequence: number, postId: number, originalText: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.TOPIC_DETAIL,
              buildTopicDetailEditDraftRouteParam(topicId, title, draftReply, draftKey, sequence, postId, originalText)));
          },
          onOpenWeb: (url: string, title: string) => {
            this.openWebPage(url, title);
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
      // 从帖子详情 pop 回来时本页重新可见:自增计数让草稿页重拉列表。
      // 续写发表后草稿已在服务端删除,不重拉的话返回时那条还挂在列表里(要手动下拉才消失)。
      .onShown(() => {
        bumpTick(DRAFTS_REFRESH_TICK_KEY);
      })
      // 续写浮层开着时返回键先关浮层,不 pop 掉草稿页。
      .onBackPressed(() => this.consumeDraftsBack())
    } else if (name === AppRouteName.BADGES && isBadgesRouteParam(param)) {
      NavDestination() {
        BadgesPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as BadgesRouteParam).username,
          badgeCount: (param as BadgesRouteParam).badgeCount,
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.USER_PROFILE && isUserProfileRouteParam(param)) {
      NavDestination() {
        UserProfilePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as UserProfileRouteParam).username,
          seedDisplayName: (param as UserProfileRouteParam).displayName ?? '',
          seedAvatarTemplate: (param as UserProfileRouteParam).avatarTemplate ?? '',
          seedUserId: (param as UserProfileRouteParam).userId ?? 0,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          },
          onOpenActivity: (username: string, filter: string, title: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.ACTIVITY, buildActivityRouteParam(username, filter, title)));
          },
          onOpenBadges: (username: string, badgeCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.BADGES, buildBadgesRouteParam(username, badgeCount)));
          },
          onOpenSolved: (username: string, solvedCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.SOLVED, buildSolvedRouteParam(username, solvedCount)));
          },
          // 互动圈头像可点:递归 push 同一路由,栈自然记住来路。
          onOpenUser: (username: string, displayName: string, avatarTemplate: string, userId: number) => {
            this.openUserProfile(username, displayName, avatarTemplate, userId);
          },
          onOpenWeb: (url: string, title?: string) => {
            this.openWebPage(url, title);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.SOLVED && isSolvedRouteParam(param)) {
      NavDestination() {
        SolvedPostsPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as SolvedRouteParam).username,
          solvedCount: (param as SolvedRouteParam).solvedCount,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.PLACEHOLDER) {
      // 双栏右详情栏的空占位:仅在宽屏未选帖子时垫在栈底,让右栏显示品牌空态而非系统默认空白。
      NavDestination() {
        Column() {
          Text('ArkDO')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
          Text('从左侧选择一个帖子开始阅读')
            .fontSize(15)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.page_bg'))
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.LDC_CREDIT && isLdcCreditRouteParam(param)) {
      NavDestination() {
        LdcCreditPage({
          startLogin: (param as LdcCreditRouteParam).startLogin,
          scroller: this.ldcCreditScroller,
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else {
      NavDestination() {
        Column() {
          Text('页面不存在')
            .fontSize(18)
            .fontColor($r('app.color.text_primary'))
          Button('返回')
            .margin({ top: 16 })
            .onClick(() => {
              this.popNavigation();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.page_bg'))
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    }
  }

  @Builder
  private RootSheetBuilder() {
    if (this.activeSheet === RootSheet.CHALLENGE) {
      CfChallengePage({
        bridge: this.bridge,
        onClose: () => {
          this.closeChallengePage();
        },
        onChallengeResolved: () => {
          this.handleChallengeResolved();
        }
      })
    } else {
      LoginPage({
        onClose: () => {
          this.closeLoginPage();
        },
        onLoginSuccess: () => {
          this.handleLoginSuccess();
        }
      })
    }
  }

  private rootSheetBlurStyle(): BlurStyle {
    return this.activeSheet === RootSheet.LOGIN ? BlurStyle.Regular : BlurStyle.NONE;
  }

  @Builder
  private HomeRoot() {
    HomePage({
      bridge: this.bridge,
      isArkWebReady: this.isArkWebReady,
      hostReadyEpoch: this.hostReadyEpoch,
      accountUser: this.currentUser ?? this.getAnonymousUser(),
      isLoggedIn: this.currentUser !== undefined,
      // 侧栏自选的标签/版块单独传:它们由会话检查与通知轮询两条链路更新,不跟 accountUser 走同一份状态。
      sidebarTags: this.sidebarTags,
      sidebarCategoryIds: this.sidebarCategoryIds,
      isCheckingSession: this.isCheckingSession,
      hasCheckedSession: this.hasCheckedSession,
      onAccountClick: () => {
        this.handleAccountClick();
      },
      // 左滑跟手拉出个人中心:手势在 HomePage,导航栈在这里,故三个阶段由它上抛给宿主驱动。
      onProfileSwipeStart: () => {
        this.handleProfileSwipeStart();
      },
      onProfileSwipeUpdate: (progress: number) => {
        this.handleProfileSwipeUpdate(progress);
      },
      onProfileSwipeEnd: (progress: number, velocity: number) => {
        this.handleProfileSwipeEnd(progress, velocity);
      },
      onSessionRecheck: () => {
        this.recheckSessionIfNeeded();
      },
      onOpenNotifications: () => {
        this.navPathStack.pushPath(new NavPathInfo(AppRouteName.NOTIFICATIONS, buildNotificationsRouteParam('homeBell')));
      },
      onOpenSearch: () => {
        this.openSearch();
      },
      onTopicClick: (topic: Topic) => {
        this.selectTopicFromMaster(topic.id, topic.slug, topic.title);
      },
      onOpenTopicById: (topicId: number, postNumber?: number) => {
        this.selectTopicFromMaster(topicId, undefined, undefined, postNumber, postNumber !== undefined);
      },
      onOpenTopicAtPost: (topic: Topic, postNumber: number) => {
        this.selectTopicFromMaster(topic.id, topic.slug, topic.title, postNumber);
      },
      onOpenSites: () => {
        this.navPathStack.pushPath(new NavPathInfo(AppRouteName.SITES, buildSitesRouteParam('drawer')));
      },
      onOpenSite: (url: string, title: string, siteId: string) => {
        this.openWebPage(url, title, siteId);
      }
    })
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    // 视差:跟手期间首页左移,补上自绘转场缺失的层次感
    // (系统默认转场自带这层,一旦用 customNavContentTransition 接管就得自己画,否则首页完全静止)。
    // 百分比相对自身宽度,不必测屏宽。手势闸关闭时恒复位,点头像那条路不受影响。
    //
    // 曾经这里还配了一笔 .brightness 压暗(幅度 0.08)。已移除:brightness 是颜色滤镜,即便手势不活动、
    // 值恒为 1,修饰符也常年挂在首页根节点上,让整棵首页子树走离屏合成——每次 pop 回首页的转场都要
    // 为此掉帧(首页列表越长越明显)。而那 8% 压暗只在跟手拖动的几百毫秒内、且首页仅露出左侧 25% 时
    // 可见,实测拿掉后观感无差别。日后若想把压暗找回来,别再用滤镜:改成仅 profileSwipeActive 期间
    // 挂载的半透明黑色浮层(opacity 跟 progress 走),静止态节点根本不在树上,零常驻成本。
    .translate({ x: this.profileSwipeActive ? `${-SWIPE_PARALLAX_RATIO * 100 * this.profileSwipeProgress}%` : 0 })
  }

  private openLoginPage(): void {
    // 弹层已开(CF 挑战/上一轮兜底)时不打断:与 openChallengeSheet/challenge-required 守卫一致。
    // 新接入的全局 LoginGate.requestLogin 可从任意深层页触发,防止覆盖正在进行的静默过盾。
    if (this.isSheetVisible) {
      return;
    }
    this.activeSheet = RootSheet.LOGIN;
    this.isSheetVisible = true;
  }

  private closeLoginPage(): void {
    this.isSheetVisible = false;
    this.activeSheet = RootSheet.NONE;
  }

  private closeChallengePage(): void {
    this.isSheetVisible = false;
    this.activeSheet = RootSheet.NONE;
  }

  private openTopicDetail(topic: Topic): void {
    this.openTopicDetailById(topic.id, topic.slug, topic.title);
  }

  // 按帖子 ID 跳转详情的通用入口(slug/title 可选,缺省时详情页按 id 加载)。
  // targetPostNumber:定位楼号(未读徽标/通知);highlightTarget:落地后短暂高亮目标楼(通知)。
  private openTopicDetailById(topicId: number, slug?: string, title?: string, targetPostNumber?: number, highlightTarget?: boolean): void {
    Log.i(`${LOG_TAG} open topic detail topicId=${topicId} title=${title ? title : ''} target=${targetPostNumber ?? 0}`);
    this.navPathStack.pushPath(new NavPathInfo(
      AppRouteName.TOPIC_DETAIL,
      buildTopicDetailRouteParam(topicId, slug, title ? title : '', targetPostNumber, highlightTarget)
    ));
  }

  // 左栏(navBar)发起的选帖。宽屏 Split 下左栏与右栏并排常驻、列表一直可点,若沿用 push
  // 就是每点一次往右栏摞一层([占位,详情,详情,…]),返回键要按十几次才退得出,且旧详情页
  // 连同各自的 Web / 公式引擎全悬着不释放。故宽屏改走「清回占位基座 + 压入新详情」:
  // 栈深恒为 2,点一百次也是 2,返回一次即回占位空态。
  // 窄屏(手机 / 平板竖屏)是 Stack 单栏,详情盖满屏、左栏根本点不到,原样 push,与改前完全一致。
  private selectTopicFromMaster(topicId: number, slug?: string, title?: string, targetPostNumber?: number, highlightTarget?: boolean): void {
    if (!this.appIsWide) {
      this.openTopicDetailById(topicId, slug, title, targetPostNumber, highlightTarget);
      return;
    }
    // 点的就是右栏正显示的那一帖 → 短路。否则白白重建详情页:Web 重载、滚动位置归零。
    if (this.isTopicOnTop(topicId, targetPostNumber)) {
      return;
    }
    Log.i(`${LOG_TAG} master select topicId=${topicId} target=${targetPostNumber ?? 0} depth=${this.navPathStack.size()}`);
    this.resetWideContentToPlaceholder();
    // 两次栈操作同帧合并,占位页拿不到渲染机会,不会闪;分栏换选中项本也不该有推入动效。
    this.navPathStack.pushPath(new NavPathInfo(
      AppRouteName.TOPIC_DETAIL,
      buildTopicDetailRouteParam(topicId, slug, title ? title : '', targetPostNumber, highlightTarget)
    ), false);
  }

  // 把右栏清成只剩占位基座。占位不在栈里(竖屏期间被 removeByName 清掉、转回横屏时 size()≠0
  // 未补垫的遗留栈)则就地重建——反正本就要整个换掉右栏内容,顺手自愈这条路径。
  private resetWideContentToPlaceholder(): void {
    const baseIndex: number = this.navPathStack.getAllPathName().indexOf(AppRouteName.PLACEHOLDER);
    if (baseIndex >= 0) {
      this.navPathStack.popToIndex(baseIndex, false);
    } else {
      this.navPathStack.clear(false);
      this.navPathStack.pushPathByName(AppRouteName.PLACEHOLDER, undefined, false);
    }
  }

  // 右栏栈顶是否已是目标帖。定位楼号也要一致——点未读徽标是要跳到另一楼,不算同一目标。
  private isTopicOnTop(topicId: number, targetPostNumber?: number): boolean {
    const names: string[] = this.navPathStack.getAllPathName();
    const topIndex: number = names.length - 1;
    if (topIndex < 0 || names[topIndex] !== AppRouteName.TOPIC_DETAIL) {
      return false;
    }
    const param: Object | undefined = this.navPathStack.getParamByIndex(topIndex) as Object | undefined;
    if (!isTopicDetailRouteParam(param)) {
      return false;
    }
    const top: TopicDetailRouteParam = param as TopicDetailRouteParam;
    return top.topicId === topicId && top.targetPostNumber === targetPostNumber;
  }

  // 统一的链接点击入口:经 LinkRouter 判断——站内帖子链接提取 topicId 跳原生详情页,
  // 站内用户主页链接(含正文 @提及)跳原生他人主页,其余(外站、站内其他页)一律打开通用 WebView。
  private handleOpenLink(url: string): void {
    const target: LinkTarget = LinkRouter.resolve(url);
    if (target.kind === LinkTargetKind.TOPIC && target.topicId !== undefined) {
      Log.i(`${LOG_TAG} link -> native topic detail topicId=${target.topicId}`);
      this.openTopicDetailById(target.topicId);
      return;
    }
    if (target.kind === LinkTargetKind.USER && target.username !== undefined) {
      Log.i(`${LOG_TAG} link -> native user profile username=${target.username}`);
      // 资料由主页自己按 username 拉,这里没有 displayName/头像可透传。
      this.openUserProfile(target.username, '', '', 0);
      return;
    }
    if (target.kind === LinkTargetKind.DOWNLOAD) {
      this.startDownload(target.url);
      return;
    }
    this.openWebPage(target.url);
  }

  /**
   * 跨论坛的推送:先切到通知所属的论坛,再跳。
   *
   * 不切的话,route.url 带的是 A 站的 topicId,而全 app 的接口地址指向 B 站 —— 要么打开
   * 一篇完全无关的帖子,要么 404。此前的行为是 resolveDiscoursePushUrl 直接把跨站地址判空、
   * route 作废,表现成「点通知毫无反应」:安全但等于功能缺失。
   *
   * 只切**用户自己添加过**的论坛。通知里声明的 host 不在列表里就不动 —— 那意味着用户已经
   * 把这个论坛删了(或订阅是别的设备留下的),擅自替他加回来不合适。
   *
   * 切站是异步的(要重建宿主 webview、清导航栈),所以这里不当场跳:把 route 留在 pending,
   * 切完之后由既有的「宿主就绪 → 消费 pending」那条通路接手。返回 true 表示已交给切站流程。
   */
  private redirectPushRouteToItsForum(route: PushNotificationRoute): boolean {
    const host: string = route.siteHost;
    if (host.length === 0 || host === AppConstants.HOST) {
      return false;
    }
    const context: common.Context = this.hostContext();
    const forums: ForumDef[] = ForumPrefs.getForums(context);
    let target: ForumDef | undefined = undefined;
    for (let index: number = 0; index < forums.length; index++) {
      if (SiteUrl.hostOf(forums[index].baseUrl) === host) {
        target = forums[index];
        break;
      }
    }
    if (!target) {
      Log.i(`${LOG_TAG} push route dropped: forum not in list host=${host}`);
      PushNotificationNavigationEventBus.clearPending(route.id);
      this.showToast(`通知来自 ${host}，该论坛已不在列表中`);
      return true;
    }
    Log.i(`${LOG_TAG} push route needs forum switch ${AppConstants.HOST} → ${host}`);
    // 不 clearPending:切站后要靠它把这次跳转接上。
    CurrentSite.switchTo(context, target);
    return true;
  }

  private handlePushNotificationRoute(route: PushNotificationRoute): void {
    if (this.redirectPushRouteToItsForum(route)) {
      return;
    }
    PushNotificationNavigationEventBus.clearPending(route.id);
    const target: LinkTarget = LinkRouter.resolve(route.url);
    Log.i(`${LOG_TAG} push route path=${describePushNotificationRoute(route)} kind=${target.kind}`);
    if (target.kind === LinkTargetKind.TOPIC && target.topicId !== undefined) {
      // 走 selectTopicFromMaster 而非 openTopicDetailById:宽屏(平板横屏)下它会先清回占位基座
      // 再压栈,栈深恒为 2。否则连点多条推送会把详情页一层层摞上去,要按同样次数返回键才退得出来,
      // 且每层的 Web/MathJax 引擎都悬着不释放。窄屏时它内部自动回退到 openTopicDetailById。
      this.selectTopicFromMaster(target.topicId, undefined, route.title, target.postNumber, target.postNumber !== undefined);
      // 点推送即视为已看这条通知:把它标为已读并把铃铛未读数减 1。即发即忘,不阻塞打开帖子。
      this.markPushNotificationRead(target.topicId, target.postNumber);
      return;
    }
    if (target.kind === LinkTargetKind.USER && target.username !== undefined) {
      this.openUserProfile(target.username, '', '', 0);
      return;
    }
    this.openWebPage(target.url, route.title);
  }

  // 点推送即视为看过这条通知:反查该帖对应通知并标记已读,同时把铃铛未读数乐观减 1。
  // 委托给 notificationService(它持有 bridge 与未读数总线)。即发即忘,不阻塞打开帖子。
  private markPushNotificationRead(topicId: number, postNumber?: number): void {
    this.notificationService.markPushNotificationRead(topicId, postNumber);
  }

  // 附件下载:交给 host webview 的原生下载委托(带会话 Cookie、跟随重定向)。结果经 DownloadEventBus 回调。
  private startDownload(url: string): void {
    const started: boolean = this.bridge.startDownload(url);
    if (started) {
      this.showToast('开始下载…');
    } else {
      this.showToast('无法下载：宿主未就绪');
    }
  }

  // 下载完成/失败:toast 反馈;成功则拉起系统「打开方式/分享」,弥补文件在沙箱内、系统「文件」App 不可见。
  private handleDownloadResult(result: DownloadResult): void {
    this.showToast(result.message);
    if (!result.success) {
      return;
    }
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context) {
      DownloadService.openWithSystem(context, result.filePath);
    }
  }









  private showToast(message: string): void {
    promptToast(this.getUIContext(), message);
  }

  private openWebPage(url: string, title?: string, siteId?: string): void {
    if (!url || url.length === 0) {
      return;
    }
    Log.i(`${LOG_TAG} open web page host=${url.replace(/^https?:\/\/([^\/?#]+).*$/i, '$1')}`);
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.WEB, buildWebRouteParam(url, title, siteId)));
  }

  // 缓存站点 favicon:仅对「我的站点」打开的页面(带 siteId)落盘,其余一律丢弃。
  // 引擎每次加载都会回调,故站点换 logo 后下次打开即自动更新。失败只记日志——图标是锦上添花,
  // 拿不到就回退默认图标,不该打扰用户。
  private cacheSiteFavicon(siteId: string | undefined, favicon: image.PixelMap): void {
    if (!siteId || siteId.length === 0) {
      return;
    }
    SiteIconStore.save(this.hostContext(), siteId, favicon);
  }

  private popNavigation(): void {
    this.navPathStack.pop();
  }

  // 宽<->窄切换时的右栏占位同步:
  //  · 宽屏(Split)且内容栈为空 → 垫入 PLACEHOLDER 当栈底,右栏显示品牌空态而非系统空白;
  //    垫在栈底后,后续打开的帖子 push 在其上,返回到底即回到占位,不会退成空白。
  //  · 窄屏(Stack / 手机)→ 移除所有 PLACEHOLDER,保证手机返回栈干净、绝不出现占位页。
  private onWideChanged(): void {
    this.syncWidePlaceholder();
  }

  private syncWidePlaceholder(): void {
    if (this.appIsWide) {
      if (this.navPathStack.size() === 0) {
        // 无动画压入,避免占位页出现时的推入动效。
        this.navPathStack.pushPathByName(AppRouteName.PLACEHOLDER, undefined, false);
      }
    } else {
      this.navPathStack.removeByName(AppRouteName.PLACEHOLDER);
    }
  }

  // 图片浏览器开关:详情页经 onOpenImages 回调冒泡上来触发。开关场动效在 ImageViewer 内部
  // (hero 从列表原位飞入 / 飞回,拿不到源节点几何时降级淡入淡出),这里只负责挂载与卸载。
  // 窗口常驻全屏布局(ImmersiveWindow),浮层在 Navigation 之外天然铺满物理屏——无须切窗口模式、
  // 无须背景补偿。这里只做一件窗口级小事:预览期间隐藏状态栏(时间/电量不印在图上),关闭时恢复。
  //
  // 隐藏/恢复的时机要卡在「浮层已经盖满屏」的窗口内(onCovered / onRevealing),不能跟着
  // 挂载卸载走:详情页标题栏是 HdsNavigation,开了 avoidLayoutSafeArea 会实时读系统安全区,
  // 状态栏一隐藏它就自己往上塌一个状态栏高度——这个重排 suppressInsetSync 管不着
  // (那只冻结喂给内容 spacer 的 AppStorage 镜像),只能靠不透明黑底盖住它发生的那一帧。
  private openImageViewer(images: ViewerImage[], startIndex: number): void {
    this.viewerImages = images;
    this.viewerStartIndex = startIndex;
    // 镜像可见态:预览打开期间系统返回键由 Index @Entry 拦截(翻回上一张/首图关闭)。
    AppStorage.setOrCreate(IMAGE_VIEWER_VISIBLE_KEY, true);
    // 先暂停插图同步,之后隐藏状态栏的归零事件不落到背景 padding 上。
    ImmersiveWindow.suppressInsetSync(true);
    // 窗口引用先拿着(异步),等入场动效放完再真正动系统栏。
    window.getLastWindow(this.hostContext()).then((win: window.Window) => {
      this.viewerWindow = win;
    }).catch(() => {});
    // 直接挂载,不套动画:hero 飞入由 ImageViewer 自己跑(它首帧就渲染成源图大小)。
    this.showImageViewer = true;
  }

  // 入场动效已放完、黑底铺满:此刻才隐藏状态栏,底层标题栏的塌陷藏在黑底底下。
  private onImageViewerCovered(): void {
    const win: window.Window | undefined = this.viewerWindow;
    if (win === undefined || this.viewerBarHidden) {
      return;
    }
    this.viewerBarHidden = true;
    win.setWindowSystemBarEnable(['navigation']).catch(() => {});
    // 底部手势条图标改白,黑底上可见。
    win.setWindowSystemBarProperties({
      navigationBarContentColor: '#FFFFFF'
    }).catch(() => {});
  }

  // 退场动效即将开始、黑底还满着:趁现在把状态栏还回去,标题栏塌回原位那一帧同样被盖住。
  // 入场动效没放完就被关掉时 viewerBarHidden 还是 false,这里什么都不用做。
  private onImageViewerRevealing(): void {
    const win: window.Window | undefined = this.viewerWindow;
    if (win === undefined || !this.viewerBarHidden) {
      return;
    }
    this.viewerBarHidden = false;
    // 恢复状态栏显示;图标色统一走 ImmersiveWindow 按当前主题基线恢复。
    win.setWindowSystemBarEnable(['status', 'navigation']).catch(() => {});
    const dark: boolean = (AppStorage.get(APP_IS_DARK_STORAGE_KEY) as boolean | undefined) ?? false;
    ImmersiveWindow.applyBarContentColor(dark);
  }

  // 详情页返回键统一入口:先看全屏编辑器浮层(可见则 bump tick 交详情页一镜回落),再看图片预览。
  // 都没开返回 false 放行默认 pop(弹掉详情页)。挂在详情页 NavDestination 的 onBackPressed 上。
  // 草稿页的续写浮层打开时消费返回键(bump tick 让 DraftsPage 关浮层);未开则放行默认 pop。
  private consumeDraftsBack(): boolean {
    const visible: boolean = (AppStorage.get(DRAFTS_COMPOSER_VISIBLE_KEY) as boolean | undefined) ?? false;
    if (visible) {
      bumpTick(DRAFTS_COMPOSER_BACK_TICK_KEY);
      return true;
    }
    return false;
  }

  private consumeTopicDetailBack(): boolean {
    const composerVisible: boolean = (AppStorage.get(COMPOSER_OVERLAY_VISIBLE_KEY) as boolean | undefined) ?? false;
    if (composerVisible) {
      bumpTick(COMPOSER_OVERLAY_BACK_TICK_KEY);
      return true;
    }
    if (this.consumeViewerBack()) {
      return true;
    }
    return false;
  }

  // 图片预览打开时消费返回键:bump 信号计数,交 ImageViewer 决定翻回上一张还是关闭;
  // 未打开时返回 false 放行默认 pop。挂在详情页 NavDestination 的 onBackPressed 上。
  private consumeViewerBack(): boolean {
    if (!this.showImageViewer) {
      return false;
    }
    bumpTick(IMAGE_VIEWER_BACK_TICK_KEY);
    return true;
  }

  private closeImageViewer(): void {
    AppStorage.setOrCreate(IMAGE_VIEWER_VISIBLE_KEY, false);
    // 常规路径下状态栏已在 onRevealing 还回去了;这里兜底,防止某条路径没走到那一步就卸载。
    this.onImageViewerRevealing();
    this.viewerWindow = undefined;
    // 恢复插图同步:状态栏重新出现触发的 avoidAreaChange 会把插图写回(与预览前同值,padding 不动)。
    ImmersiveWindow.suppressInsetSync(false);
    // onClose 由 ImageViewer 在退场动效播完后才回调,这里直接卸载即可。
    this.showImageViewer = false;
  }

  // 搜索 Flow 开关:根 Stack 覆盖层负责首页搜索图标 -> 搜索页图标的一镜到底;
  // 搜索结果 -> 详情 -> Web 由 SearchFlow 内部 Navigation 承载,不进入主 Navigation 栈。
  private openSearch(): void {
    if (this.showSearchFlow) {
      return;
    }
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, () => {
      AppStorage.setOrCreate(SEARCH_OVERLAY_VISIBLE_KEY, true);
      this.searchFlowMounted = true;
      this.showSearchFlow = true;
    });
  }

  private closeSearch(): void {
    if (!this.searchFlowMounted) {
      return;
    }
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.Friction,
      onFinish: () => {
        if (!this.showSearchFlow) {
          this.searchFlowMounted = false;
        }
      }
    }, () => {
      AppStorage.setOrCreate(SEARCH_OVERLAY_VISIBLE_KEY, false);
      this.showSearchFlow = false;
    });
  }

  private handleArkWebReady(): void {
    this.isArkWebReady = true;
    // 宿主真就绪:清掉失败态,网络恢复监听回到静默(仅在下次真失败时才再介入)。
    this.hostLoadFailed = false;
    // 宿主真就绪:自增信号驱动首页重拉列表。看门狗/失败路径已提前把 isArkWebReady 置真、烧掉了
    // false→true 跳变,单靠 @Watch(isArkWebReady) 无法在真就绪时唤醒列表(会卡在失败态直到手点重试);
    // 这个独立计数专门补上「真就绪 → 自愈列表」这条路径。
    this.hostReadyEpoch++;
    // 注入沙箱上下文,让 host webview 的下载委托知道文件保存目录(filesDir/download)。
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context) {
      this.bridge.setDownloadContext(context);
    }
    this.checkCurrentUser();
  }

  // 宿主首屏加载失败(DoH 关 + 无代理导致 linux.do 不可达):强制解锁 UI 进入降级可导航态——
  // 首页跳出"准备环境中"、汉堡菜单出现、头像退化为可点的人像入口,用户得以进设置页开 DoH/代理自救。
  // 不必干等 DNS/连接超时(可长达 30s+)。开启 DoH 后 SessionEventBus 触发宿主重载,成功即走 onReady
  // 正常刷新列表与登录态(reloadBaseUrl 已改判 isControllerAttached,首屏失败后仍能重载)。
  private handleArkWebLoadFailed(): void {
    if (this.isArkWebReady) {
      return;
    }
    Log.i(`${LOG_TAG} ArkWeb host load failed: unblock UI so user can reach DoH settings`);
    this.isArkWebReady = true;
    // 标记失败态:此后网络恢复(netAvailable / netCapabilitiesChange)会触发一次宿主重载自愈。
    this.hostLoadFailed = true;
    this.checkCurrentUser();
  }

  private ensureIconSymbolsLoaded(): void {
    const hostContext: Context | undefined = this.getUIContext().getHostContext();
    if (!hostContext) {
      Log.i(`${LOG_TAG} icon symbols load skipped: no host context`);
      return;
    }

    const iconCount: number = ensureFaIconsLoaded(hostContext.resourceManager);
    const tagIconCount: number = ensureTagIconsLoaded(hostContext.resourceManager);
    Log.i(`${LOG_TAG} icon assets loaded symbols=${iconCount} tagIcons=${tagIconCount}`);
  }

  private handleLoginSuccess(): void {
    // 会话变化会触发 host webview 重载,先关闭就绪门闩,确保随后并发的 fetch 排队到重载完成后。
    this.bridge.markHostReloading();
    // RootTabPage 自身订阅了 SessionEventBus,通知后会统一排队检查当前会话。
    SessionEventBus.notifySessionChanged();
    this.closeLoginPage();
  }

  // DoH 变更(切换/开关/删除当前项)后重载宿主 webview,让新 DNS 立即用于解析。
  // 复用会话变更的重载门闩:先关就绪门闩,让并发 fetch 排队到重载完成。
  private reloadHostForDoh(): void {
    this.bridge.markHostReloading();
    SessionEventBus.notifySessionChanged();
  }

  // 订阅网络状态。netAvailable=连上新网络(飞行模式关/切 Wi-Fi);
  // netCapabilitiesChange=网络能力变化(出隧道后内网校验通过,信号一直在但数据恢复的场景靠它)。
  // 两者都只在宿主处于失败态时才触发重载,故正常在线启动/切网不受影响。
  private startNetworkRecoveryWatch(): void {
    if (this.netConnection) {
      return;
    }
    try {
      const netCon: connection.NetConnection = connection.createNetConnection();
      netCon.on('netAvailable', (_netHandle: connection.NetHandle) => {
        this.handleNetworkRecovered('netAvailable');
      });
      netCon.on('netCapabilitiesChange', (_info: connection.NetCapabilityInfo) => {
        this.handleNetworkRecovered('netCapabilitiesChange');
      });
      netCon.register((error: BusinessError) => {
        if (error) {
          Log.i(`${LOG_TAG} net connection register failed code=${error.code}`);
        }
      });
      this.netConnection = netCon;
    } catch (error) {
      Log.i(`${LOG_TAG} net connection watch start failed error=${JSON.stringify(error)}`);
    }
  }

  private stopNetworkRecoveryWatch(): void {
    if (!this.netConnection) {
      return;
    }
    const netCon: connection.NetConnection = this.netConnection;
    this.netConnection = undefined;
    try {
      netCon.unregister((error: BusinessError) => {
        if (error) {
          Log.i(`${LOG_TAG} net connection unregister failed code=${error.code}`);
        }
      });
    } catch (error) {
      Log.i(`${LOG_TAG} net connection watch stop failed error=${JSON.stringify(error)}`);
    }
  }

  // 网络恢复:仅当宿主此前加载失败(冷启动即离线是唯一无自动重连入口的场景)才重载一次宿主,
  // 一并把 MessageBus 与全站数据救回来。冷却窗口内的重复上报忽略,避免网络抖动反复重载。
  private handleNetworkRecovered(source: string): void {
    if (!this.hostLoadFailed) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastNetRecoveryReloadTs < NET_RECOVERY_RELOAD_COOLDOWN_MS) {
      return;
    }
    this.lastNetRecoveryReloadTs = now;
    // 网络已回,允许启动会话检查那条自愈重载后续再次生效。
    this.hasSelfHealedNetwork = false;
    Log.i(`${LOG_TAG} network recovered (${source}), reload host to recover failed cold start`);
    this.reloadHostForDoh();
  }

  private handleAccountClick(): void {
    // 登录与否都进个人中心:未登录时该页仍有齿轮(设置→DoH)和登录入口,
    // 避免网络不通时点右上角直接弹登录、够不到 DoH 配置而被卡在门外。
    this.openProfilePage();
  }

  private openProfilePage(): void {
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.PROFILE, buildProfileRouteParam('homeAvatar')));
  }

  // 他人主页:点任意头像(帖子作者、互动圈、通知等)进来。
  // displayName/avatarTemplate 由调用方顺手透传,资料请求回来前先渲染,避免首屏跳动。
  // 点自己的头像不进这里——「我的」页有登出/设置/草稿,是另一个页面。
  private openUserProfile(username: string, displayName: string, avatarTemplate: string, userId: number): void {
    if (username.length === 0) {
      return;
    }
    if (this.currentUser !== undefined && username === this.currentUser.username) {
      this.openProfilePage();
      return;
    }
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.USER_PROFILE,
      buildUserProfileRouteParam(username, displayName, avatarTemplate, userId)));
  }

  // 从 User 对象开头像入口:各处调用点手里拿的都是 User,省得每处都拆字段。
  private openUserProfileFor(user?: User): void {
    if (!user || user.username.length === 0) {
      return;
    }
    this.openUserProfile(user.username, user.displayName ? user.displayName : '',
      user.avatarTemplate ? user.avatarTemplate : '', user.id);
  }

  private getAnonymousUser(): User {
    return {
      id: 0,
      username: ''
    };
  }

  // 删除接口已确认成功，直接更新唯一的共享角标数；会话接口可能短暂返回删除前的缓存值，
  // 因此这里不立即重查 /session/current.json。
  private handleDraftDeleted(draftKey: string): void {
    const storedCount: number | undefined = AppStorage.get<number>(PROFILE_DRAFT_COUNT_KEY);
    const draftCount: number = storedCount !== undefined ? storedCount : (this.currentUser?.draftCount ?? 0);
    const nextDraftCount: number = Math.max(0, draftCount - 1);
    AppStorage.setOrCreate(PROFILE_DRAFT_COUNT_KEY, nextDraftCount);
    Log.i(`${LOG_TAG} draft count updated key=${draftKey} ${draftCount}->${nextDraftCount}`);
  }

  // 登出已被服务端确认(DELETE /session/{username} 返回 2xx)时的本地清态。
  // 不等随后的 /session/current.json 复查:那一次若撞上 CF 盾或断网会走「失败保留上一次登录态」
  // 的兜底,登录态就卡在已经不存在的会话上。DELETE 成功即事实,本地直接落地。
  // 同时作废进行中的会话检查——它可能是登出前发出的,回来会把旧账号又写回去。
  private applyLoggedOut(): void {
    this.sessionCheckSequence++;
    this.sessionCheckQueued = false;
    this.lastSessionCheckFailed = false;
    this.currentUser = undefined;
    this.applySidebarPrefs(undefined);
    LoginGate.setLoggedIn(false);
    AppStorage.setOrCreate(PROFILE_DRAFT_COUNT_KEY, 0);
    this.notificationService.stop();
    // 登出:清掉自愈基准,让下一个账号登录时重新兑现自己的订阅。
    this.pushCoordinator.resetReconcileState();
    Log.i(`${LOG_TAG} logged out locally applied`);
  }

  private async checkCurrentUser(): Promise<void> {
    if (!this.isArkWebReady) {
      return;
    }

    const requestId: number = this.sessionCheckSequence + 1;
    this.sessionCheckSequence = requestId;
    if (this.isCheckingSession) {
      // 新的会话事件已经发生:递增后的 requestId 会让旧请求返回时放弃写状态。
      this.sessionCheckQueued = true;
      return;
    }

    this.isCheckingSession = true;
    this.hasCheckedSession = false;
    const result: NetworkResult<User | undefined> = await new AuthService(this.bridge).getCurrentUser();
    if (requestId !== this.sessionCheckSequence) {
      this.isCheckingSession = false;
      this.startQueuedSessionCheckIfNeeded();
      return;
    }

    this.isCheckingSession = false;
    this.hasCheckedSession = true;
    if (result.success) {
      this.lastSessionCheckFailed = false;
      // 连接恢复,复位自愈闸,允许下一段网络故障再自愈一次。
      this.hasSelfHealedNetwork = false;
      this.currentUser = result.data;
      // 侧栏自选数据跟着这次权威结果走(登出时 result.data 为空 → 一并清空,下一个账号不会看到上一个的)。
      this.applySidebarPrefs(result.data);
      AppStorage.setOrCreate(PROFILE_DRAFT_COUNT_KEY,
        this.currentUser?.draftCount !== undefined ? this.currentUser.draftCount : 0);
      // 同步全局登录态镜像:供深层页面/楼层动作的写操作闸门(LoginGate)读取。
      LoginGate.setLoggedIn(this.currentUser !== undefined);
      Log.i(`${LOG_TAG} current user checked loggedIn=${this.currentUser !== undefined} username=${this.currentUser?.username ?? ''} hasAvatar=${this.currentUser?.avatarTemplate !== undefined}`);
      // 登录:本次响应已带未读数,立即广播一次(铃铛与头像同帧出现),再启动前台轮询;
      // 登出:停表并清零。
      if (this.currentUser !== undefined) {
        NotificationEventBus.publish({
          unread: this.currentUser.unreadNotifications !== undefined ? this.currentUser.unreadNotifications : 0,
          highPriority: this.currentUser.unreadHighPriorityNotifications !== undefined ? this.currentUser.unreadHighPriorityNotifications : 0
        });
        this.notificationService.start();
        // 登录态已落定:此刻才拿得到 userId,兑现该账号此前开过的推送订阅(保活/自愈)。
        // 内部按账号去重,不会每轮轮询都跑。
        this.pushCoordinator.reconcile(false);
        // 会话检查刚成功 = 刚发过请求,内存里几乎必是服务端最新轮换的 `_t`;顺手落盘一次,
        // 堵住「前台长时间停留、宿主一直没重载」时磁盘 `_t` 落后于内存的窗口。与退后台保存互补。
        WebSessionManager.saveCookies('sessionCheck');
      } else {
        this.notificationService.stop();
        // 登出/换号:清掉自愈基准,让下一个账号登录时重新兑现自己的订阅。
        this.pushCoordinator.resetReconcileState();
      }
      this.startQueuedSessionCheckIfNeeded();
      return;
    }

    // 检查失败(CF 盾/网络抖动)≠确认未登录:保持上一次的登录状态与通知轮询不动,
    // 仅记失败标记,等下一次下拉刷新时补查。只有成功响应且 current_user 为空才真正置为未登录。
    this.lastSessionCheckFailed = true;
    Log.i(`${LOG_TAG} current user check failed status=${result.statusCode} challenge=${result.challengeState}, keep previous loggedIn=${this.currentUser !== undefined}`);

    // 长时间后台回前台后,宿主 webview 的连接/DNS 解析器可能已僵死:表现为 status=0 的纯网络
    // 失败(error=network_failure),且非 CF 盾(challengeState=NONE)。这条旧连接自己不会恢复,
    // 再怎么用它重查都白搭;重载一次宿主拿一条全新连接(等价于用户手动切 DoH 触发的重载)。
    // reloadHostForDoh 会同步 bump 会话版本 → handleSessionChanged → 宿主重载完再自动重查,
    // 无需在此显式重查。每段失败只自愈一次,重载后仍失败就退回既有兜底,不再循环重载。
    const isNetworkFailure: boolean =
      result.error?.code === NetworkErrorCode.NETWORK_FAILURE &&
      result.challengeState === ChallengeState.NONE;
    if (isNetworkFailure && !this.hasSelfHealedNetwork) {
      this.hasSelfHealedNetwork = true;
      Log.i(`${LOG_TAG} network failure self-heal: reload host and recheck`);
      this.reloadHostForDoh();
    }
    this.startQueuedSessionCheckIfNeeded();
  }

  private startQueuedSessionCheckIfNeeded(): void {
    if (!this.sessionCheckQueued) {
      return;
    }
    this.sessionCheckQueued = false;
    // 让当前响应先完成状态写入,再启动最新检查,避免递归叠加。
    setTimeout(() => {
      this.checkCurrentUser();
    }, 0);
  }

  /**
   * 通知轮询顺路带回来的 current_user 快照。只取侧栏自选的标签与版块,其余一概不动。
   *
   * 三条约束,少一条都会踩到会话链路:
   *  · **绝不碰登录态**。轮询是静默链路(不走 checkCurrentUser,否则头像每轮闪一次 loading),
   *    它发现真登出时走 SessionEventBus 让本页重查;这里连 currentUser 都不写。
   *  · 只在本页已认定登录、且账号 id 对得上时采纳。换号瞬间可能收到旧账号的在途快照,
   *    id 一对就挡住了。
   *  · 会话检查在飞时让路:那条链路的结果更权威,不与它抢同一份状态。
   *
   * 未读数不在这里处理:它有自己的总线(NotificationEventBus),轮询早就发过了。
   * 草稿数也不碰:删草稿是本地乐观递减的,服务端那个值可能还是删之前的缓存(见 handleDraftDeleted)。
   */
  private applyCurrentUserSnapshot(user: User): void {
    const current: User | undefined = this.currentUser;
    if (current === undefined || this.isCheckingSession || current.id !== user.id) {
      return;
    }
    this.applySidebarPrefs(user);
  }

  // 侧栏自选数据落地。两条链路(会话检查 / 静默快照)共用,数组整体替换才能触发 @State 更新。
  private applySidebarPrefs(user?: User): void {
    this.sidebarTags = user?.sidebarTags !== undefined ? user.sidebarTags : [];
    this.sidebarCategoryIds = user?.sidebarCategoryIds !== undefined ? user.sidebarCategoryIds : [];
  }

  // 下拉刷新时的会话补查:仅在上次检查失败(状态可能不真实)时重查一次,正常情况零开销。
  private recheckSessionIfNeeded(): void {
    if (this.lastSessionCheckFailed && !this.isCheckingSession) {
      Log.i(`${LOG_TAG} recheck session after previous failure`);
      this.checkCurrentUser();
    }
  }

  /**
   * 切站。三件事,顺序不能反:
   *
   * 1. 先清导航栈。栈里可能还压着旧站的帖子详情/用户主页,那些 id 在新站上要么不存在、
   *    要么指向另一篇完全无关的帖子 —— 必须在任何新请求发出前清掉,否则用户返回时会看到
   *    一个用新站数据渲染的旧站页面。
   * 2. 再做切站善后(清缓存、重置登录判断位、重下发 DoH、重载宿主 webview)。
   * 3. 最后广播会话变更,让复查登录态与列表刷新按既有链路跑一遍 —— 与过盾恢复复用同一条路。
   */
  private handleSiteChanged(): void {
    Log.i(`${LOG_TAG} site changed → ${CurrentSite.baseUrl} epoch=${CurrentSite.epoch}`);
    // 先丢弃正在进行的过盾:它在探测旧站,且会把「恢复中」状态带到新站,吞掉新站的第一个
    // 挑战信号。排在最前面还有个好处——它内部会还原持久化的 DoH 模式,之后 afterSwitch
    // 再按新站重下发一次,顺序正好。
    this.challengeRecovery?.resetForSiteSwitch();
    this.navPathStack.clear();
    SiteSwitchCoordinator.afterSwitch(this.hostContext(), this.bridge);
    SessionEventBus.notifySessionChanged();
    // 若这次切站是被跨论坛的推送点击触发的,pending 里还留着那条跳转 —— 现在地址已指向
    // 目标论坛,把它接上。放在最后:前面刚清过导航栈,更早跳会被一起清掉。
    const pendingPush: PushNotificationRoute | undefined = PushNotificationNavigationEventBus.takePending();
    if (pendingPush) {
      Log.i(`${LOG_TAG} resume push route after forum switch path=${describePushNotificationRoute(pendingPush)}`);
      this.handlePushNotificationRoute(pendingPush);
    }
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    this.checkCurrentUser();
  }

  private handleChallengeRequired(event: ChallengeRequiredEvent): void {
    if (event.version <= this.handledChallengeVersion) {
      return;
    }

    this.handledChallengeVersion = event.version;
    Log.i(`${LOG_TAG} challenge required version=${event.version} source=${event.source} status=${event.statusCode} state=${event.challengeState}`);
    Log.i(`${DIAG_TAG} stage=rootChallengeRequired version=${event.version} source=${event.source} status=${event.statusCode} state=${event.challengeState} activeSheet=${this.activeSheet} sheetVisible=${this.isSheetVisible}`);
    // 弹窗已开(登录/上一轮兜底)时不再打扰;其余交给协调器决定静默恢复还是升级弹窗。
    if (this.isSheetVisible) {
      return;
    }
    this.challengeRecovery?.handleChallengeSignal(event.source);
  }

  // 协调器升级:静默两次失败后才打开交互式挑战弹窗兜底。
  private openChallengeSheet(): void {
    if (this.isSheetVisible) {
      return;
    }
    this.activeSheet = RootSheet.CHALLENGE;
    this.isSheetVisible = true;
    Log.i(`${DIAG_TAG} stage=rootChallengeOpen`);
  }

  private handleChallengeResolved(): void {
    Log.i(`${LOG_TAG} challenge resolved`);
    Log.i(`${DIAG_TAG} stage=rootChallengeResolved sheetVisible=${this.isSheetVisible}`);
    // 先进冷却再关窗:onDisappear 的 notifySheetDismissed 在冷却态下即为空操作。
    this.challengeRecovery?.notifySheetResolved();
    // 盾已过:收起详情页右上角的过盾快捷入口(不等下一次 timings 上报成功才收,免得图标空挂着)。
    ChallengeShortcutEventBus.notifyCleared();
    this.closeChallengePage();
    // 反馈:已过盾时验证页会秒关(源站 404 即通过),给个 toast 免得用户以为闪退/没反应。
    this.showToast('已通过 Cloudflare 验证');
  }
}
