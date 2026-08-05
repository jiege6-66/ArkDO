import { Log } from '../../services/logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][TopicListStyle]';
// 与 ThemeManager / FabGlassPrefs / FeedPrefs 共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_TITLE_FONT_SIZE: string = 'topic_list_title_font_size';
const PREF_KEY_TITLE_FONT_WEIGHT: string = 'topic_list_title_font_weight';
const PREF_KEY_LINE_HEIGHT_RATIO: string = 'topic_list_line_height_ratio';
const PREF_KEY_ROW_PADDING: string = 'topic_list_row_padding';
const PREF_KEY_AVATAR_SIZE: string = 'topic_list_avatar_size';

// AppStorage 镜像 key:帖子列表行(TopicListItem)用 @StorageProp 逐个绑定,拖动滑块即时重排。
//
// 为什么是五个独立的 number key 而不是一个打包对象:AppStorage 里放对象时,改其字段不会穿透到
// @StorageProp,列表不会重渲染。标量键是这条链路上唯一可靠的形态。
export const TOPIC_LIST_TITLE_FONT_SIZE_KEY: string = 'topicListTitleFontSize';
export const TOPIC_LIST_TITLE_FONT_WEIGHT_KEY: string = 'topicListTitleFontWeight';
export const TOPIC_LIST_LINE_HEIGHT_RATIO_KEY: string = 'topicListLineHeightRatio';
export const TOPIC_LIST_ROW_PADDING_KEY: string = 'topicListRowPadding';
export const TOPIC_LIST_AVATAR_SIZE_KEY: string = 'topicListAvatarSize';

// ---------------------------------------------------------------------------
// 取值区间
//
// 上下限不是防呆凑数,每一档都卡在「再进一步这条列表就不成立」的位置上:
// 字号下限压到与次要文字同级就没有层次了,上限再高两行标题就吃掉大半屏;
// 行高下限之下中文字形上下相碰;行留白下限还有分割线兜底,上限之后一屏只剩五条;
// 头像下限是还能认出人脸的最小直径,上限已与两行标题等高。
//
// 默认值一律等于改造前的硬编码值,保证不动设置的老用户升级后列表分毫不变。
// ---------------------------------------------------------------------------

/** 标题字号。默认 17 即 Metrics 的 FONT_BODY_LARGE。 */
export const TITLE_FONT_SIZE_MIN: number = 13;
export const TITLE_FONT_SIZE_MAX: number = 21;
export const TITLE_FONT_SIZE_DEFAULT: number = 17;

/** 标题字重:只有这三档在字体里真实存在,故用分段按钮而非滑块。数值即 CSS 字重。 */
export const TITLE_FONT_WEIGHT_REGULAR: number = 400;
export const TITLE_FONT_WEIGHT_MEDIUM: number = 500;
export const TITLE_FONT_WEIGHT_SEMI_BOLD: number = 600;
export const TITLE_FONT_WEIGHT_DEFAULT: number = TITLE_FONT_WEIGHT_MEDIUM;

/** 行高倍率。存倍率而非绝对行高:改字号时行高自动跟随,不会出现「字变大了行距没跟上」。 */
export const LINE_HEIGHT_RATIO_MIN: number = 1.15;
export const LINE_HEIGHT_RATIO_MAX: number = 1.9;
export const LINE_HEIGHT_RATIO_STEP: number = 0.05;
// 1.35 × 17 四舍五入正好 23,与改造前的 lineHeight(23) 逐像素一致。
export const LINE_HEIGHT_RATIO_DEFAULT: number = 1.35;

/** 每行内容区的上下留白。 */
export const ROW_PADDING_MIN: number = 4;
export const ROW_PADDING_MAX: number = 20;
export const ROW_PADDING_DEFAULT: number = 8;

/** 头像直径。 */
export const AVATAR_SIZE_MIN: number = 32;
export const AVATAR_SIZE_MAX: number = 56;
export const AVATAR_SIZE_DEFAULT: number = 48;

