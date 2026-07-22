const DEFAULT_FLOATING_ACTION_MARGIN: number = 16;

export function floatingActionBottomMargin(bottomInsetVp: number): number {
  return DEFAULT_FLOATING_ACTION_MARGIN + (bottomInsetVp > 0 ? bottomInsetVp : 0);
}
