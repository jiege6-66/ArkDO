import { Log } from '../logging/Log';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ArkWebNetworkBridge, ImageFetchResult } from './ArkWebNetworkBridge';

/**
 * 经 host webview 取图字节并解码成 PixelMap 的通用引擎(头像与正文图共用)。
 *
 * 为什么必须有这条路:原生 Image 走系统 netstack,既会被 SNI 封锁(TLS 握手 RST),也完全吃不到
 * DoH —— DohManager 唯一的下发手段 webview.WebviewController.setHttpDns 只作用于 ArkWeb 内核。
 * 于是"接口能通、头像能出、正文图全白"就成了受限网络下的典型症状。这条路把 URL 交给 host 文档
 * fetch,与 API 请求同栈,DoH / 过盾 / Cookie 一并生效。
 *
 * 子类只提供参数:并发上限、已解码缓存条数上限、解码长边上限(头像天生小,正文大图要降采样)。
 */
export class BridgeImageLoader {
  private readonly logTag: string;
  private readonly maxConcurrency: number;
  private readonly maxCacheEntries: number;
  // 解码后长边上限(px),0 = 原尺寸解码。正文大图动辄 4000px 宽,整幅解进内存是几十 MB。
  private readonly maxPixelSide: number;
  private readonly cacheLogStep: number = 20;

  private bridge?: ArkWebNetworkBridge;
  private cache: Map<string, image.PixelMap> = new Map();
  private inflight: Map<string, Promise<image.PixelMap | undefined>> = new Map();
  private active: number = 0;
  private queue: Array<() => void> = [];
  private lastLoggedCacheBucket: number = -1;

  constructor(logTag: string, maxConcurrency: number, maxCacheEntries: number, maxPixelSide: number) {
    this.logTag = logTag;
    this.maxConcurrency = maxConcurrency;
    this.maxCacheEntries = maxCacheEntries;
    this.maxPixelSide = maxPixelSide;
  }

  /** 注入 host webview 的 bridge(唯一联通 host 文档的实例)。在 host 就绪处调用一次。 */
  attachBridge(bridge: ArkWebNetworkBridge): void {
    this.bridge = bridge;
  }

  /** 桥是否已就绪:没就绪时调用方不必白等一次注定 undefined 的 load。 */
  isReady(): boolean {
    return this.bridge !== undefined;
  }

  /**
   * 取原始字节的 base64(不解码、不缓存、不限流)。分享/保存要的是原图字节而非降采样后的
   * PixelMap,故单开这条口子。桥未就绪或取不到时返回空串。
   */
  async fetchBase64(url: string): Promise<string> {
    if (!this.bridge || url.length === 0) {
      return '';
    }
    const result: ImageFetchResult = await this.bridge.getImageBase64(url);
    if (!result.ok) {
      Log.i(`${this.logTag} bridge bytes failed url=${url}`);
      return '';
    }
    return result.base64;
  }

  /** 同步命中已解码缓存(供首帧直接显示,避免闪烁)。 */
  getCached(url: string): image.PixelMap | undefined {
    return this.cache.get(url);
  }

  debugSnapshot(): string {
    return `cache=${this.cache.size}/${this.maxCacheEntries} inflight=${this.inflight.size} active=${this.active} queue=${this.queue.length}`;
  }

  /** 取图 PixelMap:命中缓存直接返回;否则经 host webview 取字节并解码。失败返回 undefined。 */
  async load(url: string): Promise<image.PixelMap | undefined> {
    if (url.length === 0) {
      return undefined;
    }
    const cached: image.PixelMap | undefined = this.cache.get(url);
    if (cached) {
      return cached;
    }
    const pending: Promise<image.PixelMap | undefined> | undefined = this.inflight.get(url);
    if (pending) {
      return pending;
    }
    const task: Promise<image.PixelMap | undefined> = this.fetchAndDecode(url);
    this.inflight.set(url, task);
    try {
      return await task;
    } finally {
      this.inflight.delete(url);
    }
  }

