const HDS_TITLE_BAR_BASE_HEIGHT: number = 56;
const HDS_TITLE_BAR_CONTENT_GAP: number = 8;

export function immersiveTitleBarContentTopSpacer(sysTopInset: number): number {
  const safeTop: number = sysTopInset > 0 ? sysTopInset : 0;
  return safeTop + HDS_TITLE_BAR_BASE_HEIGHT + HDS_TITLE_BAR_CONTENT_GAP;
}
