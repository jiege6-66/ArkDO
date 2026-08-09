import { Log } from '../logging/Log';
import { DownloadService } from './DownloadService';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { ContentImageCache } from '../network/ContentImageCache';
import { BlockedImageHosts } from '../network/BlockedImageHosts';

const LOG_TAG: string = '[ArkDO][ImageShare]';
// 分享暂存目录（cacheDir 下,系统可回收）。每次分享前整目录清空,不累积。
const SHARE_DIR_NAME: string = 'share_images';
const REQUEST_TIMEOUT_MS: number = 20000;
// 分享面板走 IPC 传 uri,文件本身不过 IPC;但过大的图下载本身就不合理,超过即放弃。
const MAX_IMAGE_BYTES: number = 32 * 1024 * 1024;

// MIME → UTD。系统分享面板按 utd 决定能出现哪些目标应用,给准了微信/相册才认得是图片。
const UTD_BY_MIME: Record<string, string> = {
  'image/png': utd.UniformDataType.PNG,
  'image/jpeg': utd.UniformDataType.JPEG,
  'image/gif': utd.UniformDataType.GIF,
  'image/webp': utd.UniformDataType.IMAGE,
  'image/bmp': utd.UniformDataType.BMP
};

/**
 * 大图预览的「分享当前这张图」。
 *
 * 图片必须先落到本地再交给系统分享面板——面板要的是 uri,直接把 https 链接塞进去只会
 * 被当成一条文本链接分享出去,而不是一张图。落地目标是 cacheDir(非 filesDir):这是
 * 一次性的分享中转件,不是用户资产,跟 DownloadService 经手的附件不是一回事,故不共用
 * 目录、也不进「文件」App 可见的下载区,只复用它的扩展名 → MIME 推断。
 *
 * 首选普通 http:帖子里的图本来就是原生 Image 组件直接加载的公开资源,不需要会话 Cookie,
 * 没必要为此依赖 webview 就绪。但原生栈吃不到 DoH(setHttpDns 只作用于 ArkWeb 内核),
 * 域名被污染/封锁的网络里这一路必然失败——那种情况下正文图本身也已改走 host webview,
 * 分享同样退到桥上取字节(见 downloadViaBridge),否则会出现"图看得见却分享不出去"。
 */
export class ImageShareService {
  /** 下载图片到沙箱并拉起系统分享面板。返回是否成功走到面板。 */
  static async share(context: common.UIAbilityContext, url: string, title: string): Promise<boolean> {
    if (url.length === 0) {
      return false;
    }
    const path: string | undefined = await ImageShareService.download(context, url);
    if (path === undefined) {
      return false;
    }
    return ImageShareService.present(context, path, title);
  }

  /**
   * 下载到 cacheDir/share_images,返回沙箱绝对路径;失败返回 undefined。
   * 域名已判定原生走不通就直接走桥,否则先 http、失败再退到桥(桥能过 SNI 封锁、吃得到 DoH)。
   */
  private static async download(context: common.UIAbilityContext, url: string): Promise<string | undefined> {
    if (!BlockedImageHosts.isBlocked(url)) {
      const viaHttp: string | undefined = await ImageShareService.downloadViaHttp(context, url);
      if (viaHttp !== undefined) {
        return viaHttp;
      }
    }
    return await ImageShareService.downloadViaBridge(context, url);
  }

  // 经 host webview 取原图字节(与正文兜底同一条路)。桥未就绪/跨源不回 ACAO 时返回 undefined。
  private static async downloadViaBridge(context: common.UIAbilityContext, url: string): Promise<string | undefined> {
    try {
      const base64: string = await ContentImageCache.getInstance().fetchBase64(url);
      if (base64.length === 0) {
        return undefined;
      }
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(base64, util.Type.BASIC);
      // 切出精确字节区间:base64 解码结果可能带偏移/多余尾字节,整块 buffer 写进去文件会坏。
      const body: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      return ImageShareService.writeToShareDir(context, url, body);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Log.i(`${LOG_TAG} bridge download error code=${error.code}`);
      return undefined;
    }
  }

