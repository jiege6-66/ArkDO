import { Log } from '../../services/logging/Log';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { TopicCategory } from '../../models/Topic';
import { TopicMetadataBadges } from '../components/TopicBadges';
import { User } from '../../models/User';
import {
  UserActionType,
  UserActivityItem,
  UserBadgeItem,
  UserProfileDetail,
  UserSummary,
  UserSummaryStats
} from '../../models/UserProfile';
import { AppRouteName, buildLdcCreditRouteParam } from '../../navigation/AppRoutes';
import { LdcUserInfo } from '../../models/LdcCredit';
import { AuthService } from '../../services/auth/AuthService';
import { LdcCreditEventBus } from '../../services/credit/LdcCreditEventBus';
import { LdcCreditService } from '../../services/credit/LdcCreditService';
import { LdcCreditSession } from '../../services/credit/LdcCreditSession';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { LdcCreditWebHost } from '../components/LdcCreditWebHost';
import { SiteCapabilities } from '../../services/site/SiteCapabilities';
import { formatLdcAmount } from '../../common/utils/LdcFormat';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { UserProfileCache } from '../../services/user/UserProfileCache';
import { UserProfileService } from '../../services/user/UserProfileService';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { BadgeTile } from '../components/BadgeTile';
import { UserAvatar } from '../components/UserAvatar';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { showToast as promptToast } from '../../common/utils/Toast';
import { badgeHeadLabel, badgeRowFillers, badgeRowsOf, daysSince, formatCount, formatTimeRead, trustLabelWithTitleOf } from '../../common/utils/ProfileFormat';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';
import { ACTIVE_FORUM_NAME_KEY, PROFILE_DRAFT_COUNT_KEY } from '../../common/constants/StorageKeys';

const LOG_TAG: string = '[ArkDO][Profile]';

// Discourse 信任等级中文名(0-4),user.title 缺省时的兜底展示。

// 鸿蒙设置页式卡片分组:灰底 + 无描边圆角卡片。
// 页面两侧留白 12,卡片圆角 16,卡片内部留白 16,卡片间距 12。
// 统计区固定高度:加载占位与 4×2 数据网格同高,避免数据回来后卡片长高跳动。
const STATS_AREA_HEIGHT: number = 126;
// 用户卡 meta 行(加入天数/最近发帖/浏览量)固定高度,同理防跳动。
const USER_META_HEIGHT: number = 26;

// LDC 入口行的取数状态。credit.linux.do 的会话与 linux.do 各自独立:linux.do 已登录不代表
// credit 也登录,故 ANON 是常态而非异常,要给出「去登录」而不是错误提示。
enum LdcEntryPhase {
  LOADING = 0,
  READY = 1,
  ANON = 2,
  ERROR = 3
}

