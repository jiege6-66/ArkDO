import { image } from '@kit.ImageKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { discourseErrorMessage } from '../network/DiscourseErrors';
import { IMAGE_EXTENSIONS, SiteSettingsService, SiteUploadSettings } from '../site/SiteSettingsService';

// POST /uploads/lookup-urls 的响应项:把 upload:// 短码换成真实 CDN 直链。
interface DiscourseLookupUrlItem {
  short_url?: string;
  url?: string;
  short_path?: string;
}

// 一次成功上传的结果。字段对齐 UploadSerializer,写正文用 shortUrl(图片/附件)或 shortPath(裸 video 标签)。
export interface UploadedFile {
  /** upload://xxx.ext。写进 markdown 的短码,服务端 cook 时换成真实地址。 */
  shortUrl: string;
  /** /uploads/short-url/xxx.ext。裸 HTML(如 <video src>)里只能用它,markdown 短码在原始 HTML 里不会被解析。 */
  shortPath: string;
  /** 真实 CDN 直链(预览用)。 */
  url: string;
  /** original_filename,服务端回显的原始文件名。 */
  fileName: string;
  width: number;
  height: number;
  /** 字节数。 */
  fileSize: number;
  /** 服务端算好的人类可读体积,如 "38.3 KB"。附件 markdown 末尾那段就用它。 */
  humanFileSize: string;
}

/**
 * 一次上传的结果。失败时 error 是**可直接展示给用户**的中文文案。
 *
 * 原先失败一律回 undefined,页面只能弹一句「有图片上传失败」—— 而失败原因往往很具体
 * (超出本站 4 MB 上限 / 扩展名不在白名单 / 新用户不能发附件),不告诉用户等于让他反复重试。
 */
export interface UploadOutcome {
  file?: UploadedFile;
  error?: string;
}

// /uploads.json 成功响应的关注字段(其余忽略)。
interface UploadResponse {
  short_url?: string;
  short_path?: string;
  url?: string;
  original_filename?: string;
  width?: number;
  height?: number;
  filesize?: number;
  human_filesize?: string;
}

// ── 图片优化参数:对齐 Discourse 官方 composer,免得原生端比网页端更狠地劣化画质。
// 依据 discourse main 分支 frontend/discourse/app/services/media-optimization-worker.js
// 与 frontend/discourse/app/workers/media-optimization/codecs.js。

// 小于此体积的图不重编码,原样上传(官方 composer_media_optimization_image_bytes_optimization_threshold)。
// 小图重编码是画质净赔:省不下几个字节,却白吃一遍有损压缩。
const BYTES_OPTIMIZATION_THRESHOLD: number = 524288;
// 宽度超过此值才缩放。官方只看宽度、不看最长边,故长截图这类竖图能保住原分辨率。
const RESIZE_THRESHOLD: number = 1920;
// 缩放目标宽度,高度按原比例。
const RESIZE_TARGET: number = 1920;
// 编码质量。90 对应官方 image_quality 默认档 high(其 medium 档才是 70)。
const ENCODE_QUALITY: number = 90;
// 嗅探文件头魔数所需字节数(HEIC 的 ftyp box 位置最靠后,12 字节够用)。
const SNIFF_BYTES: number = 16;
// 扫 PNG 块找 acTL 的窗口。acTL 必须出现在首个 IDAT 之前,不会藏在很后面。
const PNG_CHUNK_SCAN_BYTES: number = 4096;

/**
 * 客户端自定的体积硬上限(字节)。取 min(站点上限, 本值) 作为实际生效上限。
 *
 * 我们的上传要把整个文件读进 ArrayBuffer → base64 字符串 → 再拼进注入脚本的源码字符串,
 * Web 侧 atob 还要再解一份,峰值内存大约是文件本身的 4 倍。站点上限是站长按服务器定的
 * (Discourse 允许配到 1 GB),照着它走会直接把 App 撑爆。
 *
 * 32 MB 能容下实测见过的最宽松配置(meta.discourse.org 的 30000 KB),又把峰值压在 ~128 MB。
 */
const CLIENT_MAX_UPLOAD_BYTES: number = 32 * 1024 * 1024;

// 一次最多选几个文件/视频。
export const MAX_PICK_FILES: number = 5;

