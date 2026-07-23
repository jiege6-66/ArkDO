import { Log } from '../../services/logging/Log';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { NotificationItem } from '../../models/Notification';
import { NotificationApi } from '../../services/notification/NotificationApi';
import { NotificationEventBus } from '../../services/notification/NotificationEventBus';
import { LoginGate } from '../../services/session/LoginGate';
import { JsonNetworkClient, NetworkResult } from '../../services/network/NetworkTypes';
import { NotificationListItem } from '../components/NotificationListItem';
import { LoadStateView } from '../components/LoadStateView';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { ListFooter } from '../components/ListFooter';
import { immersiveTitleBarContentTopSpacer } from '../../common/ui/ImmersiveTitleBarLayout';
import {
  ImmersiveLightArea,
  requiresHdsComponentSafeArea,
  requiresHdsLayoutSafeAreaAvoidance
} from '../../common/ui/ImmersiveLightMaterial';
import { buildImmersiveTitleBarStyle } from '../../common/ui/ImmersiveTitleBarStyle';

const LOG_TAG: string = '[ArkDO][NotificationPage]';
const PAGE_SIZE: number = 30;

@Component
export struct NotificationPage {
  // 窗口常驻全屏布局:根列自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  onBack: () => void = () => {};
  // postNumber:通知指向的具体楼层,详情页据此定位并高亮;无楼层的通知(徽章等)为 undefined。
  onOpenTopic: (topicId: number, slug: string | undefined, title: string, postNumber?: number) => void = () => {};

