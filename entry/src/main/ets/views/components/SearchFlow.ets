import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import {
  ActivityRouteParam,
  BadgesRouteParam,
  buildActivityRouteParam,
  buildBadgesRouteParam,
  buildSolvedRouteParam,
  buildTopicDetailRouteParam,
  buildUserProfileRouteParam,
  buildWebRouteParam,
  isActivityRouteParam,
  isBadgesRouteParam,
  isSolvedRouteParam,
  isTopicDetailRouteParam,
  isUserProfileRouteParam,
  isWebRouteParam,
  SolvedRouteParam,
  TopicDetailRouteParam,
  UserProfileRouteParam,
  WebRouteParam
} from '../../navigation/AppRoutes';
import { LinkRouter, LinkTarget, LinkTargetKind } from '../../services/content/LinkRouter';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { bumpTick, COMPOSER_OVERLAY_BACK_TICK_KEY, COMPOSER_OVERLAY_VISIBLE_KEY } from '../../common/constants/StorageKeys';
import { SearchOverlay } from './SearchOverlay';
import { ViewerImage } from './ImageViewer';
import { ActivityListPage } from '../pages/ActivityListPage';
import { BadgesPage } from '../pages/BadgesPage';
import { SolvedPostsPage } from '../pages/SolvedPostsPage';
import { TopicDetailPage } from '../pages/TopicDetailPage';
import { UserProfilePage } from '../pages/UserProfilePage';
import { WebViewPage } from '../pages/WebViewPage';

const SEARCH_FLOW_TOPIC_DETAIL: string = 'searchTopicDetail';
const SEARCH_FLOW_WEB: string = 'searchWeb';
// 个人主页及其下级页面都在搜索自己的栈里打开:点搜索结果里的用户不再关掉搜索页,
// 与「点帖子进详情」一致,返回即回到原来的搜索结果。
const SEARCH_FLOW_USER_PROFILE: string = 'searchUserProfile';
const SEARCH_FLOW_ACTIVITY: string = 'searchUserActivity';
const SEARCH_FLOW_BADGES: string = 'searchUserBadges';
const SEARCH_FLOW_SOLVED: string = 'searchUserSolved';

