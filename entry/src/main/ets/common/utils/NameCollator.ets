import { intl } from '@kit.LocalizationKit';
import { Log } from '../../services/logging/Log';

const LOG_TAG: string = '[ArkDO][Collator]';

/**
 * 中文名称排序。
 *
 * **不要用 String.localeCompare**:它在 ArkTS 运行时是码点序,不是语言环境排序。
 * 实测「前沿快讯」(U+524D) 会排到「国产替代」(U+56FD) 前面,而按拼音应是 guó < qián。
 * zh-Hans 的默认排序规则即拼音,与浏览器上 Discourse 拿 zh_CN 语言环境跑 localeCompare 的结果一致
 * (侧栏标签的排序就发生在前端:frontend/discourse/app/models/user.js 的 sidebarTags getter)。
 *
 * 语言标签写死 zh-Hans 而不跟设备语言走:要对齐的是网页版在中文环境下的顺序,
 * 跟着设备走的话英文设备上又会漂回码点序。
 */
export class NameCollator {
  // Collator 构造有成本,建一次存着复用。
  private static collator: intl.Collator | undefined = undefined;
  private static failed: boolean = false;

  static compare(left: string, right: string): number {
    if (NameCollator.collator === undefined && !NameCollator.failed) {
      try {
        NameCollator.collator = new intl.Collator('zh-Hans');
      } catch (err) {
        // 理论上不会;真发生了就退回码点序——顺序不对,但不至于让列表整个排不出来。
        NameCollator.failed = true;
        Log.e(`${LOG_TAG} init failed: ${JSON.stringify(err)}`);
      }
    }
    const collator: intl.Collator | undefined = NameCollator.collator;
    return collator !== undefined ? collator.compare(left, right) : left.localeCompare(right);
  }
}
