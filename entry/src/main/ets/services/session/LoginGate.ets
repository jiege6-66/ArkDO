import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][LoginGate]';
const STORAGE_KEY_LOGGED_IN: string = 'arkdoIsLoggedIn';

/** 全局登录态在 AppStorage 中的 key，供宿主 webview 等通过 @StorageProp 响应式绑定（如 MessageBus 启停）。 */
export const LOGGED_IN_STORAGE_KEY: string = STORAGE_KEY_LOGGED_IN;

/** 信任等级「还没查到」。区别于 TL0(已确认是新用户),两者要走不同分支。 */
export const TRUST_LEVEL_UNKNOWN: number = -1;

export type RequireLoginListener = () => void;
// 登录态由「未登录」翻成「已登录」时触发:供已在场的页面(如详情页)补做只在登录后才能起的动作。
export type LoginStateListener = () => void;

// 登录闸门:全局登录态(持久化 AppStorage) + 「请求登录」事件总线。
// 各处写操作(点赞/评论/投票/收藏/通知已读等)在发网络请求前调 ensureLoggedIn():
// 已登录放行;未登录广播一次请求 → RootTabPage 弹出登录页,并返回 false 让调用方就地拦截,不再发请求。
// 登录态真源仍是 RootTabPage 的会话检查,这里只做一份可全局读取的镜像(深层 NavDestination 够不到 @Prop)。
export class LoginGate {
  private static listeners: Map<number, RequireLoginListener> = new Map();
  private static nextListenerId: number = 0;
  private static loginStateListeners: Map<number, LoginStateListener> = new Map();
  private static nextLoginStateListenerId: number = 0;
  // 只驻内存,不落盘 —— 理由见 setUserPrivileges。
  private static trustLevelValue: number = TRUST_LEVEL_UNKNOWN;
  private static staffValue: boolean = false;

  // 由 EntryAbility.onCreate 在任何页面读取 AppStorage 之前调用一次:把登录态镜像双向绑定到磁盘。
  // 冷启动即从磁盘恢复上次「检查成功」的登录态,否则默认 false → 已登录用户在首个 /session/current.json
  // 回来前(尤其命中 CF 盾时更久)被误判为游客:阅读计时器不启动(已读丢失)、写操作被静默拦截并强弹登录页。
  static initPersist(): void {
    PersistentStorage.persistProp<boolean>(STORAGE_KEY_LOGGED_IN, false);
  }

  // 由 RootTabPage 在 /session/current.json 检查「成功」后同步写入(CF 盾/网络失败不改,保持上次态)。
  // 从非登录翻成登录时广播一次:让已在场页面补启登录后才可用的逻辑(如详情页阅读追踪)。
  static setLoggedIn(loggedIn: boolean): void {
    const wasLoggedIn: boolean = LoginGate.isLoggedIn();
    AppStorage.setOrCreate<boolean>(STORAGE_KEY_LOGGED_IN, loggedIn);
    if (loggedIn && !wasLoggedIn) {
      LoginGate.notifyBecameLoggedIn();
    }
  }

  static isLoggedIn(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEY_LOGGED_IN) === true;
  }

  /**
   * 同步当前用户的信任等级与管理身份。与 setLoggedIn 同一处调用(会话检查成功后)。
   *
   * 编辑器用它决定附件按钮要不要置灰:Discourse 的 PostValidator#max_attachments_validator
   * 对非 TL1+ 且非私信的帖子,把附件数卡在 newuser_max_attachments(默认 0)。
   *
   * ## 为什么不持久化(loggedIn 却持久化了)
   * 信任等级是**按站点**的:linux.do 上 TL3,换到新加的站就是 TL0。持久化会让切站后的
   * 首个会话检查回来前用错等级 —— 而这里用错的代价是「让用户传完整个文件再吃 422」,
   * 比 loggedIn 用错(白弹一次登录页)难受得多。所以宁可开局是「未知」。
   */
  static setUserPrivileges(trustLevel: number, staff: boolean): void {
    LoginGate.trustLevelValue = trustLevel;
    LoginGate.staffValue = staff;
  }

  /** 登出/切站时复位成「未知」。 */
  static clearUserPrivileges(): void {
    LoginGate.trustLevelValue = TRUST_LEVEL_UNKNOWN;
    LoginGate.staffValue = false;
  }

  /** 当前信任等级;-1 表示还没查到(见 TRUST_LEVEL_UNKNOWN)。 */
  static trustLevel(): number {
    return LoginGate.trustLevelValue;
  }

  static isStaff(): boolean {
    return LoginGate.staffValue;
  }

  /**
   * 能否发附件。判据照抄网页版 frontend/discourse/app/models/user.js 的
   * isAllowedToUploadAFile:staff、或 TL>0、或站点把 newuser_max_attachments 开了非 0。
   *
   * **等级未知时一律放行**。宁可让用户传完被服务端拒(我们会把 422 的原因显示出来),
   * 也不要因为会话还没查回来就把功能藏掉 —— 后者看起来像 App 坏了。
   */
  static canUploadAttachment(newuserMaxAttachments: number): boolean {
    if (LoginGate.staffValue) {
      return true;
    }
    const level: number = LoginGate.trustLevelValue;
    if (level === TRUST_LEVEL_UNKNOWN) {
      return true;
    }
    return level > 0 || newuserMaxAttachments > 0;
  }

  // 写操作前置闸门:已登录返回 true 放行;未登录返回 false 并请求弹登录页。
  static ensureLoggedIn(): boolean {
    if (LoginGate.isLoggedIn()) {
      return true;
    }
    Log.i(`${LOG_TAG} write action blocked: not logged in, request login sheet`);
    LoginGate.requestLogin();
    return false;
  }

  static requestLogin(): void {
    const listeners: RequireLoginListener[] = [];
    LoginGate.listeners.forEach((listener: RequireLoginListener) => {
      listeners.push(listener);
    });
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  static subscribe(listener: RequireLoginListener): () => void {
    const listenerId: number = LoginGate.nextListenerId;
    LoginGate.nextListenerId++;
    LoginGate.listeners.set(listenerId, listener);
    return () => {
      LoginGate.listeners.delete(listenerId);
    };
  }

  // 订阅「登录态翻真」:返回取消订阅句柄。信号严格对齐 isLoggedIn 由 false→true 的那一刻,
  // 回调里读 isLoggedIn() 必为 true(不同于 SessionEventBus:会话变化事件早于 setLoggedIn 写入)。
  static subscribeBecameLoggedIn(listener: LoginStateListener): () => void {
    const listenerId: number = LoginGate.nextLoginStateListenerId;
    LoginGate.nextLoginStateListenerId++;
    LoginGate.loginStateListeners.set(listenerId, listener);
    return () => {
      LoginGate.loginStateListeners.delete(listenerId);
    };
  }

  private static notifyBecameLoggedIn(): void {
    const listeners: LoginStateListener[] = [];
    LoginGate.loginStateListeners.forEach((listener: LoginStateListener) => {
      listeners.push(listener);
    });
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        Log.i(`${LOG_TAG} login-state listener failed error=${JSON.stringify(error)}`);
      }
    }
  }
}
