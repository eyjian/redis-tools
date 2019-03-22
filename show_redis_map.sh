#!/bin/bash
# Writed by yijian on 2018/8/24
# 源码位置：https://github.com/eyjian/redis-tools
#
# Redis集群部署注意事项：
# 在一个物理IP上部署多个redis实例时，要避免：
# 1) 一对master和slave出现在同一物理IP上（影响：物理机挂掉，部分keys彻底不可用）
# 2) 同一物理IP上出现多个master（影响：物理机挂掉，将导致两对切换）
#
# 带2个参数，
# 第1个参数为REdis的节点字符串，
# 第2个参数可选，为连接REdis的密码。
# 使用示例1）show_redis_map.sh 192.168.0.21:6380
# 使用示例2）show_redis_map.sh 192.168.0.21:6380 password
#
# 检查Redis集群master和slave映射关系的命令行工具：
# 1) 查看是否多master出现在同一IP；
# 2) 查看一对master和slave出现在同一IP。
#
# 当同一IP出现二个或多个master，则相应的行标星显示，
# 如果一对master和slave出现在同一IP上，则相应的行标星显示。
#
# 输出效果：
# [01][MASTER]  192.168.0.21:6379 00cc3f37d938ee8ba672bc77b71d8e0a3881a98b
# [02][MASTER]  192.168.0.22:6379   1115713e3c311166207f3a9f1445b4e32a9202d7
# [03][MASTER]  192.168.0.23:6379   5cb6946f46ccdf543e5a1efada6806f3df72b727
# [04][MASTER]  192.168.0.24:6379   b91b1309b05f0dcc1e3a2a9521b8c00702999744
# [05][MASTER]  192.168.0.25:6379   00a1ba8e5cb940ba4171e0f4415b91cea96977bc
# [06][MASTER]  192.168.0.26:6379     64facb201cc5c7d8cdccb5fa211af5e1a04a9786
# [07][MASTER]  192.168.0.27:6379     f119780359c0e43d19592db01675df2f776181b1
# [08][MASTER]  192.168.0.28:6379     d374e28578967f96dcb75041e30a5a1e23693e56
# [09][MASTER]  192.168.0.29:6380     a153d2071251657004dbe77abd10e2de7f0a209a
#
# [01][SLAVE=>MASTER]  192.168.0.21:6380  =>  192.168.0.28:6379
# [02][SLAVE=>MASTER]    192.168.0.22:6380  =>  192.168.0.25:6379
# [03][SLAVE=>MASTER]    192.168.0.23:6380  =>  192.168.0.24:6379
# [04][SLAVE=>MASTER]    192.168.0.24:6380  =>  192.168.0.23:6379
# [05][SLAVE=>MASTER]    192.168.0.25:6380  =>  192.168.0.22:6379
# [06][SLAVE=>MASTER]      192.168.0.26:6380  =>  192.168.0.27:6379
# [07][SLAVE=>MASTER]      192.168.0.27:6380  =>  192.168.0.29:6380
# [08][SLAVE=>MASTER]      192.168.0.28:6380  =>  192.168.0.21:6379
# [09][SLAVE=>MASTER]      192.168.0.29:6379  =>  192.168.0.26:6379

REDIS_CLI=${REDIS_CLI:-redis-cli}
REDIS_IP=${REDIS_IP:-127.0.0.1}
REDIS_PORT=${REDIS_PORT:-6379}