/**
 * linux.do 传音视频时伪装用的扩展名。
 *
 * 那个站的 authorized_extensions 里没有 mp4/mp3,却有 xz;而 Discourse 判白名单与限额
 * **只看扩展名**(lib/validators/upload_validator.rb:17 的 File.extname),从不嗅探文件内容。
 * 于是站方的主题组件就把视频改名成 .xz 传上去,再插一个写死 type="video/mp4" 的裸 <video>
 * 标签 —— 播放器认 type 属性,不认后缀,所以照播。
 *
 * 这是那个站的私有约定,不是 Discourse 行为,故整条路径由 SiteCapabilities.mediaUpload 关着。
 */
const DISGUISE_EXTENSION: string = 'xz';
const DISGUISE_MIME: string = 'application/x-xz';

// 常见扩展名 → MIME。Discourse 服务端实际按文件名重新判定(MiniMime.lookup_by_filename),
// 这里给个像样的值即可,认不出就 octet-stream。
const MIME_BY_EXTENSION: Record<string, string> = {
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif',
  'webp': 'image/webp', 'avif': 'image/avif', 'heic': 'image/heic', 'heif': 'image/heif',
  'svg': 'image/svg+xml', 'bmp': 'image/bmp', 'ico': 'image/x-icon', 'jxl': 'image/jxl',
  'mp4': 'video/mp4', 'm4v': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
  'mkv': 'video/x-matroska', '3gp': 'video/3gpp', 'avi': 'video/x-msvideo',
  'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'aac': 'audio/aac', 'wav': 'audio/wav',
  'ogg': 'audio/ogg', 'oga': 'audio/ogg', 'opus': 'audio/opus', 'flac': 'audio/flac',
  'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown', 'csv': 'text/csv',
  'json': 'application/json', 'yml': 'text/yaml', 'yaml': 'text/yaml',
  'zip': 'application/zip', '7z': 'application/x-7z-compressed', 'gz': 'application/gzip',
  'xz': 'application/x-xz', 'tar': 'application/x-tar', 'rar': 'application/vnd.rar',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
};

/**
 * 上传服务:选文件 → 按需处理 → base64 → 经 host webview multipart 传 /uploads.json。
 *
 * 三条入口,差别只在「传之前对字节做什么」:
 *  · 图片   uploadImageUri  —— 按 encodeForUpload 的策略择机重编码/缩放,文件名由格式决定
 *  · 附件   uploadFileUri   —— 原样字节,**保留原始文件名**(扩展名决定白名单与限额,不能改)
 *  · 音视频 uploadMediaUri  —— 原样字节,改名成 .xz(见 DISGUISE_EXTENSION)
 *
 * 另维护 short_url → 真实 url 映射,供编辑器预览把 raw 里的 upload:// 短码换成可加载直链
 * (CookedHtmlParser 对 upload:// 原样返回、无法加载,故预览必须替换)。
 */
export class UploadService {
  private bridge: JsonNetworkClient;
  private context?: common.Context;
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  // short_url → 真实 url。上传成功即登记,预览渲染时据此替换短码。
  private shortUrlToRealUrl: Map<string, string> = new Map();

  // context 只给 DocumentViewPicker 用(它要 UIAbilityContext);不传则「选文件」不可用,
  // 选图/选视频走相册 picker,不需要它。
  constructor(bridge: JsonNetworkClient, context?: common.Context) {
    this.bridge = bridge;
    this.context = context;
  }

  // ==================== 选择 ====================

  // 拉起系统相册选图,返回选中的 uri 列表(最多 maxCount 张)。取消或失败返回空数组。
  async pickImages(maxCount: number): Promise<string[]> {
    return this.pickFromGallery(maxCount, photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE);
  }

  // 拉起系统相册选视频。
  async pickVideos(maxCount: number): Promise<string[]> {
    return this.pickFromGallery(maxCount, photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE);
  }