/** 帖子列表行的一整套可调样式。 */
export interface TopicListStyle {
  titleFontSize: number;
  titleFontWeight: number;
  lineHeightRatio: number;
  rowPadding: number;
  avatarSize: number;
}

// ---------------------------------------------------------------------------
// 钳制:任何入口(读盘、滑块、外部调用)都要过这里
// ---------------------------------------------------------------------------

function clampInt(value: number, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, Math.round(value)));
}

export function clampTitleFontSize(value: number): number {
  return clampInt(value, TITLE_FONT_SIZE_MIN, TITLE_FONT_SIZE_MAX, TITLE_FONT_SIZE_DEFAULT);
}

export function clampRowPadding(value: number): number {
  return clampInt(value, ROW_PADDING_MIN, ROW_PADDING_MAX, ROW_PADDING_DEFAULT);
}

export function clampAvatarSize(value: number): number {
  return clampInt(value, AVATAR_SIZE_MIN, AVATAR_SIZE_MAX, AVATAR_SIZE_DEFAULT);
}

/** 行高倍率保留两位小数:滑块步进 0.05,浮点累加会攒出 1.3500000000000003 这种值。 */
export function clampLineHeightRatio(value: number): number {
  if (!Number.isFinite(value)) {
    return LINE_HEIGHT_RATIO_DEFAULT;
  }
  const bounded: number = Math.min(LINE_HEIGHT_RATIO_MAX, Math.max(LINE_HEIGHT_RATIO_MIN, value));
  return Math.round(bounded * 100) / 100;
}

/** 字重只认三个合法值,其余(含旧数据/脏值)一律回默认,不做就近取整。 */
export function normalizeTitleFontWeight(value: number): number {
  if (value === TITLE_FONT_WEIGHT_REGULAR || value === TITLE_FONT_WEIGHT_SEMI_BOLD) {
    return value;
  }
  return TITLE_FONT_WEIGHT_MEDIUM;
}

// ---------------------------------------------------------------------------
// 派生度量
//
// 次要文字、未读药丸、内联图标、内部间距都不单独开设置项——它们与标题同处一个文字流,
// 不跟着缩放就会错位(药丸和标题基线对不齐、图标比字还大)。全部由上面五个值算出来,
// 且默认值一律还原改造前的硬编码数字。
// ---------------------------------------------------------------------------

/** 标题行高。 */
export function titleLineHeight(titleFontSize: number, ratio: number): number {
  return Math.round(clampTitleFontSize(titleFontSize) * clampLineHeightRatio(ratio));
}

/** 次要文字(搜索摘要、时间):默认 13。上限封在 17,免得字号拉满时次要文字也跟着抢戏。 */
export function secondaryFontSize(titleFontSize: number): number {
  return clampInt(clampTitleFontSize(titleFontSize) - 4, 10, 17, 13);
}

/** 未读数药丸的字号:默认 12。 */
export function unreadBadgeFontSize(titleFontSize: number): number {
  return clampInt(clampTitleFontSize(titleFontSize) - 5, 9, 16, 12);
}

/** 未读药丸圆角 = 半个行高,默认 9。 */
export function unreadBadgeRadius(badgeFontSize: number): number {
  return Math.max(6, Math.round(badgeFontSize * 0.75));
}

/** 全新主题的小蓝点:默认 8。 */
export function unseenDotFontSize(titleFontSize: number): number {
  return clampInt(clampTitleFontSize(titleFontSize) - 9, 6, 12, 8);
}

/** 标题行首内联图标(书签 / 已解决)的边长:默认 15。 */
export function inlineIconSize(titleFontSize: number): number {
  return clampInt(clampTitleFontSize(titleFontSize) * 15 / 17, 11, 19, 15);
}

/** 内联图标与标题文字的间距:默认 5。 */
export function inlineIconGap(iconSize: number): number {
  return Math.max(3, Math.round(iconSize / 3));
}

/** 头像与文字列的间距:默认 8。 */
export function avatarGap(avatarSize: number): number {
  return Math.max(6, Math.round(clampAvatarSize(avatarSize) / 6));
}

