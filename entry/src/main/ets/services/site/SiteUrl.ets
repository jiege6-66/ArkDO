/**
 * 站点 URL 的规范化与校验。
 *
 * 从 SitePrefs 抽出来的:论坛列表(ForumPrefs)与生态站点列表(SitePrefs)都要用同一套规则,
 * 否则「同一个域名在两处被判定成不同结果」会出很隐蔽的 bug。SitePrefs 的同名静态方法
 * 保留为薄壳转发,故既有调用点无需改动。
 */
export class SiteUrl {
  /** 补全裸域名为 https:// 并去首尾空白。从论坛复制来的多是全 URL,手输的多是裸域名。 */
  static normalize(input: string): string {
    const trimmed: string = input.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const lower: string = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    return `https://${trimmed}`;
  }

  /** 粗校验:必须 http(s) 且 host 带点。挡空输入与明显笔误,不做严格 RFC 解析。 */
  static isValid(url: string): boolean {
    const lower: string = url.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    const host: string = SiteUrl.hostOf(url);
    return host.length > 0 && host.indexOf('.') > 0;
  }

  /** 取 host(不含协议/路径/端口);解析不出时返回空串。 */
  static hostOf(url: string): string {
    const trimmed: string = url.trim();
    const schemeEnd: number = trimmed.indexOf('://');
    if (schemeEnd < 0) {
      return '';
    }
    let rest: string = trimmed.substring(schemeEnd + 3);
    const slash: number = rest.indexOf('/');
    if (slash >= 0) {
      rest = rest.substring(0, slash);
    }
    const colon: number = rest.indexOf(':');
    if (colon >= 0) {
      rest = rest.substring(0, colon);
    }
    return rest;
  }

  /**
   * 去掉尾部斜杠。站点根地址必须无尾斜杠——全 app 的接口地址都靠 `${BASE_URL}/xxx.json`
   * 拼接,带尾斜杠会拼出 `//xxx.json`,Discourse 会 301 到无斜杠版本,白跑一趟重定向。
   */
  static stripTrailingSlash(url: string): string {
    let result: string = url.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /** 规范化成可直接当站点根地址用的形式:补协议 + 去尾斜杠。非法输入返回空串。 */
  static toBaseUrl(input: string): string {
    const normalized: string = SiteUrl.normalize(input);
    if (!SiteUrl.isValid(normalized)) {
      return '';
    }
    return SiteUrl.stripTrailingSlash(normalized);
  }
}
