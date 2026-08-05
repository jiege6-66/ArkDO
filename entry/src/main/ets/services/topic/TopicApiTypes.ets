// Discourse 服务端响应/请求 DTO(数据传输对象):仅描述 API 的 JSON 形状,供 TopicService 内部
// 解析与映射使用,不对外暴露。纯类型定义,不依赖领域模型与任何逻辑。

export interface DiscourseLatestResponse {
  topic_list?: DiscourseTopicList;
  users?: DiscourseUser[];
}

export interface DiscourseTopicList {
  topics?: DiscourseTopic[];
  more_topics_url?: string;
}

export interface DiscourseTopic {
  id?: number;
  title?: string;
  slug?: string;
  category_id?: number;
  tags?: Object[];
  posts_count?: number;
  reply_count?: number;
  like_count?: number;
  created_at?: string;
  last_posted_at?: string;
  unseen?: boolean;
  unread_posts?: number;
  last_read_post_number?: number;
  highest_post_number?: number;
  posters?: DiscoursePoster[];
  has_accepted_answer?: boolean;
  bookmarked?: boolean;
}

export interface DiscoursePoster {
  user_id?: number;
  description?: string;
}

export interface DiscourseUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string;
  flair_url?: string;
  flair_bg_color?: string;
  flair_color?: string;
  flair_name?: string;
}

export interface DiscourseTopicDetail {
  id?: number;
  title?: string;
  slug?: string;
  category_id?: number;
  tags?: Object[];
  posts_count?: number;
  reply_count?: number;
  like_count?: number;
  views?: number;
  created_at?: string;
  post_stream?: DiscoursePostStream;
  last_read_post_number?: number;
  highest_post_number?: number;
  unread_posts?: number;
  user_badges?: DiscourseUserBadges;
  accepted_answers?: DiscourseAcceptedAnswer[];
  // 主题作者(楼主)用户 id:优先 details.created_by.id,回退顶层 user_id。
  user_id?: number;
  bookmarked?: boolean;
  // 已关闭回复 / 已归档。
  closed?: boolean;
  archived?: boolean;
  details?: DiscourseTopicDetailsField;
  // linux.do shared issue（"俺也一样"）:一楼下方举手按钮的真源(非 topic-voting)。
  shared_issue_visible?: boolean;
  can_create_shared_issue?: boolean;
  user_created_shared_issue?: boolean;
  shared_issue_count?: number;
  // 当前用户在本主题下被扣进审核队列、尚未过审的回复(TopicPendingPostSerializer 只给这三个字段)。
  pending_posts?: DiscoursePendingPost[];
  // MessageBus 订阅起点游标(TopicViewSerializer 顶层 message_bus_last_id):
  // 订阅 /topic/<id> 时以此为起点,闭合"加载与订阅之间"的窗口;缺失则回落 -1(只收新)。
  message_bus_last_id?: number;
}

// 待审帖:序列化器不带作者信息——按定义只有本人看得到自己的待审帖,作者即当前用户。
export interface DiscoursePendingPost {
  id?: number;
  raw?: string;
  created_at?: string;
}

// topic.json 顶层 details:此处只取 created_by(楼主),其余字段暂不消费。
export interface DiscourseTopicDetailsField {
  created_by?: DiscourseCreatedBy;
}

export interface DiscourseCreatedBy {
  id?: number;
}

export interface DiscoursePostStream {
  posts?: DiscoursePost[];
  stream?: number[];
}

// discourse-solved 采纳答案快照:自带 cooked HTML,面板据此自渲染,无需回列表找楼。
export interface DiscourseAcceptedAnswer {
  post_number?: number;
  username?: string;
  avatar_template?: string;
  created_at?: string;
  cooked?: string;
}

// 楼层作者状态:user_status.emoji 是具名表情短名(lollipop / tieba_003 …),经 EmojiUrlRegistry 查 url。
export interface DiscourseUserStatus {
  emoji?: string;
  description?: string;
}

// 顶层 user_badges:users 按 user_id 给出展示的 badge_ids,badges 按 id 给出图标名(FontAwesome)。
export interface DiscourseUserBadges {
  users?: Record<string, DiscourseUserBadgeUser>;
  badges?: Record<string, DiscourseBadgeDef>;
}

