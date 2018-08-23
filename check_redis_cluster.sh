#!/bin/bash
# Writed by yijian on 2018/8/20
# Batch to check all nodes using SCAN command

REDIS_CLI=${REDIS_CLI:-redis-cli}
REDIS_IP=${REDIS_IP:-127.0.0.1}
REDIS_PORT=${REDIS_PORT:-6379}

function usage()
{
    echo "usage: check_redis_cluster.sh redis_node"    
    echo "example: check_redis_cluster.sh 127.0.0.1:6379"    
}

# with a parameter: single redis node
if test $# -ne 1; then
    usage    
    exit 1
fi

eval $(echo "$1" | awk -F[\:] '{ printf("REDIS_IP=%s\nREDIS_PORT=%s\n",$1,$2) }')
if test -z "$REDIS_IP" -o -z "$REDIS_PORT"; then
    echo "parameter error"
    usage
    exit 1
fi

# 确保redis-cli可用
echo "checking \`$REDIS_CLI\` ..."
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -ne 0; then
    echo "\`redis-cli\` not exists or not executable"
    exit 1
fi

redis_nodes=`redis-cli -h $REDIS_IP -p $REDIS_PORT cluster nodes | awk -F[\ \:\@] '!/ERR/{ printf("%s:%s\n",$2,$3); }'`
if test -z "$redis_nodes"; then
    # standlone
    $REDIS_CLI -h $REDIS_IP -p $REDIS_PORT SCAN 0 COUNT 1
else
    # cluster
    for redis_node in $redis_nodes;
    do
        if test ! -z "$redis_node"; then
            eval $(echo "$redis_node" | awk -F[\:] '{ printf("redis_node_ip=%s\nredis_node_port=%s\n",$1,$2) }')

            if test ! -z "$redis_node_ip" -a ! -z "$redis_node_port"; then
                echo -e "checking \033[1;33m${redis_node_ip}:${redis_node_port}\033[m ..."
                $REDIS_CLI -h $redis_node_ip -p $redis_node_port SCAN 0 COUNT 1                
            fi
        fi
    done
fi
