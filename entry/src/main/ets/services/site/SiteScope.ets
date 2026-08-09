import { AppConstants } from '../../common/constants/AppConstants';

/**
 * 站点级存储的分键约定。
 *
 * ArkDO 是多论坛客户端,但历史上所有 preferences 都塞在同一个 `app_settings` 库里、
 * 只靠键名区分,且键名不带站点 —— 于是「搜索历史」「推送订阅」这类**属于某个论坛**的数据
 * 会在论坛之间互相覆盖或串味。
 *
 * 统一走这里分键,而不是每处各写一套:
 *
 *     store.getSync(SiteScope.key('search_history'), '')
 *     // → 'search_history@linux.do'
 *
 * ## 为什么按 host 而不是论坛 id
 * host 才是站点的真实身份。按 id 分的话,用户删掉再重新添加同一个论坛(id 变了)就会丢掉
 * 原有数据;按 host 分则能接回去。代价是**改论坛地址会让旧数据成为孤儿** —— 那种操作
 * 本就等于换了个站,数据不该跟过去,所以这个代价是想要的。
 *
 * ## 全局 vs 站点级
 * 只有「属于某个论坛」的数据才分键。主题深浅色、字号行高、DoH 配置、日志开关这些是
 * 用户对 App 本身的偏好,必须保持全局,不要套进来。
 */
export class SiteScope {
  /**
   * 给基础键加上当前站点后缀。未选定站点时返回带 `@` 空后缀的形式而非裸键 ——
   * 宁可让那一小段时间的读写落在一个谁也不用的键上,也不要污染某个真实站点的数据。
   */
  static key(baseKey: string): string {
    return `${baseKey}@${AppConstants.HOST}`;
  }

  /** 给基础键加上指定站点后缀。用于推送这类「要按通知来源站点取数据」的场景。 */
  static keyFor(baseKey: string, host: string): string {
    return `${baseKey}@${host}`;
  }
}