export interface DiscourseUserBadgeUser {
  id?: number;
  badge_ids?: number[];
}

export interface DiscourseBadgeDef {
  id?: number;
  icon?: string;
}

export interface DiscourseReaction {
  id?: string;
  type?: string;
  count?: number;
}

export interface DiscourseCurrentReaction {
  id?: string;
  type?: string;
  can_undo?: boolean;
}

// discourse-reactions 的反应用户分页接口。该接口不含各表情总数，总数仍以帖子详情的 reactions 为准。
export interface DiscourseReactionUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string;
  reaction?: string;
}

export interface DiscourseReactionUsersPage {
  users?: DiscourseReactionUser[];
  total_rows?: number;
}

// discourse-boosts:发 boost 的用户。
export interface DiscourseBoostUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string;
}

// discourse-boosts:一条 boost(id + cooked 短文本 + 用户)。
export interface DiscourseBoost {
  id?: number;
  cooked?: string;
  user?: DiscourseBoostUser;
}

// discourse-poll:一个投票选项(id + 展示 html + 票数)。
export interface DiscoursePollOption {
  id?: string;
  html?: string;
  votes?: number;
}

// discourse-poll:一个投票的服务端结构。
export interface DiscoursePoll {
  name?: string;
  type?: string;
  status?: string;
  public?: boolean;
  results?: string;
  options?: DiscoursePollOption[];
  voters?: number;
  title?: string;
}

export interface DiscoursePost {
  id?: number;
  topic_id?: number;
  post_number?: number;
  // 本楼是不是当前登录用户发的(PostSerializer#yours)。为真时不能给自己点赞,详情页把心形换成编辑入口。
  yours?: boolean;
  // 当前用户能不能改这一楼(PostSerializer#can_edit,走 Guardian)。注意「是我的」不等于「还能改」——
  // 超过 SiteSetting 的编辑时限后 yours 仍为真而 can_edit 变假。
  can_edit?: boolean;
  // 编辑用的 Markdown 原文。只有单帖接口 /posts/{id}.json 会带,列表接口不返回。
  raw?: string;
  user_id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string;
  cooked?: string;
  created_at?: string;
  updated_at?: string;
  reply_count?: number;
  like_count?: number;
  read?: boolean;
  user_title?: string;
  user_status?: DiscourseUserStatus;
  flair_url?: string;
  flair_bg_color?: string;
  flair_color?: string;
  flair_name?: string;
  reply_to_post_number?: number;
  reply_to_user?: DiscourseBoostUser;
  reactions?: DiscourseReaction[];
  reaction_users_count?: number;
  current_user_reaction?: DiscourseCurrentReaction;
  boosts?: DiscourseBoost[];
  can_boost?: boolean;
  bookmarked?: boolean;
  bookmark_id?: number;
  // discourse-poll:该楼的投票列表、当前用户各投票的已投项、能否投票。
  polls?: DiscoursePoll[];
  polls_votes?: Record<string, string[]>;
  can_vote?: boolean;
  // 本楼正文里各链接的被点击次数(PostSerializer#link_counts)。
  link_counts?: DiscourseLinkCount[];
}

// link_counts 的一项。url 与 cooked 里的 href 同源(站内链接也是绝对地址),据此配对挂角标。
// reflection=true 是「反链」——别的帖引用了本帖,它压根不出现在本楼正文里,只用于话题摘要,须剔除。
export interface DiscourseLinkCount {
  url?: string;
  internal?: boolean;
  reflection?: boolean;
  title?: string;
  clicks?: number;
}

// PUT/DELETE /polls/vote 的响应外壳:poll 为更新后的投票,vote 为当前用户已投项(撤销时缺省)。
export interface DiscoursePollVoteResponse {
  poll?: DiscoursePoll;
  vote?: string[];
}

// shared issue（"俺也一样"）toggle 的响应:{ count, user_created_shared_issue }——最新计数 + 已点态。
export interface DiscourseSharedIssueResponse {
  count?: number;
  user_created_shared_issue?: boolean;
}

// POST /bookmarks.json 的响应:{ success:"OK", id:<bookmarkId> }。
export interface DiscourseBookmarkResponse {
  success?: string;
  id?: number;
}

