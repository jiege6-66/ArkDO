import { AppConstants } from '../../common/constants/AppConstants';
import { Log } from '../logging/Log';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';

const LOG_TAG: string = '[ArkDO][SiteSettings]';

/**
 * 站点客户端设置(`GET /site/settings.json`)。
 *
 * Discourse 把标了 `client: true` 的设置从这个端点原样吐出(SiteController#settings →
 * SiteSetting.client_settings_json),匿名也能读,服务端还有 30 分钟缓存,拉一次很便宜。
 *
 * ## 为什么必须动态读
 * 上传相关的每一项都是站长可改的,实测差得很远:
 *
 *     linux.do            : 图片 4096 KB / 附件 4096 KB
 *     meta.discourse.org  : 图片 10240 KB / 附件 30000 KB
 *
 * 白名单更是天差地别(linux.do 允许 zip/7z/xz 却不允许 mp4)。ArkDO 是通用 Discourse
 * 客户端,任何写死的数字都会在某个站上是错的。
 *
 * ## 拿不到时的策略
 * 回落到 Discourse 出厂默认值而不是「禁用上传」。设置拉失败多半是网络抖动,直接封掉入口
 * 对用户来说是莫名其妙的功能消失;按默认值放行,真超限了服务端会拒,我们再把错误显示出来。
 */
export interface SiteUploadSettings {
  /** 图片体积上限(KB)。判据是扩展名属于 IMAGE_EXTENSIONS,不是 MIME。 */
  maxImageSizeKb: number;
  /** 非图片文件体积上限(KB)。mp4/mp3 这类也走这条,别被「媒体」二字带偏。 */
  maxAttachmentSizeKb: number;
  /** 允许上传的扩展名(小写、不带点)。空数组=站点没开任何上传。 */
  authorizedExtensions: string[];
  /** 版主额外允许的扩展名。多数站为空。 */
  authorizedExtensionsForStaff: string[];
  /** TL0 最多能发几个附件。默认 0,即新用户一个附件都发不出去。 */
  newuserMaxAttachments: number;
  /** TL0 最多能发几张图/内嵌媒体。 */
  newuserMaxEmbeddedMedia: number;
}

/**
 * Discourse 认定为「图片」的扩展名,抄自 lib/file_helper.rb 的 supported_images。
 *
 * 这张表决定走 max_image_size_kb 还是 max_attachment_size_kb(见 lib/validators/
 * upload_validator.rb:30-35),所以必须与服务端逐字一致 —— 注意 mp4/mp3/mov/webm
 * **不在**表里,音视频在 Discourse 眼里是附件。
 */
export const IMAGE_EXTENSIONS: string[] =
  ['jpg', 'jpeg', 'png', 'gif', 'svg', 'ico', 'webp', 'avif', 'heic', 'heif', 'jxl'];

// /site/settings.json 里我们关心的字段(其余数百项忽略)。
interface DiscourseClientSettings {
  max_image_size_kb?: number;
  max_attachment_size_kb?: number;
  authorized_extensions?: string;
  authorized_extensions_for_staff?: string;
  newuser_max_attachments?: number;
  newuser_max_embedded_media?: number;
}

// Discourse 出厂默认值,拉取失败时的兜底。
function defaultSettings(): SiteUploadSettings {
  return {
    maxImageSizeKb: 10240,
    maxAttachmentSizeKb: 10240,
    authorizedExtensions: IMAGE_EXTENSIONS.slice(),
    authorizedExtensionsForStaff: [],
    newuserMaxAttachments: 0,
    newuserMaxEmbeddedMedia: 5
  };
}

export class SiteSettingsService {
  // 内存缓存 + 它属于哪个 host。切站后 host 对不上即视为未命中,不必订阅 CurrentSite 的
  // 切站事件 —— 比对 host 是自证的,少一条要维护的订阅关系。
  private static cachedHost: string = '';
  private static cachedSettings: SiteUploadSettings | undefined = undefined;
  // 同一时刻只允许一发在途:编辑器可能同时问附件上限和白名单,不必打两次。
  private static inflight: Promise<SiteUploadSettings> | undefined = undefined;