  private async pickFromGallery(maxCount: number, mimeType: photoAccessHelper.PhotoViewMIMETypes): Promise<string[]> {
    try {
      const galleryPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = mimeType;
      options.maxSelectNumber = Math.max(1, maxCount);
      const result: photoAccessHelper.PhotoSelectResult = await galleryPicker.select(options);
      return result.photoUris ? result.photoUris : [];
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Upload] pick failed code=${err.code} msg=${err.message}`);
      return [];
    }
  }

  /**
   * 拉起文件管理器选文件。后缀过滤按站点 authorized_extensions 里的**非图片**项生成 ——
   * 图片走相册那条路,混在这里只会让列表更乱。
   * 没有 context(未传)或站点不允许任何非图片扩展名时返回空数组。
   */
  async pickFiles(maxCount: number): Promise<string[]> {
    const context: common.Context | undefined = this.context;
    if (!context) {
      Log.i('[ArkDO][Upload] pickFiles skipped: no context');
      return [];
    }
    const settings: SiteUploadSettings = await this.settings();
    const suffixes: string[] = UploadService.nonImageExtensions(settings);
    if (suffixes.length === 0) {
      return [];
    }
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = Math.max(1, maxCount);
      options.selectMode = picker.DocumentSelectMode.FILE;
      // 格式是 ['描述|.ext1,.ext2']。给一条即可,描述会显示在选择器的类型下拉里。
      const joined: string = suffixes.map((ext: string) => `.${ext}`).join(',');
      options.fileSuffixFilters = [`可上传的文件|${joined}`];
      const uris: string[] = await documentPicker.select(options);
      return uris ? uris : [];
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Upload] pickFiles failed code=${err.code} msg=${err.message}`);
      return [];
    }
  }

  // ==================== 上传 ====================

  /**
   * 上传单张图片。读文件 → 按需优化(见 encodeForUpload) → 查体积上限 → 传 /uploads.json。
   *
   * 体积检查放在优化**之后**:服务端量的是它收到的字节数,原图 6 MB 但压完 800 KB 是能过的,
   * 提前按原图判会把本来能传的图误拒。
   */
  async uploadImageUri(uri: string): Promise<UploadOutcome> {
    let encoded: EncodedFile | undefined;
    try {
      encoded = await this.encodeForUpload(uri);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Upload] encode failed code=${err.code} msg=${err.message}`);
      return { error: '图片读取失败' };
    }
    if (!encoded) {
      return { error: '图片读取失败' };
    }

    const settings: SiteUploadSettings = await this.settings();
    const overLimit: string = UploadService.checkSize(encoded.byteLength, settings.maxImageSizeKb, '图片');
    if (overLimit.length > 0) {
      return { error: overLimit };
    }
    return this.uploadEncoded(encoded);
  }

  /**
   * 上传任意文件(附件)。原样字节、原样文件名 —— 扩展名既决定服务端白名单校验,
   * 也决定用哪条体积上限,改名等于换了一套规则。
   */
  async uploadFileUri(uri: string): Promise<UploadOutcome> {
    const settings: SiteUploadSettings = await this.settings();
    const fileName: string = UploadService.fileNameFromUri(uri);
    const extension: string = UploadService.extensionOf(fileName);
    if (!UploadService.isAuthorized(extension, settings)) {
      return { error: `本站不允许上传 .${extension} 文件` };
    }
    const limitKb: number = UploadService.isImageExtension(extension)
      ? settings.maxImageSizeKb : settings.maxAttachmentSizeKb;
    return this.uploadRawFile(uri, fileName, UploadService.mimeFor(extension), limitKb, '文件');
  }

  /**
   * 上传音视频(linux.do 专用路径)。改名成 .xz 绕过白名单,详见 DISGUISE_EXTENSION。
   * 走的是附件限额(max_attachment_size_kb),因为 .xz 不属于 Discourse 认定的图片扩展名。
   */
  async uploadMediaUri(uri: string): Promise<UploadOutcome> {
    const settings: SiteUploadSettings = await this.settings();
    const originalName: string = UploadService.fileNameFromUri(uri);
    const disguised: string = `${UploadService.baseNameOf(originalName)}.${DISGUISE_EXTENSION}`;
    return this.uploadRawFile(uri, disguised, DISGUISE_MIME, settings.maxAttachmentSizeKb, '视频');
  }

  // 原样读字节 → 查体积 → 上传。三条入口里附件与音视频共用。
  private async uploadRawFile(uri: string, fileName: string, mimeType: string,
    limitKb: number, kindLabel: string): Promise<UploadOutcome> {
    let encoded: EncodedFile;
    try {
      const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const size: number = fs.statSync(file.fd).size;
        // 体积检查放在 base64 **之前**:超限的文件根本不该被读进内存,
        // 否则一个 500 MB 的包会在「告诉用户传不了」之前先把 App 撑死。
        const overLimit: string = UploadService.checkSize(size, limitKb, kindLabel);
        if (overLimit.length > 0) {
          return { error: overLimit };
        }
        if (size === 0) {
          return { error: '文件是空的' };
        }
        encoded = this.readRaw(file, size, fileName, mimeType);
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Upload] read failed code=${err.code} msg=${err.message}`);
      return { error: '文件读取失败' };
    }
    return this.uploadEncoded(encoded);
  }

  // 真正发请求并解析响应。三条入口最终都汇到这里。
  private async uploadEncoded(encoded: EncodedFile): Promise<UploadOutcome> {
    const referrer: string = `${AppConstants.BASE_URL}/`;
    const response: NetworkResult<string> = await this.bridge.uploadImage(
      encoded.base64, encoded.fileName, encoded.mimeType, { notifyChallenge: true, referrer: referrer });
    if (!response.success || response.data === undefined) {
      Log.i(`[ArkDO][Upload] upload failed status=${response.statusCode}`);
      return { error: UploadService.failureMessage(response) };
    }

    try {
      const parsed: UploadResponse = JSON.parse(response.data) as UploadResponse;
      const shortUrl: string = parsed.short_url ? parsed.short_url : '';
      const realUrl: string = parsed.url ? parsed.url : '';
      if (shortUrl.length === 0) {
        // 2xx 但没有 short_url:Discourse 对部分校验失败会回 200 + {"errors":[...]}。
        const reason: string = discourseErrorMessage(response);
        Log.i('[ArkDO][Upload] response missing short_url');
        return { error: reason.length > 0 ? reason : '上传失败' };
      }
      if (realUrl.length > 0) {
        this.shortUrlToRealUrl.set(shortUrl, realUrl);
      }
      return {
        file: {
          shortUrl: shortUrl,
          shortPath: parsed.short_path ? parsed.short_path : '',
          url: realUrl,
          fileName: parsed.original_filename ? parsed.original_filename : encoded.fileName,
          width: typeof parsed.width === 'number' ? parsed.width : encoded.width,
          height: typeof parsed.height === 'number' ? parsed.height : encoded.height,
          fileSize: typeof parsed.filesize === 'number' ? parsed.filesize : encoded.byteLength,
          humanFileSize: parsed.human_filesize ? parsed.human_filesize : UploadService.humanSize(encoded.byteLength)
        }
      };
    } catch (error) {
      Log.i('[ArkDO][Upload] response not valid JSON');
      return { error: '上传失败' };
    }
  }

  // 把失败响应翻译成能给用户看的一句话。优先用服务端给的原因(已按站点语言本地化)。
  private static failureMessage(response: NetworkResult<string>): string {
    const reason: string = discourseErrorMessage(response);
    if (reason.length > 0) {
      return reason;
    }
    // 413 是 nginx/网关层拦的,body 是 HTML 错误页而非 Discourse JSON —— 站长把
    // max_attachment_size_kb 调大了却没同步改 client_max_body_size 时就会撞上这条。
    if (response.statusCode === 413) {
      return '文件超出服务器限制';
    }
    if (response.statusCode === 429) {
      return '上传太频繁,请稍后再试';
    }
    return '上传失败';
  }

  // ==================== 短码解析(预览用) ====================

  // 取某短码对应的真实直链(预览替换用);未登记返回 undefined。
  getRealUrl(shortUrl: string): string | undefined {
    return this.shortUrlToRealUrl.get(shortUrl);
  }

  // 预览用:把 markdown-it 编译出的 HTML 里 <img src="upload://…"> 的短码换成真实直链。
  // CookedHtmlParser 对 upload:// 原样返回、无法加载,故预览前必须替换成本次上传拿到的直链。
  resolvePreviewHtml(html: string): string {
    let result: string = html;
    this.shortUrlToRealUrl.forEach((realUrl: string, shortUrl: string) => {
      result = result.split(shortUrl).join(realUrl);
    });
    return result;
  }

  // 预解析正文里「本会话没上传过」的 upload:// 短码:草稿续写/编辑旧帖时,图片是以前传的,
  // 本地映射表里没有,预览会留着 upload:// 加载不出来。走官方 POST /uploads/lookup-urls 批量换真实直链
  // (返回的 url 与服务端 cook 帖子里的图片同一形式,渲染路径已验证可用;不要自行拼 /uploads/short-url/,
  // 那条会 302 到跨源 CDN 且被 CF 挡,见 MediaSource 的记录)。
  // 结果并进同一张映射表,后续 resolvePreviewHtml 原样受益;已解析过的不再请求。
  async prefetchShortUrls(raw: string): Promise<void> {
    const pending: string[] = [];
    const pattern: RegExp = new RegExp('upload://[A-Za-z0-9]+\\.[A-Za-z0-9]+', 'g');
    let match: RegExpExecArray | null = pattern.exec(raw);
    while (match !== null) {
      const shortUrl: string = match[0];
      if (!this.shortUrlToRealUrl.has(shortUrl) && pending.indexOf(shortUrl) < 0) {
        pending.push(shortUrl);
      }
      match = pattern.exec(raw);
    }
    if (pending.length === 0) {
      return;
    }

    let body: string = '';
    for (let index: number = 0; index < pending.length; index++) {
      body += `${index > 0 ? '&' : ''}short_urls%5B%5D=${encodeURIComponent(pending[index])}`;
    }
    const response: NetworkResult<string> = await this.bridge.postForm('/uploads/lookup-urls', body, {
      notifyChallenge: false,
      referrer: `${AppConstants.BASE_URL}/`
    });
    if (!response.success || response.data === undefined) {
      // 解析失败不阻断预览:该图仍显示不出来,但正文与其余内容照常(发帖时服务端会自行解析短码)。
      return;
    }
    try {
      const items: DiscourseLookupUrlItem[] = JSON.parse(response.data) as DiscourseLookupUrlItem[];
      for (let index: number = 0; index < items.length; index++) {
        const item: DiscourseLookupUrlItem = items[index];
        if (typeof item.short_url === 'string' && typeof item.url === 'string' && item.url.length > 0) {
          this.shortUrlToRealUrl.set(item.short_url, item.url);
        }
      }
    } catch (error) {
      // 响应非 JSON:同上,静默降级。
    }
  }

  // ==================== 正文片段 ====================

  // 生成插入正文的图片 markdown:![文件名|宽x高](upload://…)。宽高缺失则省略尺寸段。
  static buildImageMarkdown(file: UploadedFile): string {
    const name: string = UploadService.markdownSafeName(file.fileName, 'image');
    if (file.width > 0 && file.height > 0) {
      return `![${name}|${file.width}x${file.height}](${file.shortUrl})`;
    }
    return `![${name}](${file.shortUrl})`;
  }

  /**
   * 附件 markdown:`[文件名.zip|attachment](upload://…) (38.3 KB)`。
   * 格式抄自 frontend/discourse/app/lib/uploads.js 的 attachmentMarkdown —— 那个 `|attachment`
   * 标记是 Discourse 服务端 cook 成 `<a class="attachment">` 的依据,少了它就只是个普通链接,
   * 也不会被 PostAnalyzer#attachment_count 数进去。
   */
  static buildAttachmentMarkdown(file: UploadedFile): string {
    const name: string = UploadService.markdownSafeName(file.fileName, 'file');
    const size: string = file.humanFileSize.length > 0 ? ` (${file.humanFileSize})` : '';
    return `[${name}|attachment](${file.shortUrl})${size}`;
  }

  /**
   * 音视频的裸 <video> 标签(linux.do 专用)。
   *
   * 三个要点,都不能改:
   *  · 用 shortPath 而不是 upload:// —— 短码只在 markdown 的链接/图片 token 里被
   *    upload-protocol 规则改写,写进原始 HTML 不会被解析,出来就是个死链。
   *  · type 写真实媒体类型而非 .xz 的类型 —— 播放器认 type 属性,这正是伪装能生效的原因。
   *  · 保留降级文案 —— 与站方主题组件插出来的内容保持一致,别人编辑这条帖子时看不出差别。
   */
  static buildVideoHtml(file: UploadedFile, mediaMimeType: string): string {
    const src: string = file.shortPath.length > 0 ? file.shortPath : file.url;
    return `<video width="640" height="360" controls>\n  <source src="${src}" type="${mediaMimeType}">\n  您的浏览器不支持 HTML5 video 标签。\n</video>`;
  }

  // markdown 链接文字里的 [ ] | 会破坏语法,与官方 uploads.js 一样直接剔除。
  private static markdownSafeName(fileName: string, fallback: string): string {
    const cleaned: string = fileName.replace(/[\[\]|]/g, '');
    return cleaned.length > 0 ? cleaned : fallback;
  }

  // ==================== 站点设置与判定 ====================

  private async settings(): Promise<SiteUploadSettings> {
    return SiteSettingsService.load(this.bridge);
  }

  /** 该扩展名是否被站点允许(含 staff 专属白名单)。 */
  private static isAuthorized(extension: string, settings: SiteUploadSettings): boolean {
    if (extension.length === 0) {
      return false;
    }
    if (settings.authorizedExtensions.indexOf(extension) >= 0) {
      return true;
    }
    return settings.authorizedExtensionsForStaff.indexOf(extension) >= 0;
  }

  /** 站点允许的非图片扩展名。选文件对话框的后缀过滤用它。 */
  static nonImageExtensions(settings: SiteUploadSettings): string[] {
    const result: string[] = [];
    const all: string[] = settings.authorizedExtensions.concat(settings.authorizedExtensionsForStaff);
    for (let index: number = 0; index < all.length; index++) {
      const ext: string = all[index];
      if (!UploadService.isImageExtension(ext) && result.indexOf(ext) < 0) {
        result.push(ext);
      }
    }
    return result;
  }

  /** 是否是 Discourse 认定的图片扩展名(决定走哪条体积上限)。 */
  static isImageExtension(extension: string): boolean {
    return IMAGE_EXTENSIONS.indexOf(extension) >= 0;
  }

  // 超限返回可展示的文案,没超返回空串。实际上限取「站点上限」与「客户端硬上限」的较小者。
  private static checkSize(bytes: number, siteLimitKb: number, kindLabel: string): string {
    const siteLimitBytes: number = siteLimitKb * 1024;
    const effective: number = Math.min(siteLimitBytes, CLIENT_MAX_UPLOAD_BYTES);
    if (bytes <= effective) {
      return '';
    }
    if (siteLimitBytes <= CLIENT_MAX_UPLOAD_BYTES) {
      return `${kindLabel} ${UploadService.humanSize(bytes)} 超过本站上限 ${UploadService.humanSize(siteLimitBytes)}`;
    }
    return `${kindLabel} ${UploadService.humanSize(bytes)} 超过 App 单次上传上限 ${UploadService.humanSize(effective)}`;
  }

  // 只用于我们自己生成的文案;服务端回了 human_filesize 时优先用它的。
  static humanSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb: number = bytes / 1024;
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`;
    }
    return `${(kb / 1024).toFixed(1)} MB`;
  }

  // ==================== 文件名 ====================

  // 从 picker 返回的 uri 里取文件名。相册与文管的 uri 都是路径形态,最后一段即文件名。
  static fileNameFromUri(uri: string): string {
    let path: string = uri;
    const query: number = path.indexOf('?');
    if (query >= 0) {
      path = path.substring(0, query);
    }
    const slash: number = path.lastIndexOf('/');
    const raw: string = slash >= 0 ? path.substring(slash + 1) : path;
    let decoded: string = raw;
    try {
      decoded = decodeURIComponent(raw);
    } catch (error) {
      // uri 里有非法百分号转义时保持原样,总比抛出去中断上传好。
    }
    return decoded.length > 0 ? decoded : 'file';
  }

  // 小写扩展名,不带点;没有扩展名返回空串。
  static extensionOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    if (dot < 0 || dot === fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  // 去掉扩展名的部分。没有扩展名则原样返回。
  static baseNameOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  static mimeFor(extension: string): string {
    const known: string | undefined = MIME_BY_EXTENSION[extension];
    return known !== undefined ? known : 'application/octet-stream';
  }

  // ==================== 图片编码 ====================

  // 把 uri 编码成可上传的字节。策略对齐 Discourse 官方 composer:只有 jpeg/png 且体积过门槛才重编码,
  // 带透明通道编 WebP(不支持则 PNG)以保住 alpha,其余格式(gif/webp/bmp/…)一律原样传。
  // 重编码失败、或结果反而更大,都退回原图字节——原图永远是安全兜底。
  private async encodeForUpload(uri: string): Promise<EncodedFile | undefined> {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const originalSize: number = fs.statSync(file.fd).size;
      const format: string = this.sniffFormat(file);
      const raw: RawDescriptor = UploadService.rawDescriptor(format);

      // gif/webp/bmp 等不重编码:gif 会丢动画,其余官方端同样不碰。
      if (!raw.optimizable) {
        return this.readRaw(file, originalSize, raw.fileName, raw.mimeType);
      }
      // HEIC 论坛多半不在 authorized_extensions 里,原样传会被拒,故无视体积门槛一律转码。
      const mustConvert: boolean = format === 'heic';
      if (!mustConvert && originalSize < BYTES_OPTIMIZATION_THRESHOLD) {
        return this.readRaw(file, originalSize, raw.fileName, raw.mimeType);
      }
      // APNG 的动画帧会被解码器丢掉只剩首帧,故原样传。
      if (format === 'png' && this.isAnimatedPng(file)) {
        return this.readRaw(file, originalSize, raw.fileName, raw.mimeType);
      }

      let optimized: EncodedFile | undefined;
      try {
        optimized = await this.optimize(file, originalSize);
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        Log.i(`[ArkDO][Upload] optimize failed code=${err.code} msg=${err.message}, keeping original`);
      }
      return optimized ? optimized : this.readRaw(file, originalSize, raw.fileName, raw.mimeType);
    } finally {
      fs.closeSync(file);
    }
  }

  // 解码 → 按需缩放 → 编码。返回 undefined 表示调用方应退回原图(结果没比原图小)。
  private async optimize(file: fs.File, originalSize: number): Promise<EncodedFile | undefined> {
    let imageSource: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    try {
      imageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const target: TargetSize = UploadService.fitWidth(info.size.width, info.size.height);
      const decodeOptions: image.DecodingOptions = {
        desiredSize: { width: target.width, height: target.height }
      };
      pixelMap = await imageSource.createPixelMap(decodeOptions);

      // 有透明像素就不能编 JPEG(透明区会被拍平成黑底)。官方编 WebP;鸿蒙 packer 不支持 WebP 时退 PNG。
      const transparent: boolean = await UploadService.hasTransparency(pixelMap);
      packer = image.createImagePacker();
      const outputFormat: string = transparent ? UploadService.pickAlphaFormat(packer) : 'image/jpeg';
      const packOptions: image.PackingOption = { format: outputFormat, quality: ENCODE_QUALITY };
      const arrayBuffer: ArrayBuffer = await packer.packToData(pixelMap, packOptions);

      // 编完不比原图小就没必要换:退回原图既省体积又零损失(PNG 无损重编码常撞上这条)。
      if (arrayBuffer.byteLength >= originalSize) {
        Log.i(`[ArkDO][Upload] encoded ${arrayBuffer.byteLength}B >= original ${originalSize}B, keeping original`);
        return undefined;
      }

      const base64: string = this.base64Helper.encodeToStringSync(new Uint8Array(arrayBuffer));
      return {
        base64: base64,
        byteLength: arrayBuffer.byteLength,
        fileName: UploadService.fileNameFor(outputFormat),
        mimeType: outputFormat,
        width: target.width,
        height: target.height
      };
    } finally {
      if (pixelMap) {
        pixelMap.release();
      }
      if (packer) {
        packer.release();
      }
      if (imageSource) {
        imageSource.release();
      }
    }
  }

  // 是否含透明像素。先用 alphaType 快速排除(照片/相机图都是 OPAQUE),只有可能带 alpha 时才真扫像素:
  // 「有 alpha 通道」不等于「用到了透明」,截图 PNG 常常整幅不透明,扫完才敢放心编 JPEG。
  private static async hasTransparency(pixelMap: image.PixelMap): Promise<boolean> {
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    if (info.alphaType === image.AlphaType.OPAQUE) {
      return false;
    }
    // 仅这两种排布的 alpha 落在每像素第 4 字节;其余格式(RGB_565/RGB_888…)本就无 alpha。
    if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 &&
      info.pixelFormat !== image.PixelMapFormat.BGRA_8888) {
      return false;
    }

    const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
    await pixelMap.readPixelsToBuffer(buffer);
    const bytes: Uint8Array = new Uint8Array(buffer);
    // 逐行按 stride 走:行尾可能有对齐填充,填充字节是 0,顺序扫会把它误判成透明像素。
    const width: number = info.size.width;
    const height: number = info.size.height;
    const stride: number = info.stride > 0 ? info.stride : width * 4;
    for (let y: number = 0; y < height; y++) {
      const rowStart: number = y * stride;
      for (let x: number = 3; x < width * 4; x += 4) {
        if (bytes[rowStart + x] < 255) {
          return true;
        }
      }
    }
    return false;
  }

  // 选一个能保住 alpha 的输出格式。官方用 WebP;鸿蒙 packer 是否支持 WebP 编码只能运行时问
  // supportedFormats,不支持就退 PNG(无损、体积大些,总好过把透明拍平)。
  private static pickAlphaFormat(packer: image.ImagePacker): string {
    const supported: string[] = packer.supportedFormats;
    return supported && supported.includes('image/webp') ? 'image/webp' : 'image/png';
  }

  private static fileNameFor(mimeType: string): string {
    if (mimeType === 'image/webp') {
      return 'image.webp';
    }
    if (mimeType === 'image/png') {
      return 'image.png';
    }
    return 'image.jpg';
  }

  // 按文件头魔数判断真实格式。不能靠扩展名:相册返回的 uri 未必带真实后缀,
  // 之前 gif 就是靠 .gif 后缀识别的,一旦 uri 不带后缀就会被压成静帧。
  private sniffFormat(file: fs.File): string {
    const header: ArrayBuffer = new ArrayBuffer(SNIFF_BYTES);
    const read: number = fs.readSync(file.fd, header, { offset: 0 });
    const b: Uint8Array = new Uint8Array(header);
    if (read >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
      return 'jpeg';
    }
    if (read >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
      return 'png';
    }
    if (read >= 6 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) {
      return 'gif';
    }
    if (read >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) {
      return 'webp';
    }
    if (read >= 2 && b[0] === 0x42 && b[1] === 0x4d) {
      return 'bmp';
    }
    // ISO-BMFF ftyp box:HEIC/HEIF 共用,品牌位不再细分(都走转码)。
    if (read >= 12 && b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) {
      return 'heic';
    }
    return 'unknown';
  }

  // APNG 在首个 IDAT 前带 acTL 块;解码器只会给首帧,压了就丢动画,故需提前识别并原样传。
  private isAnimatedPng(file: fs.File): boolean {
    const buffer: ArrayBuffer = new ArrayBuffer(PNG_CHUNK_SCAN_BYTES);
    const read: number = fs.readSync(file.fd, buffer, { offset: 0 });
    const view: DataView = new DataView(buffer);
    let offset: number = 8; // 跳过 PNG 签名
    while (offset + 8 <= read) {
      const length: number = view.getUint32(offset);
      const type: string = String.fromCharCode(
        view.getUint8(offset + 4), view.getUint8(offset + 5),
        view.getUint8(offset + 6), view.getUint8(offset + 7));
      if (type === 'acTL') {
        return true;
      }
      if (type === 'IDAT' || type === 'IEND') {
        return false;
      }
      offset += 12 + length; // length(4) + type(4) + data + crc(4)
    }
    return false;
  }

  // 原样读取文件字节并 base64。宽高交给服务端(/uploads.json 响应里带,故这里给 0 即可)。
  private readRaw(file: fs.File, size: number, fileName: string, mimeType: string): EncodedFile {
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    fs.readSync(file.fd, buffer, { offset: 0 });
    const base64: string = this.base64Helper.encodeToStringSync(new Uint8Array(buffer));
    return { base64: base64, byteLength: size, fileName: fileName, mimeType: mimeType, width: 0, height: 0 };
  }

  // 各格式原样上传时的文件名/类型,以及是否该走重编码。
  private static rawDescriptor(format: string): RawDescriptor {
    switch (format) {
      case 'png':
        return { fileName: 'image.png', mimeType: 'image/png', optimizable: true };
      case 'heic':
        return { fileName: 'image.heic', mimeType: 'image/heic', optimizable: true };
      case 'gif':
        return { fileName: 'image.gif', mimeType: 'image/gif', optimizable: false };
      case 'webp':
        return { fileName: 'image.webp', mimeType: 'image/webp', optimizable: false };
      case 'bmp':
        return { fileName: 'image.bmp', mimeType: 'image/bmp', optimizable: false };
      default: // jpeg 及嗅探不出的,按 jpeg 处理(与改造前的行为一致)
        return { fileName: 'image.jpg', mimeType: 'image/jpeg', optimizable: true };
    }
  }

  // 宽度超过阈值则等比缩到目标宽度,否则原样返回。只看宽度是照抄官方:竖向长图因此保住原分辨率。
  private static fitWidth(width: number, height: number): TargetSize {
    if (width <= RESIZE_THRESHOLD || width === 0) {
      return { width: width, height: height };
    }
    return {
      width: RESIZE_TARGET,
      height: Math.max(1, Math.round((height / width) * RESIZE_TARGET))
    };
  }
}

// 某格式原样上传时的描述,以及它是否适合重编码。
interface RawDescriptor {
  fileName: string;
  mimeType: string;
  optimizable: boolean;
}

// 编码后待上传的字节。byteLength 是真实字节数(不是 base64 长度),体积上限按它判。
interface EncodedFile {
  base64: string;
  byteLength: number;
  fileName: string;
  mimeType: string;
  width: number;
  height: number;
}

interface TargetSize {
  width: number;
  height: number;
}