// DELETE /bookmarks/<id>.json 的响应:{ success:"OK", topic_bookmarked:bool }。
// topic_bookmarked = 取消这个书签后,该主题下是否仍有其它书签(主题级书签图标的权威真源)。
export interface DiscourseBookmarkDeleteResponse {
  success?: string;
  topic_bookmarked?: boolean;
}

// POST /posts 的响应外壳:真正的楼层在 post 字段里,不在顶层。
export interface CreatePostResponse {
  action?: string;
  success?: boolean;
  post?: DiscoursePost;
  // 进入审核队列时返回 pending_post(而非 post),action 为 'enqueued'。
  // 注意它不是楼层:NewPostResultSerializer 对该字段用的是 TopicPendingPostSerializer,
  // 与 topic.json 顶层 pending_posts 同构,只有 id/raw/created_at 三个字段。
  pending_post?: DiscoursePendingPost;
}

// 发表评论/回复 POST /posts 的请求体(对齐官方 composer 提交字段)。
export interface CreateReplyPayload {
  raw: string;
  unlist_topic: boolean;
  topic_id: number;
  category?: number;
  // 定向回复某楼时携带该楼号(对齐 Discourse composer);缺省=回复整个话题的顶层回复。
  reply_to_post_number?: number;
  is_warning: boolean;
  // 悄悄话(仅管理组可见)回复,普通回复为 false(对齐官方 composer)。
  whisper: boolean;
  archetype: string;
  typing_duration_msecs: number;
  composer_open_duration_msecs: number;
  composer_version: number;
  tags: string[];
  featured_link: string | null;
  shared_draft: boolean;
  draft_key: string;
  locale: string;
  // 图片尺寸表,无图时为空对象(对齐官方 composer)。
  image_sizes: Record<string, number>;
  nested_post: boolean;
}

// 发新主题 POST /posts 的请求体。与 CreateReplyPayload 同走 /posts,差别在于:
// 不带 topic_id/reply_to_post_number(没有可回的帖),改带 title + category;
// draft_key 是官方 composer 对新主题的固定值 'new_topic'。
export interface CreateTopicPayload {
  raw: string;
  title: string;
  category: number;
  unlist_topic: boolean;
  is_warning: boolean;
  archetype: string;
  typing_duration_msecs: number;
  composer_open_duration_msecs: number;
  composer_version: number;
  tags: string[];
  featured_link: string | null;
  shared_draft: boolean;
  draft_key: string;
  locale: string;
  image_sizes: Record<string, number>;
  nested_post: boolean;
}

// /tags/filter/search 的响应外壳。
export interface DiscourseTagFilterResponse {
  results?: DiscourseTagResult[];
}

export interface DiscourseTagResult {
  id?: number;
  name?: string;
  text?: string;
  count?: number;
  description?: string;
  pm_only?: boolean;
}

// /search.json 响应外壳:命中楼层在 posts、其主题元数据在 topics、命中作者在 users,
// 排序与"是否有下一页"在 grouped_search_result。
export interface DiscourseSearchResponse {
  posts?: DiscourseSearchPost[];
  topics?: DiscourseTopic[];
  users?: DiscourseUser[];
  grouped_search_result?: DiscourseGroupedSearchResult;
}

// 命中楼层:topic_id 指回其主题,blurb 是带 <span class="search-highlight"> 的摘要 HTML。
// 作者字段用于兜底:search 的 topics 常不带 posters,用命中楼作者补 topic.author 出头像。
export interface DiscourseSearchPost {
  id?: number;
  topic_id?: number;
  post_number?: number;
  blurb?: string;
  created_at?: string;
  user_id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
}

// grouped_search_result:post_ids 给出命中楼层的相关度排序;more_full_page_results 为真表示还有下一页。
export interface DiscourseGroupedSearchResult {
  post_ids?: number[];
  more_full_page_results?: boolean;
  term?: string;
}

// PUT /posts/{id} 的响应外壳:更新后的整个 post 挂在 post 字段下(与创建接口的裸对象不同)。
export interface DiscoursePostUpdateResponse {
  post?: DiscoursePost;
}