  /**
   * 取当前站点的上传设置。命中缓存直接返回,否则拉一次。
   * 永远返回可用的值(失败时是出厂默认值),调用方不必处理 undefined。
   */
  static async load(bridge: JsonNetworkClient): Promise<SiteUploadSettings> {
    const host: string = AppConstants.HOST;
    const cached: SiteUploadSettings | undefined = SiteSettingsService.cachedSettings;
    if (cached && SiteSettingsService.cachedHost === host) {
      return cached;
    }
    const inflight: Promise<SiteUploadSettings> | undefined = SiteSettingsService.inflight;
    if (inflight) {
      return inflight;
    }
    const task: Promise<SiteUploadSettings> = SiteSettingsService.fetch(bridge, host);
    SiteSettingsService.inflight = task;
    try {
      return await task;
    } finally {
      SiteSettingsService.inflight = undefined;
    }
  }

  /**
   * 同步取已缓存的设置;没拉过返回 undefined。
   * 给「渲染时要立刻判断按钮显不显示」这类场合用,拿不到就先按保守态渲染,等 load 回来再刷。
   */
  static snapshot(): SiteUploadSettings | undefined {
    if (SiteSettingsService.cachedHost !== AppConstants.HOST) {
      return undefined;
    }
    return SiteSettingsService.cachedSettings;
  }

  private static async fetch(bridge: JsonNetworkClient, host: string): Promise<SiteUploadSettings> {
    const response: NetworkResult<string> = await bridge.getJson('/site/settings.json');
    if (!response.success || response.data === undefined) {
      Log.i(`${LOG_TAG} fetch failed status=${response.statusCode}, using defaults`);
      return defaultSettings();
    }
    let parsed: DiscourseClientSettings;
    try {
      parsed = JSON.parse(response.data) as DiscourseClientSettings;
    } catch (error) {
      Log.i(`${LOG_TAG} response not valid JSON, using defaults`);
      return defaultSettings();
    }

    const fallback: SiteUploadSettings = defaultSettings();
    const settings: SiteUploadSettings = {
      maxImageSizeKb: SiteSettingsService.positiveOr(parsed.max_image_size_kb, fallback.maxImageSizeKb),
      maxAttachmentSizeKb:
        SiteSettingsService.positiveOr(parsed.max_attachment_size_kb, fallback.maxAttachmentSizeKb),
      authorizedExtensions: SiteSettingsService.splitExtensions(parsed.authorized_extensions),
      authorizedExtensionsForStaff: SiteSettingsService.splitExtensions(parsed.authorized_extensions_for_staff),
      // 这两项 0 是合法值(且是默认值),不能用 positiveOr 兜。
      newuserMaxAttachments:
        typeof parsed.newuser_max_attachments === 'number' ? parsed.newuser_max_attachments : fallback.newuserMaxAttachments,
      newuserMaxEmbeddedMedia:
        typeof parsed.newuser_max_embedded_media === 'number' ? parsed.newuser_max_embedded_media : fallback.newuserMaxEmbeddedMedia
    };
    // 只在拿到真数据后才写缓存;失败态不缓存,下次进编辑器还会再试。
    SiteSettingsService.cachedHost = host;
    SiteSettingsService.cachedSettings = settings;
    Log.i(`${LOG_TAG} loaded host=${host} image=${settings.maxImageSizeKb}KB attachment=${settings.maxAttachmentSizeKb}KB exts=${settings.authorizedExtensions.length}`);
    return settings;
  }

  private static positiveOr(value: number | undefined, fallback: number): number {
    return typeof value === 'number' && value > 0 ? value : fallback;
  }

  // 'jpg|jpeg|png' → ['jpg','jpeg','png']。对齐 frontend/discourse/app/lib/uploads.js 的
  // extensionsToArray:小写、去空白与点、丢掉带 '*' 的通配项(通配另有 authorizesAllExtensions 判)。
  private static splitExtensions(raw: string | undefined): string[] {
    if (!raw || raw.length === 0) {
      return [];
    }
    const parts: string[] = raw.toLowerCase().replace(/[\s.]+/g, '').split('|');
    const result: string[] = [];
    for (let index: number = 0; index < parts.length; index++) {
      const ext: string = parts[index];
      if (ext.length > 0 && ext.indexOf('*') < 0) {
        result.push(ext);
      }
    }
    return result;
  }
}
