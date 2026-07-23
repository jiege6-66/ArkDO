import {
  BlurStrategy,
  HdsNavigationTitleBarStyle,
  HdsTitleBarContentStyle,
  ScrollEffectOptions,
  ScrollEffectType,
  SystemMaterialParams,
  TitleBarStyleOptions
} from '@kit.UIDesignKit';
import { LengthMetrics } from '@ohos.arkui.node';
import {
  adaptiveSystemMaterialEffect,
  HDS_TITLE_BAR_BLUR_RADIUS,
  HDS_TITLE_BAR_MASK_EXTRA_HEIGHT,
  ImmersiveLightSystemMaterialEffect,
  preferredTitleBarScrollEffectType
} from './ImmersiveLightMaterial';

// 各页面仅声明自身真正不同的滚动行为。视觉材质统一在 buildImmersiveTitleBarStyle 中维护，
// 避免某个页面遗漏半透明底色或模糊策略后，再次出现深色内容被扩散成黑影的问题。
export interface ImmersiveTitleBarStyleConfig {
  enableRefreshOffsetChange?: boolean;
  blurEffectiveStartOffset?: LengthMetrics;
  blurEffectiveEndOffset?: LengthMetrics;
  // HDS 只开放按钮容器背景与前景色，不开放边框/圆角。该参数只调整返回按钮背景，
  // 未传时保持系统默认沉浸光感按钮，便于先在单个页面验证对比度。
  backIconBackgroundColor?: ResourceColor;
  menuBackgroundColor?: ResourceColor;
  // 默认使用系统 ADAPTIVE，让 HDS 根据设备能力绘制原生按钮亮边；特殊页面仍可覆盖。
  // 标题栏半透明底色、模糊策略和滚动阈值始终由本公共样式统一控制。
  materialEffect?: ImmersiveLightSystemMaterialEffect;
}

function buildTitleBarContentStyle(
  config: ImmersiveTitleBarStyleConfig
): HdsTitleBarContentStyle | undefined {
  const contentStyle: HdsTitleBarContentStyle = {};
  let hasCustomStyle: boolean = false;
  if (config.backIconBackgroundColor !== undefined) {
    contentStyle.backIconStyle = { backgroundColor: config.backIconBackgroundColor };
    hasCustomStyle = true;
  }
  if (config.menuBackgroundColor !== undefined) {
    contentStyle.menuStyle = { backgroundColor: config.menuBackgroundColor };
    hasCustomStyle = true;
  }
  return hasCustomStyle ? contentStyle : undefined;
}

export function buildImmersiveTitleBarStyle(
  config: ImmersiveTitleBarStyleConfig = {}
): TitleBarStyleOptions {
  const scrollEffectOpts: ScrollEffectOptions = {
    enableScrollEffect: true,
    scrollEffectType: preferredTitleBarScrollEffectType() as ScrollEffectType
  };
  if (config.enableRefreshOffsetChange !== undefined) {
    scrollEffectOpts.enableRefreshOffsetChange = config.enableRefreshOffsetChange;
  }
  if (config.blurEffectiveStartOffset !== undefined) {
    scrollEffectOpts.blurEffectiveStartOffset = config.blurEffectiveStartOffset;
  }
  if (config.blurEffectiveEndOffset !== undefined) {
    scrollEffectOpts.blurEffectiveEndOffset = config.blurEffectiveEndOffset;
  }

  const originalStyle: HdsNavigationTitleBarStyle = {
    backgroundStyle: {
      backgroundColor: Color.Transparent,
      blurRadius: 0
    }
  };
  const scrollEffectStyle: HdsNavigationTitleBarStyle = {
    backgroundStyle: {
      backgroundColor: $r('app.color.hds_title_bar_scrolled_bg'),
      maskExtraHeight: HDS_TITLE_BAR_MASK_EXTRA_HEIGHT,
      blurRadius: HDS_TITLE_BAR_BLUR_RADIUS
    }
  };
  const originalContentStyle: HdsTitleBarContentStyle | undefined = buildTitleBarContentStyle(config);
  const scrolledContentStyle: HdsTitleBarContentStyle | undefined = buildTitleBarContentStyle(config);
  if (originalContentStyle !== undefined) {
    originalStyle.contentStyle = originalContentStyle;
  }
  if (scrolledContentStyle !== undefined) {
    scrollEffectStyle.contentStyle = scrolledContentStyle;
  }

  return {
    scrollEffectOpts: scrollEffectOpts,
    // 初始态不垫实体背景，列表可以自然穿入标题栏区域。
    originalStyle: originalStyle,
    // 滚动态先用主题半透明底色压淡深色内容，再执行渐变模糊，消除过渡阶段的黑影。
    scrollEffectStyle: scrollEffectStyle,
    // 模糊始终启用以抑制滚动黑影；材质默认交给系统 ADAPTIVE，保留原生按钮高光边缘。
    blurStrategy: BlurStrategy.ENABLE,
    systemMaterialEffect: (config.materialEffect !== undefined
      ? config.materialEffect
      : adaptiveSystemMaterialEffect()) as SystemMaterialParams
  };
}
