#!/bin/sh
# Writed by yijian on 2020/8/26
# 停止监控在指定端口的 redis-server 进程
# 执行依赖 netstat 和 awk 两个命令
#
# 带一个参数：
# 1）参数1：redis-server 的监听端口号

# 使用帮助函数
function usage()
{
  echo "Stop redis-server process listen on the given port."
  echo "Usage: `basename $0` redis-port"
  echo "Example: `basename $0` 6379"
}

# 参数检查
if test $# -ne 1; then
  usage
  exit 1
fi

# 参数指定的 redis-server 监听端口
REDIS_PORT=$1

# 取得 redis-server 进程ID
# 命令 ps 输出的时间格式有两种：“7月17”和“20:42”，所以端口所在字段有区别：
pid=`ps -f -C redis-server | awk -v port=$REDIS_PORT -F'[ :]*' '{ if ($12==port || $13==port) print $2 }'`
if test -z "$pid"; then
  echo "redis-server[$REDIS_PORT] is not running"
else
  # 检查 $pid 是否为数字值，
  # 它可能是“12 34”这样的值，即包含了两个 pid。
  $(expr $pid + 0 > /dev/null 2>&1)
  if test $? -ne 0; then
    echo "Can not kill: \"$pid\""
  else
    if test "$pid" -eq 0; then
      echo "redis-server[$REDIS_PORT]'s pid is 0"
    else
      echo "kill $pid (redis-server[$REDIS_PORT])"
      #kill -0 $pid
      kill $pid
    fi
  fi
fi
