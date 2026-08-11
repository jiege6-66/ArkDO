import { BridgeImageLoader } from './BridgeImageLoader';

const LOG_TAG: string = '[ArkDO][Avatar]';
// 并发取图上限:头像一次可能几十张,限流避免瞬间灌爆 host webview 的 runJavaScript 通道。
const MAX_CONCURRENCY: number = 5;
// 已解码 PixelMap 内存缓存上限:首页长列表头像会快速累积,控制上限避免高水位过宽。
// 超出按插入序淘汰最旧(仅丢引用不 release,防止仍在显示的图被销毁崩溃)。
const MAX_CACHE_ENTRIES: number = 160;
// 头像本身只有几十到几百 px,不需要降采样,原尺寸解码。
const MAX_PIXEL_SIDE: number = 0;
// 字节预算。头像天生小(120px 见方约 58 KB),160 条正常也就几 MB;这个上限是给
// 「站点把头像配成了大图」这种意外兜底,正常情况下永远碰不到,先触发的是条数上限。
const MAX_CACHE_BYTES: number = 48 * 1024 * 1024;

/**
 * 头像 PixelMap 缓存。原生 Image 走系统 netstack 会被 SNI 封锁(TLS 握手 RST),
 * 故头像统一经 host webview(能藏 SNI 过盾)取字节,解码成 PixelMap 供 UserAvatar 显示。
 * 单例:UserAvatar 深层嵌套拿不到注入的 bridge,由 RootTabPage 在 host 就绪处 attachBridge 一次。
 * 取字节/解码/限流/淘汰的实现在 BridgeImageLoader,与正文图(ContentImageCache)共用。
 */
export class AvatarImageCache extends BridgeImageLoader {
  private static instance: AvatarImageCache = new AvatarImageCache();

  constructor() {
    super(LOG_TAG, MAX_CONCURRENCY, MAX_CACHE_ENTRIES, MAX_PIXEL_SIDE, MAX_CACHE_BYTES);
  }

  static getInstance(): AvatarImageCache {
    return AvatarImageCache.instance;
  }
}
