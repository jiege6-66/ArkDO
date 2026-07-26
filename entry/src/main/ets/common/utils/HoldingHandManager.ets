import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Log } from '../../services/logging/Log';
import { AppStateEventBus } from '../../services/session/AppStateEventBus';
import { SMART_REACH_LEFT_HAND_STORAGE_KEY } from '../ui/SmartReachLayout';

const LOG_TAG: string = '[ArkDO][SmartReach]';
// 与 ThemeManager / RealtimeTopicsPrefs 等共用同一个 preferences 库，只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'smart_reach_enabled';

// 全应用只订阅一次握姿变化。页面只消费 AppStorage 中的稳定左右状态，避免各自重复监听传感器。
export class HoldingHandManager {
  // 智感握姿开关(默认关)。关闭时传感器不订阅，布局恒为默认右侧。init 时从 preferences 载入。
  private static enabled: boolean = false;
  private static activated: boolean = false;
  private static subscribed: boolean = false;
  private static unsupported: boolean = false;

  private static readonly holdingHandChanged: Callback<motion.HoldingHandStatus> =
    (status: motion.HoldingHandStatus): void => {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        // 双手、未持握和未知状态不触发换边，沿用上一次明确结果，避免短暂识别抖动导致控件来回跳。
        if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
          HoldingHandManager.publishLeftHanded(true);
        } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
          HoldingHandManager.publishLeftHanded(false);
        }
      }
    };

  static init(context: common.Context): void {
    // 默认右侧与改造前布局完全一致；不支持该能力或订阅失败时不改变现有界面。
    AppStorage.setOrCreate<boolean>(SMART_REACH_LEFT_HAND_STORAGE_KEY, false);
    // 读取开关(默认关)。关闭时 start() 直接跳过订阅，界面沿用默认右侧布局。
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      const value: preferences.ValueType = store.getSync(PREF_KEY_ENABLED, false);
      HoldingHandManager.enabled = value === true;
    } catch (err) {
      HoldingHandManager.enabled = false;
      Log.i(`${LOG_TAG} read enabled failed, fallback to disabled`);
    }
  }

  static isEnabled(): boolean {
    return HoldingHandManager.enabled;
  }

  // 用户在设置里切换开关：持久化并即时生效。开⇒(已激活且前台时)订阅传感器开始识别；
  // 关⇒停订阅并把布局复位到默认右侧。
  static setEnabled(context: common.Context, enabled: boolean): void {
    HoldingHandManager.enabled = enabled;
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      store.putSync(PREF_KEY_ENABLED, enabled);
      store.flush();
      Log.i(`${LOG_TAG} enabled=${enabled}`);
    } catch (err) {
      Log.i(`${LOG_TAG} save enabled failed enabled=${enabled}`);
    }
    if (enabled) {
      if (HoldingHandManager.activated && AppStateEventBus.isForeground()) {
        HoldingHandManager.start();
      }
    } else {
      HoldingHandManager.stop();
      AppStorage.setOrCreate<boolean>(SMART_REACH_LEFT_HAND_STORAGE_KEY, false);
    }
  }

  // UIContent 首帧创建完成后才激活，确保传感器首个回调写入 AppStorage 时已有 UI 观察者。
  static activate(): void {
    HoldingHandManager.activated = true;
    if (AppStateEventBus.isForeground()) {
      HoldingHandManager.start();
    }
  }

  static resume(): void {
    if (HoldingHandManager.activated) {
      HoldingHandManager.start();
    }
  }

  static pause(): void {
    HoldingHandManager.stop();
  }

  static destroy(): void {
    HoldingHandManager.activated = false;
    HoldingHandManager.stop();
  }

  private static start(): void {
    // 开关关闭(默认)时不订阅传感器：零后台功耗，布局恒为默认右侧。
    if (!HoldingHandManager.enabled) {
      return;
    }
    if (HoldingHandManager.subscribed || HoldingHandManager.unsupported) {
      return;
    }
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      HoldingHandManager.unsupported = true;
      Log.i(`${LOG_TAG} capability unavailable, keep right-side layout`);
      return;
    }
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      try {
        motion.on('holdingHandChanged', HoldingHandManager.holdingHandChanged);
        HoldingHandManager.subscribed = true;
        Log.i(`${LOG_TAG} holdingHandChanged subscribed`);
      } catch (err) {
        const error: BusinessError = err as BusinessError;
        // 801 表示机型硬件不支持，后续前台切换无需重复尝试；其余瞬态错误下次前台再重试。
        if (error.code === 801) {
          HoldingHandManager.unsupported = true;
        }
        Log.i(`${LOG_TAG} subscribe failed code=${error.code ?? 0} message=${error.message ?? ''}`);
      }
    }
  }

  private static stop(): void {
    if (!HoldingHandManager.subscribed) {
      return;
    }
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      try {
        motion.off('holdingHandChanged', HoldingHandManager.holdingHandChanged);
      } catch (err) {
        const error: BusinessError = err as BusinessError;
        Log.i(`${LOG_TAG} unsubscribe failed code=${error.code ?? 0} message=${error.message ?? ''}`);
      }
    }
    HoldingHandManager.subscribed = false;
  }

  private static publishLeftHanded(leftHanded: boolean): void {
    if (AppStorage.get<boolean>(SMART_REACH_LEFT_HAND_STORAGE_KEY) === leftHanded) {
      return;
    }
    AppStorage.setOrCreate<boolean>(SMART_REACH_LEFT_HAND_STORAGE_KEY, leftHanded);
    Log.i(`${LOG_TAG} stableSide=${leftHanded ? 'left' : 'right'}`);
  }
}
