// LDC 金额与日期的展示格式化。
//
// 金额一律以字符串进出:credit 的接口返回的就是字符串型数字("1395.01"),转成 number 再转回来
// 会引入浮点尾差,金额差一分钱就是 bug。故这里只做**字符串层面**的修剪(去掉无意义的尾随零),
// 不做任何数值运算。需要比大小/画柱状条时才用 ldcAmountValue 临时取数值。

// 展示用金额:'1395.01' → '1395.01','16' → '16','16.00' → '16','0.50' → '0.5'。
// 非数字形状(接口异常)原样返回,不猜、不吞——让异常在界面上可见好过显示一个假的 0。
export function formatLdcAmount(amount: string): string {
  const trimmed: string = amount.trim();
  if (trimmed.length === 0) {
    return '0';
  }
  const dotIndex: number = trimmed.indexOf('.');
  if (dotIndex < 0) {
    return trimmed;
  }
  let end: number = trimmed.length;
  while (end > dotIndex && trimmed.charAt(end - 1) === '0') {
    end--;
  }
  if (end - 1 === dotIndex) {
    end = dotIndex;
  }
  return trimmed.substring(0, end);
}

// 金额的数值形式,仅用于比较/画图等派生用途。非数字返回 0。
export function ldcAmountValue(amount: string): number {
  const value: number = Number(amount);
  return Number.isFinite(value) ? value : 0;
}

// 日期标签:'2026-07-29' → '07-29'。接口给的是本地日期串,不做时区换算(换算反而会串行)。
export function ldcDayLabel(date: string): string {
  const parts: string[] = date.split('-');
  if (parts.length < 3) {
    return date;
  }
  return `${parts[1]}-${parts[2]}`;
}