  // 把字节写进分享中转目录,返回沙箱绝对路径;超限/写失败返回 undefined。
  private static writeToShareDir(context: common.UIAbilityContext, url: string, body: ArrayBuffer): string | undefined {
    if (body.byteLength === 0 || body.byteLength > MAX_IMAGE_BYTES) {
      Log.i(`${LOG_TAG} download rejected bytes=${body.byteLength}`);
      return undefined;
    }
    let file: fs.File | undefined = undefined;
    try {
      const dir: string = ImageShareService.prepareDir(context);
      const path: string = `${dir}/${ImageShareService.fileNameOf(url)}`;
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, body);
      Log.i(`${LOG_TAG} downloaded bytes=${body.byteLength}`);
      return path;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Log.i(`${LOG_TAG} write error code=${error.code}`);
      return undefined;
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (err) {
          Log.e(`${LOG_TAG} close failed: ${JSON.stringify(err)}`);
        }
      }
    }
  }

  private static async downloadViaHttp(context: common.UIAbilityContext, url: string): Promise<string | undefined> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (response.responseCode !== http.ResponseCode.OK) {
        Log.i(`${LOG_TAG} download failed code=${response.responseCode}`);
        return undefined;
      }
      return ImageShareService.writeToShareDir(context, url, response.result as ArrayBuffer);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Log.i(`${LOG_TAG} download error code=${error.code}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private static async present(context: common.UIAbilityContext, path: string, title: string): Promise<boolean> {
    try {
      const record: systemShare.SharedRecord = {
        utd: ImageShareService.utdOf(path),
        uri: fileUri.getUriFromPath(path),
        title: title
      };
      const controller: systemShare.ShareController = new systemShare.ShareController(new systemShare.SharedData(record));
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      return true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Log.i(`${LOG_TAG} present panel failed code=${error.code}`);
      return false;
    }
  }

  // 建目录并清空历史中转件:上一次分享早已完成,留着只会白占缓存。
  private static prepareDir(context: common.UIAbilityContext): string {
    const dir: string = `${context.cacheDir}/${SHARE_DIR_NAME}`;
    try {
      if (fs.accessSync(dir)) {
        const stale: string[] = fs.listFileSync(dir);
        for (let i: number = 0; i < stale.length; i++) {
          try {
            fs.unlinkSync(`${dir}/${stale[i]}`);
          } catch (err) {
            Log.e(`${LOG_TAG} unlink stale failed: ${JSON.stringify(err)}`);
          }
        }
        return dir;
      }
      fs.mkdirSync(dir);
    } catch (err) {
      Log.e(`${LOG_TAG} prepare dir failed: ${JSON.stringify(err)}`);
    }
    return dir;
  }

  // 文件名取 URL 末段(去掉 query/fragment),脏字符换成下划线;没有可用扩展名时补 .jpg,
  // 否则部分接收方按扩展名认类型会拿不准。
  private static fileNameOf(url: string): string {
    let tail: string = url;
    const query: number = tail.indexOf('?');
    if (query >= 0) {
      tail = tail.substring(0, query);
    }
    const hash: number = tail.indexOf('#');
    if (hash >= 0) {
      tail = tail.substring(0, hash);
    }
    const slash: number = tail.lastIndexOf('/');
    if (slash >= 0) {
      tail = tail.substring(slash + 1);
    }
    tail = tail.replace(/[^A-Za-z0-9._-]/g, '_');
    if (tail.length === 0) {
      tail = 'image';
    }
    if (tail.indexOf('.') < 0) {
      tail = `${tail}.jpg`;
    }
    return tail;
  }

  // 扩展名 → MIME 复用 DownloadService 的表,再映射到 UTD;认不出的一律 general.image。
  private static utdOf(path: string): string {
    const mime: string = DownloadService.mimeOf(path);
    const mapped: string | undefined = UTD_BY_MIME[mime];
    return mapped !== undefined ? mapped : utd.UniformDataType.IMAGE;
  }
}
