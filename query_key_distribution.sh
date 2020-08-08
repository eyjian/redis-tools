#!/bin/sh
# Writed by yijian on 2020/8/8
# 查询key的分布信息
# 可带5个参数：
# 1）被查询key的前缀
# 2）被查询key的数量
# 3）目标redis的ip
# 4）目标redis的端口号
# 5）目标redis的访问密码，可选参数

# 确保redis-cli可用
REDIS_CLI=${REDIS_CLI:-redis-cli}
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -ne 0; then
    echo "\`redis-cli\` not exists or not executable"
    exit 1
fi

# 参数检查
if test $# -ne 4 -a $# -ne 5; then
  echo "Usage: `basename $0` key_prefix key_number redis_ip redis_port [redis_password]"
  echo "Example1: `basename $0` k: 10 127.0.0.1 6379"
  echo "Example2: `basename $0` k: 10 127.0.0.1 6379 password123456"
  exit 1
fi

KEY_PREFIX="$1"
KEY_NUMBER=$2
REDIS_IP=$3
REDIS_PORT=$4
REDIS_PASSOWRD="$5"

for ((i=0; i<$KEY_NUMBER; ++i))
do
  key="${KEY_PREFIX}${i}"
  slot=`$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" -h $REDIS_IP -p $REDIS_PORT CLUSTER KEYSLOT "$key"`
  str=`$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" -h $REDIS_IP -p $REDIS_PORT GET "$key"`
  if test ! -z "$str"; then
    err=`echo "$str" | awk '{printf("%s",$1)}'`
  fi
  if test -z "$str" -o "$err" != "MOVED"; then
    echo -e "[${KEY_PREFIX}\033[1;33m${i}\033[m] slot=>\033[1;33m$slot\033[m node=>\033[1;33m$REDIS_IP:$REDIS_PORT\033[m"
  else
    node=`echo "$str" | awk '{printf("%s",$3)}'`
    echo -e "[${KEY_PREFIX}\033[1;33m${i}\033[m] slot=>\033[1;33m$slot\033[m node=>\033[1;33m$node\033[m"
  fi
done
