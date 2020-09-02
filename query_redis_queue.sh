#!/bin/bash
# Writed by yijian on 2019/8/29
# 查看redis队列长度工具，
# 支持同时查看多个redis或redis集群的多个队列。
#
# 在使用之前，必须设置好三个环境变量：
# 1）REDIS_PASSWORD 可不设置，指定访问redis的密码，没设置或值为空时表示密码为空。
# 2）REDIS_CLUSTERS 必须设置，用于指定查询的redis或redis集群，如果是多套redis则密码得相同。
# 3）REDIS_QUEUES 必须设置，用于指定查询的redis队列，队列key的前缀和数量以斜杠“/”分隔。
#
# REDIS_CLUSTERS示例1（单套redis集群）：
# REDIS_CLUSTERS="127.0.0.1:6379"
#
# REDIS_CLUSTERS示例2（多套redis集群，注意用“空格”分开）：
# REDIS_CLUSTERS="127.0.0.1:2021 127.0.0.1:3021"
#
# REDIS_QUEUES示例1（单组队列，队列key的前缀为kprefix，队列数9个）：
# REDIS_QUEUES="kprefix:/9"
#
# REDIS_QUEUES示例2（多组队列，注意用“空格”分开）
# REDIS_QUEUES="kprefix1:/9 kprefix2:/11 kprefix3:/6"

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

# 检查是否设置了环境变量 REDIS_CLUSTERS
if test -z "$REDIS_CLUSTERS"; then
  echo "Environment variable \`REDIS_CLUSTERS\` is not set or is empty."
  exit 1
fi
# 字符串值转成数组值
REDIS_CLUSTERS=(`echo $REDIS_CLUSTERS`)
if test ${#REDIS_CLUSTERS[@]} -eq 0; then
  # 不是数组或者是空数组
  echo "Environment variable \`REDIS_CLUSTERS\` have an empty value."
  echo "Example1:"
  echo "export REDIS_CLUSTERS=\"127.0.0.1:6379\""
  echo "Example2:"
  echo "export REDIS_CLUSTERS=\"127.0.0.1:2021 127.0.0.1:3021\""
  exit 1
fi

# 检查是否设置了环境变量 REDIS_QUEUES
if test -z "$REDIS_QUEUES"; then
  echo "Environment variable \`REDIS_QUEUES\` is not set or is empty."
  exit 1
fi
# 字符串值转成数组值
REDIS_QUEUES=(`echo $REDIS_QUEUES`)
if test ${#REDIS_QUEUES[@]} -eq 0; then
  # 不是数组或者是空数组
  echo "Environment variable \`REDIS_QUEUES\` have an empty value."
  echo "Example1:"
  echo "export REDIS_QUEUES=\"kprefix:/9\""
  echo "Example2:"
  echo "export REDIS_QUEUES=\"kprefix1:/9 kprefix2:/11 kprefix3:/6\""
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

        for queue in ${REDIS_QUEUES[@]}
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
