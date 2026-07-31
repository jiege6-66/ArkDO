import { Log } from '../logging/Log';
import { inputMethod } from '@kit.IMEKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';

const LOG_TAG: string = '[ArkDO][LoginKbd]';

// 注入到登录页的全局对象名。登录页是第三方页面(linux.do 自己的表单 + hCaptcha 的 iframe),
// 名字取得长而怪是刻意的:bridge / native / app 这类通名很容易被无关脚本探到。
const BRIDGE_NAME: string = 'arkdoLoginKeyboard7f3a';

/**
 * 页面侧唯一能调到的东西:请求收起软键盘。无参、无返回值、拿不到任何应用数据。
 *
 * 往第三方页面注入的能力面必须压到最小 —— 刻意不复用 ArkWebNetworkBridge 那个代理,
 * 那个能替应用发带 Cookie 的请求,给登录页用是过度授权。
 */
class LoginKeyboardProxy {
  // reason 是触发来源(touchstart / submit / …),只在出错时进日志、不参与任何逻辑 ——
  // 页面能传进来的东西必须是惰性的。
  dismissKeyboard(reason: string): void {
    const tag: string = typeof reason === 'string' ? reason.slice(0, 32) : '?';
    try {
      inputMethod.getController().stopInputSession()
        .catch((error: BusinessError) => {
          // 12800003 = 编辑框未聚焦 / 没有绑定的编辑框。调用时机不对才会走到这里,
          // 错误码一定要打出来,否则下次只能看到一句「rejected」去猜。
          Log.i(`${LOG_TAG} stopInputSession rejected by=${tag} code=${error.code} msg=${error.message}`);
        });
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`${LOG_TAG} stopInputSession threw by=${tag} code=${err.code}`);
    }
  }
}

/**
 * 登录页的软键盘收起桥。
 *
 * 要解决的问题:登录表单在 WebView 里,输入密码后键盘还杵着,ArkUI 的键盘避让把整个登录 sheet
 * 顶了上去;此时点「登录」,hCaptcha 的人机验证弹层按被顶起后的视口定位,弹出来就有一截在可视区外,
 * 被 sheet 裁掉,用户没法完成验证。实测手动收起键盘再点登录就一切正常,故只需在点击的那一刻把键盘收掉。
 *
 * 两道保险:
 *  · 页面侧 blur() —— 摘掉焦点,多数情况下 WebView 会顺势收起输入法
 *  · 原生 stopInputSession() —— blur 在 ArkWeb 上不保证一定收起键盘,这条是权威手段
 */
export class LoginKeyboardBridge {
  private readonly proxy: LoginKeyboardProxy = new LoginKeyboardProxy();

  createProxy(controller: webview.WebviewController): JavaScriptProxy {
    return {
      object: this.proxy,
      name: BRIDGE_NAME,
      methodList: ['dismissKeyboard'],
      controller: controller
    };
  }

  /**
   * 注入脚本。每次 onPageEnd 都跑一遍:页面内有真实导航时 document 会换新,标记位随之失效,
   * 正好重新挂上;同一份文档里重复注入则被标记位挡掉。
   *
   * 用「点了任何非输入元素就摘焦点」而不是「找到登录按钮再处理」:后者要盯死站点的 DOM 结构,
   * linux.do 改一次登录表单我们就得跟着改,那种代码活不长。
   */
  static script(): string {
    return `(function () {
  if (window.__arkdoLoginKbdReady) { return; }
  window.__arkdoLoginKbdReady = true;

  function isEditable(node) {
    if (!node || !node.tagName) { return false; }
    var tag = node.tagName.toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select') { return true; }
    return node.isContentEditable === true;
  }

  var lastAt = 0;
  function dismiss(reason) {
    // 同一次点击会连着触发 touchstart / mousedown / click,只放行第一条。
    var now = Date.now();
    if (now - lastAt < 400) { return; }
    lastAt = now;
    // 顺序不能反:stopInputSession 要求「编辑框仍处于聚焦态」(否则报 12800003),
    // 所以必须先请原生收键盘,再把页面焦点摘掉。先 blur 会亲手毁掉它的前提。
    try { ${BRIDGE_NAME}.dismissKeyboard(reason); } catch (e) {}
    try {
      var el = document.activeElement;
      if (el && typeof el.blur === 'function') { el.blur(); }
    } catch (e) {}
  }

  // 一次点击到底会派发哪些事件,取决于 WebView 的实现 —— ArkWeb 未必派发 Pointer Events。
  // 与其赌某一种,不如几种都挂上,由上面的去重保证只生效一次。
  ['touchstart', 'pointerdown', 'mousedown'].forEach(function (type) {
    document.addEventListener(type, function (event) {
      if (!isEditable(event.target)) { dismiss(type); }
    }, true);
  });

  // 软键盘上的「前往 / 回车」会直接提交表单,不产生上面那些事件,得单独接一道。
  document.addEventListener('submit', function () { dismiss('submit'); }, true);
})();`;
  }
}
