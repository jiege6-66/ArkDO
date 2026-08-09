import { CurrentSite } from './CurrentSite';

/**
 * 站点能力开关。决定哪些功能在当前论坛下露出。
 *
 * ArkDO 是通用 Discourse 客户端,但有一批功能是 linux.do 生态特有的:它们依赖那个站的
 * 独立子域(connect / credit)、主题组件配置、或写死的帖子 id。换到别的 Discourse 站,
 * 这些入口要么打不开、要么指向一篇完全无关的帖子,必须整体隐藏。
 *
 * 判据统一走这里,不在各页里散写 `CurrentSite.isLinuxDo` —— 否则以后新增专属功能或
 * 支持第二个特殊站点时,必然漏掉几处。
 *
 * ## 为什么按域名而不按能力探测
 * 理想做法是读 `/site.json` 看站点装了哪些插件。但这几项都不是标准 Discourse 插件:
 * connect/credit 是独立站点、标签图标是主题组件的私有配置、反馈帖是一个具体 topic id
 * —— `/site.json` 里没有任何字段能表达它们。所以按域名判定是这里唯一可行的办法。
 * 走标准插件路线的能力(solved、poll 等)不在此列,那些该由 `/site.json` 决定。
 */
export class SiteCapabilities {
  /** 等级进度页(connect.linux.do,经 SSO 复用主站会话)。 */
  static get levelProgress(): boolean {
    return CurrentSite.isLinuxDo;
  }

  /** LINUX DO Credit 页(credit.linux.do,独立站点 + 独立会话)。 */
  static get ldcCredit(): boolean {
    return CurrentSite.isLinuxDo;
  }

  /** 「反馈与建议」入口。指向写死的 topic id,只在 linux.do 上存在。 */
  static get feedbackTopic(): boolean {
    return CurrentSite.isLinuxDo;
  }

  /**
   * 「我的站点」生态站点快捷方式。它的卖点是「复用论坛登录态免登录进生态站点」,
   * 而那依赖 linux.do 作为 OAuth 身份提供方 —— 换站后既没有生态站点可去,
   * 也没有可复用的授权关系。
   */
  static get ecosystemSites(): boolean {
    return CurrentSite.isLinuxDo;
  }

  /** 抽奖帖提醒与规则帖。linux.do 的社区玩法与约定,非 Discourse 标准能力。 */
  static get lotteryTopics(): boolean {
    return CurrentSite.isLinuxDo;
  }

  /** 标签图标。来自 linux.do 主题组件的私有配置表,别的站点的标签对不上。 */
  static get tagIcons(): boolean {
    return CurrentSite.isLinuxDo;
  }
}
