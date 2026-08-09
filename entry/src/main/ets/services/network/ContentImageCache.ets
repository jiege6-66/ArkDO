import { BridgeImageLoader } from './BridgeImageLoader';

const LOG_TAG: string = '[ArkDO][ContentImage]';
// 并发取图上限:正文图单张体积远大于头像(base64 过 runJavaScript 通道会再放大 1/3),
// 放得比头像小,避免一屏十几张图同时挤爆通道、把接口请求也拖慢。
const MAX_CONCURRENCY: number = 3;
// 已解码 PixelMap 缓存条数:正文大图单张内存是头像的几百倍,只留最近这些张。
const MAX_CACHE_ENTRIES: number = 24;
// 解码长边上限(px):够手机/平板全屏放大看,又不至于把 4000px 原图整幅解进内存。
const MAX_PIXEL_SIDE: number = 2048;

/**
 * 正文图片的 PixelMap 缓存(仅在原生 Image 直载失败、或该域名已被判定为"原生走不通"时才用)。
 * 与头像共用 BridgeImageLoader,只是并发更小、缓存更浅、解码降采样。
 * 单例:PostRichContent / ImageViewer 深层嵌套拿不到注入的 bridge,由 RootTabPage attachBridge 一次。
 */
export class ContentImageCache extends BridgeImageLoader {
  private static instance: ContentImageCache = new ContentImageCache();

  constructor() {
    super(LOG_TAG, MAX_CONCURRENCY, MAX_CACHE_ENTRIES, MAX_PIXEL_SIDE);
  }

  static getInstance(): ContentImageCache {
    return ContentImageCache.instance;
  }
}
