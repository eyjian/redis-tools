#!/bin/sh
# Writed by yijian on 2021/7/21
# 将一个大 key 分解成小 keys 时，
# 用于计算出均衡分布的小 keys 取值。
#
# 带2个参数：
# 第1个参数为REdis的节点字符串，
# 第2个参数可选，为连接REdis的密码。
# 使用前，需要先修改 KEY 的值，以及 NUM_KEYS 的值。
REDIS_CLI=/usr/local/bin/redis-cli
NUM_KEYS=10 # 目标 keys 的数量，可考虑为集群的主节点整数倍

function usage()
{
    echo "Usage: `basename $0` redis_node [redis-password]"
    echo "Example1: `basename $0` 127.0.0.1:6379"
    echo "Example2: `basename $0` 127.0.0.1:6379 redis-password"
}

# with a parameter: single redis node
if test $# -ne 1 -a $# -ne 2; then
    usage
    exit 1
fi

# 检查参数
eval $(echo "$1" | awk -F[\:] '{ printf("REDIS_IP=%s\nREDIS_PORT=%s\n",$1,$2) }')
if test -z "$REDIS_IP" -o -z "$REDIS_PORT"; then
    echo "Parameter error"
    usage
    exit 1
fi

# 确保redis-cli可用
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -ne 0; then
    echo -e "\`redis-cli\` not exists or not executable"
    exit 1
fi

# 根据 keys 的数量计算出 slots 的分布
NUM_SLOTS=16384
STEP=$(($NUM_SLOTS / $NUM_KEYS))
declare -A slots_table # 存储 slots 分布表
for ((i=0;i<$NUM_SLOTS;i+=$STEP))
do
  slot=$(($i+99)) # 加 99 大体上跳过相邻边界值
  slots_table[$slot]="2021"
  if test ${#slots_table[@]} -eq $NUM_KEYS; then
    break
  fi
done
index=0
for slot in ${!slots_table[*]}; do
  echo -e "[$index] \033[1;33m$slot\033[m"
  index=$(($index+1))
done
echo ""

index=0
CURRENT_KEYS=0 # 已取得的 keys 数
echo "Available keys:"
for ((i=0;;++i))
do
  KEY="k:$i"
  if test $# -eq 1; then
    slot=`$REDIS_CLI -h $REDIS_IP -p $REDIS_PORT CLUSTER KEYSLOT "$KEY"`
  else
    slot=`$REDIS_CLI --no-auth-warning -a "$2" -h $REDIS_IP -p $REDIS_PORT CLUSTER KEYSLOT "$KEY"`
  fi
  v="${slots_table[$slot]}"
  if test "X$v" == "X2021"; then
    echo -e "[$index] \033[1;33m$KEY\033[m => $slot"

    slots_table[$slot]="0"
    CURRENT_KEYS=$(($CURRENT_KEYS+1))
    index=$(($index+1))
    if test $CURRENT_KEYS -eq $NUM_KEYS; then
      break
    fi
  fi
done
