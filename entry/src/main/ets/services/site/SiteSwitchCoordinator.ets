import { ArkWebNetworkBridge } from '../network/ArkWebNetworkBridge';
import { CategoryIndex } from './CategoryIndex';
import { CurrentSite } from './CurrentSite';
import { DohManager } from '../network/DohManager';
import { LoginGate } from '../session/LoginGate';
import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';

const LOG_TAG: string = '[ArkDO][SiteSwitch]';

/**
 * 切站善后。CurrentSite 只负责「换掉地址」,真正要跟着动的东西都收在这里。
 *
 * 顺序是有讲究的,别随手调换:
 *
 * 1. **先清进程内缓存**。宿主 webview 一重载,新站的请求可能立刻发出并回来;这时若旧站
 *    的版块缓存还在,新站的数据会跟旧站的版块树混在一起。
 * 2. **再重置登录态**。先置未登录,而不是等新站的会话检查回来 —— 否则中间那段时间里
 *    界面会用上一个论坛的登录身份(能点赞、能发帖),点下去必然 403。
 *    注意:这只是 App 侧的判断位,**不动任何 cookie**。各论坛的 cookie 由系统按域名分仓
 *    存放,原论坛的登录不受影响,切回来仍然是登录态。
 * 3. **然后重下发 DoH**。DoH 是按域名解析的,新站的域名要重新走一遍当前的 DoH 配置,
 *    否则首个请求会以系统 DNS 出去(可能被污染/超时)。
 * 4. **最后重载宿主 webview**。它必须是最后一步:reloadHost 会加载新站的
 *    HOST_BOOTSTRAP_URL(该 getter 此刻已指向新站)拿到一个新 origin 的同源文档,而排队中
 *    的注入式 fetch 会在重载后的 onPageEnd 一起放行 —— 前面几步没做完就放行,请求会带着
 *    旧状态出去。
 *
 * epoch 的事不在这里做:CurrentSite.switchTo 已经自增过代次,各请求方自己用
 * isCurrentEpoch 丢弃过期响应。
 */
export class SiteSwitchCoordinator {
  /**
   * 执行切站善后。调用方需在 CurrentSite 已切换之后调用(即在其订阅回调里)。
   * bridge 未就绪(冷启动尚未 attachController)时跳过重载 —— 那种情况下宿主本来
   * 就还没建起来,首次建立时读的已经是新地址。
   */
  static afterSwitch(context: common.Context, bridge: ArkWebNetworkBridge): void {
    const target: string = CurrentSite.baseUrl;
    Log.i(`${LOG_TAG} begin target=${target} epoch=${CurrentSite.epoch}`);

    CategoryIndex.clearCache();

    // 只在「原本判定为已登录」时才需要翻回未登录:未登录切未登录不必惊动订阅者。
    if (LoginGate.isLoggedIn()) {
      LoginGate.setLoggedIn(false);
      Log.i(`${LOG_TAG} login flag reset (cookies untouched)`);
    }

    try {
      DohManager.applyActive(context);
    } catch (err) {
      Log.e(`${LOG_TAG} re-apply DoH failed: ${JSON.stringify(err)}`);
    }

    if (target.length === 0) {
      // 论坛被删空:没有可引导的地址,不要拿空 URL 去 loadUrl。Index 此时已切回引导页。
      Log.i(`${LOG_TAG} no active site, skip host reload`);
      return;
    }
    // reloadHost 内部已 markHostLoadIssued(关门闩 + 记一笔在途重载),不必在外面再关一次。
    const ok: boolean = bridge.reloadHost();
    Log.i(`${LOG_TAG} host reload issued ok=${ok}`);
  }
}
