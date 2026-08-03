// MessageBus long poll 必须完整地留在 ArkWeb 文档中运行。ArkTS 只接收轻量事件，
// 避免占用一次性 JSON 请求通道，也不受原生请求超时限制。
export function buildMessageBusScript(): string {
  return `(() => {
      // 注入即代表"要运行"：清掉可能残留的停止请求，让本次循环正常起跑。
      window.__arkdoMessageBusStopRequested = false;
      // 详情页等临时频道：持久集合(跨同文档内的循环重启存活) + 运行时增删入口。
      // ArkTS 侧经桥调用这两个函数动态订阅/退订 /topic/<id>。定义在 start 外，每次注入都(重)定义。
      window.__arkdoMessageBusChannels = window.__arkdoMessageBusChannels || {};
      window.__arkdoMessageBusAddChannel = (name, position) => {
        const pos = (typeof position === 'number') ? position : -1;
        // 已存在则不覆盖游标：避免重订阅(循环重启补订)把已推进的游标重置回起点。
        if (!Object.prototype.hasOwnProperty.call(window.__arkdoMessageBusChannels, name)) {
          window.__arkdoMessageBusChannels[name] = pos;
        }
        const active = window.__arkdoMessageBusActiveState;
        if (active && !Object.prototype.hasOwnProperty.call(active.channels, name)) {
          active.channels[name] = window.__arkdoMessageBusChannels[name];
        }
      };
      window.__arkdoMessageBusRemoveChannel = (name) => {
        delete window.__arkdoMessageBusChannels[name];
        const active = window.__arkdoMessageBusActiveState;
        if (active) {
          delete active.channels[name];
        }
      };
      const emit = (event) => {
        try {
          window.ArkDOBridge.onBusEvent(JSON.stringify(event));
        } catch (_) {
        }
      };
      const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      const uniqueId = () => 'xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx'.replace(/[xy]/g, (char) => {
        const random = (Math.random() * 16) | 0;
        const value = char === 'x' ? random : (random & 0x3) | 0x8;
        return value.toString(16);
      });
      const findLongPollingBaseUrl = (value, depth) => {
        if (value === null || value === undefined || depth > 8) {
          return '';
        }
        if (typeof value === 'string') {
          if (!value.includes('long_polling_base_url')) {
            return '';
          }
          try {
            return findLongPollingBaseUrl(JSON.parse(value), depth + 1);
          } catch (_) {
            return '';
          }
        }
        if (Array.isArray(value)) {
          for (const item of value) {
            const found = findLongPollingBaseUrl(item, depth + 1);
            if (found) {
              return found;
            }
          }
          return '';
        }
        if (typeof value === 'object') {
          if (typeof value.long_polling_base_url === 'string') {
            return value.long_polling_base_url;
          }
          for (const key of Object.keys(value)) {
            const found = findLongPollingBaseUrl(value[key], depth + 1);
            if (found) {
              return found;
            }
          }
        }
        return '';
      };
      const resolvePollBaseUrl = async () => {
        const fallback = new URL('/', window.location.origin).toString();
        const fallbackConfig = {
          baseUrl: fallback,
          sharedSessionKey: '',
          currentUserId: 0,
          source: 'fallback'
        };
        try {
          const response = await fetch(fallback, {
            credentials: 'include',
            cache: 'no-store',
            headers: {
              'Accept': 'text/html',
              'X-Requested-With': 'XMLHttpRequest'
            }
          });
          if (!response.ok) {
            fallbackConfig.source = 'http-' + response.status;
            return fallbackConfig;
          }
          const html = await response.text();
          const documentRoot = new DOMParser().parseFromString(html, 'text/html');
          const preload = documentRoot.querySelector('#data-preloaded');
          const rawPreloaded = preload
            ? (preload.textContent || preload.getAttribute('data-preloaded') || '')
            : '';
          if (!rawPreloaded) {
            fallbackConfig.source = 'preload-missing';
            return fallbackConfig;
          }
          const preloaded = JSON.parse(rawPreloaded);
          // 登录用户 id：用于订阅 /notification/<id>。preloaded.currentUser 与 siteSettings 一样
          // 可能是字符串化 JSON，两种形态都兼容；解析失败/未登录则保持 0（不订阅通知频道）。
          let currentUserId = 0;
          try {
            const currentUser = typeof preloaded.currentUser === 'string'
              ? JSON.parse(preloaded.currentUser)
              : preloaded.currentUser;
            if (currentUser && typeof currentUser.id === 'number') {
              currentUserId = currentUser.id;
            }
          } catch (_) {
          }
          const siteSettings = typeof preloaded.siteSettings === 'string'
            ? JSON.parse(preloaded.siteSettings)
            : preloaded.siteSettings;
          const configured = siteSettings && typeof siteSettings.long_polling_base_url === 'string'
            ? siteSettings.long_polling_base_url
            : findLongPollingBaseUrl(preloaded, 0);
          if (!configured) {
            fallbackConfig.currentUserId = currentUserId;
            fallbackConfig.source = 'setting-missing';
            return fallbackConfig;
          }
          const resolved = new URL(configured, fallback).toString();
          const sharedSessionMeta = documentRoot.querySelector('meta[name=shared_session_key]');
          return {
            baseUrl: resolved.endsWith('/') ? resolved : resolved + '/',
            sharedSessionKey: sharedSessionMeta ? (sharedSessionMeta.getAttribute('content') || '') : '',
            currentUserId: currentUserId,
            source: 'site-settings'
          };
        } catch (_) {
          fallbackConfig.source = 'parse-error';
          return fallbackConfig;
        }
      };
      const start = async () => {
        // 覆盖 challenge 后 setTimeout(start,30000) 的延迟重启：期间被请求停止则不再起跑。
        if (window.__arkdoMessageBusStopRequested) {
          return;
        }
        if (window.__arkdoMessageBusStarted) {
          return;
        }
        window.__arkdoMessageBusStarted = true;
        // 本次循环的代次：stop 与新的 start 都会 bump 全局代次，旧循环据此在下一轮自然退出。
        // 防止快速「关→开」时旧循环(仍在 await 中)因停止标志被重置而复活，造成双开。
        const generation = (window.__arkdoMessageBusGeneration || 0) + 1;
        window.__arkdoMessageBusGeneration = generation;
        const state = {
          clientId: uniqueId(),
          baseUrl: '',
          sharedSessionKey: '',
          // 两个常驻频道,首页的实时提示按当前排序二选一(见 HomePage.incomingTopicsChannel):
          //  · /latest 新建 + 被回复顶起来的,配「最新」(bumped_at 排序)
          //  · /new    只有新建(publish_new),配「最新发布」(created_at 排序)
          // /new 不做成按需订阅:它得跟着首页排序增删,而首页一卸载(进详情页)就会退订,回来又没人补订,
          // 提示条从此不涨。常驻的代价只是 poll body 多一个键 —— /new 比 /latest 安静一个数量级。
          channels: { '/latest': -1, '/new': -1 },
          seq: 0,
          running: true,
          retryDelayMs: 1000
        };
        emit({ type: 'status', stage: 'started', message: 'message bus loop started' });
        const pollConfig = await resolvePollBaseUrl();
        state.baseUrl = pollConfig.baseUrl;
        state.sharedSessionKey = pollConfig.sharedSessionKey;
        // 已登录才订阅通知频道；游标 -1=只收新消息（旧通知无需回放，权威计数由 ArkTS 侧 refresh 兜底）。
        if (pollConfig.currentUserId > 0) {
          state.channels['/notification/' + pollConfig.currentUserId] = -1;
        }
        // 并入详情页等动态订阅的持久频道（循环重启后仍生效）；再暴露 state 供运行时增删。
        const extraChannels = window.__arkdoMessageBusChannels || {};
        Object.keys(extraChannels).forEach((name) => {
          state.channels[name] = extraChannels[name];
        });
        window.__arkdoMessageBusActiveState = state;
        emit({
          type: 'status',
          stage: 'config-ready',
          message: state.baseUrl + ' source=' + pollConfig.source +
            ' sharedSessionKey=' + String(Boolean(state.sharedSessionKey)) +
            ' userId=' + String(pollConfig.currentUserId) +
            // 本次循环真正要 poll 的频道全集(常驻 + 动态并入的)。查「某频道收不到消息」时先看这行:
            // 它没在里面 = 客户端压根没订;在里面却没有对应的 cursor-ready = 服务端不认这个频道。
            ' channels=' + Object.keys(state.channels).join(',')
        });
        const backoff = async () => {
          const waitMs = state.retryDelayMs;
          state.retryDelayMs = Math.min(state.retryDelayMs * 2, 30000);
          await delay(waitMs);
        };
        const stopForChallenge = (event) => {
          emit(event);
          state.running = false;
          window.__arkdoMessageBusStarted = false;
          setTimeout(start, 30000);
        };

        const poll = async () => {
          while (state.running && !window.__arkdoMessageBusStopRequested &&
            generation === window.__arkdoMessageBusGeneration) {
            const body = new URLSearchParams();
            Object.keys(state.channels).forEach((channel) => {
              body.append(channel, String(state.channels[channel]));
            });
            body.append('__seq', String(++state.seq));

            try {
              const headers = {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-Requested-With': 'XMLHttpRequest',
                'X-SILENCE-LOGGER': 'true',
                'Dont-Chunk': 'true'
              };
              if (state.sharedSessionKey && new URL(state.baseUrl).origin !== window.location.origin) {
                headers['X-Shared-Session-Key'] = state.sharedSessionKey;
              }
              const response = await fetch(
                new URL('message-bus/' + encodeURIComponent(state.clientId) + '/poll', state.baseUrl).toString(),
                {
                  method: 'POST',
                  credentials: 'include',
                  cache: 'no-store',
                  headers: headers,
                  body: body.toString()
                }
              );
              const responseText = await response.text();
              if (response.status === 403 || response.status === 429) {
                stopForChallenge({ type: 'challenge', statusCode: response.status, message: 'message bus blocked' });
                return;
              }

              let messages;
              try {
                messages = JSON.parse(responseText);
              } catch (_) {
                const contentType = response.headers ? (response.headers.get('content-type') || '') : '';
                const lowerBody = responseText.toLowerCase();
                const looksLikeChallenge = response.status === 403 || response.status === 429 ||
                  contentType.includes('text/html') || lowerBody.includes('cf-chl') ||
                  lowerBody.includes('just a moment');
                if (looksLikeChallenge) {
                  stopForChallenge({
                    type: 'challenge',
                    statusCode: response.status,
                    message: 'message bus returned challenge html'
                  });
                  return;
                }
                emit({
                  type: 'error',
                  stage: 'poll-response',
                  statusCode: response.status,
                  message: 'message bus returned non-json'
                });
                await backoff();
                continue;
              }
              if (!response.ok || !Array.isArray(messages)) {
                emit({ type: 'error', statusCode: response.status, message: 'message bus poll failed' });
                await backoff();
                continue;
              }

              state.retryDelayMs = 1000;
              for (const message of messages) {
                if (!message || typeof message.channel !== 'string') {
                  continue;
                }
                if (message.channel === '/__status' && message.data && typeof message.data === 'object') {
                  Object.keys(state.channels).forEach((channel) => {
                    if (typeof message.data[channel] === 'number') {
                      state.channels[channel] = message.data[channel];
                      emit({
                        type: 'status',
                        stage: 'cursor-ready',
                        channel: channel,
                        messageId: message.data[channel],
                        message: 'message bus cursor initialized'
                      });
                    }
                  });
                  continue;
                }
                if (typeof message.message_id !== 'number') {
                  continue;
                }
                if (Object.prototype.hasOwnProperty.call(state.channels, message.channel)) {
                  state.channels[message.channel] = message.message_id;
                  // 持久集合里的动态频道游标同步推进，循环重启后从最新位置续订，避免重放或漏收。
                  if (window.__arkdoMessageBusChannels &&
                    Object.prototype.hasOwnProperty.call(window.__arkdoMessageBusChannels, message.channel)) {
                    window.__arkdoMessageBusChannels[message.channel] = message.message_id;
                  }
                }
                emit({
                  type: 'message',
                  channel: message.channel,
                  messageId: message.message_id,
                  data: message.data
                });
              }
            } catch (error) {
              emit({ type: 'error', statusCode: 0, message: String(error) });
              await backoff();
            }
          }
          // 退出循环时复位启动标志，允许重新起跑；但仅当自己仍是最新代次——被更新的循环取代时
          // 不能清掉接替者的运行标志，也不能清掉接替者暴露的 activeState。
          if (generation === window.__arkdoMessageBusGeneration) {
            window.__arkdoMessageBusStarted = false;
            window.__arkdoMessageBusActiveState = undefined;
          }
        };

        poll();
      };

      start();
      return 'started';
    })();`;
}
