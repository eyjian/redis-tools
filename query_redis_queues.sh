#!/bin/bash
# Writed by yijian on 2021/5/12
# 查看一个或多个 redis 队列长度工具
# 可选带一个参数：
# redis 队列配置文件，如果不指定则默认为当前目录下的 redis.queues 文件。
#
# redis.queues 文件的每一行格式要求为：
# IP|port|password|prefix/num
# 其中 password 为访问 redis 的密码，值可以为空，
# prefix 为队列前缀，num 为队列个数。
#
# 输出结果：
# 最后一个值为队列中元素个数，前面的值为各子队列中的元素个数。
FILEPATH="$(readlink -f $0)"
BASEDIR="$(dirname $FILEPATH)" # 本脚本文件所在目录
interval_seconds=2 # 统计间隔（单位：秒）

# 检查 redis-cli 是否可用
# 依赖redis的命令行工具redis-cli
# 一般建议将redis-cli放在/usr/local/bin目录下
REDIS_CLI=""
if test -x /usr/local/bin/redis-cli; then
  REDIS_CLI=/usr/local/bin/redis-cli
else
  REDIS_CLI=redis-cli
fi
which $REDIS_CLI >/dev/null 1>&1
if test $? -ne 0; then
  echo "\`redis-cli\` is not exists or not executable."
  echo "You can copy \`redis-cli\` to the directory \`/usr/local/bin\`."
  exit 1
fi

# 检查队列文件是否存在
queues_file=redis.queues
if test ! -f $queues_file; then
  echo "\`$queues_file\` is not exists"
  exit 1
fi

while true
do
  sleep $interval_seconds

  # line 的格式：
  # IP:PORT|password|prefix/num
  while read line
  do
    if test -z $line; then
      break
    fi

    queue_load=0
    eval $(echo "$line"|awk -F[\|/] '{printf("ip=%s\nport=%s\npassword=%s\nprefix=%s\nnum=%s\n",$1,$2,$3,$4,$5);}')
    echo -en "[`date +'%Y-%m-%d %H:%M:%S'`][\033[1;33m$prefix\033[m/$num]"
    for ((i=0;i<$num;++i))
    do
      if test -z "$password"; then
        sub_queue_load=`$REDIS_CLI -h $ip -p $port LLEN "$prefix:$i"`
      else
        sub_queue_load=`$REDIS_CLI --no-auth-warning -a "$password" -h $ip -p $port LLEN "$prefix:$i"`
      fi
      queue_load=$(($queue_load + $sub_queue_load))
      echo -n " $sub_queue_load"
    done
    echo -e " \033[1;33m$queue_load\033[m"
  done < $queues_file
  echo ""
done
