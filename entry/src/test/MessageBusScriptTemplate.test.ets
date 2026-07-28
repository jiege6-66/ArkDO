import { describe, it, expect } from '@ohos/hypium';
import { buildMessageBusScript } from '../main/ets/services/network/webscript/MessageBusScriptTemplate';

export default function messageBusScriptTemplateTest() {
  describe('messageBusScriptTemplateTest', () => {
    it('buildsLatestLongPollWithRequiredHeaders', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain("channels: { '/latest': -1 }");
      expect(script).assertContain("new URL('message-bus/'");
      expect(script).assertContain("'X-Requested-With': 'XMLHttpRequest'");
      expect(script).assertContain("'Dont-Chunk': 'true'");
      expect(script).assertContain("'Content-Type': 'application/x-www-form-urlencoded'");
      expect(script.includes("'Discourse-Present'" )).assertFalse();
    });

    it('guardsAgainstDuplicateLoopsAndReportsBridgeEvents', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain('window.__arkdoMessageBusStarted');
      expect(script).assertContain('window.ArkDOBridge.onBusEvent');
      expect(script).assertContain("type: 'message'");
      expect(script).assertContain("type: 'challenge'");
    });

    it('advancesLatestCursorFromStatusBeforePollingAgain', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain("message.channel === '/__status'");
      expect(script).assertContain('state.channels[channel] = message.data[channel]');
      expect(script).assertContain('continue;');
    });

    it('allowsDelayedRestartAfterChallenge', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain('window.__arkdoMessageBusStarted = false');
      expect(script).assertContain('setTimeout(start, 30000)');
    });

    it('honorsExternalStopRequestFlag', 0, () => {
      const script: string = buildMessageBusScript();

      // 注入即清停止标志，让本次循环起跑。
      expect(script).assertContain('window.__arkdoMessageBusStopRequested = false');
      // start() 与 poll 循环都尊重外部停止请求。
      expect(script).assertContain('if (window.__arkdoMessageBusStopRequested)');
      expect(script).assertContain('while (state.running && !window.__arkdoMessageBusStopRequested');
    });

    it('killsSupersededLoopsViaGenerationToken', 0, () => {
      const script: string = buildMessageBusScript();

      // 每次 start 捕获并递增全局代次；poll 循环据此在被取代时退出，防止快速关→开双开。
      expect(script).assertContain('window.__arkdoMessageBusGeneration = generation');
      expect(script).assertContain('generation === window.__arkdoMessageBusGeneration');
    });

    it('usesOfficialUuidClientIdAndReportsLifecycle', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain("'xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx'.replace");
      expect(script).assertContain("stage: 'started'");
      expect(script).assertContain("stage: 'cursor-ready'");
    });

    it('doesNotTreatOrdinaryNonJsonErrorsAsCloudflareChallenge', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain('const looksLikeChallenge');
      expect(script).assertContain("type: 'error',");
      expect(script).assertContain("message: 'message bus returned non-json'");
    });

    it('resolvesConfiguredLongPollingBaseUrl', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain('long_polling_base_url');
      expect(script).assertContain("querySelector('#data-preloaded')");
      expect(script).assertContain('preload.textContent');
      expect(script).assertContain("JSON.parse(preloaded.siteSettings)");
      expect(script).assertContain("stage: 'config-ready'");
      expect(script).assertContain("new URL('message-bus/'");
    });

    it('forwardsSharedSessionKeyToExternalMessageBus', 0, () => {
      const script: string = buildMessageBusScript();

      expect(script).assertContain("querySelector('meta[name=shared_session_key]')");
      expect(script).assertContain("headers['X-Shared-Session-Key'] = state.sharedSessionKey");
    });

    it('subscribesNotificationChannelForLoggedInUser', 0, () => {
      const script: string = buildMessageBusScript();

      // 从 preloaded.currentUser 解析登录用户 id（兼容字符串化 JSON）。
      expect(script).assertContain('preloaded.currentUser');
      // 仅登录时订阅 /notification/<id>，游标 -1 只收新消息。
      expect(script).assertContain('pollConfig.currentUserId > 0');
      expect(script).assertContain("state.channels['/notification/' + pollConfig.currentUserId] = -1");
    });

    it('exposesDynamicChannelSubscriptionApi', 0, () => {
      const script: string = buildMessageBusScript();

      // 详情页动态订阅 /topic/<id> 的运行时增删入口 + 持久集合。
      expect(script).assertContain('window.__arkdoMessageBusAddChannel');
      expect(script).assertContain('window.__arkdoMessageBusRemoveChannel');
      expect(script).assertContain('window.__arkdoMessageBusChannels = window.__arkdoMessageBusChannels || {}');
      // start() 并入持久集合并暴露活跃 state，供运行时增删。
      expect(script).assertContain('state.channels[name] = extraChannels[name]');
      expect(script).assertContain('window.__arkdoMessageBusActiveState = state');
      // 动态频道游标随 poll 推进同步进持久集合，循环重启后从最新位置续订。
      expect(script).assertContain('window.__arkdoMessageBusChannels[message.channel] = message.message_id');
    });
  });
}
