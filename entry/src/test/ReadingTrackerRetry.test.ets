import { describe, it, expect } from '@ohos/hypium';
import { ChallengeState, NetworkResult } from '../main/ets/services/network/NetworkTypes';
import { ReadingTracker } from '../main/ets/services/reading/ReadingTracker';

/**
 * 不可重试失败之后的重发节奏。
 *
 * 守的是这样一个回归:为了解开「记过账但从没上报成功」的死区(蓝点不消),把丢弃批次的
 * totalTimings 抹掉了 —— 但 totalTimings 里那条非零记录**同时还兼着节流闸**
 * (rush 的判定条件是 alreadyTotalled === 0)。只抹不压的话,下一个 tick 就会重新 rush,
 * 配合 5 秒的攒批间隔变成每 5 秒对着一个注定失败的端点打一次,而且用户只要停在这一页就不停。
 * /topics/timings 恰恰是代码里反复强调不能猛打的端点(会喂 CF 的速率盾)。
 *
 * 这条用例靠真实计时器跑,所以刻意只测「窗口内发了几次」这种粗粒度的事实,不测具体时刻。
 */
export default function readingTrackerRetryTest() {
  describe('ReadingTrackerRetry', () => {
    it('does not hammer the endpoint after a non-retryable failure', 0, (done: () => void) => {
      let calls: number = 0;
      // 404 不在 ALLOWED_AJAX_FAILURES 里 => 走「不可重试」分支。
      const reportFn = (): Promise<NetworkResult<string>> => {
        calls++;
        return Promise.resolve({
          success: false,
          statusCode: 404,
          challengeState: ChallengeState.NONE,
          error: undefined
        } as NetworkResult<string>);
      };

      const tracker: ReadingTracker = new ReadingTracker();
      tracker.start(1, reportFn, () => {});
      // 让楼层持续在屏并保持"刚滚动过",这正是回归场景:用户就停在这一页不动。
      tracker.setOnscreen([1, 2, 3]);
      const keepScrolling: number = setInterval(() => {
        tracker.scrolled();
        tracker.setOnscreen([1, 2, 3]);
      }, 500);

      // 时间线(tick 每 1s):
      //   t≈2s 首批发出(start 把 lastReportAt 拨到一个攒批周期之前,故第二个 tick 就 batchDue)
      //   → 404 落地 → 走不可重试分支
      //   t≈7s 若没有静默期,rush 会重新成立且 batchDue 又满足 → 第二发
      // 所以观察窗必须**越过 7s**。早先取 6s 的版本看着是绿的,其实是在第二发到来之前就收工了 ——
      // 把静默期那行删掉重跑仍然通过,等于什么都没测。取 10s 留出余量。
      setTimeout(() => {
        clearInterval(keepScrolling);
        // **先记账再 stop()**:stop 会走 drainRemaining,那是刻意「忽略 inProgress 与退避门闩、
        // 把队列里剩下的批次全发出去」的收尾语义(不这么做离页前的已读会丢),它必然多一次调用。
        // 把它算进来就变成在测收尾行为,而不是在测重发节奏了。
        const observed: number = calls;
        tracker.stop();
        // 断言放在 finally 之前但不让它吞掉 done:断言抛出的话本例会以「超时」而不是
        // 「断言失败」收场,排查时极易误判成框架问题。
        try {
          expect(observed).assertEqual(1);
        } finally {
          done();
        }
      }, 10000);
    });
  });
}