@Component
export struct SearchFlow {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop isArkWebReady: boolean = false;
  @Prop currentUser: User = { id: 0, username: '' };
  @Prop @Watch('handleBackTickChanged') backTick: number = 0;
  @StorageProp(COMPOSER_OVERLAY_VISIBLE_KEY) private composerVisible: boolean = false;
  onClose: () => void = () => {};
  onOpenChallenge: () => void = () => {};
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onOpenUser: (user: User) => void = () => {};

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.navPathStack) {
      SearchOverlay({
        bridge: this.bridge,
        isArkWebReady: this.isArkWebReady,
        onClose: () => {
          this.closeSearchFlow();
        },
        onOpenTopic: (topic: Topic) => {
          this.openTopic(topic);
        },
        // 「用户」类型的搜索结果:在搜索自己的栈里 push 个人主页,不关搜索页。
        onOpenUser: (user: User) => {
          this.openUserProfile(user.username, user.displayName ?? '', user.avatarTemplate ?? '', user.id);
        }
      })
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.NavDestinationBuilder)
  }

  @Builder
  private NavDestinationBuilder(name: string, param: Object | undefined) {
    if (name === SEARCH_FLOW_TOPIC_DETAIL && isTopicDetailRouteParam(param)) {
      NavDestination() {
        TopicDetailPage({
          param: param as TopicDetailRouteParam,
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          currentUser: this.currentUser,
          onBack: () => {
            this.popInternal();
          },
          onOpenChallenge: () => {
            this.onOpenChallenge();
          },
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.onOpenImages(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.handleOpenLink(url);
          },
          onOpenUser: (user: User) => {
            this.openUserProfile(user.username, user.displayName ?? '', user.avatarTemplate ?? '', user.id);
          }
        })
      }
      .hideTitleBar(true)
      .onBackPressed(() => this.consumeTopicDetailBack())
      .backgroundColor($r('app.color.topic_detail_page_bg'))
    } else if (name === SEARCH_FLOW_USER_PROFILE && isUserProfileRouteParam(param)) {
      NavDestination() {
        UserProfilePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as UserProfileRouteParam).username,
          seedDisplayName: (param as UserProfileRouteParam).displayName ?? '',
          seedAvatarTemplate: (param as UserProfileRouteParam).avatarTemplate ?? '',
          seedUserId: (param as UserProfileRouteParam).userId ?? 0,
          onBack: () => {
            this.popInternal();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.navPathStack.pushPath(new NavPathInfo(
              SEARCH_FLOW_TOPIC_DETAIL,
              buildTopicDetailRouteParam(topicId, undefined, title, postNumber, postNumber !== undefined)
            ));
          },
          onOpenActivity: (username: string, filter: string, title: string) => {
            this.navPathStack.pushPath(new NavPathInfo(
              SEARCH_FLOW_ACTIVITY,
              buildActivityRouteParam(username, filter, title)
            ));
          },
          onOpenBadges: (username: string, badgeCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(SEARCH_FLOW_BADGES, buildBadgesRouteParam(username, badgeCount)));
          },
          onOpenSolved: (username: string, solvedCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(SEARCH_FLOW_SOLVED, buildSolvedRouteParam(username, solvedCount)));
          },
          // 互动圈头像可点:递归 push 同一路由,栈自然记住来路。
          onOpenUser: (username: string, displayName: string, avatarTemplate: string, userId: number) => {
            this.openUserProfile(username, displayName, avatarTemplate, userId);
          },
          onOpenWeb: (url: string, title?: string) => {
            this.navPathStack.pushPath(new NavPathInfo(SEARCH_FLOW_WEB, buildWebRouteParam(url, title)));
          },
          // 简介/网站里的链接:可能是站内帖子、他人主页,也可能是外站,交给搜索栈内的统一路由。
          onOpenLink: (url: string) => {
            this.handleOpenLink(url);
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === SEARCH_FLOW_ACTIVITY && isActivityRouteParam(param)) {
      NavDestination() {
        ActivityListPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as ActivityRouteParam).username,
          filter: (param as ActivityRouteParam).filter,
          pageTitle: (param as ActivityRouteParam).title,
          onBack: () => {
            this.popInternal();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.navPathStack.pushPath(new NavPathInfo(
              SEARCH_FLOW_TOPIC_DETAIL,
              buildTopicDetailRouteParam(topicId, undefined, title, postNumber, postNumber !== undefined)
            ));
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === SEARCH_FLOW_BADGES && isBadgesRouteParam(param)) {
      NavDestination() {
        BadgesPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as BadgesRouteParam).username,
          badgeCount: (param as BadgesRouteParam).badgeCount,
          onBack: () => {
            this.popInternal();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === SEARCH_FLOW_SOLVED && isSolvedRouteParam(param)) {
      NavDestination() {
        SolvedPostsPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as SolvedRouteParam).username,
          solvedCount: (param as SolvedRouteParam).solvedCount,
          onBack: () => {
            this.popInternal();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.navPathStack.pushPath(new NavPathInfo(
              SEARCH_FLOW_TOPIC_DETAIL,
              buildTopicDetailRouteParam(topicId, undefined, title, postNumber, postNumber !== undefined)
            ));
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === SEARCH_FLOW_WEB && isWebRouteParam(param)) {
      NavDestination() {
        WebViewPage({
          url: (param as WebRouteParam).url,
          pageTitle: (param as WebRouteParam).title ?? '',
          onBack: () => {
            this.popInternal();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else {
      NavDestination() {
        Column() {
          Text('页面不存在')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    }
  }

  private openTopic(topic: Topic): void {
    this.navPathStack.pushPath(new NavPathInfo(
      SEARCH_FLOW_TOPIC_DETAIL,
      buildTopicDetailRouteParam(topic.id, topic.slug, topic.title)
    ));
  }

  private handleBackTickChanged(): void {
    if (this.composerVisible) {
      bumpTick(COMPOSER_OVERLAY_BACK_TICK_KEY);
      return;
    }
    if (this.navPathStack.size() > 0) {
      this.popInternal();
      return;
    }
    // @Watch 正处于 AppStorage 状态刷新事务中，直接关闭会吞掉外层 opacity 动画。
    // 下一任务再进入与“取消”按钮相同的普通关闭路径，让淡出动画正常起播。
    setTimeout(() => {
      this.closeSearchFlow();
    }, 0);
  }

  private consumeTopicDetailBack(): boolean {
    if (this.composerVisible) {
      bumpTick(COMPOSER_OVERLAY_BACK_TICK_KEY);
      return true;
    }
    this.popInternal();
    return true;
  }

  private popInternal(): void {
    if (this.navPathStack.size() > 0) {
      this.navPathStack.pop();
    }
  }

  private closeSearchFlow(): void {
    this.onClose();
  }

  // 正文里点链接:凡是「导航」都留在搜索自己的栈里,不关搜索页。
  // 原先只有 WEB 走站内 push,帖子链接 / @提及 一律 onClose() 交给外层,
  // 于是正文里点个 @某人,整个搜索结果就没了——与「点帖子能返回」自相矛盾。
  private handleOpenLink(url: string): void {
    const target: LinkTarget = LinkRouter.resolve(url);
    if (target.kind === LinkTargetKind.TOPIC && target.topicId !== undefined) {
      // 标题从链接里拿不到,留空由详情页自己加载;带楼号的链接落地即高亮该楼(对齐官网 anchor)。
      this.navPathStack.pushPath(new NavPathInfo(
        SEARCH_FLOW_TOPIC_DETAIL,
        buildTopicDetailRouteParam(target.topicId, undefined, '', target.postNumber, target.postNumber !== undefined)
      ));
      return;
    }
    if (target.kind === LinkTargetKind.USER && target.username !== undefined) {
      this.openUserProfile(target.username, '', '', 0);
      return;
    }
    if (target.kind === LinkTargetKind.DOWNLOAD) {
      // 下载是个动作不是跳转,交给外层触发原生下载即可,更没有理由把搜索页关掉。
      this.onOpenLink(url);
      return;
    }
    if (target.url.length === 0) {
      return;
    }
    this.navPathStack.pushPath(new NavPathInfo(
      SEARCH_FLOW_WEB,
      buildWebRouteParam(target.url)
    ));
  }

  // 帖子详情里点头像也走站内 push,与「搜索结果点用户」一致:
  // 原来是 onClose() + onOpenUser() 关掉整个搜索页再去主页,返回时搜索结果就没了。
  private openUserProfile(username: string, displayName: string, avatarTemplate: string, userId: number): void {
    if (username.length === 0) {
      return;
    }
    this.navPathStack.pushPath(new NavPathInfo(
      SEARCH_FLOW_USER_PROFILE,
      buildUserProfileRouteParam(username, displayName, avatarTemplate, userId)
    ));
  }
}