function usage()
{
    echo "Usage: `basename $0` redis_node [redis_password]"
    echo "Example1: `basename $0` 127.0.0.1:6379"
    echo "Example2: `basename $0` 127.0.0.1:6379 password"
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

# master映射表，key为master的id，value为master的“ip:port”
declare -A master_map=()
# slave映表，key为master的id，value为slave的“ip:port”
declare -A slave_map=()
master_nodes_str=
master_slave_maps_str=

# 如果出错，不用继续
set -e

# 找出所有master
# 因为前面的“set -e”，所以如果第1步出错，则后面的awk将不会执行
if test $# -eq 1; then    
    masters=`$REDIS_CLI -h $REDIS_IP -p $REDIS_PORT CLUSTER NODES | awk -F[\ \@] '/master/{ printf("%s,%s\n",$1,$2); }' | sort`
else
    masters=`$REDIS_CLI -a "$2" -h $REDIS_IP -p $REDIS_PORT CLUSTER NODES | awk -F[\ \@] '/master/{ printf("%s,%s\n",$1,$2); }' | sort`
fi
if test -z "$masters"; then
    # 可能是因为密码错误
    # (error) NOAUTH Authentication required.
    $REDIS_CLI -a "$2" -h $REDIS_IP -p $REDIS_PORT PING "hello"    
    exit 1
fi
for master in $masters;
do    
    eval $(echo $master | awk -F[,] '{ printf("master_id=%s\nmaster_node=%s\n",$1,$2); }')

    master_map[$master_id]=$master_node    
    if test -z "$master_nodes_str"; then
        master_nodes_str="$master_node|$master_id"
    else
        master_nodes_str="$master_node|$master_id,$master_nodes_str"
    fi
done

# 找出所有slave
# “CLUSTER NODES”命令的输出格式当前有两个版本，需要awk需要根据NF的值做区分
if test $# -eq 1; then
    slaves=`$REDIS_CLI -h $REDIS_IP -p $REDIS_PORT CLUSTER NODES | awk -F[\ \@] '/slave/{ if (NF==9) printf("%s,%s\n",$5,$2); else printf("%s,%s\n",$4,$2); }' | sort`
else
    slaves=`$REDIS_CLI -a "$2" -h $REDIS_IP -p $REDIS_PORT CLUSTER NODES | awk -F[\ \@] '/slave/{ if (NF==9) printf("%s,%s\n",$5,$2); else printf("%s,%s\n",$4,$2); }' | sort`
fi
for slave in $slaves;
do
    eval $(echo $slave | awk -F[,] '{ printf("master_id=%s\nslave_node=%s\n",$1,$2); }')
    slave_map[$master_id]=$slave_node
done

for key in ${!master_map[@]}
do
    master_node=${master_map[$key]}
    slave_node=${slave_map[$key]}

    if test -z "$master_slave_maps_str"; then
        master_slave_maps_str="$slave_node|$master_node"
    else
        master_slave_maps_str="$slave_node|$master_node,$master_slave_maps_str"
    fi
done

# 显示所有master
index=1
old_master_node_ip=
master_nodes_str=`echo "$master_nodes_str" | tr ',' '\n' | sort`
for master_node_str in $master_nodes_str;
do
    eval $(echo "$master_node_str" | awk -F[\|] '{ printf("master_node=%s\nmaster_id=%s\n", $1, $2); }')
    eval $(echo "$master_node" | awk -F[\:] '{ printf("master_node_ip=%s\nmaster_node_port=%s\n", $1, $2); }')

    tag=
    # 同一IP上出现多个master，标星
    if test "$master_node_ip" = "$old_master_node_ip"; then
        tag="  (*)"
    fi

    printf "[%02d][MASTER]  %-20s \033[0;32;31m%s\033[m%s\n" $index "$master_node" "$master_id" "$tag"
    old_master_node_ip=$master_node_ip
    index=$((++index))
done

# 显示所有slave到master的映射
index=1
echo ""
master_slave_maps_str=`echo "$master_slave_maps_str" | tr ',' '\n' | sort`
for master_slave_map_str in $master_slave_maps_str;
do
    eval $(echo "$master_slave_map_str" | awk -F[\|] '{ printf("slave_node=%s\nmaster_node=%s\n", $1, $2); }')
    eval $(echo "$slave_node" | awk -F[\:] '{ printf("slave_node_ip=%s\nslave_node_port=%s\n", $1, $2); }')
    eval $(echo "$master_node" | awk -F[\:] '{ printf("master_node_ip=%s\nmaster_node_port=%s\n", $1, $2); }')

    tag=
    # 一对master和slave出现在同一IP，标星
    if test ! -z "$slave_node_ip" -a "$slave_node_ip" = "$master_node_ip"; then
        tag="  (*)"
    fi

    n=$(($index % 2))
    if test $n -eq 0; then
        printf "[%02d][SLAVE=>MASTER] \033[1;33m%21s\033[m  =>  \033[1;33m%s\033[m%s\n" $index $slave_node $master_node "$tag"
    else
        printf "[%02d][SLAVE=>MASTER] %21s  =>  %s%s\n" $index $slave_node $master_node "$tag"
    fi

    index=$((++index))
done

echo ""
exit 0
