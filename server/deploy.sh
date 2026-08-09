#!/usr/bin/env bash
# 把仓库里的 relay.py 部署到中继服务器。
#
# 以仓库为准:改中继请改本文件同目录的 relay.py 并提交,再用本脚本部署。
# 别直接改服务器上的副本——那样仓库和线上很快就对不上了。
#
# 用法: ./deploy.sh <ssh-host>            部署并重启
#       ./deploy.sh <ssh-host> --dry      只比对差异,不改动
set -euo pipefail

HOST="${1:-}"
DRY="${2:-}"
REMOTE_DIR="/opt/wp-relay"
LOCAL_PY="$(cd "$(dirname "$0")" && pwd)/relay.py"

if [ -z "$HOST" ]; then
  echo "用法: $0 <ssh-host> [--dry]" >&2
  exit 1
fi

[ -f "$LOCAL_PY" ] || { echo "找不到 $LOCAL_PY" >&2; exit 1; }

# 本地先过一遍语法,别把语法错误推上去导致服务起不来。
python3 -c "import py_compile; py_compile.compile('$LOCAL_PY', doraise=True)"
echo "✓ 本地语法检查通过"

# 先确认连得上,且线上文件确实存在。
# 原先这里是 `ssh ... cat ... 2>/dev/null | diff`,SSH 的错误被吞掉:连不上时 cat 输出为空,
# diff 就把整个文件报成"新增",看起来像首次部署——而实际是压根没连上。那种误判很危险
# (会让人以为线上是空的而直接确认部署),所以连接与存在性都要显式检查、失败即退出。
if ! ssh -n -o ConnectTimeout=10 "$HOST" "test -f $REMOTE_DIR/relay.py"; then
  echo "✗ 连不上 $HOST,或 $REMOTE_DIR/relay.py 不存在。" >&2
  echo "  连接问题请先单独试 ssh $HOST;确属首次部署请手工创建 $REMOTE_DIR 后再跑本脚本。" >&2
  exit 1
fi

echo "── 与线上的差异 ──"
if ssh -n "$HOST" "cat $REMOTE_DIR/relay.py" | diff -u - "$LOCAL_PY"; then
  echo "(无差异)"
  [ "$DRY" = "--dry" ] && exit 0
fi

if [ "$DRY" = "--dry" ]; then
  echo "--dry:仅比对,未改动。"
  exit 0
fi

# 上面的 ssh 一律带 -n:ssh 默认会读走 stdin 转发给远端命令,那样这里的 read 会直接拿到
# EOF,表现成"没确认就退出"(用管道喂 y 时尤其明显)。
read -r -p "确认部署到 $HOST ? [y/N] " ok
[ "$ok" = "y" ] || { echo "已取消"; exit 0; }

# 先备份线上版本,出问题能立刻回滚。
ssh -n "$HOST" "sudo cp $REMOTE_DIR/relay.py $REMOTE_DIR/relay.py.bak.\$(date +%Y%m%d_%H%M%S)"
scp "$LOCAL_PY" "$HOST:/tmp/relay-new.py"
ssh -n "$HOST" "sudo mv /tmp/relay-new.py $REMOTE_DIR/relay.py \
  && sudo chmod 644 $REMOTE_DIR/relay.py \
  && python3 -c \"import py_compile; py_compile.compile('$REMOTE_DIR/relay.py', doraise=True)\" \
  && sudo systemctl restart wp-relay"

sleep 2
echo "── 部署结果 ──"
ssh -n "$HOST" "systemctl is-active wp-relay && sudo journalctl -u wp-relay -n 3 --no-pager"
echo "✓ 完成。健康检查请访问 <RELAY_PUBLIC_BASE>/wp/health"
