import { Log } from '../logging/Log';
import webview from '@ohos.web.webview';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ChallengeEventBus } from '../challenge/ChallengeEventBus';
import { DownloadEventBus } from '../content/DownloadEventBus';
import { detectChallenge } from './ChallengeDetector';
import { FileLogger } from '../logging/FileLogger';
import { ChallengeState, HttpHeaderEntry, JsonNetworkClient, JsonRequestOptions, NetworkErrorCode, NetworkResult } from './NetworkTypes';
import { buildMessageBusScript } from './webscript/MessageBusScriptTemplate';
import { createFetchScript, createFormScript, createHeaderedFetchScript, createImageFetchScript, createPostJsonScript,
  createPutScript, createUploadScript, REQUEST_ID_TOKEN } from './ArkWebFetchScriptFactory';
import { MessageBusEventBus } from '../message/MessageBusEventBus';

const MEDIA_DOWNLOAD_TIMEOUT_MS: number = 120000;
// 下载意图在队列里的最长存活时间。startDownload 成功返回不等于下载真的起得来(被 CF 拦、
// 连接失败、用户从系统层取消),那种情况下 onBeforeDownload 永远不来,意图就永久留在队里 ——
// 而队列是按 FIFO 认「这次回调是媒体还是附件」的,留一个死意图会让**此后所有**下载整体错位一格:
// 媒体被存进附件目录、等待者只能等满 120s 超时,附件则被当成媒体吞掉、不再弹「已下载」。
//
// 这个值要对齐的是「startDownload 到 onBeforeDownload 的间隔」,**不是**整个下载耗时:
// onBeforeDownload 是下载启动时的第一个回调,在任何字节传输之前就会到,正常只隔几百毫秒
// (它的作用就是让我们指定保存路径)。所以取十几秒足够宽松。
// 早先按媒体下载超时(120s+)来取是把两件事搞混了,后果是最常见的那条路径根本盖不住:
// 下载起不来、用户立刻重试时,死意图才几秒大、不会被清掉,照样错位。
const DOWNLOAD_INTENT_TTL_MS: number = 15000;
const BODY_LOG_CHUNK_SIZE: number = 3000;
// 响应体转储上限:仅对挑战/错误/异常响应保留头部证据(判定是挑战页还是数据),截断以控制日志体积。
const BODY_LOG_MAX_CHARS: number = 1500;
// 单个请求最多为「宿主重载」让路几轮。每轮各自带 HOST_RELOAD_READY_TIMEOUT_MS 超时,
// 所以这也是等待时长的硬上限,防止连环重载把请求无限期压住。
const HOST_READY_MAX_ROUNDS: number = 3;

function logNetwork(message: string): void {
  Log.i(`[ArkDO][Network] ${message}`);
}

function logNetworkBody(message: string): void {
  Log.i(`[ArkDO][Network][Body] ${message}`);
}

export interface ArkWebJsonExecutor {
  run(script: string): Promise<string>;
}

interface ArkWebResultReceiver {
  onJsonResult(requestId: string, payload: string): void;
  onBusEvent(payload: string): void;
}

interface WebFetchEnvelope {
  statusCode?: number;
  contentType?: string;
  cfMitigated?: string;
  body?: string;
  errorMessage?: string;
  // POST 诊断:本次使用的 CSRF token 来源(session/meta/none)与长度,用于定位 403 是否为 CSRF 不匹配。
  csrfSource?: string;
  csrfLength?: number;
}

class PendingJsonRequest {
  resolve: (value: string) => void;
  reject: (reason: string) => void;
  timeoutId: number;

  constructor(resolve: (value: string) => void, reject: (reason: string) => void, timeoutId: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timeoutId = timeoutId;
  }
}

// 一次下载意图:委托的 getUrl() 会被重写成跟随 302 后的 CDN 直链,无法按 URL 回认。
// 故每次发起下载按顺序入队一个意图,onBeforeDownload 按序出队即可辨别当前下载是媒体还是附件、
// 以及媒体对应的原始 URL(下载在单线程 native 队列中按发起顺序回调)。
class DownloadIntent {
  isMedia: boolean;
  url: string;
  // 入队时刻。onBeforeDownload 迟迟不来的意图会被当作「这次下载压根没起来」丢弃,见 pruneStaleIntents。
  queuedAt: number;

  constructor(isMedia: boolean, url: string) {
    this.isMedia = isMedia;
    this.url = url;
    this.queuedAt = Date.now();
  }
}

// 一次媒体下载的等待者:委托完成/失败后按原始 URL 找到它并 resolve 本地路径 / reject。
class MediaDownloadWaiter {
  resolve: (path: string) => void;
  reject: (reason: Object) => void;
  timeoutId: number;

  constructor(resolve: (path: string) => void, reject: (reason: Object) => void, timeoutId: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timeoutId = timeoutId;
  }
}

export class ArkWebCallbackProxy {
  private receiver: ArkWebResultReceiver;

  constructor(receiver: ArkWebResultReceiver) {
    this.receiver = receiver;
  }

  onJsonResult(requestId: string, payload: string): void {
    this.receiver.onJsonResult(requestId, payload);
  }

  onBusEvent(payload: string): void {
    this.receiver.onBusEvent(payload);
  }
}

