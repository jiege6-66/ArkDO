import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][Transcode]';

/**
 * 把视频压到目标体积以内。
 *
 * ## 为什么是「测量 → 重试」而不是查表
 * 同样码率下,录屏比实拍好压一个数量级(画面大半静止,H.264 大量跳过块)。按固定的
 * 「某分辨率至少要多少码率」查表去决定降到几档,会把本来能保住 1080p 的录屏无脑降成 720p。
 * 所以第一遍按原分辨率乐观地试,量出来超了再降档重来 —— 录屏基本一遍过。
 *
 * ## 时长才是真正的约束
 * 4 MiB = 33.55 Mbit。扣掉容器开销与码率超调按 88% 算,再减去音频,留给视频的是:
 *
 *     10s → 2.89 Mbps(1080p 几乎无损)      60s → 428 kbps(480p)
 *     30s → 920 kbps(720p)                 90s → 264 kbps(360p)
 *     2min → 182 kbps(360p,糊)            3min → 100 kbps(没法看)
 *
 * 所以「10 MB 的视频压不压得动」问错了问题:手机实拍 1080p 约 17 Mbps,10 MB 才 5 秒,
 * 随便压;而 3 分钟的视频哪怕原文件只有 8 MB 也压不进 4 MB 还能看。
 * 上限由 LADDER 最低档反推,见 maxDurationSeconds。
 */

/** 一次压缩任务的产出。error 是可直接展示给用户的文案。 */
export interface VideoTranscodeResult {
  /** 沙箱里的产物路径。调用方用完**必须**调 VideoTranscoder.discard 删掉。 */
  path?: string;
  error?: string;
  /** 实际落到的分辨率短边。≤360 时画质已明显劣化,调用方可据此提示。 */
  shortSide?: number;
}

/** 探测完成、真正开压之前的计划,供 UI 提前告知用户。 */
export interface VideoTranscodePlan {
  durationSeconds: number;
  /** 首遍目标分辨率短边。 */
  shortSide: number;
  /** 预计画质会明显下降(首遍就已经要降到 360p 及以下)。 */
  willDegrade: boolean;
}

export interface VideoTranscodeHooks {
  /** 探测完、开压前回调一次。 */
  onPlan?: (plan: VideoTranscodePlan) => void;
  /** 进度。percent 0~100,pass 从 1 开始(重试时会重新从 0 走一遍)。 */
  onProgress?: (percent: number, pass: number) => void;
  /**
   * 压缩结束、即将开始上传时回调一次(由 UploadService 触发,不是 VideoTranscoder 自己)。
   * 没有它的话,浮层会在整个上传过程里一直停在「压缩中 100%」——上传才是接下来在跑的事。
   */
  onCompressed?: () => void;
}

/** 分辨率阶梯:short 是短边像素(竖屏视频同样适用),minVideoBps 是这一档还看得过去的码率下限。 */
interface QualityTier {
  short: number;
  minVideoBps: number;
}

// 下限取系统默认码率的一半左右(SDK 文档:240~480p 默认 1 Mbps、480~720p 2 Mbps、
// 720~1080p 4 Mbps),即「明显有损但仍可看」的水位。
const LADDER: QualityTier[] = [
  { short: 1080, minVideoBps: 2500000 },
  { short: 720, minVideoBps: 1200000 },
  { short: 540, minVideoBps: 700000 },
  { short: 480, minVideoBps: 500000 },
  { short: 360, minVideoBps: 300000 },
  { short: 240, minVideoBps: 150000 }
];

// 音频码率。SDK 默认 48 kbps,这里给 64 kbps 换点音质 —— 90 秒下也只多吃 0.2 MB。
const AUDIO_BITRATE: number = 64000;
// 可用比例。MP4 容器开销(moov、每帧头)加上码率控制的超调,留 12% 余量。
const SIZE_SAFETY: number = 0.88;
// 最多压几遍。每遍都是一次完整重编码,30 秒的 1080p 单遍就可能十几秒。
const MAX_PASSES: number = 3;
// 重试时在「按实测比例回推」的基础上再压一点,避免又踩在线上。
const RETRY_SHRINK: number = 0.9;
// 低于此短边就认为画质已经明显劣化,提示用户。
const DEGRADED_SHORT_SIDE: number = 360;
// 转码产物的文件名前缀。冷启动清扫(clearStaleOutputs)靠它认出「是我们留下的」,
// 故此处与产物命名必须共用同一个常量。
const TRANSCODE_FILE_PREFIX: string = 'arkdo_transcode_';

