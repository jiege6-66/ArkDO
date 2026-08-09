import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][ImageHost]';
// 同一域名上有这么多张不同的图"原生取不到、桥能取到",才判定"这个域名原生走不通"。
const FAIL_THRESHOLD: number = 2;

/**
 * 记住"原生 Image 走不通"的图片域名(仅本次运行内存态,冷启动自动复位)。
 *
 * 背景:DoH(setHttpDns)只作用于 ArkWeb 内核,原生 Image 走系统 netstack,域名被污染或被 SNI
 * 封锁时无论怎么配 DoH 都是白图。哪些域名被封因网络而异(有的用户 ldstatic.com 直连没问题,
 * 有的全挂),写死名单必然漏,所以改成运行时学:够多张图印证过就记下来,之后同域名的图直接走桥,
 * 不用每张都先白等一次注定失败的原生请求。
 *
 * 判据刻意不是"原生失败"而是"原生失败 + 同一张图桥能取到":onError 分不清"网络被封"和
 * "这张图 404",而 404 在两条路上都取不到,于是天然不构成证据。少了这道门槛,帖子里有两张
 * 失效图就会把整个 CDN 推去走桥——代价是那个域名的 GIF 全变成 PixelMap 单帧(不动了)。
 *
 * 不落盘是有意的:网络环境会变(换 WiFi/出国/运营商恢复),重启即给原生一次重新证明自己的机会。
 */
export class BlockedImageHosts {
  private static rescuedUrls: Map<string, Set<string>> = new Map();
  private static blocked: Set<string> = new Set();

  /** 是否已有任何域名被判定走不通。健康网络下恒 false,调用方据此整段跳过兜底逻辑。 */
  static hasAny(): boolean {
    return BlockedImageHosts.blocked.size > 0;
  }

  /** 取 URL 的 host(小写)。取不到返回空串。 */
  static hostOf(url: string): string {
    const schemeEnd: number = url.indexOf('://');
    if (schemeEnd < 0) {
      return '';
    }
    const rest: string = url.substring(schemeEnd + 3);
    const slash: number = rest.indexOf('/');
    const authority: string = slash >= 0 ? rest.substring(0, slash) : rest;
    const at: number = authority.lastIndexOf('@');
    const hostPort: string = at >= 0 ? authority.substring(at + 1) : authority;
    const colon: number = hostPort.lastIndexOf(':');
    const host: string = colon > 0 ? hostPort.substring(0, colon) : hostPort;
    return host.toLowerCase();
  }

  /** 该 URL 所在域名是否已判定为原生走不通(→ 直接走桥,别再试原生)。 */
  static isBlocked(url: string): boolean {
    const host: string = BlockedImageHosts.hostOf(url);
    return host.length > 0 && BlockedImageHosts.blocked.has(host);
  }

  /**
   * 记一条"原生取不到、桥取到了"的证据(只有这种才算数,见类注释)。累计到门槛即判定该域名走不通。
   * 调用点在桥接取图成功的回调里,且必须是原生先失败过的那张图。
   */
  static markBridgeRescued(url: string): void {
    const host: string = BlockedImageHosts.hostOf(url);
    if (host.length === 0 || BlockedImageHosts.blocked.has(host)) {
      return;
    }
    let urls: Set<string> | undefined = BlockedImageHosts.rescuedUrls.get(host);
    if (!urls) {
      urls = new Set<string>();
      BlockedImageHosts.rescuedUrls.set(host, urls);
    }
    urls.add(url);
    if (urls.size < FAIL_THRESHOLD) {
      return;
    }
    BlockedImageHosts.blocked.add(host);
    BlockedImageHosts.rescuedUrls.delete(host);
    Log.i(`${LOG_TAG} native blocked host=${host} rescued=${urls.size}`);
  }

  /**
   * 桥接也取不到(多半是跨源图床不回 ACAO,而非网络被封)→ 撤销该域名的标记。
   * 否则一个 CORS 拿不到的第三方图床会被永久钉在"只走桥"上,原生本来能显示的也白了。
   */
  static clearBlocked(url: string): void {
    const host: string = BlockedImageHosts.hostOf(url);
    if (host.length === 0 || !BlockedImageHosts.blocked.has(host)) {
      return;
    }
    BlockedImageHosts.blocked.delete(host);
    Log.i(`${LOG_TAG} native unblocked host=${host} (bridge failed too)`);
  }
}