/** 分类/标签/时间那一行与标题的间距:默认 3。跟随行留白一起松紧。 */
export function metaRowGap(rowPadding: number): number {
  return Math.max(2, Math.round(clampRowPadding(rowPadding) * 3 / 8));
}

/** 搜索摘要与标题的间距:默认 4。 */
export function blurbGap(rowPadding: number): number {
  return Math.max(2, Math.round(clampRowPadding(rowPadding) / 2));
}

/** 全默认的一套样式。 */
export function defaultTopicListStyle(): TopicListStyle {
  return {
    titleFontSize: TITLE_FONT_SIZE_DEFAULT,
    titleFontWeight: TITLE_FONT_WEIGHT_DEFAULT,
    lineHeightRatio: LINE_HEIGHT_RATIO_DEFAULT,
    rowPadding: ROW_PADDING_DEFAULT,
    avatarSize: AVATAR_SIZE_DEFAULT
  };
}

/**
 * 帖子列表行样式的持久化 + AppStorage 响应式镜像。
 *
 * 首页 / 搜索结果 / 已读列表共用 TopicListItem,故这套设置对三处同时生效——同一个组件
 * 维持同一套视觉语言,分开配置只会让人以为哪里出了 bug。
 *
 * 写盘与预览分离:滑块 onChange 每帧都来,只更新内存与 AppStorage(列表与预览即时跟手),
 * 松手(SliderChangeMode.End/Click)时才调 flush 落盘,避免每帧 store.flush() 卡顿。
 */
export class TopicListStylePrefs {
  // 内存镜像:同步读取路径用,避免每次 await。首次 load 后由各 setter 维护。
  private static cached: TopicListStyle = defaultTopicListStyle();
  private static loaded: boolean = false;

  /** 当前生效的样式副本。 */
  static current(): TopicListStyle {
    return {
      titleFontSize: TopicListStylePrefs.cached.titleFontSize,
      titleFontWeight: TopicListStylePrefs.cached.titleFontWeight,
      lineHeightRatio: TopicListStylePrefs.cached.lineHeightRatio,
      rowPadding: TopicListStylePrefs.cached.rowPadding,
      avatarSize: TopicListStylePrefs.cached.avatarSize
    };
  }

  /** 冷启动调用一次:读盘回填内存镜像并种入 AppStorage,保证任何列表挂载前首帧就按用户设置渲染。 */
  static load(context: common.UIAbilityContext | common.Context): void {
    if (!TopicListStylePrefs.loaded) {
      try {
        const store: preferences.Preferences =
          preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
        TopicListStylePrefs.cached = {
          titleFontSize: clampTitleFontSize(
            TopicListStylePrefs.readNumber(store, PREF_KEY_TITLE_FONT_SIZE, TITLE_FONT_SIZE_DEFAULT)),
          titleFontWeight: normalizeTitleFontWeight(
            TopicListStylePrefs.readNumber(store, PREF_KEY_TITLE_FONT_WEIGHT, TITLE_FONT_WEIGHT_DEFAULT)),
          lineHeightRatio: clampLineHeightRatio(
            TopicListStylePrefs.readNumber(store, PREF_KEY_LINE_HEIGHT_RATIO, LINE_HEIGHT_RATIO_DEFAULT)),
          rowPadding: clampRowPadding(
            TopicListStylePrefs.readNumber(store, PREF_KEY_ROW_PADDING, ROW_PADDING_DEFAULT)),
          avatarSize: clampAvatarSize(
            TopicListStylePrefs.readNumber(store, PREF_KEY_AVATAR_SIZE, AVATAR_SIZE_DEFAULT))
        };
        TopicListStylePrefs.loaded = true;
      } catch (error) {
        // 读失败按默认处理:纯外观设置,不该因存储异常影响启动。
        Log.i(`${LOG_TAG} load failed, fallback to defaults`);
        TopicListStylePrefs.cached = defaultTopicListStyle();
      }
    }
    TopicListStylePrefs.mirror();
  }

