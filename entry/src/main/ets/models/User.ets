/**
 * 侧栏自选标签的一项(current_user.sidebar_tags,即网页版侧栏「标签」分区点「编辑」挑出来的那批)。
 *
 * 字段与 TopicTag 完全一致,却在这里另立一份:models 里 Topic 单向 import User,反过来再引就成了循环依赖。
 * 用于列表筛选时由 CategoryDrawer 转成 TopicTag(带 id+slug,正好拼得出最稳的 /tag/{slug}/{id} 路由)。
 */
export interface SidebarTag {
  id?: number;
  name: string;
  slug?: string;
}

export interface User {
  id: number;
  username: string;
  displayName?: string;
  avatarTemplate?: string;
  animatedAvatar?: string;
  // 头像右下角角标(flair):flairUrl 要么是 FontAwesome 图标名(如 "gem"),要么是一张图片 URL(gif/png)。
  // 图标形态用 flairBgColor 作底色圆、flairColor 作图标色;图片形态直接显示图。flairName 是组名(g-premium 等)。
  flairUrl?: string;
  flairBgColor?: string;
  flairColor?: string;
  flairName?: string;
  // 来自 /session/current.json 的 current_user:头像未读徽标用。
  // unreadNotifications=总未读(含私信等高优先级,对齐 Discourse 铃铛角标);
  // unreadHighPriorityNotifications=其中的高优先级子集(私信等)。
  unreadNotifications?: number;
  unreadHighPriorityNotifications?: number;
  // 未发出的草稿数(current_user.draft_count),个人中心草稿角标用。
  draftCount?: number;
  // 侧栏自选的标签与版块(current_user.sidebar_tags / sidebar_category_ids),在网页版侧栏点「编辑」维护。
  // 首页筛选抽屉把它们各自置顶,省得在几百个标签、几十个版块里翻;空数组=没配置过,抽屉照旧只给热门标签。
  sidebarTags?: SidebarTag[];
  sidebarCategoryIds?: number[];
  // 信任等级(0~4)与管理身份。来自 /session/current.json 的 current_user
  // (CurrentUserSerializer 的 trust_level / admin? / moderator?)。
  //
  // 编辑器据此提前拦上传:Discourse 的附件门是 PostValidator#max_attachments_validator ——
  // 非 TL1+ 且非私信时,附件数不得超过 newuser_max_attachments(默认 0)。网页版同样在前端
  // 先判一次(frontend/discourse/app/models/user.js 的 isAllowedToUploadAFile)。
  // 不判就让用户传完整个文件再吃一个 422,白等一场。
  trustLevel?: number;
  admin?: boolean;
  moderator?: boolean;
}
