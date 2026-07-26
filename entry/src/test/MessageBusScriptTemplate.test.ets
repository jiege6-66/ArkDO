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
  });
}