class WebviewJsonExecutor implements ArkWebJsonExecutor, ArkWebResultReceiver {
  private controller: webview.WebviewController;
  private callbackProxy: ArkWebCallbackProxy = new ArkWebCallbackProxy(this);
  private pendingRequests: Map<string, PendingJsonRequest> = new Map();
  private requestSequence: number = 0;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  getCallbackProxy(): ArkWebCallbackProxy {
    return this.callbackProxy;
  }

  run(script: string): Promise<string> {
    const requestId: string = `arkdo_${this.requestSequence}`;
    this.requestSequence++;
    logNetwork(`ArkWeb executor start requestId=${requestId}`);

    return new Promise<string>((resolve: (value: string) => void, reject: (reason: string) => void) => {
      const timeoutId: number = setTimeout(() => {
        this.rejectRequest(requestId, 'ArkWeb 请求超时。');
      }, AppConstants.DEFAULT_TIMEOUT_MS);
      this.pendingRequests.set(requestId, new PendingJsonRequest(resolve, reject, timeoutId));

      try {
        this.controller.runJavaScript(script.replace(REQUEST_ID_TOKEN, requestId))
          .catch(() => {
            this.rejectRequest(requestId, 'ArkWeb 脚本执行失败。');
          });
      } catch (error) {
        this.rejectRequest(requestId, 'ArkWeb 脚本执行失败。');
      }
    });
  }

  onJsonResult(requestId: string, payload: string): void {
    const pendingRequest: PendingJsonRequest | undefined = this.pendingRequests.get(requestId);
    if (!pendingRequest) {
      logNetwork(`ArkWeb callback ignored requestId=${requestId}`);
      return;
    }

    logNetwork(`ArkWeb callback received requestId=${requestId} payloadLength=${payload.length}`);
    clearTimeout(pendingRequest.timeoutId);
    this.pendingRequests.delete(requestId);
    pendingRequest.resolve(payload);
  }

  onBusEvent(payload: string): void {
    MessageBusEventBus.publishPayload(payload);
  }

  private rejectRequest(requestId: string, message: string): void {
    const pendingRequest: PendingJsonRequest | undefined = this.pendingRequests.get(requestId);
    if (!pendingRequest) {
      return;
    }

    logNetwork(`ArkWeb executor reject requestId=${requestId} reason=${message}`);
    clearTimeout(pendingRequest.timeoutId);
    this.pendingRequests.delete(requestId);
    pendingRequest.reject(message);
  }
}

/** 经 host webview 取到的二进制资源(头像等):base64 是原始字节的 base64,失败时 ok=false。 */
export interface ImageFetchResult {
  ok: boolean;
  base64: string;
  contentType: string;
}

