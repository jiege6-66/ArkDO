import { Log } from '../services/logging/Log';
import { CurrentSite } from '../services/site/CurrentSite';
import { AbilityConstant, Configuration, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { ThemeManager } from '../common/theme/ThemeManager';
import { BreakpointManager } from '../common/utils/BreakpointManager';
import { ImmersiveWindow } from '../common/utils/ImmersiveWindow';
import { DohManager } from '../services/network/DohManager';
import { FileLogger } from '../services/logging/FileLogger';
import { AppStateEventBus } from '../services/session/AppStateEventBus';
import { WebSessionManager } from '../services/web/WebSessionManager';
import { LINUXDO_FA_SYMBOLS_RAWFILE, loadFaIconsFromRawContent } from '../views/components/FaIcon';
import { LINUXDO_TAG_ICONS_RAWFILE, loadTagIconsFromRawContent } from '../views/components/TagIconRegistry';
import { ArkWebNetworkBridge } from '../services/network/ArkWebNetworkBridge';
import { LoginGate } from '../services/session/LoginGate';
import { parsePushNotificationRouteFromParameters, PushNotificationRoute, describePushNotificationRoute } from '../services/push/PushNotificationNavigation';
import { PushNotificationNavigationEventBus } from '../services/push/PushNotificationNavigationEventBus';
import { PushTokenUpdateEventBus } from '../services/push/PushTokenUpdateEventBus';
import { loadPushRelayConfigFromRawContent, PUSH_RELAY_CONFIG_RAWFILE } from '../services/push/PushRelayConfig';
import { pushService } from '@kit.PushKit';
import { HoldingHandManager } from '../common/utils/HoldingHandManager';
import { RealtimeTopicsPrefs } from '../services/realtime/RealtimeTopicsPrefs';
import { BadgeFilterPrefs } from '../services/home/BadgeFilterPrefs';
import { LotteryTipPrefs } from '../services/topic/LotteryTipPrefs';
import { RealtimePostsPrefs } from '../services/realtime/RealtimePostsPrefs';
import { FabGlassPrefs } from '../common/ui/FabGlassPrefs';
import { TopicListStylePrefs } from '../common/theme/TopicListStylePrefs';
import { AnimatedAvatarPrefs } from '../services/avatar/AnimatedAvatarPrefs';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private crashObserverId: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 日志系统须最先初始化,后续经 Log 门面写入的日志才能落盘。
    FileLogger.init(this.context);
    this.handlePushNotificationWant(want, 'onCreate');
    // 计时锚点①:应用启动。与首页帖子列表开始加载的日志配对,测量冷启动到首屏拉取的耗时。
    Log.i(`[ArkDO][Startup] stage=appOnCreate ts=${Date.now()}`);
    this.registerCrashHandler();
    // 当前论坛:必须排在最前面。全 app 的 BASE_URL / LOGIN_URL / HOST_BOOTSTRAP_URL 都由它
    // 派生,DoH 要按它的域名下发、宿主 webview 要按它的 origin 引导、首页要按它拉列表——
    // 任何一项跑在它前面都会拿到空地址。未配置论坛时保持未配置状态,由首启引导页接手。
    CurrentSite.init(this.context);
    // 登录态镜像绑定磁盘,须早于任何页面读取 AppStorage:冷启动即恢复上次登录态,
    // 避免已登录用户在首个会话检查回来前被误判为游客(阅读追踪不启动、写操作被拦)。
    LoginGate.initPersist();
    ThemeManager.init(this.context);
    // 响应式断点监听:决定平板横屏双栏 / 竖屏单栏,须早于首页渲染写入初始值。手机恒为非宽屏。
    BreakpointManager.init();
    HoldingHandManager.init(this.context);
    // 「首页新话题提醒」开关：读盘并种入 AppStorage 镜像，须早于宿主 webview 与首页挂载，
    // 保证首个 onPageEnd 的注入决策拿到正确值(默认关⇒不注入长轮询)。
    RealtimeTopicsPrefs.load(this.context);
    BadgeFilterPrefs.load(this.context);
    // 「抽奖帖提醒」开关：读盘并种入 AppStorage 镜像，须早于详情页挂载(默认开)，
    // 否则从推送/通知直开抽奖帖时提醒卡会晚一帧才冒出来。
    LotteryTipPrefs.load(this.context);
    // 「帖子内新回复提醒」开关：读盘并种入 AppStorage 镜像，须早于详情页挂载(默认开)。
    RealtimePostsPrefs.load(this.context);
    // 「悬浮按钮玻璃效果」开关：读盘并种入 AppStorage 镜像，须早于首页/详情页 FAB 挂载，
    // 保证首帧 FAB 就按正确样式渲染(默认关⇒当前透明样式)。
    FabGlassPrefs.load(this.context);
    // 「帖子列表样式」(字号/字重/行高/行间距/头像):读盘并种入 AppStorage 镜像,须早于任何
    // 帖子列表挂载,保证首帧就按用户设置渲染,不出现「先按默认画一遍再跳成设置值」。
    TopicListStylePrefs.load(this.context);
    // 「动态头像」开关：读盘并种入 AppStorage 镜像，须早于任何列表挂载——UserAvatar 在
    // aboutToAppear 就要据此决定走原生 Image(可播动图)还是走桥取首帧(静态)。
    AnimatedAvatarPrefs.load(this.context);
    // setHttpDns 只有在 Web 引擎初始化之后才生效(引擎网络服务需先就绪),故须先显式
    // initializeWebEngine 再下发 DoH;且早于任何页面,确保宿主 webview 首次解析
    // linux.do 就走 DoH,规避被污染的系统 DNS。否则请求会以 useHttpDns:0 走系统 DNS 超时。
    try {
      webview.WebviewController.initializeWebEngine();
    } catch (err) {
      Log.e(`[ArkDO][EntryAbility] initializeWebEngine failed: ${JSON.stringify(err)}`);
    }
    DohManager.init(this.context);
    this.loadIconAssets();
    // 冷启动清空音视频缓存目录,避免下载文件无限堆积占存储。
    ArkWebNetworkBridge.clearMediaCacheDir(this.context);
    this.loadPushRelayConfig();
    this.registerPushTokenUpdate();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    this.handlePushNotificationWant(want, 'onNewWant');
  }

  // 系统配置变化(切深浅色、定时深色触发、字号等)。颜色模式转给 ThemeManager 刷新 appIsDark——
  // 资源色靠限定符自动翻转,但非资源染色(高亮底色、公式位图)只认这个布尔。
  onConfigurationUpdate(newConfig: Configuration): void {
    ThemeManager.applyConfiguration(newConfig);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    HoldingHandManager.destroy();
    this.unregisterCrashHandler();
    FileLogger.flush();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 常驻沉浸式:loadContent 前就切全屏布局并同步系统栏插图高度,首帧即按最终布局渲染,
    // 避免"先非全屏渲染一帧再跳全屏"的冷启动闪动。详见 ImmersiveWindow 注释。
    try {
      ImmersiveWindow.init(windowStage.getMainWindowSync());
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'immersive init failed: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      HoldingHandManager.activate();
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 回前台补读一次颜色模式:后台期间(或熄屏时定时深色触发)的变化未必有 onConfigurationUpdate,
    // 补这一手保证前台首帧的 appIsDark 一定与资源色一致。
    ThemeManager.applyConfiguration(this.context.config);
    AppStateEventBus.notifyForegroundChanged(true);
    HoldingHandManager.resume();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    AppStateEventBus.notifyForegroundChanged(false);
    HoldingHandManager.pause();
    // 退后台可能随即被系统回收,把缓冲日志强制落盘,避免丢最后一段。
    FileLogger.flush();
    // Discourse 的 `_t` 认证 cookie 每活跃约 10 分钟就被服务端轮换一次,新值先落在 Chromium
    // 内存 cookie 仓;若进程在后台被回收前未落盘,冷启动会从磁盘恢复过期旧 `_t` → 掉登录。
    // 退后台是被回收前最后可确定执行代码的时机,在此 flush 一次,保证磁盘快照=最新 `_t`。
    WebSessionManager.saveCookies('onBackground');
  }

  // 全局未捕获异常:崩溃堆栈写入日志并立即刷盘,导出日志里保留闪退现场。
  private registerCrashHandler(): void {
    try {
      this.crashObserverId = errorManager.on('error', {
        onUnhandledException: (errMsg: string): void => {
          Log.e(`[ArkDO][Crash] unhandledException: ${errMsg}`);
          FileLogger.flush();
        }
      });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'register crash handler failed: %{public}s', JSON.stringify(error));
    }
  }

  private unregisterCrashHandler(): void {
    if (this.crashObserverId < 0) {
      return;
    }
    try {
      errorManager.off('error', this.crashObserverId);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'unregister crash handler failed: %{public}s', JSON.stringify(error));
    }
    this.crashObserverId = -1;
  }

  private loadIconAssets(): void {
    try {
      const rawContent: Uint8Array = this.context.resourceManager.getRawFileContentSync(LINUXDO_FA_SYMBOLS_RAWFILE);
      const iconCount: number = loadFaIconsFromRawContent(rawContent);
      hilog.info(DOMAIN, 'testTag', 'Loaded Linux.do FontAwesome symbols: %{public}d', iconCount);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to load Linux.do FontAwesome symbols. Cause: %{public}s',
        JSON.stringify(err));
    }

    try {
      const rawContent: Uint8Array = this.context.resourceManager.getRawFileContentSync(LINUXDO_TAG_ICONS_RAWFILE);
      const tagIconCount: number = loadTagIconsFromRawContent(rawContent);
      hilog.info(DOMAIN, 'testTag', 'Loaded Linux.do tag icons: %{public}d', tagIconCount);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to load Linux.do tag icons. Cause: %{public}s',
        JSON.stringify(err));
    }

    // 表情表不在这里加载:它已改为按当前论坛从 /emojis.json 动态获取(EmojiCatalogService),
    // 由 RootTabPage 在宿主就绪后触发,冷启动先吃磁盘缓存。此处只留下与站点无关的图标字库。
  }

  // 载入随包的中继配置(relay-config.json,不进版本控制)。文件缺失属正常情况——
  // 自行编译且未配置中继时推送不可用,其余功能照常,故只记日志不报错。
  private loadPushRelayConfig(): void {
    try {
      const rawContent: Uint8Array = this.context.resourceManager.getRawFileContentSync(PUSH_RELAY_CONFIG_RAWFILE);
      const configured: boolean = loadPushRelayConfigFromRawContent(rawContent);
      Log.i(`[ArkDO][EntryAbility] push relay config loaded configured=${configured}`);
    } catch (err) {
      Log.i(`[ArkDO][EntryAbility] push relay config absent, push disabled unless set in settings`);
    }
  }

  // 设备 Push Token 轮换(重装/恢复出厂/系统侧刷新)后,中继里存的旧 token 就投不到本机了,
  // 推送会静默失效。这里只负责接住事件并广播,真正的重新登记由 RootTabPage 做(它才有登录态)。
  // 监听须挂在 UIAbility 上:pushService.on('tokenUpdate', ...) 要求传 Ability 实例。
  private registerPushTokenUpdate(): void {
    try {
      pushService.on('tokenUpdate', this, (token: string) => {
        Log.i(`[ArkDO][EntryAbility] push tokenUpdate tokenLength=${token.length}`);
        PushTokenUpdateEventBus.publish();
      });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Log.i(`[ArkDO][EntryAbility] push tokenUpdate subscribe failed code=${error.code} message=${error.message ?? ''}`);
    }
  }

  private handlePushNotificationWant(want: Want, source: string): void {
    try {
      const route: PushNotificationRoute | undefined = parsePushNotificationRouteFromParameters(want.parameters);
      if (!route) {
        Log.i(`[ArkDO][EntryAbility] push ${source} no route`);
        return;
      }
      Log.i(`[ArkDO][EntryAbility] push ${source} route path=${describePushNotificationRoute(route)}`);
      PushNotificationNavigationEventBus.publish(route);
    } catch (err) {
      Log.i(`[ArkDO][EntryAbility] push ${source} parse failed error=${JSON.stringify(err)}`);
    }
  }
}