  @State private items: NotificationItem[] = [];
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private loadFailed: boolean = false;
  @State private message: string = '';
  private api?: NotificationApi = undefined;
  private loading: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (this.bridge) {
      this.api = new NotificationApi(this.bridge);
    }
    this.loadInitial();
  }

  build() {
    HdsNavigation() {
      this.Content()
    }
    .titleBar({
      avoidLayoutSafeArea: requiresHdsLayoutSafeAreaAvoidance(ImmersiveLightArea.TITLE_BAR),
      enableComponentSafeArea: requiresHdsComponentSafeArea(ImmersiveLightArea.TITLE_BAR),
      style: buildImmersiveTitleBarStyle({ enableRefreshOffsetChange: true }),
      content: {
        title: {
          mainTitle: '通知'
        },
        backIcon: {
          icon: $r('sys.symbol.chevron_left'),
          label: '返回',
          action: () => {
            this.onBack();
          }
        },
        menu: this.hasUnread() ? {
          value: [{
            content: {
              icon: $r('sys.symbol.checkmark'),
              label: '全部已读',
              isEnabled: true,
              action: () => {
                this.markAllRead();
              }
            }
          }]
        } : undefined
      }
    })
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  private Content() {
    if (this.items.length === 0) {
      Column() {
        LoadStateView({
          isLoading: this.isInitialLoading,
          loadingText: '加载中…',
          message: this.message.length > 0 ? this.message : '通知加载失败,请重试',
          showRetry: this.loadFailed,
          emptyTitle: '暂无通知',
          onRetry: () => {
            this.loadInitial();
          }
        })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    } else {
      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List({ scroller: this.scroller }) {
          ListItemGroup({ header: this.TitleBarListHeader }) {
            ForEach(this.items, (item: NotificationItem) => {
              ListItem() {
                NotificationListItem({
                  item: item,
                  onItemClick: (clicked: NotificationItem) => {
                    this.handleItemClick(clicked);
                  }
                })
              }
            }, (item: NotificationItem) => `${item.id}_${item.read}`)

            ListItem() {
              ListFooter({
                isLoading: this.isLoadingMore,
                hasMore: this.hasMore,
                endText: '已到底',
                accentColor: $r('app.color.brand'),
                textColor: $r('app.color.text_secondary')
              })
            }
          }
          .divider({ strokeWidth: 1, color: $r('app.color.border'), startMargin: 70, endMargin: 0 })
        }
        .width('100%')
        .height(`calc(100% + ${immersiveTitleBarContentTopSpacer(this.sysTopInset)}vp)`)
        .position({ x: 0, y: -immersiveTitleBarContentTopSpacer(this.sysTopInset) })
        .clip(false)
        .scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onReachEnd(() => {
          this.loadMore();
        })
      }
      .width('100%')
      .height('100%')
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onRefreshing(() => {
        this.loadInitial();
      })
    }
  }

  @Builder
  private TitleBarListHeader() {
    Column() {
      Blank()
        .height(immersiveTitleBarContentTopSpacer(this.sysTopInset))
    }
    .width('100%')
  }

  private hasUnread(): boolean {
    for (let index: number = 0; index < this.items.length; index++) {
      if (!this.items[index].read) {
        return true;
      }
    }
    return false;
  }

  // 首次加载 / 下拉刷新:recent=true(服务端 bump seen 清红点),并同步铃铛置零。
  private async loadInitial(): Promise<void> {
    if (!this.api || this.loading) {
      if (!this.api) {
        this.message = '正在准备请求环境';
      }
      // 若因重复触发提前返回,也要收起可能已被下拉手势拉起的刷新态。
      this.isRefreshing = false;
      return;
    }
    // Refresh 单向绑定:必须自己把 isRefreshing 置 true(刷新已有列表时)、结束再置 false,
    // 靠这个跳变收起下拉 spinner。首次空列表用 isInitialLoading 走中心 loading。
    const isFirstLoad: boolean = this.items.length === 0;
    this.loading = true;
    this.isInitialLoading = isFirstLoad;
    this.isRefreshing = !isFirstLoad;
    this.loadFailed = false;

    const result: NetworkResult<NotificationItem[]> = await this.api.load(PAGE_SIZE, 0, true);
    this.loading = false;
    this.isInitialLoading = false;
    this.isRefreshing = false;

    if (!result.success || result.data === undefined) {
      this.loadFailed = true;
      this.message = '通知加载失败,请重试';
      Log.i(`${LOG_TAG} initial load failed status=${result.statusCode}`);
      return;
    }

    this.items = result.data;
    this.hasMore = result.data.length >= PAGE_SIZE;
    this.message = '';
    // 已看见(seen 已 bump):把铃铛未读清零,保留私信高优先级计数不动。
    NotificationEventBus.publish({ unread: 0, highPriority: NotificationEventBus.current().highPriority });
  }

  private async loadMore(): Promise<void> {
    if (!this.api || this.loading || !this.hasMore || this.items.length === 0) {
      return;
    }
    this.loading = true;
    this.isLoadingMore = true;

    const result: NetworkResult<NotificationItem[]> = await this.api.load(PAGE_SIZE, this.items.length, false);
    this.loading = false;
    this.isLoadingMore = false;

    if (!result.success || result.data === undefined) {
      Log.i(`${LOG_TAG} load more failed status=${result.statusCode}`);
      return;
    }

    if (result.data.length === 0) {
      this.hasMore = false;
      return;
    }
    this.items = this.items.concat(result.data);
    this.hasMore = result.data.length >= PAGE_SIZE;
  }

  // 点某行:乐观标记已读 → 跳转帖子;标记请求 fire-and-forget。
  private handleItemClick(item: NotificationItem): void {
    if (!item.read) {
      this.setRead(item.id);
      if (this.api) {
        this.api.markRead(item.id);
      }
    }
    if (item.topicId !== undefined) {
      this.onOpenTopic(item.topicId, item.slug, item.title, item.postNumber);
    }
  }

  private setRead(id: number): void {
    const next: NotificationItem[] = [];
    for (let index: number = 0; index < this.items.length; index++) {
      const cur: NotificationItem = this.items[index];
      if (cur.id === id && !cur.read) {
        next.push(this.cloneRead(cur));
      } else {
        next.push(cur);
      }
    }
    this.items = next;
  }

  private async markAllRead(): Promise<void> {
    // 未登录:拦截并弹登录页,不发请求(全部标记已读)。
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    const next: NotificationItem[] = [];
    for (let index: number = 0; index < this.items.length; index++) {
      next.push(this.items[index].read ? this.items[index] : this.cloneRead(this.items[index]));
    }
    this.items = next;
    NotificationEventBus.publish({ unread: 0, highPriority: 0 });
    if (this.api) {
      await this.api.markAllRead();
    }
  }

  private cloneRead(src: NotificationItem): NotificationItem {
    return {
      id: src.id, type: src.type, read: true, createdAt: src.createdAt,
      actorName: src.actorName, actorUsername: src.actorUsername, avatarTemplate: src.avatarTemplate,
      actionText: src.actionText, title: src.title, topicId: src.topicId, postNumber: src.postNumber,
      slug: src.slug, iconId: src.iconId, iconColor: src.iconColor
    };
  }
}
