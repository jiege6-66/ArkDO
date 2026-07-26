// ArkWeb 注入脚本工厂:为各类网络请求(GET / 取图 / 表单 / JSON / 上传 / PUT)生成在 WebView 内
// 执行的 fetch 脚本。纯字符串生成,不持有状态;脚本内用 REQUEST_ID_TOKEN 占位,由执行器在运行前
// 替换成真实 requestId。写请求统一走 buildCsrfScript(带 CSRF 令牌与 Discourse 头)。
import { buildCsrfScript } from './webscript/CsrfScriptTemplate';

// 脚本里的 requestId 占位符:执行器 run() 时用真实 id 替换(见 ArkWebNetworkBridge 的 WebviewJsonExecutor)。
export const REQUEST_ID_TOKEN: string = '__ARKDO_REQUEST_ID__';

export function createFetchScript(path: string): string {
  const encodedPath: string = JSON.stringify(path);

  return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedPath}, window.location.origin);
      fetch(requestUrl.toString(), {
        credentials: 'include',
        cache: 'no-store',
        headers: {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache'
        }
      }).then((response) => {
        response.text().then((body) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            cfMitigated: response.headers.get('cf-mitigated') || '',
            body: body
          }));
        }).catch((error) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: 0,
            contentType: '',
            body: '',
            errorMessage: String(error)
          }));
        });
      }).catch((error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0,
          contentType: '',
          body: '',
          errorMessage: String(error)
        }));
      });
      return requestId;
    })();`;
}

// 二进制取图脚本:fetch 头像 → arrayBuffer → base64(分块 fromCharCode 避免大数组爆栈)。
// 支持跨源:CDN(cdn/s3.ldstatic.com)回 ACAO=linux.do 具体源且无 Allow-Credentials,故跨源必须
// credentials:'omit'(带 cookie 会被 CORS 拒),同源仍 include。cache:'default' 命中 webview HTTP 缓存。
export function createImageFetchScript(target: string): string {
  const encodedTarget: string = JSON.stringify(target);

  return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedTarget}, window.location.origin);
      const sameOrigin = requestUrl.origin === window.location.origin;
      const fail = (error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0, contentType: '', body: '', errorMessage: String(error)
        }));
      };
      fetch(requestUrl.toString(), {
        credentials: sameOrigin ? 'include' : 'omit',
        cache: 'default',
        headers: { 'Accept': 'image/*' }
      }).then((response) => {
        response.arrayBuffer().then((buf) => {
          const bytes = new Uint8Array(buf);
          let binary = '';
          const chunk = 8192;
          for (let i = 0; i < bytes.length; i += chunk) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
          }
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: btoa(binary)
          }));
        }).catch(fail);
      }).catch(fail);
      return requestId;
    })();`;
}

export function createFormScript(method: string, path: string, body: string, referrer: string): string {
  // 表单写请求(timings / 点赞 / 投票等)。X-SILENCE-LOGGER + Discourse-Background 是
  // 后台静默请求的标记,照抓包对齐,勿删勿重排。
  return buildCsrfScript({
    requestIdToken: REQUEST_ID_TOKEN,
    urlExpr: JSON.stringify(path),
    methodExpr: JSON.stringify(method),
    headerLines: [
      "'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'",
      "'Accept': '*/*'",
      "'X-CSRF-Token': csrf",
      "'X-Requested-With': 'XMLHttpRequest'",
      "'X-SILENCE-LOGGER': 'true'",
      "'Discourse-Background': 'true'",
      "'Discourse-Present': 'true'",
      "'Discourse-Logged-In': 'true'"
    ],
    prelude: '',
    bodyExpr: JSON.stringify(body),
    referrerExpr: JSON.stringify(referrer)
  });
}

export function createPostJsonScript(path: string, body: string, referrer: string): string {
  // 发表评论/回复:POST /posts,application/json。
  // 这是用户主动发起的前台请求,故不带 X-SILENCE-LOGGER / Discourse-Background。
  return buildCsrfScript({
    requestIdToken: REQUEST_ID_TOKEN,
    urlExpr: JSON.stringify(path),
    methodExpr: "'POST'",
    headerLines: [
      "'Content-Type': 'application/json'",
      "'Accept': '*/*'",
      "'X-CSRF-Token': csrf",
      "'X-Requested-With': 'XMLHttpRequest'",
      "'Discourse-Present': 'true'",
      "'Discourse-Logged-In': 'true'"
    ],
    prelude: '',
    bodyExpr: JSON.stringify(body),
    referrerExpr: JSON.stringify(referrer)
  });
}

export function createUploadScript(base64: string, fileName: string, mimeType: string, referrer: string): string {
  const encodedBase64: string = JSON.stringify(base64);
  const encodedFileName: string = JSON.stringify(fileName);
  const encodedMimeType: string = JSON.stringify(mimeType);
  // 图片上传:base64 → Uint8Array → Blob → FormData。
  // 刻意不设 Content-Type——FormData 要由浏览器自己写 multipart boundary,手设会破坏分隔符。
  return buildCsrfScript({
    requestIdToken: REQUEST_ID_TOKEN,
    urlExpr: "'/uploads.json'",
    methodExpr: "'POST'",
    headerLines: [
      "'Accept': '*/*'",
      "'X-CSRF-Token': csrf",
      "'X-Requested-With': 'XMLHttpRequest'",
      "'Discourse-Present': 'true'",
      "'Discourse-Logged-In': 'true'"
    ],
    prelude: `        const binary = atob(${encodedBase64});
        const len = binary.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) { bytes[i] = binary.charCodeAt(i); }
        const blob = new Blob([bytes], { type: ${encodedMimeType} });
        const fd = new FormData();
        fd.append('upload_type', 'composer');
        fd.append('relativePath', 'null');
        fd.append('name', ${encodedFileName});
        fd.append('type', ${encodedMimeType});
        fd.append('file', blob, ${encodedFileName});
`,
    bodyExpr: 'fd',
    referrerExpr: JSON.stringify(referrer)
  });
}

export function createPutScript(path: string, referrer: string): string {
  // 空 body 的 PUT(书签等)。不带 body,故 headers 收尾无逗号。
  return buildCsrfScript({
    requestIdToken: REQUEST_ID_TOKEN,
    urlExpr: JSON.stringify(path),
    methodExpr: "'PUT'",
    headerLines: [
      "'Accept': '*/*'",
      "'X-CSRF-Token': csrf",
      "'X-Requested-With': 'XMLHttpRequest'",
      "'X-SILENCE-LOGGER': 'true'",
      "'Discourse-Background': 'true'",
      "'Discourse-Present': 'true'",
      "'Discourse-Logged-In': 'true'"
    ],
    prelude: '',
    bodyExpr: '',
    referrerExpr: JSON.stringify(referrer)
  });
}
