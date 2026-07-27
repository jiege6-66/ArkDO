import { describe, it, expect } from '@ohos/hypium';
import { DraftService } from '../main/ets/services/draft/DraftService';
import { DraftEventBus } from '../main/ets/services/draft/DraftEventBus';
import {
  ChallengeState,
  JsonNetworkClient,
  JsonRequestOptions,
  NetworkResult
} from '../main/ets/services/network/NetworkTypes';

class FakeBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';
  requestedBody: string = '';
  requestedReferrer: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedBody = body;
    this.requestedReferrer = options?.referrer ? options.referrer : '';
    return Promise.resolve(this.result);
  }

  uploadImage(base64: string, fileName: string, mimeType: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }
}

function ok(payload: string): NetworkResult<string> {
  return { success: true, statusCode: 200, challengeState: ChallengeState.NONE, data: payload };
}

export default function draftServiceTest() {
  describe('draftServiceTest', () => {
    it('deletesDraftWithKeyAndSequence', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(ok('{"success":"OK"}'));
      const service: DraftService = new DraftService(bridge);

      const result: NetworkResult<boolean> =
        await service.deleteDraft('new_private_message_1781604136983', 0);

      expect(bridge.requestedPath).assertEqual('/drafts/new_private_message_1781604136983.json');
      expect(bridge.requestedBody).assertEqual('draft_key=new_private_message_1781604136983&sequence=0');
      expect(bridge.requestedReferrer).assertEqual('https://linux.do/my/activity/drafts');
      expect(result.success).assertTrue();
      expect(result.data).assertTrue();
    });

    it('rejectsDeleteResponseWithoutSuccessConfirmation', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(ok('{}'));
      const result: NetworkResult<boolean> = await new DraftService(bridge).deleteDraft('topic_42', 3);

      expect(result.success).assertFalse();
      expect(result.error?.message).assertEqual('Linux.do 未确认草稿已删除。');
    });

    it('publishesDraftDeletionToCurrentSubscribersOnly', 0, () => {
      let receivedKey: string = '';
      const unsubscribe: () => void = DraftEventBus.subscribeDeleted((draftKey: string) => {
        receivedKey = draftKey;
      });

      DraftEventBus.notifyDeleted('topic_42');
      expect(receivedKey).assertEqual('topic_42');

      unsubscribe();
      DraftEventBus.notifyDeleted('topic_43');
      expect(receivedKey).assertEqual('topic_42');
    });
  });
}
