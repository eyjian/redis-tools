#!/bin/sh
# Writed by yijian on 2020/9/5
# 查看指定端口的 redis-server 进程的内存和CPU
# 执行依赖 top 和 awk 两个命令，
# 支持 mooon_ssh 远程批量执行。
#
# 带一个参数：
# 1）参数1：redis-server 的监听端口号

# 使用帮助函数
function usage()
{
  echo "Top redis-server process listen on the given port."
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

# top 命令可能位于不同目录下
TOP=/usr/bin/top
which $TOP > /dev/null 2>&1
if test $? -ne 0; then
  TOP=/bin/top
  which $TOP > /dev/null 2>&1
  if test $? -ne 0; then
    echo "\`top\` is not exists or is not executable."
    exit 1
  fi
fi

# 取得 redis-server 进程ID
# 命令 ps 输出的时间格式有两种：“7月17”和“20:42”，所以端口所在字段有区别：
pid=`ps -f -C redis-server | awk -v port=$REDIS_PORT -F'[ :]*' '{ if ($12==port || $13==port) print $2 }'`

# 执行 top 之前需要设置好环境变量“TERM”，否则执行将报如下错：
# TERM environment variable not set.
export TERM=xterm

# 各列
echo "PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND"

# 后台方式执行命令 top 时，
# 需要加上参数“-b”（非交互模式），不然报错“top: failed tty get”
$TOP -b -p $pid -n 1 | grep redis-serv+