@Component
export struct ProfilePage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  @StorageProp(PROFILE_DRAFT_COUNT_KEY) private draftCount: number = 0;
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  // 登录态由 RootTabPage 统一维护(会话事件 + 前台轮询),本页只接收,不再自己查
  // /session/current.json——否则每次 push 进来都闪一次「检查登录状态」。
  @Prop @Watch('handleAccountChanged') accountUser: User = { id: 0, username: '' };
  @Prop @Watch('handleAccountChanged') isLoggedIn: boolean = false;
  @Prop isCheckingSession: boolean = false;
  @Prop hasCheckedSession: boolean = false;
  // 当前论坛名镜像:未登录态要显示「登录哪个论坛」。
  @StorageProp(ACTIVE_FORUM_NAME_KEY) private activeForumName: string = '';
  onLoginClick: () => void = () => {};
  // 打开站内 Web 页(草稿等尚未原生化的入口)与原生帖子详情,由 RootTabPage 注入。
  onOpenWeb: (url: string, title?: string) => void = () => {};
  onOpenTopic: (topicId: number, title: string, postNumber?: number) => void = () => {};
  // 已读帖子列表(/read.json):当前登录用户读过的主题,无需用户名。
  onOpenReadTopics: () => void = () => {};
  // 书签已原生化:进原生书签页而非 Web。
  onOpenBookmarks: (username: string) => void = () => {};
  // 草稿已原生化:进原生草稿页而非 Web。
  onOpenDrafts: (username: string) => void = () => {};
  // 登出前的系统推送清理(退订 linux.do + 解绑中继)。由 RootTabPage 注入,必须在 logout
  // 请求之前 await 完:登出后没了登录 cookie 就退不掉订阅,本机会继续收到该账号的推送。
  onLogoutCleanup: () => Promise<void> = async () => {};
  // 服务端已确认登出后的本地清态(清 currentUser / 登录态镜像 / 通知轮询 / 推送基准),由 RootTabPage
  // 注入。不靠随后的会话复查:那一次若遇 CF 盾或断网会走「失败保留上一次登录态」兜底,登录态就卡死。
  onLoggedOut: () => void = () => {};
  // 用户动态列表(我的话题/回复/点赞/最近活动全部)已原生化:filter 见 UserActionType。
  onOpenActivity: (username: string, filter: string, title: string) => void = () => {};
  // 全部徽章页已原生化:数据取自 /user-badges/{username}.json。
  onOpenBadges: (username: string, badgeCount: number) => void = () => {};
  // 设置与诊断日志已拆到独立设置页,右上角齿轮入口触发。
  onOpenSettings: () => void = () => {};
  // 点击信任等级标进入原生等级进度页(数据取自 connect.linux.do)。
  onOpenLevelProgress: () => void = () => {};
  // 本页是从首页头像 push 进来的二级页,返回栏走标准返回按钮。
  onBack: () => void = () => {};
  @State private profileDetail?: UserProfileDetail = undefined;
  @State private summaryStats?: UserSummaryStats = undefined;
  @State private topBadges: UserBadgeItem[] = [];
  @State private recentActivity: UserActivityItem[] = [];
  @State private categories: TopicCategory[] = [];
  @State private isLoggingOut: boolean = false;
  // LINUX DO Credit 入口行的状态。
  @State private ldcPhase: LdcEntryPhase = LdcEntryPhase.LOADING;
  @State private ldcInfo?: LdcUserInfo = undefined;
  // credit 宿主的挂载开关:只在真要取数的那一小段时间挂上,取完即卸,不让个人中心常驻一个 webview。
  @State private ldcHostActive: boolean = false;
  private scroller: Scroller = new Scroller();
  // 已加载资料的用户名:切换账号后重新加载,同账号重进不重复拉取。
  private loadedProfileUsername: string = '';
  private categoryIndex: CategoryIndex = new CategoryIndex();
  // credit.linux.do 专用的桥:必须挂在 credit 同源文档上,不能复用 linux.do 的 host bridge
  // (跨源 fetch 会被 CORS 挡)。
  private ldcBridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private unsubscribeLdcChanged?: () => void = undefined;

  aboutToAppear(): void {
    this.handleAccountChanged();
    // 详情页取到新余额后广播,本页压在它下面不会重新 appear,靠这条订阅刷新入口行的数字。
    if (!this.unsubscribeLdcChanged) {
      this.unsubscribeLdcChanged = LdcCreditEventBus.subscribe(() => {
        this.applyLdcCache();
      });
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeLdcChanged) {
      this.unsubscribeLdcChanged();
      this.unsubscribeLdcChanged = undefined;
    }
  }

  // 卡片分组容器:无描边,靠灰底衬托。
  @Styles
  cardStyle() {
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // credit 同源宿主:压在最底层、近透明且不吃触摸,被上层内容完全遮挡;满视口是为了给 CF
      // 挑战 JS 一个真实浏览器环境(1×1 会被判机器人)。余额取到即卸载,不常驻。
      if (this.ldcHostActive) {
        LdcCreditWebHost({
          bridge: this.ldcBridge,
          interactive: false,
          navTarget: '',
          onReady: () => {
            this.loadLdcBalance();
          },
          onLoadFailed: () => {
            this.settleLdcFailure();
          }
        })
      }
      this.ProfileScrollableContent()
      this.ProfileTitleBarOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg_gray'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private ProfileScrollableContent() {
    Scroll(this.scroller) {
      Column() {
        Blank()
          .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))

        if (this.isLoggedIn) {
          this.LoggedInContent()
        } else {
          this.AnonymousContent()
        }
      }
      .width('100%')
      .padding({ left: PAGE_MARGIN, right: PAGE_MARGIN })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private ProfileTitleBarOverlay() {
    HdsNavigation() {
      Column()
        .width('100%')
        .height('100%')
    }
    .titleBar({
      avoidLayoutSafeArea: requiresHdsLayoutSafeAreaAvoidance(ImmersiveLightArea.TITLE_BAR),
      enableComponentSafeArea: requiresHdsComponentSafeArea(ImmersiveLightArea.TITLE_BAR),
      style: buildImmersiveTitleBarStyle(),
      content: {
        title: {
          mainTitle: '我的'
        },
        backIcon: {
          icon: $r('sys.symbol.chevron_left'),
          label: '返回',
          action: () => {
            this.onBack();
          }
        },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.gearshape'),
              label: '设置',
              isEnabled: true,
              action: () => {
                this.onOpenSettings();
              }
            }
          }]
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
  }

  // ==================== 登录态 ====================

  @Builder
  private LoggedInContent() {
    Column() {
      // 卡片 1:身份 + 论坛数据
      Column() {
        // 外层 Row 不挂 onClick:头像/名字/箭头各自跳网页版资料,信任标独立跳等级进度页。
        // 这样信任标的祖先都无 onClick,不会与「打开资料」冒泡冲突(本 SDK 无 stopPropagation)。
        Row() {
          UserAvatar({ user: this.accountUser, avatarSize: 56 })
            .onClick(() => {
              this.openUserWebPage('', this.getDisplayName());
            })
          Column() {
            Text(this.getDisplayName())
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                this.openUserWebPage('', this.getDisplayName());
              })
            Row() {
              Text(this.getUsernameLabel())
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              if (trustLabelWithTitleOf(this.profileDetail).length > 0) {
                Text(' · ')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                // 信任等级标做成可点药丸:tap 进等级进度页。
                // 信任等级本身是 Discourse 标准信息,恒显;但「点进去看升级进度」的数据取自
                // connect.linux.do,是专属能力 —— 非该站时去掉箭头与点击,退化为纯展示标签,
                // 免得点了没反应。
                Row() {
                  Text(trustLabelWithTitleOf(this.profileDetail))
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ld_accent'))
                  if (SiteCapabilities.levelProgress) {
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(11)
                      .fontColor([$r('app.color.ld_accent')])
                      .margin({ left: 1 })
                  }
                }
                .padding({ left: 8, right: SiteCapabilities.levelProgress ? 6 : 8, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius(10)
                .onClick(() => {
                  if (SiteCapabilities.levelProgress) {
                    this.onOpenLevelProgress();
                  }
                })
              }
            }
            .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 14 })
          // 箭头也可点:与头像/昵称同跳 linux.do 官方个人资料页(站内 Web),补齐信息区可点区域。
          // 仍逐个子元素挂 onClick 而非外层 Row——外层无 onClick 才不与信任等级药丸的点击冒泡冲突。
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.text_faint')])
            .onClick(() => {
              this.openUserWebPage('', this.getDisplayName());
            })
        }
        .width('100%')
        .padding({ left: CARD_PADDING, right: CARD_PADDING, top: CARD_PADDING, bottom: 6 })

        // meta 行固定高度:资料回来前后卡片不跳动。
        Text(this.getUserMetaLine())
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .height(USER_META_HEIGHT)
          .padding({ left: CARD_PADDING, right: CARD_PADDING })

        this.HairlineInset()

        // 统计区固定高度:加载占位与数据网格同高。
        if (this.summaryStats) {
          this.StatsGrid(this.summaryStats)
        } else {
          Row() {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.ld_accent'))
            Text('正在加载论坛数据')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .height(STATS_AREA_HEIGHT)
          .justifyContent(FlexAlign.Center)
        }
      }
      .cardStyle()

      // 卡片 2:快捷入口
      Row() {
        this.QuickEntryNative($r('sys.symbol.arrow_counterclockwise_clock'), '浏览历史', false, () => {
          this.onOpenReadTopics();
        })
        this.QuickEntryNative($r('sys.symbol.bookmark'), '我的书签', false, () => {
          if (this.getUsername().length > 0) {
            this.onOpenBookmarks(this.getUsername());
          }
        })
        this.QuickEntryNative($r('sys.symbol.heart'), '我的点赞', true, () => {
          if (this.getUsername().length > 0) {
            this.onOpenActivity(this.getUsername(), '1', '我的点赞');
          }
        })
        this.DraftQuickEntry()
      }
      .padding({ top: CARD_PADDING, bottom: 14 })
      .cardStyle()

      // 卡片 2.5:LINUX DO Credit(credit.linux.do)
      // LDC Credit 是 credit.linux.do 的独立站点与独立会话,别的论坛没有对应物。
      if (SiteCapabilities.ldcCredit) {
        this.LdcEntryCard()
      }

      // 卡片 3:徽章
      Column() {
        this.SectionHead(badgeHeadLabel(this.profileDetail?.badgeCount), '全部 ›', () => {
          if (this.getUsername().length > 0) {
            this.onOpenBadges(this.getUsername(), this.profileDetail?.badgeCount ?? 0);
          }
        })
        if (this.topBadges.length > 0) {
          // 摘要接口最多返回 6 枚,固定 3 列网格等分展示,不做横滑。
          Column() {
            ForEach(badgeRowsOf(this.topBadges), (row: UserBadgeItem[], rowIndex: number) => {
              Row({ space: 8 }) {
                ForEach(row, (badge: UserBadgeItem) => {
                  BadgeTile(badge, (tapped: UserBadgeItem) => {})
                }, (badge: UserBadgeItem) => badge.id.toString())
                // 不满 3 枚的行用透明占位补齐,保持等分列宽。
                ForEach(badgeRowFillers(row), (filler: number) => {
                  Column()
                    .layoutWeight(1)
                }, (filler: number) => `filler_${filler}`)
              }
              .width('100%')
              .margin({ top: rowIndex > 0 ? 8 : 0 })
            }, (row: UserBadgeItem[], rowIndex: number) => `row_${rowIndex}_${row.length}`)
          }
          .width('100%')
          .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 10, bottom: CARD_PADDING })
        } else {
          Text('暂无徽章')
            .fontSize(13)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .padding({ left: CARD_PADDING, top: 10, bottom: CARD_PADDING })
        }
      }
      .cardStyle()

      // 卡片 4:最近活动
      Column() {
        this.SectionHead('最近活动', '全部 ›', () => {
          if (this.getUsername().length > 0) {
            this.onOpenActivity(this.getUsername(), '4,5', '最近活动');
          }
        })
        if (this.recentActivity.length > 0) {
          ForEach(this.recentActivity, (item: UserActivityItem, index: number) => {
            Column() {
              if (index > 0) {
                this.HairlineInset()
              }
              this.ActivityRow(item)
            }
            .width('100%')
          }, (item: UserActivityItem, index: number) => `${item.topicId}_${item.postNumber ?? 0}_${index}`)
          this.ActivityFooterLinks()
        } else {
          Text('最近没有发帖')
            .fontSize(13)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .padding({ left: CARD_PADDING, top: 10, bottom: CARD_PADDING })
        }
      }
      .cardStyle()

      // 卡片 5:退出登录
      Row() {
        if (this.isLoggingOut) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.ld_danger'))
            .margin({ right: 8 })
        }
        Text('退出登录')
          .fontSize(15)
          .fontColor($r('app.color.ld_danger'))
      }
      .justifyContent(FlexAlign.Center)
      .padding({ top: 14, bottom: 14 })
      .cardStyle()
      .onClick(() => {
        this.confirmLogout();
      })

      Row()
        .width('100%')
        .height(40)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private StatsGrid(stats: UserSummaryStats) {
    Column() {
      Row() {
        this.StatCell(formatCount(stats.daysVisited), '访问天数')
        this.StatCell(formatTimeRead(stats.timeReadSeconds), '阅读时长')
        this.StatCell(formatCount(stats.likesReceived), '收到的赞')
        this.StatCell(formatCount(stats.likesGiven), '送出的赞')
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 14 })

      Row() {
        this.StatCell(formatCount(stats.topicCount), '创建话题')
        this.StatCell(formatCount(stats.postCount), '回复')
        this.StatCell(formatCount(stats.topicsEntered), '浏览话题')
        this.StatCell(stats.solvedCount !== undefined ? formatCount(stats.solvedCount) : '—', '解决方案')
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 16, bottom: CARD_PADDING })
    }
    .width('100%')
    .height(STATS_AREA_HEIGHT)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private StatCell(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_faint'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
  }

  // LINUX DO Credit 入口:左侧图标 + 标题,右侧按状态给出余额 / 「去登录」/ 转圈 / 「重试」。
  // 整行可点:已登录 credit 进详情页看最近记录,未登录则进详情页并直接拉起 credit 登录。
  @Builder
  private LdcEntryCard() {
    Row() {
      // 与设置页的列表行同款:20 号系统符号 + 14 间距,不另造药丸/色块。
      // 金币符号本身已表达「余额」,配色沿用徽章金,和右侧的数字各司其职。
      SymbolGlyph($r('sys.symbol.coins'))
        .fontSize(20)
        .fontColor([$r('app.color.ld_gold')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)

      Column() {
        Text('LINUX DO Credit')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.getLdcSubtitle())
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 })

      if (this.ldcPhase === LdcEntryPhase.LOADING && !this.ldcInfo) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('app.color.ld_accent'))
      } else if (this.ldcInfo) {
        Text(formatLdcAmount(this.ldcInfo.availableBalance))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      } else {
        Text(this.ldcPhase === LdcEntryPhase.ANON ? '去登录' : '重试')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_faint')])
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .cardStyle()
    .onClick(() => {
      this.openLdcPage();
    })
  }

  // 无角标、走自定义点击的快捷入口(书签/点赞等已原生化的入口)。love=true 时图标用点赞粉。
  @Builder
  private QuickEntryNative(symbol: Resource, label: string, love: boolean, onEntryClick: () => void) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([love ? $r('app.color.ld_love') : $r('app.color.text_primary')])
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 7 })
    }
    .layoutWeight(1)
    .onClick(() => {
      onEntryClick();
    })
  }

  // 草稿角标直接读取组件 @StorageProp。不要把 count 作为 @Builder 普通参数传入：Navigation 复用页面
  // 实例时该参数会保留旧快照，只有销毁页面再进入才更新。
  @Builder
  private DraftQuickEntry() {
    Column() {
      Badge({
        count: this.draftCount,
        maxCount: 99,
        position: BadgePosition.RightTop,
        style: {
          badgeSize: 16,
          fontSize: 10,
          badgeColor: $r('app.color.ld_accent'),
          borderColor: $r('app.color.ld_accent'),
          borderWidth: 0
        }
      }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(24)
          .fontColor([$r('app.color.text_primary')])
      }
      Text('我的草稿')
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 7 })
    }
    .layoutWeight(1)
    .onClick(() => {
      if (this.getUsername().length > 0) {
        this.onOpenDrafts(this.getUsername());
      }
    })
  }

  @Builder
  private ActivityRow(item: UserActivityItem) {
    Column() {
      Row() {
        if (item.actionType === UserActionType.REPLY) {
          FaIconView({
            icon: this.faIcon('reply'),
            iconSize: 13,
            color: $r('app.color.text_faint')
          })
            .margin({ top: 3 })
        }
        Text(item.title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: item.actionType === UserActionType.REPLY ? 6 : 0 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 分类 + 标签与首页帖子列表同款组件;时间固定在最右侧。
      Row() {
        if (this.hasActivityBadges(item)) {
          TopicMetadataBadges({
            category: this.getCategoryFor(item.categoryId),
            parentCategory: this.getParentCategoryFor(item.categoryId),
            tags: item.tags
          })
            .layoutWeight(1)
        } else {
          Blank()
        }
        Text(RelativeTime.fromNow(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 5 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenTopic(item.topicId, item.title, item.postNumber);
    })
  }

  @Builder
  private ActivityFooterLinks() {
    Row() {
      Text(this.getTopicsLinkLabel())
        .fontSize(13)
        .fontColor($r('app.color.ld_accent'))
        .onClick(() => {
          if (this.getUsername().length > 0) {
            this.onOpenActivity(this.getUsername(), '4', '我的话题');
          }
        })
      Text('·')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .margin({ left: 10, right: 10 })
      Text(this.getRepliesLinkLabel())
        .fontSize(13)
        .fontColor($r('app.color.ld_accent'))
        .onClick(() => {
          if (this.getUsername().length > 0) {
            this.onOpenActivity(this.getUsername(), '5', '我的回复');
          }
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 8, bottom: 14 })
  }

  // ==================== 未登录态 ====================

  @Builder
  private AnonymousContent() {
    Column() {
      Column() {
        Column() {
          if (this.isCheckingSession && !this.hasCheckedSession) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color($r('app.color.ld_accent'))
          } else {
            SymbolGlyph($r('sys.symbol.person'))
              .fontSize(32)
              .fontColor([$r('app.color.text_faint')])
          }
        }
        .width(68)
        .height(68)
        .justifyContent(FlexAlign.Center)
        .borderRadius(34)
        .border({ width: 1, color: $r('app.color.border') })

        // 标题带上论坛名:多站之后这是最要紧的信息 —— 用户可能刚切过站,不写清是哪个论坛,
        // 会以为自己原来那个账号掉登录了。论坛名可以很长,单行截断。
        Text(this.getAnonymousTitle())
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 16 })
          .padding({ left: CARD_PADDING, right: CARD_PADDING })

        Text(this.getAnonymousSubtitle())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
          .padding({ left: CARD_PADDING, right: CARD_PADDING })

        if (!this.isCheckingSession || this.hasCheckedSession) {
          Button('立即登录')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.ld_accent'))
            .height(42)
            .padding({ left: 44, right: 44 })
            .borderRadius(21)
            .margin({ top: 22 })
            .onClick(() => {
              this.onLoginClick();
            })

          Column() {
            Text('参与回帖、点赞与投票')
              .fontSize(13)
              .fontColor($r('app.color.text_faint'))
            Text('私信与实时通知提醒')
              .fontSize(13)
              .fontColor($r('app.color.text_faint'))
              .margin({ top: 6 })
            Text('跨设备同步阅读进度')
              .fontSize(13)
              .fontColor($r('app.color.text_faint'))
              .margin({ top: 6 })
          }
          .margin({ top: 16 })
        }
      }
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 32, bottom: 26 })
      .cardStyle()

      Row()
        .width('100%')
        .height(40)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 通用 Builder ====================

  @Builder
  private HairlineInset() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.border'))
      .margin({ left: CARD_PADDING, right: CARD_PADDING })
  }

  @Builder
  private SectionHead(title: string, more: string, onMore: () => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(more)
        .fontSize(12)
        .fontColor($r('app.color.ld_accent'))
        .onClick(() => {
          onMore();
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 4 })
  }

  // ==================== 数据加载 ====================

  // 资料/摘要/活动/分类并行加载,各自落地各自的 @State;
  // 完成时校验用户未切换(loadedProfileUsername),避免登出/换号后旧响应污染界面。
  // stale-while-revalidate:先用内存缓存秒出上次数据(无转圈),后台请求回来再原地更新。
  private loadProfileData(username: string): void {
    if (this.loadedProfileUsername === username) {
      return;
    }
    this.loadedProfileUsername = username;

    const cachedDetail: UserProfileDetail | undefined = UserProfileCache.getDetail(username);
    const cachedSummary: UserSummary | undefined = UserProfileCache.getSummary(username);
    const cachedActivity: UserActivityItem[] | undefined = UserProfileCache.getActivity(username);
    this.profileDetail = cachedDetail;
    this.summaryStats = cachedSummary ? cachedSummary.stats : undefined;
    this.topBadges = cachedSummary ? cachedSummary.topBadges : [];
    this.recentActivity = cachedActivity ? cachedActivity : [];

    const service: UserProfileService = new UserProfileService(this.bridge);
    this.loadDetail(service, username);
    this.loadSummary(service, username);
    this.loadActivity(service, username);
    this.loadCategories();
  }

  private resetProfileData(): void {
    this.loadedProfileUsername = '';
    this.profileDetail = undefined;
    this.summaryStats = undefined;
    this.topBadges = [];
    this.recentActivity = [];
  }

  private async loadDetail(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail(username);
    if (this.loadedProfileUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.profileDetail = result.data;
      UserProfileCache.setDetail(username, result.data);
      Log.i(`${LOG_TAG} profile detail loaded trustLevel=${result.data.trustLevel ?? -1}`);
    } else {
      Log.i(`${LOG_TAG} profile detail load failed status=${result.statusCode}`);
    }
  }

  private async loadSummary(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserSummary> = await service.getSummary(username);
    if (this.loadedProfileUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.summaryStats = result.data.stats;
      this.topBadges = result.data.topBadges;
      UserProfileCache.setSummary(username, result.data);
      Log.i(`${LOG_TAG} summary loaded badges=${result.data.topBadges.length}`);
    } else {
      Log.i(`${LOG_TAG} summary load failed status=${result.statusCode}`);
    }
  }

  private async loadActivity(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserActivityItem[]> = await service.getRecentActivity(username);
    if (this.loadedProfileUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.recentActivity = result.data;
      UserProfileCache.setActivity(username, result.data);
      Log.i(`${LOG_TAG} recent activity loaded count=${result.data.length}`);
    } else {
      Log.i(`${LOG_TAG} recent activity load failed status=${result.statusCode}`);
    }
  }

  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  // ==================== LINUX DO Credit ====================

  // 入口行的取数入口。三条捷径按代价从小到大:未登录 credit 直接给「去登录」(连 webview 都不起);
  // 缓存新鲜就用缓存;都不满足才挂宿主真发一次请求。
  private refreshLdcEntry(): void {
    // 换站后连余额都不必去取:那是 credit.linux.do 的接口,请求本身就没有意义。
    if (!SiteCapabilities.ldcCredit) {
      this.ldcHostActive = false;
      return;
    }
    this.ldcInfo = LdcCreditSession.getCachedInfo();

    if (!LdcCreditSession.hasSession()) {
      LdcCreditSession.clearCache();
      this.ldcInfo = undefined;
      this.ldcPhase = LdcEntryPhase.ANON;
      this.ldcHostActive = false;
      return;
    }

    if (LdcCreditSession.isCacheFresh() && this.ldcInfo) {
      this.ldcPhase = LdcEntryPhase.READY;
      return;
    }

    this.ldcPhase = LdcEntryPhase.LOADING;
    this.ldcHostActive = true;
  }

  private resetLdcEntry(): void {
    this.ldcPhase = LdcEntryPhase.LOADING;
    this.ldcInfo = undefined;
    this.ldcHostActive = false;
  }

  // 详情页刷新过余额后经事件总线叫醒本页,直接读缓存对齐,不再自己发请求。
  private applyLdcCache(): void {
    const cached: LdcUserInfo | undefined = LdcCreditSession.getCachedInfo();
    this.ldcInfo = cached;
    this.ldcPhase = cached ? LdcEntryPhase.READY : LdcEntryPhase.ANON;
  }

  private async loadLdcBalance(): Promise<void> {
    const result: NetworkResult<LdcUserInfo> = await new LdcCreditService(this.ldcBridge).getUserInfo();
    // 请求已落地,宿主的使命完成:立刻卸载,不让个人中心常驻一个 credit webview。
    this.ldcHostActive = false;
    if (result.success && result.data) {
      this.ldcInfo = result.data;
      this.ldcPhase = LdcEntryPhase.READY;
      LdcCreditSession.setCachedInfo(result.data);
      Log.i(`${LOG_TAG} ldc balance loaded`);
      return;
    }

    // 401 = credit 会话过期(cookie 还在但已失效),回落到「去登录」而非报错。
    if (result.statusCode === 401) {
      LdcCreditSession.clearCache();
      this.ldcInfo = undefined;
      this.ldcPhase = LdcEntryPhase.ANON;
      return;
    }

    Log.i(`${LOG_TAG} ldc balance load failed status=${result.statusCode}`);
    this.settleLdcFailure();
  }

  private settleLdcFailure(): void {
    this.ldcHostActive = false;
    // 有缓存就继续显示旧余额(标注不上新总比整行变成「重试」好);没有才让整行退化成可重试态。
    this.ldcPhase = this.ldcInfo ? LdcEntryPhase.READY : LdcEntryPhase.ERROR;
  }

  private getLdcSubtitle(): string {
    if (this.ldcPhase === LdcEntryPhase.ANON) {
      return '使用 LINUX DO 账号登录后查看';
    }
    if (this.ldcPhase === LdcEntryPhase.ERROR) {
      return '暂时无法获取余额';
    }
    return '查看最近 7 天获取记录';
  }

  // 进 LDC 详情页。未登录 credit 时带上 startLogin,让详情页落地即拉起登录,省一次点击。
  // 这里自取 NavPathStack 而不是让 RootTabPage 注入回调:本页的 NavDestination 分支正被别的改动
  // 占用,少动一处少一次冲突。
  private openLdcPage(): void {
    const info: NavigationInfo | undefined = this.queryNavigationInfo();
    if (!info) {
      Log.i(`${LOG_TAG} ldc navigation unavailable`);
      return;
    }
    const startLogin: boolean = this.ldcPhase === LdcEntryPhase.ANON;
    info.pathStack.pushPath(new NavPathInfo(AppRouteName.LDC_CREDIT, buildLdcCreditRouteParam(startLogin)));
  }

  // ==================== 退出登录 ====================

  private confirmLogout(): void {
    if (this.isLoggingOut) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: $r('app.color.ld_danger'),
        action: () => {
          this.performLogout();
        }
      }
    });
  }

  private async performLogout(): Promise<void> {
    const username: string = this.getUsername();
    if (username.length === 0 || this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    // 先退推送订阅再登出:顺序不能颠倒——linux.do 退订要带登录 cookie。清理内部已吞掉
    // 所有异常,失败也不该拦住用户登出。
    try {
      await this.onLogoutCleanup();
    } catch (err) {
      Log.i(`${LOG_TAG} logout push cleanup failed error=${JSON.stringify(err)}`);
    }
    const result: NetworkResult<boolean> = await new AuthService(this.bridge).logout(username);
    this.isLoggingOut = false;
    if (!result.success) {
      this.showToast(result.error?.message ? result.error.message : '退出登录失败，请稍后再试');
      Log.i(`${LOG_TAG} logout failed status=${result.statusCode}`);
      return;
    }
    Log.i(`${LOG_TAG} logout success`);
    this.showToast('已退出登录');
    // 先本地落地未登录,再广播:顺序不能反。先广播的话,复查结果回来时可能把刚清掉的登录态又写回去。
    this.onLoggedOut();
    // 会话变化会触发 host webview 重载,先关闭就绪门闩,与登录成功走同一条刷新链路。
    this.bridge.markHostReloading();
    SessionEventBus.notifySessionChanged();
  }

  private showToast(message: string): void {
    promptToast(this.getUIContext(), message);
  }

  // ==================== 事件 ====================

  // 登录态/账号变化(含登录、登出、切号):按当前 props 重新对齐本页数据。
  private handleAccountChanged(): void {
    if (this.isLoggedIn && this.accountUser.username.length > 0) {
      this.loadProfileData(this.accountUser.username);
      this.refreshLdcEntry();
      return;
    }
    this.resetProfileData();
    this.resetLdcEntry();
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady) {
      this.handleAccountChanged();
    }
  }

  // ==================== 展示辅助 ====================

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }

  private getDisplayName(): string {
    if (!this.isLoggedIn) {
      return '';
    }
    return this.accountUser.displayName && this.accountUser.displayName.length > 0
      ? this.accountUser.displayName
      : this.accountUser.username;
  }

  private getUsername(): string {
    return this.isLoggedIn ? this.accountUser.username : '';
  }

  private getUsernameLabel(): string {
    const username: string = this.getUsername();
    return username.length > 0 ? `@${username}` : '';
  }

  // 信任等级标签:优先站点头衔(user.title),否则用 TL 默认名;资料未加载完为空。

  private getUserMetaLine(): string {
    const detail: UserProfileDetail | undefined = this.profileDetail;
    if (!detail) {
      return '';
    }
    const parts: string[] = [];
    const joinedDays: number = daysSince(detail.createdAt);
    if (joinedDays > 0) {
      parts.push(`加入 ${joinedDays} 天`);
    }
    const lastPosted: string = RelativeTime.fromNow(detail.lastPostedAt);
    if (lastPosted.length > 0) {
      parts.push(`最近发帖 ${lastPosted}`);
    }
    if (detail.profileViewCount !== undefined && detail.profileViewCount > 0) {
      parts.push(`浏览量 ${formatCount(detail.profileViewCount)}`);
    }
    return parts.join(' · ');
  }

  // 徽章按 3 枚一行分组。

  // 末行不足 3 枚时需要的占位数量([1]、[1,2] 之类,仅用于 ForEach 生成透明格)。


  private getTopicsLinkLabel(): string {
    const count: number | undefined = this.summaryStats?.topicCount;
    return count !== undefined ? `我的话题 ${formatCount(count)} ›` : '我的话题 ›';
  }

  private getRepliesLinkLabel(): string {
    const count: number | undefined = this.summaryStats?.postCount;
    return count !== undefined ? `我的回复 ${formatCount(count)} ›` : '我的回复 ›';
  }

  private getAnonymousTitle(): string {
    if (!this.hasCheckedSession) {
      return '检查登录状态';
    }
    return this.activeForumName.length > 0 ? `登录 ${this.activeForumName}` : '登录论坛';
  }

  // 原先这里放的是某个社区的口号原文 —— 既是他站内容,换站后也完全不成立。
  // 改成中性表述,顺便说清「账号是论坛的、不是本应用的」:登录走的是站点自己的网页
  // 登录页(LoginPage 里装的就是 AppConstants.LOGIN_URL),App 全程不经手密码。
  private getAnonymousSubtitle(): string {
    if (!this.hasCheckedSession) {
      return '正在检查登录状态';
    }
    return '账号由该论坛提供,登录后即可参与讨论。登录在论坛自己的页面完成,ArkDO 不经手你的密码。';
  }

  private getCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.find(this.categories, categoryId);
  }

  private getParentCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.findParent(this.categories, categoryId);
  }

  private hasActivityBadges(item: UserActivityItem): boolean {
    return this.getCategoryFor(item.categoryId) !== undefined || item.tags.length > 0;
  }

  // 千位缩写:与 Discourse 列表一致(1.2k / 12k)。纯整数运算避免浮点尾差。



  private openUserWebPage(subPath: string, title?: string): void {
    const username: string = this.getUsername();
    if (username.length === 0) {
      return;
    }
    this.onOpenWeb(`${AppConstants.BASE_URL}/u/${encodeURIComponent(username)}${subPath}`, title);
  }
}
