// 富内容领域模型:CookedHtmlParser 解析 Discourse cooked HTML 后产出的块/行内节点结构。
// 纯类型定义(enum + interface),不含解析逻辑,供解析器与渲染层(PostRichContent 等)共享。
import { TopicCategory } from '../../models/Topic';

export enum RichBlockType {
  PARAGRAPH = 'paragraph',
  HEADING = 'heading',
  QUOTE = 'quote',
  // Discourse 话题/帖子引用(<aside class="quote" data-topic data-post>,带 quote-title__text-content 头部):
  // 头部含头像 + 话题标题链接 + 分类徽章,正文是被引用楼的截断预览。渲染成带头部的引用卡,右上角可展开拉全文。
  TOPIC_QUOTE = 'topic_quote',
  // Obsidian/Discourse callout(discourse-quote-callouts 主题组件):首段以 [!type]± 开头的
  // blockquote → 彩色可折叠提示框。type 决定图标/主色,+ 默认展开、- 默认折叠、无后缀不可折叠。
  CALLOUT = 'callout',
  CODE = 'code',
  IMAGE = 'image',
  LIST = 'list',
  DISCLOSURE = 'disclosure',
  // discourse-spoiler-alert 块级剧透:<div class="spoiler">…</div>,揭示前整块遮蔽。
  SPOILER = 'spoiler',
  DIVIDER = 'divider',
  POLL = 'poll',
  ONEBOX = 'onebox',
  // <audio>/<video>:原生播放器就地播放。src 为解析后的媒体 URL(和图片同源 /uploads/),
  // 直接喂给 AVPlayer / Video 组件流式播放。
  AUDIO = 'audio',
  VIDEO = 'video',
  // discourse-math 块级公式(<div class="math">):text 存裸 LaTeX(displayMode=true),
  // 渲染层交离屏 KaTeX 引擎出图后居中显示。
  MATH = 'math',
  // Markdown 表格(<table>,Discourse 常裹一层 <div class="md-table">):抽成行/单元格结构,
  // 渲染层用等宽列对齐 + 横向 Scroll,过宽时左右滑动而不撑破栏宽。
  TABLE = 'table',
  UNSUPPORTED = 'unsupported'
}

export enum RichInlineType {
  TEXT = 'text',
  LINK = 'link',
  CODE = 'code',
  IMAGE = 'image',
  // discourse-math 行内公式(<span class="math">):text 存裸 LaTeX(displayMode=false),
  // 渲染层出图后以 ImageSpan 基线内联,保证周围文字仍走原生 Text、字体字号与全帖一致。
  MATH = 'math',
  LINE_BREAK = 'line_break'
}

export interface RichInlineNode {
  type: RichInlineType;
  text: string;
  href?: string;
  src?: string;
  alt?: string;
  bold?: boolean;
  italic?: boolean;
  code?: boolean;
  // 附件下载链接(Discourse <a class="attachment"> 或指向 /uploads/ 的链接):渲染时前置下载图标,点击触发原生下载。
  attachment?: boolean;
  // 行内剧透(<span class="spoiler">):揭示前渲染为涂抹条,点击后显示。
  spoiler?: boolean;
  // 段落分隔用的换行(仅 LINE_BREAK):由 mergeAdjacentParagraphs 在合并的相邻段落之间插入,
  // 渲染成双换行空行营造段距。与 <br> 普通换行区分,后者仍是单换行。
  paragraphBreak?: boolean;
}

export interface RichListItem {
  inlines: RichInlineNode[];
  // 列表项内含块级图(lightbox/大图)时改用 blocks:文字成段落、图片各自成块级 IMAGE,
  // 避免大图退化成 18px 行内小图。纯文字项仍只用 inlines(blocks 缺省)。
  blocks?: RichBlock[];
}

// TABLE 单元格:行内节点序列 + 是否表头(<th> 或位于 <thead> 内)。
export interface RichTableCell {
  inlines: RichInlineNode[];
  header?: boolean;
}

export interface RichTableRow {
  cells: RichTableCell[];
  // 整行是否表头行(全部单元格来自 thead / 全为 th)。渲染表头行加底色与粗体。
  header?: boolean;
}

export interface RichBlock {
  type: RichBlockType;
  inlines?: RichInlineNode[];
  blocks?: RichBlock[];
  items?: RichListItem[];
  // TABLE 块:按出现顺序的行,每行含若干单元格。
  tableRows?: RichTableRow[];
  text?: string;
  title?: string;
  unsupportedKind?: string;
  language?: string;
  src?: string;
  alt?: string;
  width?: number;
  height?: number;
  href?: string;
  // AUDIO/VIDEO 块:媒体 MIME(如 audio/mp4、video/mp4),来自 <source type>,供播放器与降级判断参考。
  mediaType?: string;
  ordered?: boolean;
  level?: number;
  // POLL 块:data-poll-name,用于在正文正确位置占位、并按名字关联 TopicPost.polls 的动态数据。
  pollName?: string;
  // ONEBOX(链接预览卡片)字段:域名/站点图标/描述/缩略图;title 复用上面的 title,跳转 URL 复用 href。
  domain?: string;
  faviconUrl?: string;
  description?: string;
  thumbnailUrl?: string;
  // CALLOUT 块字段:calloutKind 归一后的类型(用于无标题时回退成类型名);calloutColor 主色(标题+图标);
  // calloutIcon FontAwesome 图标 id(对应 rawfile/fa_icons);collapsible 是否可折叠;
  // defaultExpanded 折叠态默认(+→true、-→false);titleInlines 标题段行内节点(可含粗体/链接);blocks 为正文子块。
  calloutKind?: string;
  calloutColor?: string;
  calloutIcon?: string;
  collapsible?: boolean;
  defaultExpanded?: boolean;
  titleInlines?: RichInlineNode[];
  // TOPIC_QUOTE 头部数据:头像 URL / 作者用户名 / 话题标题 / 目标 topic 与楼号(供展开按 by_number 拉全文)/
  // 分类徽章。折叠预览的 cooked 复用 text,话题链接复用 href。
  quoteAvatarUrl?: string;
  quoteAuthor?: string;
  quoteTitle?: string;
  quoteTopicId?: number;
  quotePostNumber?: number;
  quoteCategory?: TopicCategory;
  // 同帖回复引用(title 只有「显示名:」无话题链接):跳转是在本帖内定位到那一楼 → 按被引用楼在
  // 本楼之后/之前给 arrow-down / arrow-up;跨帖引用(有话题链接)则是打开另一个帖子 → 用 arrow-right。
  quoteIsReply?: boolean;
}