  static setTitleFontSize(value: number): number {
    TopicListStylePrefs.cached.titleFontSize = clampTitleFontSize(value);
    TopicListStylePrefs.mirror();
    return TopicListStylePrefs.cached.titleFontSize;
  }

  static setTitleFontWeight(value: number): number {
    TopicListStylePrefs.cached.titleFontWeight = normalizeTitleFontWeight(value);
    TopicListStylePrefs.mirror();
    return TopicListStylePrefs.cached.titleFontWeight;
  }

  static setLineHeightRatio(value: number): number {
    TopicListStylePrefs.cached.lineHeightRatio = clampLineHeightRatio(value);
    TopicListStylePrefs.mirror();
    return TopicListStylePrefs.cached.lineHeightRatio;
  }

  static setRowPadding(value: number): number {
    TopicListStylePrefs.cached.rowPadding = clampRowPadding(value);
    TopicListStylePrefs.mirror();
    return TopicListStylePrefs.cached.rowPadding;
  }

  static setAvatarSize(value: number): number {
    TopicListStylePrefs.cached.avatarSize = clampAvatarSize(value);
    TopicListStylePrefs.mirror();
    return TopicListStylePrefs.cached.avatarSize;
  }

  /** 恢复默认:内存 + 镜像 + 落盘一次到位。 */
  static resetDefaults(context: common.UIAbilityContext | common.Context): TopicListStyle {
    TopicListStylePrefs.cached = defaultTopicListStyle();
    TopicListStylePrefs.mirror();
    TopicListStylePrefs.flush(context);
    return TopicListStylePrefs.current();
  }

  /** 把当前内存镜像整体落盘。滑块松手 / 切换字重 / 恢复默认时各调一次。 */
  static flush(context: common.UIAbilityContext | common.Context): void {
    TopicListStylePrefs.loaded = true;
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      store.putSync(PREF_KEY_TITLE_FONT_SIZE, TopicListStylePrefs.cached.titleFontSize);
      store.putSync(PREF_KEY_TITLE_FONT_WEIGHT, TopicListStylePrefs.cached.titleFontWeight);
      store.putSync(PREF_KEY_LINE_HEIGHT_RATIO, TopicListStylePrefs.cached.lineHeightRatio);
      store.putSync(PREF_KEY_ROW_PADDING, TopicListStylePrefs.cached.rowPadding);
      store.putSync(PREF_KEY_AVATAR_SIZE, TopicListStylePrefs.cached.avatarSize);
      store.flush();
      Log.i(`${LOG_TAG} saved size=${TopicListStylePrefs.cached.titleFontSize} ` +
        `weight=${TopicListStylePrefs.cached.titleFontWeight} ` +
        `ratio=${TopicListStylePrefs.cached.lineHeightRatio} ` +
        `padding=${TopicListStylePrefs.cached.rowPadding} ` +
        `avatar=${TopicListStylePrefs.cached.avatarSize}`);
    } catch (error) {
      Log.i(`${LOG_TAG} save failed`);
    }
  }

  private static mirror(): void {
    AppStorage.setOrCreate<number>(TOPIC_LIST_TITLE_FONT_SIZE_KEY, TopicListStylePrefs.cached.titleFontSize);
    AppStorage.setOrCreate<number>(TOPIC_LIST_TITLE_FONT_WEIGHT_KEY, TopicListStylePrefs.cached.titleFontWeight);
    AppStorage.setOrCreate<number>(TOPIC_LIST_LINE_HEIGHT_RATIO_KEY, TopicListStylePrefs.cached.lineHeightRatio);
    AppStorage.setOrCreate<number>(TOPIC_LIST_ROW_PADDING_KEY, TopicListStylePrefs.cached.rowPadding);
    AppStorage.setOrCreate<number>(TOPIC_LIST_AVATAR_SIZE_KEY, TopicListStylePrefs.cached.avatarSize);
  }

  private static readNumber(store: preferences.Preferences, key: string, fallback: number): number {
    const raw: preferences.ValueType = store.getSync(key, fallback);
    return typeof raw === 'number' ? raw : fallback;
  }
}
