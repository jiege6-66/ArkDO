import { describe, it, expect } from '@ohos/hypium';
import { User } from '../main/ets/models/User';
import { AuthService } from '../main/ets/services/auth/AuthService';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class FakeBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  // 接口占位:本套测试不触及图片上传,只为满足 JsonNetworkClient 而实现。
  uploadImage(base64: string, fileName: string, mimeType: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }
}

export default function authServiceTest() {
  describe('authServiceTest', () => {
    it('loadsCurrentUserFromDiscourseSessionPayload', 0, async () => {
      const payload: string = '{"current_user":{"id":7,"username":"linuxdo_user","name":"Linux.do User","avatar_template":"/user_avatar/linux.do/linuxdo_user/{size}/1_2.png"}}';
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(bridge.requestedPath).assertEqual('/session/current.json');
      expect(result.success).assertTrue();
      expect(result.data?.id).assertEqual(7);
      expect(result.data?.username).assertEqual('linuxdo_user');
      expect(result.data?.displayName).assertEqual('Linux.do User');
      expect(result.data?.avatarTemplate).assertEqual('/user_avatar/linux.do/linuxdo_user/{size}/1_2.png');
    });

    // 匿名会话的真实响应:Discourse 回 404 + 空 body(SessionController#current 的
    // render body: nil, status: 404),桥层据此判 success=false。这是「确认未登录」,
    // 必须被翻译成 success=true + data=undefined,否则上层按「检查失败」保留旧登录态,登出清不掉。
    it('returnsUndefinedWhenCurrentSessionIsAnonymous', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: false,
        statusCode: 404,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.UNEXPECTED_RESPONSE,
          message: 'Linux.do 返回 HTTP 404。',
          requiresChallenge: false
        }
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(bridge.requestedPath).assertEqual('/session/current.json');
      expect(result.success).assertTrue();
      expect(result.data).assertEqual(undefined);
    });

    // 带挑战态的 404 不是登出:CF 若用 404 壳子返回挑战页,必须继续走过盾链路而不是清登录态。
    it('keepsFailureWhenNotFoundCarriesChallenge', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: false,
        statusCode: 404,
        challengeState: ChallengeState.REQUIRED,
        error: {
          code: NetworkErrorCode.CHALLENGE_REQUIRED,
          message: 'Cloudflare challenge required.',
          requiresChallenge: true
        }
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(result.success).assertFalse();
      expect(result.challengeState).assertEqual(ChallengeState.REQUIRED);
    });

    // 纯网络失败(status=0)同样不是登出:上层据此保留上一次登录态,不能被误判成会话失效。
    it('keepsFailureForNetworkError', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: 'ArkWeb 请求失败。',
          requiresChallenge: false
        }
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual(NetworkErrorCode.NETWORK_FAILURE);
    });

    it('preservesChallengeRequiredResult', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: false,
        statusCode: 403,
        challengeState: ChallengeState.REQUIRED,
        error: {
          code: NetworkErrorCode.CHALLENGE_REQUIRED,
          message: 'Cloudflare challenge required.',
          requiresChallenge: true
        }
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(result.success).assertFalse();
      expect(result.statusCode).assertEqual(403);
      expect(result.challengeState).assertEqual(ChallengeState.REQUIRED);
      expect(result.error?.requiresChallenge).assertTrue();
    });

    it('returnsUnexpectedResponseForInvalidCurrentUserPayload', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: '{"current_user":{"id":"7","username":"linuxdo_user"}}'
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual(NetworkErrorCode.UNEXPECTED_RESPONSE);
    });
  });
}