export class VideoTranscoder {
  private context: common.Context;
  private active?: media.AVTranscoder;
  private cancelled: boolean = false;
  // 当前这遍的等待句柄:取消时要主动把它拒掉,否则 'complete' 不会来,await 永远挂着。
  private abortPass?: (reason: Error) => void;

  constructor(context: common.Context) {
    this.context = context;
  }

  /**
   * 把 sourceUri 压到 targetBytes 以内。成功返回沙箱里的 mp4 路径。
   * 全程不抛异常,失败以 result.error 返回可展示文案。
   *
   * known 是调用方已经探过的元数据。探测要开 fd、建 extractor、解容器头,而 UploadService
   * 为了给 <video> 标签算播放方向尺寸本来就先探了一次 —— 传进来就不必再探第二遍。
   */
  async fit(sourceUri: string, targetBytes: number, hooks?: VideoTranscodeHooks,
    known?: VideoProbe): Promise<VideoTranscodeResult> {
    this.cancelled = false;

    let probe: VideoProbe;
    if (known !== undefined) {
      probe = known;
    } else {
      try {
        probe = await VideoTranscoder.probeVideo(sourceUri);
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        Log.i(`${LOG_TAG} probe failed code=${err.code} msg=${err.message}`);
        return { error: '读不出这个视频的信息，无法压缩' };
      }
    }
    if (probe.durationSeconds <= 0 || probe.width <= 0 || probe.height <= 0) {
      return { error: '读不出这个视频的时长或尺寸，无法压缩' };
    }

    const usableBits: number = targetBytes * 8 * SIZE_SAFETY;
    const totalBps: number = usableBits / probe.durationSeconds;
    let videoBps: number = totalBps - AUDIO_BITRATE;
    const floorBps: number = LADDER[LADDER.length - 1].minVideoBps;
    if (videoBps < floorBps) {
      // 时长超限。把上限算出来告诉用户,比干巴巴一句「太长了」有用。
      const limit: number = VideoTranscoder.maxDurationSeconds(targetBytes);
      return {
        error: `视频 ${VideoTranscoder.readableDuration(probe.durationSeconds)} 太长，`
          + `压不进 ${VideoTranscoder.readableSize(targetBytes)}（上限约 ${VideoTranscoder.readableDuration(limit)}）`
      };
    }

    // 首遍:在「原分辨率」和「这个码率撑得住的最高档」里取低的那个 —— 既不上采样
    // (prepare 对目标尺寸大于源尺寸会直接报 401),也不拿 300 kbps 去硬编 1080p。
    const sourceShort: number = Math.min(probe.width, probe.height);
    let tierIndex: number = VideoTranscoder.tierIndexFor(sourceShort, videoBps);

    if (hooks?.onPlan) {
      hooks.onPlan({
        durationSeconds: probe.durationSeconds,
        shortSide: Math.min(sourceShort, LADDER[tierIndex].short),
        willDegrade: Math.min(sourceShort, LADDER[tierIndex].short) <= DEGRADED_SHORT_SIDE
      });
    }

    let lastError: string = '';
    for (let pass: number = 1; pass <= MAX_PASSES; pass++) {
      if (this.cancelled) {
        return { error: '' };
      }
      const targetShort: number = Math.min(sourceShort, LADDER[tierIndex].short);
      const size: VideoSize | undefined = VideoTranscoder.scaleTo(probe.width, probe.height, targetShort);
      const outputPath: string = `${this.context.cacheDir}/${TRANSCODE_FILE_PREFIX}${Date.now()}_${pass}.mp4`;
      const sizeLabel: string = size ? `${size.width}x${size.height}` : `${probe.width}x${probe.height}(原样)`;
      Log.i(`${LOG_TAG} pass=${pass} ${sizeLabel} videoBps=${Math.round(videoBps)}`);

      let produced: number = -1;
      try {
        produced = await this.runPass(sourceUri, outputPath, size, Math.round(videoBps), pass, hooks);
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        VideoTranscoder.discard(outputPath);
        if (this.cancelled) {
          return { error: '' };
        }
        Log.i(`${LOG_TAG} pass=${pass} failed code=${err.code} msg=${err.message}`);
        lastError = '视频压缩失败';
        break;
      }

      if (produced <= targetBytes) {
        Log.i(`${LOG_TAG} pass=${pass} ok size=${produced}`);
        return { path: outputPath, shortSide: targetShort };
      }

      // 超了:按实测比例回推码率,再多压一点,同时降一档分辨率。
      // 只降码率不降分辨率的话,下一遍会在同样的像素上摊更少的比特,糊得更难看。
      VideoTranscoder.discard(outputPath);
      Log.i(`${LOG_TAG} pass=${pass} overshoot size=${produced} > ${targetBytes}`);
      videoBps = videoBps * (targetBytes / produced) * RETRY_SHRINK;
      if (tierIndex < LADDER.length - 1) {
        tierIndex++;
      }
      if (videoBps < floorBps) {
        break;
      }
    }

    return { error: lastError.length > 0 ? lastError : `这个视频压不到 ${VideoTranscoder.readableSize(targetBytes)} 以内` };
  }

