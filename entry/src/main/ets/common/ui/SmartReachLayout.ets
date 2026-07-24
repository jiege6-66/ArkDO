// 智感握姿的 UI 状态与布局参数集中在这里，三个接入点必须使用同一动画节奏。
export const SMART_REACH_LEFT_HAND_STORAGE_KEY: string = 'smartReachLeftHand';
export const SMART_REACH_ANIMATION_DURATION: number = 300;

export function smartReachBottomAlignRules(leftHanded: boolean): AlignRuleOption {
  if (leftHanded) {
    return {
      left: { anchor: '__container__', align: HorizontalAlign.Start },
      bottom: { anchor: '__container__', align: VerticalAlign.Bottom }
    };
  }
  return {
    right: { anchor: '__container__', align: HorizontalAlign.End },
    bottom: { anchor: '__container__', align: VerticalAlign.Bottom }
  };
}

export function smartReachCenterAlignRules(leftHanded: boolean): AlignRuleOption {
  if (leftHanded) {
    return {
      left: { anchor: '__container__', align: HorizontalAlign.Start },
      center: { anchor: '__container__', align: VerticalAlign.Center }
    };
  }
  return {
    right: { anchor: '__container__', align: HorizontalAlign.End },
    center: { anchor: '__container__', align: VerticalAlign.Center }
  };
}
