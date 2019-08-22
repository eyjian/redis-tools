#!/bin/bash
# Writed by yijian on 2018/8/20
# Batch to check all nodes using SCAN command
# 检查redis集中是否正常工具
REDIS_CLI=${REDIS_CLI:-redis-cli}
REDIS_IP=${REDIS_IP:-127.0.0.1}
REDIS_PORT=${REDIS_PORT:-6379}

# 显示用法函数
function usage()
{
    echo "Usage: check_redis_cluster.sh a_redis_node_of_cluster redis_password"
    echo "Example1: check_redis_cluster.sh '127.0.0.1:6379'"
    echo "Example2: check_redis_cluster.sh '127.0.0.1:6379' '123456'"
}

# 检查参数个数
if test $# -lt 1 -o $# -gt 2; then
    usage
    exit 1
fi

# 第一个参数为集群中的节点，
REDIS_NODE="$1"
# 第二个参数为密码
REDIS_PASSWORD=""
if test $# -ge 2; then
    REDIS_PASSWORD="$2"
fi

# 取得IP和端口
eval $(echo "$1" | awk -F[\:] '{ printf("REDIS_IP=%s\nREDIS_PORT=%s\n",$1,$2) }')
if test -z "$REDIS_IP" -o -z "$REDIS_PORT"; then
    echo "Parameter error: \`$REDIS_NODE\`."
    usage
    exit 1
fi

# 确保redis-cli可用
echo "Checking \`redis-cli\` ..."
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -ne 0; then
    echo "Command \`redis-cli\` is not exists or not executable."
    echo "You can set environment variable \`REDIS_CLI\` to point to the redis-cli."
    echo "Example: export REDIS_CLI=/usr/local/bin/redis-cli"
    exit 1
fi

if test -z "$REDIS_PASSWORD"; then
    redis_nodes=`redis-cli -h $REDIS_IP -p $REDIS_PORT cluster nodes | awk -F[\ \:\@] '!/ERR/{ printf("%s:%s\n",$2,$3); }'`
else
    redis_nodes=`redis-cli --no-auth-warning -a "$REDIS_PASSWORD" -h $REDIS_IP -p $REDIS_PORT cluster nodes | awk -F[\ \:\@] '!/ERR/{ printf("%s:%s\n",$2,$3); }'`
fi
if test -z "$redis_nodes"; then
    # Standlone（非集群）
    if test -z "$REDIS_PASSWORD"; then
        $REDIS_CLI -h $REDIS_IP -p $REDIS_PORT SCAN 0 COUNT 20
    else
        $REDIS_CLI --no-auth-warning -a "$REDIS_PASSWORD" -h $REDIS_IP -p $REDIS_PORT SCAN 0 COUNT 20
    fi
else
    # Cluster（集群）
    for redis_node in $redis_nodes;
    do
        if test ! -z "$redis_node"; then
            eval $(echo "$redis_node" | awk -F[\:] '{ printf("redis_node_ip=%s\nredis_node_port=%s\n",$1,$2) }')

            if test ! -z "$redis_node_ip" -a ! -z "$redis_node_port"; then
                echo -e "Checking \033[1;33m${redis_node_ip}:${redis_node_port}\033[m ..."
                if test -z "$REDIS_PASSWORD"; then
                    $REDIS_CLI -h $redis_node_ip -p $redis_node_port SCAN 0 COUNT 10
                else
                    $REDIS_CLI --no-auth-warning -a "$REDIS_PASSWORD" -h $redis_node_ip -p $redis_node_port SCAN 0 COUNT 10
                fi
            fi
        fi
    done
fi