export class ArkWebNetworkBridge implements JsonNetworkClient {
  private executor?: ArkWebJsonExecutor;
  private webviewExecutor?: WebviewJsonExecutor;
  // host webview 是否正在被 loadUrl 重载。重载期间注入的 fetch 会落在正被销毁的文档上,
  // 因此排队等待,直到重载后的 onPageEnd 再执行。默认 false = 就绪,不影响正常请求。
  private reloading: boolean = false;
  private readyWaiters: Array<() => void> = [];
  // 已发出、但还没等到「自己那一次」onPageEnd 的 loadUrl 笔数。
  //
  // 光靠 reloading 这个布尔量不够:两次重载叠在一起时(典型链路 —— 过盾成功广播会话变更触发重载,
  // 抢在关门前发出的请求因文档被销毁而失败,又触发一次网络自愈重载),第一次的 onPageEnd 会把门闩
  // 打开、放行整个队列,而此时第二次 loadUrl 已经在途 —— 请求注进一个马上被销毁的文档,回调永远
  // 不来,只能干等到执行器 15s 超时。计数保证「最后一次重载真正落地」才放行。
  private outstandingLoads: number = 0;
  // host webview 控制器与其原生下载委托:附件下载走它,天然带会话 Cookie、自动跟随 302 到 CDN、不受 CORS 限制。
  private controller?: webview.WebviewController;
  private downloadContext?: Context;
  private downloadDelegateReady: boolean = false;
  // 媒体下载(音视频)复用同一下载委托。CF 会对非浏览器客户端(fetch/http/AVPlayer)返回 403,
  // 唯有 host webview(Chromium)下载能过盾、跟 302、带 cookie。按 URL 缓存本地路径 + 并发去重;
  // guid→url 用于在委托完成回调里把结果对回到正确的等待者(而非走附件的「用系统打开」通用流程)。
  private mediaWaiters: Map<string, MediaDownloadWaiter> = new Map();
  private mediaInflight: Map<string, Promise<string>> = new Map();
  private mediaGuidUrl: Map<string, string> = new Map();
  private mediaCache: Map<string, string> = new Map();
  // 下载意图 FIFO:按发起顺序入队,onBeforeDownload 出队辨别媒体/附件。
  private downloadIntents: DownloadIntent[] = [];

  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
    this.setExecutor(this.ensureWebviewExecutor(controller));
    this.configureDownloadDelegate();
  }

  // 清空媒体缓存目录(音视频下到 filesDir/media_cache)。冷启动时调用,避免缓存无限增长;
  // 同会话内文件保留以便重复播放不重复下载。不碰附件目录 download(那是用户主动下的文件)。
  static clearMediaCacheDir(context: Context): void {
    const dir: string = `${context.filesDir}/media_cache`;
    try {
      if (fs.accessSync(dir)) {
        fs.rmdirSync(dir);
        Log.i(`[ArkDO][Network] media cache cleared dir=${dir}`);
      }
    } catch (error) {
      Log.i(`[ArkDO][Network] media cache clear failed error=${JSON.stringify(error)}`);
    }
  }

  // 记录用于保存下载文件的沙箱上下文(filesDir)。在 host 就绪前由页面注入一次。
  setDownloadContext(context: Context): void {
    this.downloadContext = context;
    this.configureDownloadDelegate();
  }

  // 触发一次附件下载。成功交给 host webview 的下载委托,结果经 DownloadEventBus 上抛。
  startDownload(url: string): boolean {
    if (!this.controller) {
      Log.i('[ArkDO][Network] startDownload skipped: controller not ready');
      return false;
    }
    this.downloadIntents.push(new DownloadIntent(false, url));
    try {
      this.controller.startDownload(url);
      return true;
    } catch (error) {
      this.downloadIntents.pop();
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] startDownload failed code=${err.code} msg=${err.message}`);
      return false;
    }
  }

  // 触发一次媒体下载(音视频),返回下到沙箱后的本地文件路径。走 host webview 下载委托过 CF。
  // 已下过的直接命中缓存;进行中的复用同一 Promise(去重),避免重复播放重复下载。
  downloadMedia(url: string): Promise<string> {
    const cached: string | undefined = this.mediaCache.get(url);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const pending: Promise<string> | undefined = this.mediaInflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    if (!this.controller) {
      return Promise.reject(new Error('宿主尚未就绪'));
    }
    const promise: Promise<string> = new Promise<string>((resolve: (path: string) => void, reject: (reason: Object) => void) => {
      const timeoutId: number = setTimeout(() => {
        this.settleMediaFailure(url, new Error('媒体下载超时'));
      }, MEDIA_DOWNLOAD_TIMEOUT_MS);
      this.mediaWaiters.set(url, new MediaDownloadWaiter(resolve, reject, timeoutId));
    });
    this.mediaInflight.set(url, promise);
    this.downloadIntents.push(new DownloadIntent(true, url));
    try {
      this.controller.startDownload(url);
    } catch (error) {
      this.downloadIntents.pop();
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] downloadMedia start failed code=${err.code}`);
      this.settleMediaFailure(url, new Error('媒体下载启动失败'));
    }
    return promise;
  }

  // 丢掉队首那些早就该被消费掉的意图。只从队首扫(队列按入队时间有序),遇到还新鲜的就停。
  private pruneStaleIntents(): void {
    const deadline: number = Date.now() - DOWNLOAD_INTENT_TTL_MS;
    let dropped: number = 0;
    while (this.downloadIntents.length > 0 && this.downloadIntents[0].queuedAt < deadline) {
      this.downloadIntents.shift();
      dropped++;
    }
    if (dropped > 0) {
      Log.i(`[ArkDO][Network] dropped ${dropped} stale download intent(s)`);
    }
  }

  private settleMediaSuccess(url: string, path: string): void {
    this.mediaInflight.delete(url);
    this.mediaCache.set(url, path);
    const waiter: MediaDownloadWaiter | undefined = this.mediaWaiters.get(url);
    if (waiter) {
      this.mediaWaiters.delete(url);
      clearTimeout(waiter.timeoutId);
      waiter.resolve(path);
    }
  }

  private settleMediaFailure(url: string, reason: Object): void {
    this.mediaInflight.delete(url);
    // 刻意**保留** guid→url 映射,即使这次是超时失败。
    //
    // 那条映射是迟到的下载回调唯一的身份凭据:120s 超时先响之后,字节仍可能在 130s 到达,
    // 此时若映射已被清掉,onDownloadFinish 认不出它是媒体 —— 会落进附件分支,
    // 给一个只是想播放视频的用户弹「已下载:xxx.mp4」,而且 settleMediaSuccess 不跑、
    // mediaCache 不写,文件明明已经躺在 media_cache 里,再点播放还要从头重下一遍。
    // 保留映射则相反:迟到的完成回调照常写缓存,用户重试直接命中。
    // 代价只是「既不完成也不失败」的下载会留下一条几十字节的记录,随进程消亡,可以接受。
    const waiter: MediaDownloadWaiter | undefined = this.mediaWaiters.get(url);
    if (waiter) {
      this.mediaWaiters.delete(url);
      clearTimeout(waiter.timeoutId);
      waiter.reject(reason);
    }
  }

  // 给 host 控制器挂下载委托:onBeforeDownload 选沙箱保存路径并启动;完成/失败经 DownloadEventBus 通知页面
  // (媒体下载则对回到 downloadMedia 的等待者)。需控制器与保存上下文都就绪,且只挂一次。
  private configureDownloadDelegate(): void {
    if (this.downloadDelegateReady || !this.controller || !this.downloadContext) {
      return;
    }
    const context: Context = this.downloadContext;
    const attachmentDir: string = `${context.filesDir}/download`;
    const mediaDir: string = `${context.filesDir}/media_cache`;
    try {
      const delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
      delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
        // 先按发起顺序出队意图:委托的 getUrl() 已是 CDN 直链,无法回认,故靠 FIFO 顺序辨别媒体/附件。
        // 出队前先清掉过期意图,避免一次「起不来的下载」把队列永久错开一格(见 DOWNLOAD_INTENT_TTL_MS)。
        this.pruneStaleIntents();
        const intent: DownloadIntent | undefined = this.downloadIntents.shift();
        const isMedia: boolean = intent !== undefined && intent.isMedia;
        // 媒体下到独立目录(便于整目录清理、不误删用户附件);附件仍到 download。
        const dir: string = isMedia ? mediaDir : attachmentDir;
        try {
          if (!fs.accessSync(dir)) {
            fs.mkdirSync(dir);
          }
        } catch (error) {
          const err: BusinessError = error as BusinessError;
          Log.i(`[ArkDO][Network] download dir failed code=${err.code}`);
        }
        const suggested: string = item.getSuggestedFileName();
        const fileName: string = suggested && suggested.length > 0 ? suggested : `download_${item.getGuid()}`;
        item.start(`${dir}/${fileName}`);
        // 媒体:用 guid 记住它对应的原始 URL(media 等待者以原始 URL 为键)。
        if (isMedia && intent) {
          this.mediaGuidUrl.set(item.getGuid(), intent.url);
        }
      });
      delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
        const fullPath: string = item.getFullPath();
        const guid: string = item.getGuid();
        const mediaUrl: string | undefined = this.mediaGuidUrl.get(guid);
        if (mediaUrl !== undefined) {
          this.mediaGuidUrl.delete(guid);
          Log.i(`[ArkDO][Network] media download finished path=${fullPath}`);
          this.settleMediaSuccess(mediaUrl, fullPath);
          return;
        }
        const fileName: string = fullPath.substring(fullPath.lastIndexOf('/') + 1);
        DownloadEventBus.notify({ success: true, fileName, filePath: fullPath, message: `已下载：${fileName}` });
      });
      delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
        const guid: string = item.getGuid();
        const mediaUrl: string | undefined = this.mediaGuidUrl.get(guid);
        if (mediaUrl !== undefined) {
          this.mediaGuidUrl.delete(guid);
          Log.i('[ArkDO][Network] media download failed');
          this.settleMediaFailure(mediaUrl, new Error('媒体下载失败'));
          return;
        }
        const suggested: string = item.getSuggestedFileName();
        DownloadEventBus.notify({ success: false, fileName: suggested, filePath: '', message: '下载失败' });
      });
      this.controller.setDownloadDelegate(delegate);
      this.downloadDelegateReady = true;
      Log.i('[ArkDO][Network] download delegate configured');
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] configure download delegate failed code=${err.code}`);
    }
  }

  // 只关门,不计数。给「先关门,随后由别处真正 loadUrl」的调用方用(登录成功/登出/DoH 变更:
  // 它们广播 SessionEventBus,由 ArkWebHost 去发 loadUrl)。抢在广播之前关门,才能让同一批
  // 监听者里跑在 ArkWebHost 之前的那些请求也排进队列,而不是注进一个即将被销毁的文档。
  markHostReloading(): void {
    this.reloading = true;
  }

  // 关门 + 记一笔在途重载。给真正调 loadUrl 的地方用,必须与其后的 markHostReady() 配对。
  markHostLoadIssued(): void {
    this.reloading = true;
    this.outstandingLoads++;
  }

  // 主动重载 host 首页:一次真实页面导航,让 CF 挑战 JS 在真浏览器环境里运行以拿 cf_clearance
  // (fetch 拿到的挑战页无法执行 JS)。用于挑战恢复协调器静默过盾;onPageEnd 会放行排队的 fetch。
  reloadHost(): boolean {
    if (!this.controller) {
      Log.i('[ArkDO][Network] reloadHost skipped: controller not ready');
      return false;
    }
    try {
      this.markHostLoadIssued();
      this.controller.loadUrl(AppConstants.HOST_BOOTSTRAP_URL);
      return true;
    } catch (error) {
      // loadUrl 抛异常时不会有后续 onPageEnd,立即放行等待者以免请求悬住。
      this.markHostReady();
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] reloadHost failed code=${err.code}`);
      return false;
    }
  }

  // host webview 首屏是否已真正就绪到可发请求（executor 已在 onPageEnd → attachController 里挂上）。
  // 与 RootTabPage 的 isArkWebReady（UI 解锁标志）不同：看门狗/失败路径会把 isArkWebReady 置真以解锁
  // 导航，但那一刻 executor 仍为空，任何 fetch 都会被 getJson 等直接跳过（skipped: not ready）。
  // 首页用它区分「桥能真发请求」与「UI 已解锁」，避免在冷启动空窗里硬闪「加载失败」。
  // 重载中（reloading=true）executor 仍在，请求会经 whenHostReady 排队，故此处不看 reloading。
  canFetch(): boolean {
    return this.executor !== undefined;
  }

  // host webview 一次重载落地(onPageEnd),或那次 loadUrl 抛异常需要销账时调用:
  // 销掉一笔在途重载,只有全部落地才放行队列。还有更新的重载在途就继续压着 —— 现在放行等于
  // 把请求注进一个马上被下一次 loadUrl 销毁的文档。
  markHostReady(): void {
    if (this.outstandingLoads > 0) {
      this.outstandingLoads--;
    }
    if (this.outstandingLoads > 0) {
      logNetwork(`host page settled but ${this.outstandingLoads} reload(s) still in flight, keep gate closed`);
      return;
    }
    this.releaseHostWaiters();
  }

  // 兜底放行:清零在途计数并无条件开闸。给「不会再有 onPageEnd 了」的路径用 —— 首屏加载失败、
  // 看门狗超时、排队超时。计数万一因某次 loadUrl 没能产出 onPageEnd 而漂移,也由这里兜回来,
  // 不至于让门闩永久关死。
  forceHostReady(reason: string): void {
    if (this.outstandingLoads > 0 || this.reloading) {
      logNetwork(`force host ready reason=${reason} dropped=${this.outstandingLoads}`);
    }
    this.outstandingLoads = 0;
    this.releaseHostWaiters();
  }

  private releaseHostWaiters(): void {
    this.reloading = false;
    if (this.readyWaiters.length === 0) {
      return;
    }
    const waiters: Array<() => void> = this.readyWaiters;
    this.readyWaiters = [];
    for (let index: number = 0; index < waiters.length; index++) {
      waiters[index]();
    }
  }

  startMessageBus(): void {
    if (!this.controller) {
      logNetwork('MessageBus start skipped: controller not ready');
      return;
    }
    try {
      this.controller.runJavaScript(buildMessageBusScript()).catch(() => {
        logNetwork('MessageBus script injection failed');
      });
    } catch (error) {
      logNetwork('MessageBus script injection failed');
    }
  }

  // 与 startMessageBus 对称：置全局停止标志，让文档内正在跑的轮询循环下一轮自然退出。
  // controller 未就绪时 no-op——此时本就没有注入过循环。
  stopMessageBus(): void {
    if (!this.controller) {
      logNetwork('MessageBus stop skipped: controller not ready');
      return;
    }
    try {
      this.controller.runJavaScript(
        'window.__arkdoMessageBusStopRequested = true; window.__arkdoMessageBusStarted = false; ' +
        'window.__arkdoMessageBusGeneration = (window.__arkdoMessageBusGeneration || 0) + 1;'
      ).catch(() => {
        logNetwork('MessageBus stop injection failed');
      });
    } catch (error) {
      logNetwork('MessageBus stop injection failed');
    }
  }

  // 详情页动态订阅 /topic/<id>：注入到运行中的长轮询脚本（复用单例循环，不另起）。
  // position=打开帖子时的 message_bus_last_id（-1=只收新）。脚本已注入则即时加频道；
  // 未注入(loop 未跑)则兜底写持久集合 __arkdoMessageBusChannels，待下次 startMessageBus 并入。
  subscribeTopicChannel(topicId: number, position: number): void {
    this.subscribeChannel(`/topic/${topicId}`, position);
  }

  // 离开详情页时退订 /topic/<id>：删频道，下一轮 poll 不再携带它。
  unsubscribeTopicChannel(topicId: number): void {
    this.unsubscribeChannel(`/topic/${topicId}`);
  }

  // 通用：往运行中的长轮询循环动态订阅任意 MessageBus 频道(如 Presence 的 /presence/...)。
  // position=订阅起点游标(-1=只收新)。脚本已注入则即时加频道；未注入(loop 未跑)则兜底写持久集合，
  // 待下次 startMessageBus 并入。controller 未就绪时 skip。
  subscribeChannel(channelName: string, position: number): void {
    if (!this.controller) {
      logNetwork('MessageBus subscribeChannel skipped: controller not ready');
      return;
    }
    const channel: string = JSON.stringify(channelName);
    const pos: number = Number.isFinite(position) ? Math.floor(position) : -1;
    const script: string =
      `if (window.__arkdoMessageBusAddChannel) { window.__arkdoMessageBusAddChannel(${channel}, ${pos}); } ` +
      `else { window.__arkdoMessageBusChannels = window.__arkdoMessageBusChannels || {}; ` +
      `if (!(${channel} in window.__arkdoMessageBusChannels)) { window.__arkdoMessageBusChannels[${channel}] = ${pos}; } }`;
    try {
      this.controller.runJavaScript(script).catch(() => {
        logNetwork('MessageBus subscribeChannel injection failed');
      });
    } catch (error) {
      logNetwork('MessageBus subscribeChannel injection failed');
    }
  }

  unsubscribeChannel(channelName: string): void {
    if (!this.controller) {
      logNetwork('MessageBus unsubscribeChannel skipped: controller not ready');
      return;
    }
    const channel: string = JSON.stringify(channelName);
    const script: string =
      `if (window.__arkdoMessageBusRemoveChannel) { window.__arkdoMessageBusRemoveChannel(${channel}); } ` +
      `else if (window.__arkdoMessageBusChannels) { delete window.__arkdoMessageBusChannels[${channel}]; }`;
    try {
      this.controller.runJavaScript(script).catch(() => {
        logNetwork('MessageBus unsubscribeChannel injection failed');
      });
    } catch (error) {
      logNetwork('MessageBus unsubscribeChannel injection failed');
    }
  }

  // 醒来后要复查一次门闩再走:放行与本请求真正注入之间隔着一个微任务,期间完全可能又有新的
  // loadUrl 发出(会话变更/网络自愈常常连着来)。复查命中就重新排队,轮数设上限,免得重载风暴里
  // 无限续等 —— 超出上限就照发,让它走正常的失败/重试路径,总好过一直悬着。
  private async whenHostReady(): Promise<void> {
    for (let round: number = 0; round < HOST_READY_MAX_ROUNDS; round++) {
      if (!this.reloading) {
        return;
      }
      await this.awaitHostReadyOnce();
    }
    if (this.reloading) {
      logNetwork(`host still reloading after ${HOST_READY_MAX_ROUNDS} rounds, proceed anyway`);
    }
  }

  private awaitHostReadyOnce(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      // 兜底超时:万一重载信号丢失(onPageEnd 始终不触发),自愈放行并恢复就绪态,
      // 既不让本次请求永久悬住,也避免后续请求持续等待。
      const timeoutId: number = setTimeout(() => {
        this.forceHostReady('waiterTimeout');
      }, AppConstants.HOST_RELOAD_READY_TIMEOUT_MS);
      this.readyWaiters.push(() => {
        clearTimeout(timeoutId);
        resolve();
      });
    });
  }

  createJavaScriptProxy(controller: webview.WebviewController): JavaScriptProxy {
    const executor: WebviewJsonExecutor = this.ensureWebviewExecutor(controller);
    return {
      object: executor.getCallbackProxy(),
      name: 'ArkDOBridge',
      methodList: ['onJsonResult', 'onBusEvent'],
      controller: controller
    };
  }

  // 未选定论坛时不发请求:BASE_URL 为空,拼出来的会是 `/latest.json` 这种没有 host 的地址,
  // 打到宿主 webview 里等于向「about:blank 的同源」发请求,失败信息还很难看懂。
  // 正常路径上 Index 会用引导页顶掉主界面,不该走到这里;这里是兜住推送/通知等
  // 不经页面的后台链路,让它们拿到一条明确的失败而不是一串诡异报错。
  private noActiveSiteFailure(verb: string, requestPath: string): NetworkResult<string> {
    logNetwork(`${verb} ${requestPath} skipped: no active site`);
    return {
      success: false,
      statusCode: 0,
      challengeState: ChallengeState.NONE,
      error: {
        code: NetworkErrorCode.NETWORK_FAILURE,
        message: '尚未选择论坛。',
        requiresChallenge: false
      }
    };
  }

  setExecutor(executor: ArkWebJsonExecutor): void {
    this.executor = executor;
  }

  private hostNotReadyFailure(verb: string, requestPath: string): NetworkResult<string> {
    logNetwork(`${verb} ${requestPath} skipped: ArkWeb host is not ready`);
    return {
      success: false,
      statusCode: 0,
      challengeState: ChallengeState.NONE,
      error: {
        code: NetworkErrorCode.NETWORK_FAILURE,
        message: 'ArkWeb 宿主尚未就绪。',
        requiresChallenge: false
      }
    };
  }

  /**
   * 所有走「注入 fetch → 信封 → 挑战判定」的请求的公共骨架。
   *
   * 抽出来之前,getJson / postForm / postJson / uploadImage / putJson / sendFormWithBody 各自
   * 复制了同一段二十来行(查站点 → 查 executor → 等门闩 → run → JSON.parse → convertEnvelope
   * → catch),已经漂出过两处不一致:putJson 里有一段永远走不到的重复站点判断且日志动词标成了
   * 'GET',而除 getJson/putJson 外的写方法**根本没有站点判断** —— 未选论坛时推送等后台链路
   * 发出的写请求会拼出没有 host 的地址,报错难以理解。集中到这里后这两类问题都不可能再出现。
   *
   * verb 只用于日志(区分 GET / GET(headered) / POST(json) / UPLOAD…);method 参与
   * convertEnvelope 的判定(POST 会额外打印 CSRF 诊断),两者刻意分开。
   *
   * requireActiveSite=false 只给挂在副站点文档上的桥实例用(credit.linux.do):它的地址不由
   * 当前论坛派生,拿主站的「有没有选论坛」去拦它是错的。
   */
  private async execute(verb: string, requestPath: string, method: string,
    buildScript: () => string, options?: JsonRequestOptions,
    requireActiveSite: boolean = true): Promise<NetworkResult<string>> {
    if (requireActiveSite && !AppConstants.HAS_ACTIVE_SITE) {
      return this.noActiveSiteFailure(verb, requestPath);
    }

    const executor: ArkWebJsonExecutor | undefined = this.executor;
    if (!executor) {
      return this.hostNotReadyFailure(verb, requestPath);
    }

    await this.whenHostReady();

    try {
      const rawResult: string = await executor.run(buildScript());
      logNetwork(`${verb} ${requestPath} raw envelope received length=${rawResult.length}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, method, options);
    } catch (error) {
      logNetwork(`${verb} ${requestPath} failed before response envelope`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: 'ArkWeb 请求失败。',
          requiresChallenge: false
        }
      };
    }
  }

  async getJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    logNetwork(`GET ${requestPath} start`);
    return this.execute('GET', requestPath, 'GET', (): string => createFetchScript(requestPath), options);
  }

  /**
   * 带自定义头 + Referer 的 GET。与 getJson 同一条链路(注入 fetch → 信封 → 挑战判定),只是允许
   * 调用方补请求头与 Referer。给挂在副站点文档上的桥实例用(credit.linux.do 的接口要求
   * x-requested-with 与站内 referer);主站请求继续走 getJson,不受影响。
   */
  async getJsonWithHeaders(path: string, headers: HttpHeaderEntry[], referrer: string,
    options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    logNetwork(`GET(headered) ${requestPath} start headerCount=${headers.length}`);
    // 不查「有没有选论坛」:这条路是给副站点(credit.linux.do)的桥实例用的,它的地址
    // 不由当前论坛派生。
    return this.execute('GET(headered)', requestPath, 'GET',
      (): string => createHeaderedFetchScript(requestPath, headers, referrer), options, false);
  }

  /**
   * 经 host webview 取二进制资源(头像)并回传 base64。原生 Image/DownloadManager 走系统 netstack,
   * TLS 握手时明文 SNi=linux.do 被 RST 封锁(只有 webview 能用 ECH 藏 SNI 过盾),故头像必须走这条路。
   * 在 host 文档内 fetch → arrayBuffer → base64,复用 onJsonResult 回调通道。失败返回 ok=false。
   */
  async getImageBase64(target: string): Promise<ImageFetchResult> {
    if (!this.executor) {
      return { ok: false, base64: '', contentType: '' };
    }
    await this.whenHostReady();
    try {
      const rawResult: string = await this.executor.run(createImageFetchScript(target));
      const envelope: WebFetchEnvelope = JSON.parse(rawResult) as WebFetchEnvelope;
      const status: number = envelope.statusCode ? envelope.statusCode : 0;
      const body: string = envelope.body ? envelope.body : '';
      if (status >= 200 && status < 300 && body.length > 0) {
        return { ok: true, base64: body, contentType: envelope.contentType ? envelope.contentType : '' };
      }
      return { ok: false, base64: '', contentType: '' };
    } catch (error) {
      return { ok: false, base64: '', contentType: '' };
    }
  }

  async postForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    const referrer: string = options?.referrer ? options.referrer : '';
    logNetwork(`POST ${requestPath} start bodyLength=${body.length} referrer=${referrer}`);
    return this.execute('POST', requestPath, 'POST',
      (): string => createFormScript('POST', requestPath, body, referrer), options);
  }

  async postJson(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    const referrer: string = options?.referrer ? options.referrer : '';
    logNetwork(`POST(json) ${requestPath} start bodyLength=${body.length} referrer=${referrer}`);
    return this.execute('POST(json)', requestPath, 'POST',
      (): string => createPostJsonScript(requestPath, body, referrer), options);
  }

  // 上传图片到 /uploads.json:base64 是压缩后图片字节的 base64。脚本在 host 文档内 atob 还原字节 →
  // Blob → FormData → fetch(过 CF、带 cookie)。CSRF 复用同源逻辑;不手动设 Content-Type(FormData 自带 boundary)。
  async uploadImage(base64: string, fileName: string, mimeType: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = '/uploads.json';
    const referrer: string = options?.referrer ? options.referrer : '';
    logNetwork(`UPLOAD ${requestPath} start fileName=${fileName} base64Length=${base64.length}`);
    return this.execute('UPLOAD', requestPath, 'POST',
      (): string => createUploadScript(base64, fileName, mimeType, referrer), options);
  }

  async putJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    const referrer: string = options?.referrer ? options.referrer : '';
    logNetwork(`PUT ${requestPath} start referrer=${referrer}`);
    return this.execute('PUT', requestPath, 'PUT',
      (): string => createPutScript(requestPath, referrer), options);
  }

  async putForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    return this.sendFormWithBody('PUT', path, body, options);
  }

  async deleteForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    return this.sendFormWithBody('DELETE', path, body, options);
  }

  // PUT/DELETE + form body 的公共实现(投票/撤销投票用)。与 postForm 同源取 CSRF、带 cookie,
  // 仅 HTTP method 不同。
  private async sendFormWithBody(method: string, path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    const referrer: string = options?.referrer ? options.referrer : '';
    logNetwork(`${method} ${requestPath} start bodyLength=${body.length} referrer=${referrer}`);
    return this.execute(method, requestPath, method,
      (): string => createFormScript(method, requestPath, body, referrer), options);
  }

  private ensureWebviewExecutor(controller: webview.WebviewController): WebviewJsonExecutor {
    if (!this.webviewExecutor) {
      this.webviewExecutor = new WebviewJsonExecutor(controller);
    }
    return this.webviewExecutor;
  }

  private normalizePath(path: string): string {
    if (path.startsWith('/')) {
      return path;
    }
    return `/${path}`;
  }

  private convertEnvelope(path: string, envelope: WebFetchEnvelope, method: string, options?: JsonRequestOptions): NetworkResult<string> {
    // POST 专属诊断:打印本次 CSRF token 的来源与长度,用于比对成功/403 时 token 是否不同,定位 CSRF 问题。
    if (method === 'POST') {
      const csrfSource: string = envelope.csrfSource ? envelope.csrfSource : 'unknown';
      const csrfLength: number = envelope.csrfLength ? envelope.csrfLength : 0;
      logNetwork(`POST ${path} csrf source=${csrfSource} length=${csrfLength}`);
    }

    if (envelope.errorMessage) {
      logNetwork(`${method} ${path} envelope error=${envelope.errorMessage}`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: envelope.errorMessage,
          requiresChallenge: false
        }
      };
    }

    const statusCode: number = envelope.statusCode ? envelope.statusCode : 0;
    const contentType: string = envelope.contentType ? envelope.contentType : '';
    const cfMitigated: string = envelope.cfMitigated ? envelope.cfMitigated : '';
    const body: string = envelope.body ? envelope.body : '';
    const challengeState: ChallengeState = detectChallenge(statusCode, contentType, body, cfMitigated);
    logNetwork(`${method} ${path} response status=${statusCode} contentType=${contentType} bodyLength=${body.length} challenge=${challengeState}`);
    this.logResponseBody(path, contentType, body, method, statusCode, challengeState);

    if (challengeState !== ChallengeState.NONE) {
      logNetwork(`${method} ${path} requires challenge state=${challengeState}`);
      if (options?.notifyChallenge !== false) {
        ChallengeEventBus.notifyChallengeRequired(path, statusCode, challengeState);
      }
      return {
        success: false,
        statusCode: statusCode,
        challengeState: challengeState,
        error: {
          code: NetworkErrorCode.CHALLENGE_REQUIRED,
          message: '需要完成可见 Cloudflare 验证后重试。',
          requiresChallenge: true
        }
      };
    }

    if (statusCode < 200 || statusCode >= 300) {
      logNetwork(`${method} ${path} unexpected status=${statusCode}`);
      return {
        success: false,
        statusCode: statusCode,
        challengeState: ChallengeState.NONE,
        // 失败态也把 body 带上。Discourse 的 422 会在 body 里给 {"errors":["新用户不能上传附件"]}
        // 这类**能直接展示给用户**的原因;原先这里丢掉 body,上层只能显示「站点返回 HTTP 422」,
        // 用户完全不知道自己踩了哪条规则。success 仍为 false,既有调用方不会误读 data。
        data: body,
        error: {
          code: NetworkErrorCode.UNEXPECTED_RESPONSE,
          message: `站点返回 HTTP ${statusCode}。`,
          requiresChallenge: false
        }
      };
    }

    const result: NetworkResult<string> = {
      success: true,
      statusCode: statusCode,
      challengeState: ChallengeState.NONE,
      data: body
    };

    logNetwork(`${method} ${path} success status=${statusCode} bodyLength=${body.length}`);
    return result;
  }

  private logResponseBody(path: string, contentType: string, body: string, method: string, statusCode: number, challengeState: ChallengeState): void {
    // 成功的 JSON 响应体积大且无排查价值(status 行已记 bodyLength);仅在挑战/错误/异常响应时转储。
    if (!this.shouldLogResponseBody(contentType, body, statusCode, challengeState)) {
      return;
    }

    const formattedBody: string = this.formatBodyForLog(contentType, body);
    // 详细日志开关(设置里可开):开启时完整转储不截断,用于深挖某个具体响应;默认截断控制体积。
    const loggedBody: string = FileLogger.isVerbose() || formattedBody.length <= BODY_LOG_MAX_CHARS
      ? formattedBody
      : `${formattedBody.substring(0, BODY_LOG_MAX_CHARS)}...(truncated ${formattedBody.length - BODY_LOG_MAX_CHARS} chars)`;
    const chunkCount: number = Math.max(1, Math.ceil(loggedBody.length / BODY_LOG_CHUNK_SIZE));

    logNetworkBody(`${method} ${path} body begin contentType=${contentType} rawLength=${body.length} loggedLength=${loggedBody.length} chunks=${chunkCount}`);
    if (loggedBody.length === 0) {
      logNetworkBody(`${method} ${path} body chunk 1/1: `);
    }

    for (let start: number = 0; start < loggedBody.length; start += BODY_LOG_CHUNK_SIZE) {
      const chunkIndex: number = Math.floor(start / BODY_LOG_CHUNK_SIZE) + 1;
      const chunk: string = loggedBody.substring(start, start + BODY_LOG_CHUNK_SIZE);
      logNetworkBody(`${method} ${path} body chunk ${chunkIndex}/${chunkCount}: ${chunk}`);
    }
    logNetworkBody(`${method} ${path} body end`);
  }

  // 是否值得转储响应体:挑战页/HTTP 错误/成功但非 JSON 的意外响应(可能是未识别的软拦截页)才留;
  // 成功 JSON 和空体(如 timings 上报)一律跳过——这两类占日志体积绝大头且无排查价值。
  private shouldLogResponseBody(contentType: string, body: string, statusCode: number, challengeState: ChallengeState): boolean {
    if (FileLogger.isVerbose()) {
      return true;
    }
    if (challengeState !== ChallengeState.NONE || statusCode >= 400) {
      return true;
    }
    if (body.length === 0) {
      return false;
    }
    return contentType.toLowerCase().indexOf('application/json') < 0;
  }

  private formatBodyForLog(contentType: string, body: string): string {
    const normalizedContentType: string = contentType.toLowerCase();
    const trimmedBody: string = body.trim();
    const looksJson: boolean = normalizedContentType.indexOf('application/json') >= 0 ||
      trimmedBody.startsWith('{') ||
      trimmedBody.startsWith('[');

    if (!looksJson) {
      return body;
    }

    try {
      const parsedBody: Object = JSON.parse(body) as Object;
      const formattedBody: string = JSON.stringify(parsedBody, null, 2);
      return formattedBody;
    } catch (error) {
      return body;
    }
  }
}