  /** 中断正在进行的压缩。fit 会以空 error 返回(空=用户主动取消,调用方不必提示)。 */
  async cancel(): Promise<void> {
    this.cancelled = true;
    const transcoder: media.AVTranscoder | undefined = this.active;
    // 顺序要紧:先让引擎真的停下,再拒掉等待句柄。
    // 反过来的话,runPass 的 finally 会在 cancel() 还在飞的时候去 release() 并关掉 fd,
    // 等于在编码器仍可能写盘时抽走文件描述符。
    if (transcoder) {
      try {
        await transcoder.cancel();
      } catch (error) {
        // 已经结束/还没 start 时 cancel 会报 5400102,忽略即可。
      }
    }
    const abort: ((reason: Error) => void) | undefined = this.abortPass;
    if (abort) {
      // cancel() 之后 'complete' 不会再来,不主动拒就永远挂着。
      abort(new Error('cancelled'));
    }
  }

  /** 删掉沙箱里的临时产物。上传完成、失败、取消都要调。 */
  static discard(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      fs.unlinkSync(path);
    } catch (error) {
      // 文件本来就不存在(压缩没跑到产出这步)时会抛,无害。
    }
  }

  /**
   * 冷启动清扫遗留的转码产物。正常路径上 discard() 已经删干净了,这里兜的是**没有正常路径**
   * 的那种收场:压 1080p 要十几秒,期间切后台被系统回收、或崩溃,finally 根本不会跑,
   * 产物(可能几十 MB)就永久留在 cacheDir 里。
   *
   * 与 ArkWebNetworkBridge.clearMediaCacheDir 同一时机、同一理由调用。只删我们自己的前缀,
   * 不动 cacheDir 里别人的东西。
   */
  static clearStaleOutputs(context: common.Context): void {
    try {
      const names: string[] = fs.listFileSync(context.cacheDir);
      let removed: number = 0;
      for (let index: number = 0; index < names.length; index++) {
        const name: string = names[index];
        if (name.startsWith(TRANSCODE_FILE_PREFIX)) {
          VideoTranscoder.discard(`${context.cacheDir}/${name}`);
          removed++;
        }
      }
      if (removed > 0) {
        Log.i(`${LOG_TAG} cleared ${removed} stale transcode output(s)`);
      }
    } catch (error) {
      Log.i(`${LOG_TAG} clear stale outputs failed`);
    }
  }

  // 跑一遍完整转码,返回产物字节数。失败/取消抛异常。
  private async runPass(sourceUri: string, outputPath: string, size: VideoSize | undefined,
    videoBps: number, pass: number, hooks?: VideoTranscodeHooks): Promise<number> {
    // 三个资源分别可能开失败,各自的清理必须挂在能覆盖到它的 finally 上,
    // 否则「开 dst 时抛异常」会把已经开着的 src fd 泄漏掉。
    const srcFile: fs.File = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    let dstFile: fs.File | undefined;
    let transcoder: media.AVTranscoder | undefined;
    try {
      dstFile = fs.openSync(outputPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      transcoder = await media.createAVTranscoder();
      this.active = transcoder;
      await this.driveTranscode(transcoder, srcFile, dstFile, size, videoBps, pass, hooks);
    } finally {
      this.abortPass = undefined;
      this.active = undefined;
      if (transcoder) {
        try {
          await transcoder.release();
        } catch (error) {
          // 已 release / 服务已死时会抛,吞掉不影响后续清理。
        }
      }
      // 必须先 release 再关 fd 并读产物:文档明确要求 release 之后才能动输出文件。
      if (dstFile) {
        fs.closeSync(dstFile);
      }
      fs.closeSync(srcFile);
    }

    return fs.statSync(outputPath).size;
  }

  // 配置并跑完一次转码。资源生命周期由调用方 runPass 管。
  private async driveTranscode(transcoder: media.AVTranscoder, srcFile: fs.File, dstFile: fs.File,
    size: VideoSize | undefined, videoBps: number, pass: number, hooks?: VideoTranscodeHooks): Promise<void> {
    // 完成信号只从 'complete' 事件来(start() 只是把任务发出去就返回了)。
    const finished: Promise<void> = new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
      this.abortPass = reject;
      transcoder.on('complete', () => {
        resolve();
      });
      transcoder.on('error', (err: BusinessError) => {
        reject(new Error(`transcode error ${err.code}: ${err.message}`));
      });
    });
    if (hooks?.onProgress) {
      const report: (percent: number, pass: number) => void = hooks.onProgress;
      transcoder.on('progressUpdate', (percent: number) => {
        report(percent, pass);
      });
    }

    transcoder.fdSrc = { fd: srcFile.fd };
    transcoder.fdDst = dstFile.fd;
    const config: media.AVTranscoderConfig = {
      fileFormat: media.ContainerFormatType.CFT_MPEG_4,
      videoCodec: media.CodecMimeType.VIDEO_AVC,
      videoBitrate: videoBps,
      audioCodec: media.CodecMimeType.AUDIO_AAC,
      audioBitrate: AUDIO_BITRATE,
      // B 帧显著降体积(SDK 原话 "reduce file size"),正是我们要的。
      enableBFrame: true
    };
    // 只在真要缩小时才给分辨率。不缩就整个不传,由转码器沿用源尺寸(见 scaleTo)。
    if (size) {
      config.videoFrameWidth = size.width;
      config.videoFrameHeight = size.height;
    }
    await transcoder.prepare(config);
    await transcoder.start();
    await finished;
  }

  /**
   * 读时长、编码方向宽高、旋转角。AVMetadata 的字段全是字符串,duration 单位毫秒。
   *
   * ## 编码方向 vs 播放方向:两个用途要的不是同一个
   * 带 90/270 度旋转的视频,元数据里的宽高是**编码方向**的(如 1920x1080 + rotate 90,
   * 播放出来才是竖的)。这两处要区别对待,搞混了两边都会错:
   *
   *  · 喂给 prepare() 的目标分辨率 —— 用**编码方向**,原样不换。prepare 拿目标宽高跟
   *    编码尺寸比,换成播放方向的 1080x1920 会让 height 1920 > 源 1080 而报 401。
   *    官方 FAQ 那句「据元数据的宽高设置目标分辨率」说的正是原样用。
   *  · 写进 <video> 标签的宽高 —— 用**播放方向**(见 displaySize)。那是给渲染器算
   *    版面宽高比的,写编码方向的话竖屏视频会被摆进一个横向框里。
   *
   * 画质决策不受影响:阶梯按短边 min(w,h) 算,互换不改变这个集合。
   */
  static async probeVideo(sourceUri: string): Promise<VideoProbe> {
    // fd 先开、extractor 后建,两者的清理必须各自挂在能覆盖到它的 finally 上 ——
    // 与 runPass 同一条规则:把 createAVMetadataExtractor() 留在 try 外面的话,
    // 它一旦 reject,已经开着的 src fd 就再也关不掉了(每传一个视频泄一个)。
    const file: fs.File = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    try {
      const extractor: media.AVMetadataExtractor = await media.createAVMetadataExtractor();
      try {
        extractor.fdSrc = { fd: file.fd };
        const meta: media.AVMetadata = await extractor.fetchMetadata();
        return {
          durationSeconds: VideoTranscoder.parseNumber(meta.duration) / 1000,
          width: VideoTranscoder.parseNumber(meta.videoWidth),
          height: VideoTranscoder.parseNumber(meta.videoHeight),
          rotation: VideoTranscoder.parseNumber(meta.videoOrientation)
        };
      } finally {
        try {
          await extractor.release();
        } catch (error) {
          // 忽略:释放失败不影响已经取到的元数据。
        }
      }
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * 播放方向的宽高(应用旋转角后)。写 <video> 标签的宽高属性用这个。
   * 转码只等比缩放、不改变宽高比,所以拿源视频的比例给产物用是对的。
   */
  static displaySize(probe: VideoProbe): VideoSize {
    const rotated: boolean = probe.rotation === 90 || probe.rotation === 270;
    return {
      width: rotated ? probe.height : probe.width,
      height: rotated ? probe.width : probe.height
    };
  }

  // 在给定码率下,从原始短边出发能站住的最高一档。
  private static tierIndexFor(sourceShort: number, videoBps: number): number {
    for (let index: number = 0; index < LADDER.length; index++) {
      const tier: QualityTier = LADDER[index];
      if (tier.short > sourceShort) {
        continue; // 比原片还大的档跳过 —— 只降不升
      }
      if (videoBps >= tier.minVideoBps || index === LADDER.length - 1) {
        return index;
      }
    }
    return LADDER.length - 1;
  }

  /**
   * 等比缩到目标短边,宽高取偶数(H.264 要求)。
   * 返回 undefined = 不需要缩,此时**不要**给 prepare 传宽高,让它自己保持源分辨率 ——
   * prepare 对「目标大于源」报 401,原样回传源尺寸只是白给自己一个踩线的机会。
   */
  private static scaleTo(width: number, height: number, targetShort: number): VideoSize | undefined {
    const sourceShort: number = Math.min(width, height);
    if (sourceShort <= targetShort) {
      return undefined;
    }
    const factor: number = targetShort / sourceShort;
    return {
      width: VideoTranscoder.evenize(width * factor),
      height: VideoTranscoder.evenize(height * factor)
    };
  }

  private static evenize(value: number): number {
    const rounded: number = Math.round(value);
    return Math.max(2, rounded % 2 === 0 ? rounded : rounded - 1);
  }

  /** 给定目标体积,最长能压多久(秒)。由阶梯最低档反推,常数一改这里自动跟上。 */
  static maxDurationSeconds(targetBytes: number): number {
    const floorBps: number = LADDER[LADDER.length - 1].minVideoBps + AUDIO_BITRATE;
    return Math.floor(targetBytes * 8 * SIZE_SAFETY / floorBps);
  }

  private static parseNumber(raw: string | undefined): number {
    if (raw === undefined || raw.length === 0) {
      return 0;
    }
    const value: number = Number.parseFloat(raw);
    return Number.isFinite(value) ? value : 0;
  }

  private static readableDuration(seconds: number): string {
    const total: number = Math.round(seconds);
    if (total < 60) {
      return `${total} 秒`;
    }
    const minutes: number = Math.floor(total / 60);
    const rest: number = total % 60;
    return rest === 0 ? `${minutes} 分钟` : `${minutes} 分 ${rest} 秒`;
  }

  private static readableSize(bytes: number): string {
    const mb: number = bytes / (1024 * 1024);
    return `${mb.toFixed(mb < 10 ? 1 : 0)} MB`;
  }
}

/** 视频元数据。width/height 是**编码方向**的,播放方向见 VideoTranscoder.displaySize。 */
export interface VideoProbe {
  durationSeconds: number;
  width: number;
  height: number;
  /** 旋转角(度)。90/270 表示播放时宽高互换。 */
  rotation: number;
}

export interface VideoSize {
  width: number;
  height: number;
}
