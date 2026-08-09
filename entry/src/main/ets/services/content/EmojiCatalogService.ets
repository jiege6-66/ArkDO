import { AppConstants } from '../../common/constants/AppConstants';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { Log } from '../logging/Log';
import { emojiCount, loadEmojiUrlsFromJson, resetEmojiUrls } from '../../views/components/EmojiUrlRegistry';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const LOG_TAG: string = '[ArkDO][EmojiCatalog]';
const CACHE_DIR_NAME: string = 'emoji_catalog';
// 表情表不常变,一天刷一次足够。过期只影响"新加的自定义表情多久能看到",不影响可用性。
const REFRESH_INTERVAL_MS: number = 24 * 60 * 60 * 1000;
// 站点返回的表情表异常大时不落盘,免得一个坏站点把沙箱撑爆。linux.do 那份约 284KB,留足余量。
const MAX_CATALOG_BYTES: number = 4 * 1024 * 1024;

/**
 * 表情字典的获取与缓存。
 *
 * 数据源是 Discourse 标准接口 `GET /emojis.json` —— 它的响应结构与原先内置的那份
 * 284KB rawfile **完全一致**,所以解析逻辑一行未改,只是把来源从"打进包里"换成"按站点拉取"。
 * 内置那份只对 linux.do 成立:别的论坛自定义表情组完全不同,拿 linux.do 的表去渲染
 * 等于给用户看一堆不存在的图。
 *
 * ## 三级取数
 * 1. **内存**:已加载且是当前站点的,直接用。
 * 2. **磁盘缓存**(`filesDir/emoji_catalog/<host>.json`):冷启动/切站时立即可用,不等网络。
 *    表情选择器和作者状态表情因此不会空着等一个来回。
 * 3. **网络**:缓存缺失时立刻拉;缓存存在但超过一天,先用缓存再后台刷新(不阻塞 UI)。
 *
 * 拉不到就保持空表 —— 消费方本就按"查不到"降级(getEmojiUrl 返回 undefined、
 * 调用方跳过渲染),不会出错,只是选择器暂时没内容。
 */
export class EmojiCatalogService {
  // 内存里这份表属于哪个站点。与当前站点不一致即视为失效 —— 切站后必须重取。
  private static loadedHost: string = '';
  // 同一站点的并发请求只发一次:首页与表情选择器可能同时触发。
  private static inflight: Map<string, Promise<void>> = new Map();

  /**
   * 确保当前站点的表情表可用。可安全重复调用(命中内存即返回)。
   * 不 await 也没问题:它内部自己管并发与错误,失败只是留一张空表。
   */
  static async ensureLoaded(context: common.Context, bridge: JsonNetworkClient): Promise<void> {
    const host: string = AppConstants.HOST;
    if (host.length === 0) {
      return;
    }
    if (EmojiCatalogService.loadedHost === host && emojiCount() > 0) {
      return;
    }
    const running: Promise<void> | undefined = EmojiCatalogService.inflight.get(host);
    if (running) {
      return running;
    }
    const task: Promise<void> = EmojiCatalogService.load(context, bridge, host);
    EmojiCatalogService.inflight.set(host, task);
    try {
      await task;
    } finally {
      EmojiCatalogService.inflight.delete(host);
    }
  }

  /** 切站:丢掉内存里上一个站点的表。新站的表由 ensureLoaded 重新取。 */
  static onSiteChanged(): void {
    if (EmojiCatalogService.loadedHost.length > 0) {
      Log.i(`${LOG_TAG} reset (was ${EmojiCatalogService.loadedHost})`);
    }
    EmojiCatalogService.loadedHost = '';
    resetEmojiUrls();
  }

  // ==================== 内部 ====================

  private static async load(context: common.Context, bridge: JsonNetworkClient, host: string): Promise<void> {
    const cached: string = EmojiCatalogService.readCache(context, host);
    if (cached.length > 0) {
      const count: number = loadEmojiUrlsFromJson(cached);
      EmojiCatalogService.loadedHost = host;
      Log.i(`${LOG_TAG} loaded from cache host=${host} count=${count}`);
      // 缓存够新就到此为止;过期则后台刷新,不让用户等。
      if (!EmojiCatalogService.isCacheStale(context, host)) {
        return;
      }
      EmojiCatalogService.fetchAndStore(context, bridge, host, true);
      return;
    }
    await EmojiCatalogService.fetchAndStore(context, bridge, host, false);
  }

  // background=true 时纯后台刷新:失败不影响已在用的缓存,也不改 loadedHost。
  private static async fetchAndStore(context: common.Context, bridge: JsonNetworkClient,
    host: string, background: boolean): Promise<void> {
    const response: NetworkResult<string> = await bridge.getJson('/emojis.json');
    // 站点可能在响应回来之前被切走 —— 那这份数据属于上一个站,丢掉。
    if (AppConstants.HOST !== host) {
      Log.i(`${LOG_TAG} discard response: site changed (was ${host})`);
      return;
    }
    if (!response.success || !response.data || response.data.length === 0) {
      Log.i(`${LOG_TAG} fetch failed host=${host} status=${response.statusCode} background=${background}`);
      return;
    }
    const count: number = loadEmojiUrlsFromJson(response.data);
    if (count === 0) {
      Log.i(`${LOG_TAG} fetch parsed 0 entries host=${host}, keep as-is`);
      return;
    }
    EmojiCatalogService.loadedHost = host;
    EmojiCatalogService.writeCache(context, host, response.data);
    Log.i(`${LOG_TAG} fetched host=${host} count=${count} background=${background}`);
  }

  private static dirOf(context: common.Context): string {
    return `${context.filesDir}/${CACHE_DIR_NAME}`;
  }

  // 文件名用 host。host 里只可能出现域名合法字符(字母数字点横线),不必转义。
  private static pathOf(context: common.Context, host: string): string {
    return `${EmojiCatalogService.dirOf(context)}/${host}.json`;
  }

  private static readCache(context: common.Context, host: string): string {
    const path: string = EmojiCatalogService.pathOf(context, host);
    try {
      if (!fileIo.accessSync(path)) {
        return '';
      }
      return fileIo.readTextSync(path);
    } catch (err) {
      Log.i(`${LOG_TAG} read cache failed host=${host}: ${JSON.stringify(err)}`);
      return '';
    }
  }

  private static isCacheStale(context: common.Context, host: string): boolean {
    try {
      const stat: fileIo.Stat = fileIo.statSync(EmojiCatalogService.pathOf(context, host));
      return Date.now() - stat.mtime * 1000 > REFRESH_INTERVAL_MS;
    } catch (err) {
      // 取不到时间就当过期:多刷一次的代价远小于永远用着旧表。
      return true;
    }
  }

  private static writeCache(context: common.Context, host: string, json: string): void {
    if (json.length > MAX_CATALOG_BYTES) {
      Log.i(`${LOG_TAG} skip cache host=${host}: payload too large (${json.length} bytes)`);
      return;
    }
    try {
      const dir: string = EmojiCatalogService.dirOf(context);
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
      }
      const path: string = EmojiCatalogService.pathOf(context, host);
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, json);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      Log.i(`${LOG_TAG} write cache failed host=${host}: ${JSON.stringify(err)}`);
    }
  }
}
