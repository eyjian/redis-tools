#!/bin/bash
# Writed by yijian on 2018/8/20
# Batch to clear all nodes using FLUSHALL command
# 用来清空一个redis集群中的所有数据，要求 FLUSHALL 命令可用，
# 如果在 redis.conf 中使用 rename 改名了 FLUSHALL，则不能执行本脚本。
REDIS_CLI=${REDIS_CLI:-redis-cli}
REDIS_IP=${REDIS_IP:-127.0.0.1}
REDIS_PORT=${REDIS_PORT:-6379}

function usage()
{
    echo "Usage: clear_redis_cluster.sh a_redis_node_of_cluster"    
    echo "Example: clear_redis_cluster.sh 127.0.0.1:6379"    
}

# with a parameter: single redis node
if test $# -ne 1; then    
    usage
    exit 1
fi

eval $(echo "$1" | awk -F[\:] '{ printf("REDIS_IP=%s\nREDIS_PORT=%s\n",$1,$2) }')
if test -z "$REDIS_IP" -o -z "$REDIS_PORT"; then
    echo "Parameter error: \`$1\`."
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

redis_nodes=`redis-cli -h $REDIS_IP -p $REDIS_PORT cluster nodes | awk -F[\ \:\@] '!/ERR/{ printf("%s:%s\n",$2,$3); }'`
if test -z "$redis_nodes"; then
    # Standlone（非集群）
    $REDIS_CLI -h $REDIS_IP -p $REDIS_PORT FLUSHALL
else
    # Cluster（集群）
    for redis_node in $redis_nodes;
    do
        if test ! -z "$redis_node"; then
            eval $(echo "$redis_node" | awk -F[\:] '{ printf("redis_node_ip=%s\nredis_node_port=%s\n",$1,$2) }')

            if test ! -z "$redis_node_ip" -a ! -z "$redis_node_port"; then
                # clear
                echo -e "Clearing \033[1;33m${redis_node_ip}:${redis_node_port}\033[m ..."
                result=`$REDIS_CLI -h $redis_node_ip -p $redis_node_port FLUSHALL`

                if test ! -z "$result"; then
                    # SUCCESS
                    if test "$result" = "OK"; then
                        echo -e "\033[0;32;32m$result\033[m"
                    else
                        echo -e "\033[0;32;31m$result\033[m"
                    fi
                fi
            fi
        fi
    done
fi
