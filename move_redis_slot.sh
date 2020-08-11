#!/bin/sh
# Writed by yijian on 2020/8/10
# 迁移 slot 工具，一次只能迁移一个
#
# 使用时，需要指定如下几个参数：
# 1）参数1：必选参数，用于指定被迁移的 slot
# 2）参数2：必选参数，用于指定源节点（格式为：ip:port）
# 3）参数3：必选参数，用于指定目标节点（格式为：ip:port）
# 6）参数4：可选参数，用于指定访问 redis 的密码

# 确保redis-cli可用
REDIS_CLI=${REDIS_CLI:-redis-cli}
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -ne 0; then
    echo "\`redis-cli\` not exists or not executable"
    exit 1
fi

# 参数检查
if test $# -ne 3 -a $# -ne 4; then
  echo -e "Usage: `basename $0` \033[1;33mslot\033[m source_node destition_node redis_password"
  echo -e "Example1: `basename $0` \033[1;33m2020\033[m 127.0.0.1:6379 127.0.0.1:6380"
  echo -e "Example2: `basename $0` \033[1;33m2020\033[m 127.0.0.1:6379 127.0.0.1:6380 password123456"
  exit 1
fi

SLOT=$1
SRC_NODE="$2"
DEST_NODE="$3"
REDIS_PASSOWRD="$4"

# 得到指定节点的 nodeid
function get_node_id()
{
  node="$1"
  node_ip="`echo $node|cut -d':' -f1`"
  node_port=`echo $node|cut -d':' -f2`

  # 得到对应的 nodeid
  $REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" \
-h $node_ip -p $node_port \
CLUSTER NODES | awk -v node=$node '{if ($2==node) printf("%s",$1);}'
}

SRC_NODE_ID="`get_node_id $SRC_NODE`"
SRC_NODE_IP="`echo $SRC_NODE|cut -d':' -f1`"
SRC_NODE_PORT=`echo $SRC_NODE|cut -d':' -f2`
DEST_NODE_ID="`get_node_id $DEST_NODE`"
DEST_NODE_IP="`echo $DEST_NODE|cut -d':' -f1`"
DEST_NODE_PORT=`echo $DEST_NODE|cut -d':' -f2`

echo -e "\033[1;33mSource\033[m node: $SRC_NODE_IP:$SRC_NODE_PORT"
echo -e "\033[1;33mDestition\033[m node: $DEST_NODE_IP:$DEST_NODE_PORT"
echo -en "Confirm to continue? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
read -r -p " " input
if test "$input" != "yes"; then
  exit 1
fi
echo "........."

# 目标节点上执行 IMPORTING 操作
# 如果 $SLOT 已在目标节点，则执行时报错“ERR I'm already the owner of hash slot 1987”
echo -e "\033[1;33mImporting\033[m $SLOT from $SRC_NODE to $DEST_NODE ..."
err=`$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" \
-h $DEST_NODE_IP -p $DEST_NODE_PORT \
CLUSTER SETSLOT $SLOT IMPORTING $SRC_NODE_ID`
if test "X$err" != "XOK"; then
  echo "[destition://$DEST_NODE_IP:$DEST_NODE_PORT] $err"
  exit 1
fi

# 源节点上执行 MIGRATING 操作
# 如果 $SLOT 并不在源节点上，则执行时报错“ERR I'm not the owner of hash slot 1987”
echo -e "\033[1;33mMigrating\033[m $SLOT from $SRC_NODE to $DEST_NODE ..."
err=`$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" \
-h $SRC_NODE_IP -p $SRC_NODE_PORT \
CLUSTER SETSLOT $SLOT MIGRATING $DEST_NODE_ID`
if test "X$err" != "XOK"; then
  echo "[source://$SRC_NODE_IP:$SRC_NODE_PORT] $err"
  exit 1
fi

# 是否迁移已有的keys？
echo -en "Migrate keys in slot://$SLOT? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
read -r -p " " input
if test "$input" = "yes"; then
  first=1 # 是否第一轮keys迁移操作
  batch=100 # 一次批量迁移的keys数
  timeout_ms=60000 # 超时时长（单位：毫秒）
  destination_db=0 # 对于redis集群，取值总是为0
  num_keys=0

  echo "........."
  echo -e "Migrating keys in slot://$SLOT ..."
  while true
  do
    # 在源节点上执行：
    # 借助命令“CLUSTER GETKEYSINSLOT”和命令“MIGRATE”迁移已有的keys
    keys="`$REDIS_CLI --raw --no-auth-warning -a '$REDIS_PASSOWRD' \
-h $SRC_NODE_IP -p $SRC_NODE_PORT \
CLUSTER GETKEYSINSLOT $SLOT $batch | tr '\n' ' ' | xargs`"
    if test -z "$keys"; then
      if test $first -eq 1; then
        echo -e "No any keys to migrate in slot://$SLOT"
      else
        echo -e "Finished migrating all keys ($num_keys) in slot://$SLOT"
      fi
      break
    fi
    first=0
    n=`echo "$keys" | tr -cd ' ' | wc -c`
    num_keys=$(($num_keys + $n))

    # 在源节点上执行命令“MIGRATE”迁移到目标节点
    # MIGRATE returns OK on success,
    # or NOKEY if no keys were found in the source instance
    if test -z "$REDIS_PASSOWRD"; then
      err=`$REDIS_CLI --raw \
-h $SRC_NODE_IP -p $SRC_NODE_PORT \
MIGRATE $DEST_NODE_IP $DEST_NODE_PORT "" $destination_db $timeout_ms \
REPLACE KEYS $keys`
    else
      err=`$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" \
-h $SRC_NODE_IP -p $SRC_NODE_PORT \
MIGRATE $DEST_NODE_IP $DEST_NODE_PORT "" $destination_db $timeout_ms \
REPLACE AUTH "$REDIS_PASSOWRD" KEYS $keys`
    fi
    if test "X$err" = "XNOKEY"; then
      break
    fi
  done
fi

# 在目标节点上执行 NODE 操作
echo -n "Node destition://$DEST_NODE_IP:$DEST_NODE_PORT: "
err=`$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" \
-h $DEST_NODE_IP -p $DEST_NODE_PORT \
CLUSTER SETSLOT $SLOT NODE $DEST_NODE_ID`
echo -e "\033[1;33m$err\033[m"

exit 0
# 在源节点上执行 NODE 操作
echo -n "Node source://$SRC_NODE_IP:$SRC_NODE_PORT: "
$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" -h $SRC_NODE_IP -p $SRC_NODE_PORT \
CLUSTER SETSLOT $SLOT NODE $DEST_NODE_ID

exit 0
# 取得所有 master 节点
nodes=(`$REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" -h $DEST_NODE_IP -p $DEST_NODE_PORT \
CLUSTER NODES | awk '{if (match($3,"master")) printf("%s\n",$2);}'`)

# 在所有 master 节点上执行 NODE 操作
for node in ${nodes[*]}; do
  node_ip="`echo $node|cut -d':' -f1`"
  node_port=`echo $node|cut -d':' -f2`
  echo -e "NODE: $node_ip:$node_port"
  $REDIS_CLI --raw --no-auth-warning -a "$REDIS_PASSOWRD" \
-h $node_ip -p $node_port \
CLUSTER SETSLOT $SLOT NODE $DEST_NODE_ID
done
