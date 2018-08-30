#!/bin/bash
# Writed by yijian on 2018/8/24
#
# 检查Redis集群master和slave映射关系工具，
# 可用来查看是否多master出现在同一IP，
# 或一对master和slave出现在同一IP。
#
# 输出效果：
# [1] 192.168.1.21:6379   =>  192.168.1.27:6380
# [2] 192.168.1.22:6379   =>  192.168.1.26:6380
# [3] 192.168.1.23:6379   =>  192.168.1.29:6379
# [4] 192.168.1.24:6379   =>  192.168.1.25:6380
# [5] 192.168.1.25:6379   =>  192.168.1.24:6380
# [6] 192.168.1.26:6379   =>  192.168.1.22:6380
# [7] 192.168.1.27:6379   =>  192.168.1.21:6380
# [8] 192.168.1.28:6379   =>  192.168.1.23:6380
# [9] 192.168.1.29:6380   =>  192.168.1.28:6380

REDIS_CLI=${REDIS_CLI:-redis-cli}
REDIS_IP=${REDIS_IP:-127.0.0.1}
REDIS_PORT=${REDIS_PORT:-6379}

function usage()
{
    echo "usage: `basename $0` redis_node"
    echo "example: `basename $0` 127.0.0.1:6379"    
}

# with a parameter: single redis node
if test $# -ne 1; then
    usage    
    exit 1
fi

# 检查参数
eval $(echo "$1" | awk -F[\:] '{ printf("REDIS_IP=%s\nREDIS_PORT=%s\n",$1,$2) }')
if test -z "$REDIS_IP" -o -z "$REDIS_PORT"; then
    echo "parameter error"
    usage
    exit 1
fi

# 确保redis-cli可用
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -ne 0; then
    echo -e "\`redis-cli\` not exists or not executable"
    exit 1
fi

# master映射表，key为master的id，value为master的“ip:port”
declare -A master_map=()
# slave映表，key为master的id，value为slave的“ip:port”
declare -A slave_map=()
master_node_str=
master_slave_map_str=

# 找出所有master
masters=`$REDIS_CLI -h $REDIS_IP -p $REDIS_PORT CLUSTER NODES | awk -F[\ \@] '/master/{ printf("%s,%s\n",$1,$2); }' | sort`
for master in $masters;
do    
    eval $(echo $master | awk -F[,] '{ printf("master_id=%s\nmaster_node=%s\n",$1,$2); }')
    
    master_map[$master_id]=$master_node    
    if test -z "$master_node_str"; then
        master_node_str="$master_node"
    else
        master_node_str="$master_node,$master_node_str"
    fi
done

# 找出所有slave
slaves=`$REDIS_CLI -h $REDIS_IP -p $REDIS_PORT CLUSTER NODES | awk -F[\ \@] '/slave/{ printf("%s,%s\n",$5,$2); }' | sort`
for slave in $slaves;
do
    eval $(echo $slave | awk -F[,] '{ printf("master_id=%s\nslave_node=%s\n",$1,$2); }')
    slave_map[$master_id]=$slave_node
done

for key in ${!master_map[@]}
do
    master_node=${master_map[$key]}
    slave_node=${slave_map[$key]}

    if test -z "$master_slave_map_str"; then
        master_slave_map_str="$slave_node#$master_node"
    else
        master_slave_map_str="$slave_node#$master_node,$master_slave_map_str"
    fi
done

# 显示所有master
index=1
master_nodes=`echo "$master_node_str" | tr ',' '\n' | sort`
for maste_node in $master_nodes;
do
    printf "[%02d][MASTER] %s\n" $index "$maste_node"
    index=$((++index))
done

# 显示所有slave到master的映射
index=1
echo ""
master_slave_nodes=`echo "$master_slave_map_str" | tr ',' '\n' | sort`
for master_slave_node in $master_slave_nodes;
do
    line=`echo "$master_slave_node" | sed 's/#/  =>  /g'`

    n=$(($index % 2))
    if test $n -eq 1; then
        printf "[%02d][SLAVE=>MASTER]  \033[1;33m%s\033[m\n" $index "$line"
    else
        printf "[%02d][SLAVE=>MASTER]  %s\n" $index "$line"
    fi

    index=$((++index))
done

echo ""
