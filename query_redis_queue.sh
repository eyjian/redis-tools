#!/bin/bash
# Writed by yijian on 2019/8/29
# 查看redis队列长度工具，
# 支持同时查看多个redis或redis集群的多个队列
# 队列Key的格式要求为：
# 前缀 + 下标，下标为从0开始的递增整数值。

# 访问redis的密码，如果没有保持为空
REDIS_PASSWORD=""
# 如果redis-cli所在目录不在PATH中，则需要添加或显示指定
REDIS_CLI=redis-cli

# 要查询的 redis 或 redis集群数组
REDIS_CLUSTERS=(
    "127.0.0.1:6379"
    "127.0.0.1:6380"
)

# 要查询的 redis 队列数组，
# “/”前面是前缀，“/”后是队列数，
# 第行一组队列。
queues=(
    "keyprefix1:/9"
    "keyprefix2:/11"
    "keyprefix3:/1"
)

# 检查 redis-cli 是否可用
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -ne 0; then
    echo "\"redis-cli\" is not found or not executable."
    exit 1
fi

function view_all_clusters()
{
    # 查看所有Redis集群
    for REDIS_NODE in ${REDIS_CLUSTERS[@]}
    do
        # 取得IP和端口
        eval $(echo "$REDIS_NODE" | awk -F[\ \:,\;\t]+ '{ printf("REDIS_IP=%s\nREDIS_PORT=%s\n",$1,$2); }')
        echo -e "\033[1;33m====================\033[m"
        echo -e "[\033[1;33m$REDIS_IP:$REDIS_PORT $DATE\033[m]"

        for queue in ${queues[@]}
        do
            total_qlen=0 # 所有队列加起来的总长度
            qnum=0 # 单个队列长度

            # qprefix 队列前缀
            # qnum 队列数
            eval $(echo "$queue" | awk -F[/]+ '{ printf("qprefix=%s\nqnum=%s\n",$1,$2); }')
            if test -z "$qnum" -o $qnum -eq 0; then
                continue
            fi

            echo -n "[$qprefix/$qnum]"
            for ((i=0; i<$qnum; ++i))
            do
                if test -z "$REDIS_PASSWORD"; then
                  qlen=`$REDIS_CLI --raw -c -h $REDIS_IP -p $REDIS_PORT LLEN "$qprefix$i"`
                else
                  qlen=`$REDIS_CLI --no-auth-warning -a "$REDIS_PASSWORD" --raw -c -h $REDIS_IP -p $REDIS_PORT LLEN "$qprefix$i"`
                fi
                if test -z "$qlen"; then
                    qlen=0
                fi
                total_qlen=$(($total_qlen+$qlen))
                echo -n " $qlen"
            done
            echo -e " \033[1;33m$total_qlen\033[m"
        done
        echo ""
    done
}

while (true)
do
    view_all_clusters
    sleep 2
done
