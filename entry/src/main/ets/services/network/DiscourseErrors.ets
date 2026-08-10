import { NetworkResult } from './NetworkTypes';

/**
 * 从 Discourse 的错误响应里取出可直接展示给用户的原因。
 *
 * Discourse 对业务校验失败(422)统一回 `{"errors": ["...", "..."]}`,文案已按站点语言本地化,
 * 比我们自己编的「操作失败」有用得多 —— 发帖被 PostValidator 拦(附件超额、链接太多、正文太短)、
 * 上传被 UploadValidator 拦(扩展名不允许、体积超限),原因都只在这里。
 *
 * 少数端点用 `{"errors": {"字段": ["..."]}}` 或 `{"error": "..."}`,一并认掉。
 */

// 值可能是 string[](常见)或 Record<字段, string[]>(ActiveModel 的 errors.to_hash)。
interface DiscourseErrorBody {
  errors?: string[] | Record<string, string[]>;
  error?: string;
  // 部分端点(如 /uploads.json 的 failed_json)用 message 而非 errors。
  message?: string;
}

/**
 * 解析失败响应的 body,拿不到有意义的文案时返回空串(调用方回落到自己的兜底文案)。
 *
 * 注意传入的是 `NetworkResult<string>` 而不是裸 body:失败态的 body 由 ArkWebNetworkBridge
 * 在非 2xx 分支里塞进 `data`,这里统一从那里取,免得每个调用方都要记住这个约定。
 */
export function discourseErrorMessage(response: NetworkResult<string>): string {
  const body: string | undefined = response.data;
  if (!body || body.length === 0) {
    return '';
  }
  // CF 挑战页、nginx 错误页都是 HTML,JSON.parse 会抛;直接跳过,别把一整页 HTML 当文案。
  const trimmed: string = body.trim();
  if (trimmed.length === 0 || trimmed.charAt(0) !== '{') {
    return '';
  }

  let parsed: DiscourseErrorBody;
  try {
    parsed = JSON.parse(trimmed) as DiscourseErrorBody;
  } catch (error) {
    return '';
  }

  const messages: string[] = [];
  const errors: string[] | Record<string, string[]> | undefined = parsed.errors;
  if (Array.isArray(errors)) {
    for (let index: number = 0; index < errors.length; index++) {
      const item: string = errors[index];
      if (typeof item === 'string' && item.length > 0) {
        messages.push(item);
      }
    }
  } else if (errors !== undefined && errors !== null) {
    // 字段 → 文案数组。字段名对用户没意义,只取文案。
    const grouped: Record<string, string[]> = errors as Record<string, string[]>;
    const fields: string[] = Object.keys(grouped);
    for (let index: number = 0; index < fields.length; index++) {
      const list: string[] = grouped[fields[index]];
      if (!Array.isArray(list)) {
        continue;
      }
      for (let inner: number = 0; inner < list.length; inner++) {
        const item: string = list[inner];
        if (typeof item === 'string' && item.length > 0) {
          messages.push(item);
        }
      }
    }
  }

  if (messages.length === 0 && typeof parsed.error === 'string' && parsed.error.length > 0) {
    messages.push(parsed.error);
  }
  if (messages.length === 0 && typeof parsed.message === 'string' && parsed.message.length > 0) {
    messages.push(parsed.message);
  }
  // 多条时用顿号接起来:Discourse 常一次回好几条(如同时超字数又超链接数),只显示第一条会误导。
  return messages.join('；');
}
