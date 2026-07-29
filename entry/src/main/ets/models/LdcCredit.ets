// credit.linux.do(LINUX DO Credit)的数据模型。
//
// 金额字段一律保留**字符串**:接口返回的就是字符串型数字("1395.01"、"16"),服务端这么做正是
// 为了避开浮点误差。这里不做 Number() 转换,展示时直接用字符串——一旦转成 number,1395.01 这类
// 值会在往返中产生尾差,金额显示错一分钱都是 bug。需要比较大小的地方(如画柱状条)才临时取数值。

export interface LdcUserInfo {
  username: string;
  nickname: string;
  trustLevel: number;
  // 可用余额:个人中心入口行展示的就是它。
  availableBalance: string;
  communityBalance: string;
  pendingBalance: string;
  remainQuota: string;
  dailyLimit: string;
  totalReceive: string;
  totalPayment: string;
}

// 单日收支。date 形如 2026-07-29,income/expense 同为字符串型数字。
export interface LdcDailyStat {
  date: string;
  income: string;
  expense: string;
}
