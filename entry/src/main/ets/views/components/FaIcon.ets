import { buffer } from '@kit.ArkTS';
import resourceManager from '@ohos.resourceManager';

export const LINUXDO_FA_SYMBOLS_RAWFILE = 'linuxdo_fa_symbols.json';

export interface FaIconDefinition {
  id: string;
  rawfilePath: string;
}

interface RawFaIconDefinition {
  id?: string;
}

const faIconMap: Map<string, FaIconDefinition> = new Map();
let faIconsLoaded: boolean = false;
const FALLBACK_FA_ICON_SIZE: number = 14;

export function loadFaIconsFromRawContent(rawContent: Uint8Array): number {
  try {
    const json: string = buffer.from(rawContent as ArrayBufferLike).toString('utf8');
    return loadFaIconsFromJson(json);
  } catch (err) {
    faIconMap.clear();
    faIconsLoaded = true;
    return 0;
  }
}

export function loadFaIconsFromJson(json: string): number {
  let rawIcons: RawFaIconDefinition[] = [];
  try {
    rawIcons = JSON.parse(json) as RawFaIconDefinition[];
  } catch (err) {
    faIconMap.clear();
    faIconsLoaded = true;
    return 0;
  }

  faIconMap.clear();

  if (!Array.isArray(rawIcons)) {
    faIconsLoaded = true;
    return 0;
  }

  for (let index: number = 0; index < rawIcons.length; index++) {
    const rawIcon: RawFaIconDefinition = rawIcons[index];
    const icon: FaIconDefinition | undefined = normalizeRawIcon(rawIcon);
    if (icon) {
      faIconMap.set(icon.id, icon);
    }
  }

  faIconsLoaded = true;
  return faIconMap.size;
}

export function ensureFaIconsLoaded(manager: resourceManager.ResourceManager): number {
  if (faIconsLoaded && faIconMap.size > 0) {
    return faIconMap.size;
  }

  try {
    const rawContent: Uint8Array = manager.getRawFileContentSync(LINUXDO_FA_SYMBOLS_RAWFILE);
    return loadFaIconsFromRawContent(rawContent);
  } catch (err) {
    faIconMap.clear();
    faIconsLoaded = true;
    return 0;
  }
}

export function getFaIcon(iconId: string): FaIconDefinition | undefined {
  return faIconMap.get(iconId);
}

export function hasLoadedFaIcons(): boolean {
  return faIconsLoaded;
}

function normalizeRawIcon(rawIcon: RawFaIconDefinition): FaIconDefinition | undefined {
  if (!rawIcon.id || rawIcon.id.trim().length === 0) {
    return undefined;
  }

  const iconId: string = rawIcon.id.trim();
  return {
    id: iconId,
    rawfilePath: `fa_icons/${iconId}.svg`
  };
}

@Component
export struct FaIconView {
  // 必须是 @Prop:普通成员变量只在组件创建时被父组件赋值一次,之后父组件再传新值也不会同步进来。
  // 多数调用点的图标是定死的,或者挂在 ForEach 上(换 key 就换实例),看不出区别;但只要有一处
  // 是「同一个 FaIconView 实例换图标」——比如筛选抽屉里那个已选标签 chip、顶栏的分类/标签图标——
  // 就会出现「文字换了、图标还停在上一个」。
  @Prop icon: FaIconDefinition = {
    id: '',
    rawfilePath: ''
  };
  // 支持资源色($r),深浅色模式切换时随资源重解析;字符串色值保持兼容。
  @Prop color: ResourceColor = '#6B7280';
  @Prop iconSize: number = FALLBACK_FA_ICON_SIZE;

  build() {
    Image($rawfile(this.icon.rawfilePath))
      .objectFit(ImageFit.Contain)
      .renderMode(ImageRenderMode.Template)
      .fillColor(this.color)
      .draggable(false)
      .width(this.getFrameSize())
      .height(this.getFrameSize())
  }

  private getFrameSize(): number {
    return this.iconSize > 0 ? this.iconSize : FALLBACK_FA_ICON_SIZE;
  }
}
