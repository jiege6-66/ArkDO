import { ForumOnboardingPage } from '../views/pages/ForumOnboardingPage';
import { RootTabPage } from '../views/pages/RootTabPage';
import { ACTIVE_FORUM_URL_KEY, bumpTick, HOME_COMPOSER_BACK_TICK_KEY, HOME_COMPOSER_VISIBLE_KEY,
  IMAGE_VIEWER_BACK_TICK_KEY, IMAGE_VIEWER_VISIBLE_KEY, SEARCH_OVERLAY_BACK_TICK_KEY,
  SEARCH_OVERLAY_VISIBLE_KEY } from '../common/constants/StorageKeys';

@Entry
@Component
struct Index {
  // 当前论坛地址镜像。空串 = 一个论坛都没添加,此时整个 App 没有可用的站点地址,
  // 主界面的任何一屏都进不去,故顶替成引导页。用户添完第一个论坛,该镜像被写入,
  // 本组件重建为主界面 —— 引导只在这一条件下出现,不需要额外的「是否已引导过」标记。
  @StorageProp(ACTIVE_FORUM_URL_KEY) private activeForumUrl: string = '';
  // 搜索覆盖层可见态镜像:SearchFlow 不进主 Navigation 栈,系统返回键需在此拦截后交给它处理。
  @StorageProp(SEARCH_OVERLAY_VISIBLE_KEY) private searchOverlayVisible: boolean = false;
  // 图片预览可见态镜像:同为根级浮层,返回键在此拦截(翻回上一张/首图关闭,由 ImageViewer 消费)。
  @StorageProp(IMAGE_VIEWER_VISIBLE_KEY) private imageViewerVisible: boolean = false;
  // 首页发帖浮层可见态镜像:首页坐在 navBar,其根级浮层的返回键也在此拦截。
  @StorageProp(HOME_COMPOSER_VISIBLE_KEY) private homeComposerVisible: boolean = false;

  build() {
    Column() {
      if (this.activeForumUrl.length === 0) {
        ForumOnboardingPage()
      } else {
        RootTabPage()
      }
    }
    .width('100%')
    .height('100%')
  }

  // 返回键:根级浮层优先消费;搜索覆盖层内部自己决定 pop Web/详情页还是关闭搜索。
  onBackPress(): boolean {
    // 引导页没有可返回的上一层,也不该被返回键退出到空白主界面 —— 交给系统去后台。
    if (this.activeForumUrl.length === 0) {
      return false;
    }
    // 图片预览在最顶层,优先消费:bump 信号,ImageViewer 决定翻回上一张还是关闭。
    if (this.imageViewerVisible) {
      bumpTick(IMAGE_VIEWER_BACK_TICK_KEY);
      return true;
    }
    if (this.searchOverlayVisible) {
      bumpTick(SEARCH_OVERLAY_BACK_TICK_KEY);
      return true;
    }
    // 首页发帖浮层:开着就消费返回键,bump tick 让 HomePage 关闭。
    if (this.homeComposerVisible) {
      bumpTick(HOME_COMPOSER_BACK_TICK_KEY);
      return true;
    }
    return false;
  }
}