  private async fetchAndDecode(url: string): Promise<image.PixelMap | undefined> {
    if (!this.bridge) {
      return undefined;
    }
    await this.acquire();
    try {
      // 直接把绝对 URL 交给 host 文档 fetch:同源(/user_avatar 等)与跨源 CDN(cdn/s3.ldstatic.com,
      // 回 ACAO=linux.do)都能读到字节,跨源分支在 bridge 脚本里用 credentials:'omit' 过 CORS。
      const result: ImageFetchResult = await this.bridge.getImageBase64(url);
      if (!result.ok) {
        Log.i(`${this.logTag} bridge fetch failed url=${url}`);
        return undefined;
      }
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(result.base64, util.Type.BASIC);
      if (this.isSvgImage(result.contentType, bytes)) {
        Log.i(`${this.logTag} skip svg url=${url}`);
        return undefined;
      }
      // 切出精确字节区间再交给解码器,避免 base64 解码结果带偏移/多余尾字节。
      const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const source: image.ImageSource = image.createImageSource(buffer);
      const pixelMap: image.PixelMap = await this.decode(source);
      source.release();
      this.put(url, pixelMap);
      return pixelMap;
    } catch (error) {
      Log.i(`${this.logTag} decode failed url=${url} err=${JSON.stringify(error)}`);
      return undefined;
    } finally {
      this.release();
    }
  }

  // 按 maxPixelSide 降采样解码;取不到原图尺寸或本就够小则原尺寸解码。
  private async decode(source: image.ImageSource): Promise<image.PixelMap> {
    if (this.maxPixelSide <= 0) {
      return await source.createPixelMap();
    }
    let info: image.ImageInfo | undefined = undefined;
    try {
      info = await source.getImageInfo();
    } catch (error) {
      info = undefined;
    }
    if (!info) {
      return await source.createPixelMap();
    }
    const width: number = info.size.width;
    const height: number = info.size.height;
    const longSide: number = Math.max(width, height);
    if (longSide <= 0 || longSide <= this.maxPixelSide) {
      return await source.createPixelMap();
    }
    const ratio: number = this.maxPixelSide / longSide;
    const desired: image.Size = {
      width: Math.max(1, Math.round(width * ratio)),
      height: Math.max(1, Math.round(height * ratio))
    };
    return await source.createPixelMap({ desiredSize: desired });
  }

  private put(url: string, pixelMap: image.PixelMap): void {
    let evicted: boolean = false;
    if (this.cache.size >= this.maxCacheEntries) {
      const oldest: string | undefined = this.cache.keys().next().value;
      if (oldest !== undefined) {
        // 只移除引用不 release：被淘汰的图可能仍绑定在某个 Image 上,release 会崩溃,交给 GC。
        this.cache.delete(oldest);
        evicted = true;
      }
    }
    this.cache.set(url, pixelMap);
    this.logCacheStatsIfNeeded(evicted);
  }

  private logCacheStatsIfNeeded(evicted: boolean): void {
    const bucket: number = Math.floor(this.cache.size / this.cacheLogStep);
    if (!evicted && bucket === this.lastLoggedCacheBucket) {
      return;
    }
    this.lastLoggedCacheBucket = bucket;
    Log.i(`${this.logTag} stats ${this.debugSnapshot()} evicted=${evicted}`);
  }

  private isSvgImage(contentType: string, bytes: Uint8Array): boolean {
    if (contentType.toLowerCase().indexOf('svg') >= 0) {
      return true;
    }
    const probeLength: number = Math.min(bytes.byteLength, 128);
    let head: string = '';
    for (let index: number = 0; index < probeLength; index++) {
      head += String.fromCharCode(bytes[index]);
    }
    const normalized: string = head.trim().toLowerCase();
    return normalized.startsWith('<?xml') || normalized.startsWith('<svg') || normalized.indexOf('<svg') >= 0;
  }

  private acquire(): Promise<void> {
    if (this.active < this.maxConcurrency) {
      this.active += 1;
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.queue.push((): void => {
        this.active += 1;
        resolve();
      });
    });
  }

  private release(): void {
    this.active -= 1;
    const next: (() => void) | undefined = this.queue.shift();
    if (next) {
      next();
    }
  }
}
