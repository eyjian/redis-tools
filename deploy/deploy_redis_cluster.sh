#!/bin/bash
# Writed by yijian on 2018/8/21 (eyjian@qq.com)
# 源代码：https://github.com/eyjian/redis-tools
# a tool to deploy a redis cluster
#
# 自动化部署redis集群工具，
# 远程操作即可，不需登录到Redis集群中的任何机器。
#
# 以root用户批量创建用户redis示例：
# export H=192.168.0.5,192.168.0.6,192.168.0.7,192.168.0.8,192.168.0.9
# export U=root
# export P='root^1234'
# mooon_ssh -c='groupadd redis; useradd -g redis -m redis; echo "redis:redis#1234"|chpasswd'
#
# 批量创建redis安装目录/data/redis-4.0.11，并设置owner为用户redis，用户组为redis示例：
# mooon_ssh -c='mkdir /data/redis-4.0.11;ln -s /data/redis-4.0.11 /data/redis;chown redis:redis /data/redis*'
#
# 可使用process_monitor.sh监控redis-server进程重启：
# https://github.com/eyjian/libmooon/blob/master/shell/process_monitor.sh
# 使用示例：
# * * * * * /usr/local/bin/process_monitor.sh "/usr/local/redis/bin/redis-server 6379" "/usr/local/redis/bin/redis-server /usr/local/redis/conf/redis-6379.conf"
# * * * * * /usr/local/bin/process_monitor.sh "/usr/local/redis/bin/redis-server 6380" "/usr/local/redis/bin/redis-server /usr/local/redis/conf/redis-6380.conf"
# 可在/tmp目录找到process_monitor.sh的运行日志，当对应端口的进程不在时，5秒内即会重启对应端口的进程。
#
# 运行参数：
# 参数1 SSH端口
# 参数2 安装用户
# 参数3 安装用户密码
# 参数4 安装目录
#
# 前置条件（可借助批量工具mooon_ssh和mooon_upload完成）：
# 1）安装用户已经创建好
# 2）安装用户密码已经设置好
# 3）安装目录已经创建好，并且目录的owner为安装用户
# 4）执行本工具的机器上安装好了ruby，且版本号不低于2.0.0（仅redis-cli版本低于5.0时要求）
# 5）执行本工具的机器上安装好了redis-X.Y.Z.gem，且版本号不低于redis-3.0.0.gem（仅redis-cli版本低于5.0时要求）
#
# 6）同目录下存在以下几个可执行文件：
# 6.1）redis-server
# 6.2）redis-cli
# 6.3）redis-check-rdb
# 6.4）redis-check-aof
# 6.5）redis-trib.rb（仅redis-cli版本低于5.0时要求）
#
# 7）同目录下存在以下两个配置文件：
# 7.1）redis.conf
# 7.2）redis-PORT.conf
# 其中redis.conf为公共配置文件，
# redis-PORT.conf为指定端口的配置文件模板，
# 同时，需要将redis-PORT.conf文件中的目录和端口分别使用INSTALLDIR和REDISPORT替代，示例：
# include INSTALLDIR/conf/redis.conf
# pidfile INSTALLDIR/bin/redis-REDISPORT.pid
# logfile INSTALLDIR/log/redis-REDISPORT.log
# port REDISPORT
# dbfilename dump-REDISPORT.rdb
# dir INSTALLDIR/data/REDISPORT
#
# 其中INSTALLDIR将使用参数4的值替换，
# 而REDISPORT将使用redis_cluster.nodes中的端口号替代
#
# 配置文件redis_cluster.nodes，定义了安装redis的节点
# 文件格式（以“#”打头的为注释）：
# 每行由IP和端口号组成，两者间可以：空格、逗号、分号、或TAB符分隔
#
# 依赖：
# 1）mooon_ssh 远程操作多台机器批量命令工具
# 2）mooon_upload 远程操作多台机器批量上传工具
# 3）https://raw.githubusercontent.com/eyjian/libmooon
# 4）libmooon又依赖libssh2（http://www.libssh2.org/）

BASEDIR=$(dirname $(readlink -f $0))
REDIS_CLUSTER_NODES=$BASEDIR/redis_cluster.nodes

# 批量命令工具
MOOON_SSH=mooon_ssh
# 批量上传工具
MOOON_UPLOAD=mooon_upload
# redis-server
REDIS_SERVER=$BASEDIR/redis-server
# redis-cli（5.0版本开始支持创建集群，可取代redis-trib.rb）
REDIS_CLI=$BASEDIR/redis-cli
# 创建redis集群工具（如果REDIS_CLI为5.0版本，则该工具不需要）
REDIS_TRIB=$BASEDIR/redis-trib.rb
# redis-check-aof
REDIS_CHECK_AOF=$BASEDIR/redis-check-aof
# redis-check-rdb
REDIS_CHECK_RDB=$BASEDIR/redis-check-rdb
# redis.conf
REDIS_CONF=$BASEDIR/redis.conf
# redis-PORT.conf
REDIS_PORT_CONF=$BASEDIR/redis-PORT.conf

# 全局变量
# 组成redis集群的总共节点数
num_nodes=0
# 组成redis集群的所有IP数组
redis_node_ip_array=()
# 组成redis集群的所有节点数组（IP+port构造一个redis节点）
redis_node_array=()

# 用法
function usage()
{
    echo -e "\033[1;33mUsage\033[m: `basename $0` \033[0;32;32mssh-port\033[m install-user \033[0;32;32minstall-user-password\033[m install-dir"
    echo -e "\033[1;33mExample\033[m: `basename $0` \033[0;32;32m22\033[m redis \033[0;32;32mredis^1234\033[m /usr/local/redis-4.0.11"
}

# 需要指定五个参数
if test $# -ne 4; then
    usage
    echo ""
    exit 1
fi

ssh_port="$1"
install_user="$2"
install_user_password="$3"
install_dir="$4"
echo -e "[ssh port] \033[1;33m$ssh_port.\033[m"
echo -e "[install user] \033[1;33m$install_user.\033[m"
echo -e "[install directory] \033[1;33m$install_dir.\033[m"
echo ""

# 检查redis-cli是否可用
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_CLI OK."
else
    echo -e "$REDIS_CLI \033[0;32;31mnot exists or not executable.\033[m"
    echo -e "Exit now.\n"
    exit 1
fi

# 得到redis-cli主版本号
# 如果低于5，则用REDIS_TRIB创建集群，否则直接用redis-cli创建集群
redis_cli_ver=`$REDIS_CLI --version|awk -F[\ .] '{printf("%d\n",$2);}'`
echo -e "redis-cli major version: \033[1;33m${redis_cli_ver}\033[m"

# 如果低于5，则用REDIS_TRIB创建集群，否则直接用redis-cli创建集群
# 如果不使用redis-trib.rb，则不依赖ruby和gem
if test $redis_cli_ver -lt 5; then
    # 检查redis-trib.rb是否可用
    which "$REDIS_TRIB" > /dev/null 2>&1
    if test $? -eq 0; then
        echo -e "Checking $REDIS_TRIB OK."
    else
        echo -e "$REDIS_TRIB \033[0;32;31mnot exists or not executable.\033[m"
        echo -e "Exit now.\n"
        exit 1
    fi

    # 检查ruby是否可用
    which ruby > /dev/null 2>&1
    if test $? -eq 0; then
        echo -e "Checking ruby OK."
    else
        echo -e "ruby \033[0;32;31mnot exists or not executable.\033[m"
        echo "https://www.ruby-lang.org."
        echo -e "Exit now.\n"
        exit 1
    fi

    # 检查gem是否可用
    which gem > /dev/null 2>&1
    if test $? -eq 0; then
        echo -e "Checking gem OK."
    else
        echo -e "gem \033[0;32;31mnot exists or not executable.\033[m"
        echo "https://rubygems.org/pages/download."
        echo -e "Exit now.\n"
        exit 1
    fi
fi

# 检查mooon_ssh是否可用
which "$MOOON_SSH" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $MOOON_SSH OK."
else
    echo -e "$MOOON_SSH \033[0;32;31mnot exists or not executable.\033[m"
    echo "There are two versions: C++ and GO:"
    echo "https://github.com/eyjian/libmooon/releases"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_ssh.cpp"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_ssh.go"
    echo -e "Exit now.\n"
    exit 1
fi

# 检查mooon_upload是否可用
which "$MOOON_UPLOAD" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $MOOON_UPLOAD OK."
else
    echo -e "$MOOON_UPLOAD \033[0;32;31mnot exists or not executable.\033[m"
    echo "There are two versions: C++ and GO:"
    echo "https://github.com/eyjian/libmooon/releases"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_upload.cpp"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_upload.go"
    echo -e "Exit now.\n"
    exit 1
fi

# 检查redis-server是否可用
which "$REDIS_SERVER" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_SERVER OK."
else
    echo -e "$REDIS_SERVER \033[0;32;31mnot exists or not executable.\033[m"
    echo -e "Exit now.\n"
    exit 1
fi

# 检查redis-check-aof是否可用
which "$REDIS_CHECK_AOF" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_CHECK_AOF OK."
else
    echo -e "$REDIS_CHECK_AOF \033[0;32;31mnot exists or not executable.\033[m"
    echo -e "Exit now.\n"
    exit 1
fi

# 检查redis-check-rdb是否可用
which "$REDIS_CHECK_RDB" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_CHECK_RDB OK."
else
    echo -e "$REDIS_CHECK_RDB \033[0;32;31mnot exists or not executable.\033[m"
    echo -e "Exit now.\n"
    exit 1
fi

# 检查redis.conf是否可用
if test -r "$REDIS_CONF"; then
    echo -e "Checking $REDIS_CONF OK."
else
    echo -e "$REDIS_CONF \033[0;32;31mnot exists or not readable.\033[m"
    echo -e "Exit now.\n"
    exit 1
fi

# 检查redis-PORT.conf是否可用
if test -r "$REDIS_PORT_CONF"; then
    echo -e "Checking $REDIS_PORT_CONF OK."
else
    echo -e "$REDIS_PORT_CONF \033[0;32;31mnot exists or not readable.\033[m"
    echo -e "Exit now.\n"
    exit 1
fi

# 解析redis_cluster.nodes文件，
# 从而得到组成redis集群的所有节点。
function parse_redis_cluster_nodes()
{
    redis_nodes_str=
    redis_nodes_ip_str=
    while read line
    do
        # 删除前尾空格
        line=`echo "$line" | xargs`
        if test -z "$line" -o "$line" = "#"; then
            continue
        fi

        # 跳过注释
        begin_char=${line:0:1}
        if test "$begin_char" = "#"; then
            continue
        fi

        # 取得IP和端口
        eval $(echo "$line" | awk -F[\ \:,\;\t]+ '{ printf("ip=%s\nport=%s\n",$1,$2); }')

        # IP和端口都必须有
        if test ! -z "$ip" -a ! -z "$port"; then
            if test -z "$redis_nodes_ip_str"; then
                redis_nodes_ip_str=$ip
            else
                redis_nodes_ip_str="$redis_nodes_ip_str,$ip"
            fi

            if test -z "$redis_nodes_str"; then
                redis_nodes_str="$ip:$port"
            else
                redis_nodes_str="$redis_nodes_str,$ip:$port"
            fi
        fi
    done < $REDIS_CLUSTER_NODES

    if test -z "$redis_nodes_ip_str"; then
        num_nodes=0
    else
        # 得到IP数组redis_node_ip_array
        redis_node_ip_array=`echo "$redis_nodes_ip_str" | tr ',' '\n' | sort | uniq`

        # 得到节点数组redis_node_array
        redis_node_array=`echo "$redis_nodes_str" | tr ',' '\n' | sort | uniq`

        for redis_node in ${redis_node_array[@]};
        do
            num_nodes=$((++num_nodes))
            echo "$redis_node"
        done
    fi
}

# check redis_cluster.nodes
if test ! -r $REDIS_CLUSTER_NODES; then
    echo -e "File $REDIS_CLUSTER_NODES \033[0;32;31mnot exits.\033[m"
    echo ""
    echo -e "\033[0;32;32mFile format\033[m (columns delimited by space, tab, comma, semicolon or colon):"
    echo "IP1 port1"
    echo "IP2 port2"
    echo ""
    echo -e "\033[0;32;32mExample\033[m:"
    echo "127.0.0.1 6381"
    echo "127.0.0.1 6382"
    echo "127.0.0.1 6383"
    echo "127.0.0.1 6384"
    echo "127.0.0.1 6385"
    echo "127.0.0.1 6386"
    echo -e "Exit now.\n"
    exit 1
else
    echo -e "\033[0;32;32m"
    parse_redis_cluster_nodes
    echo -e "\033[m"

    if test $num_nodes -lt 1; then
        echo -e "Checking $REDIS_CLUSTER_NODES \033[0;32;32mfailed\033[m: no any node."
        echo -e "Exit now.\n"
        exit 1
    else
        echo -e "Checking $REDIS_CLUSTER_NODES OK, the number of nodes is \033[1;33m${num_nodes}\033[m"
    fi
fi

# 确认后再继续
while true
do
    # 组成一个redis集群至少需要六个节点
    if test $num_nodes -lt 6; then
        echo -e "\033[0;32;32mAt least 6 nodes are required to create a redis cluster.\033[m"
    fi

    # 提示是否继续
    echo -en "Are you sure to continue? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
    read -r -p " " input

    if test "$input" = "no"; then
        echo -e "Exit now.\n"
        exit 1
    elif test "$input" = "yes"; then
        echo "Starting to install ..."
        echo ""
        break
    fi
done

# 安装公共的，包括可执行程序文件和公共配置文件
# 两个参数：
# 1）参数1：目标Redis的IP
# 2）参数2：是否清空安装目录（值为yes表示清空，否则不清空）
function install_common()
{
    redis_ip="$1"
    clear_install_directory="$2"

    # 自动创建安装目录
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="if test ! -d $install_dir; then mkdir -p $install_dir; fi"

    # 检查安装目录是否存在，且有读写权限
    echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"test -d $install_dir && test -r $install_dir && test -w $install_dir && test -x $install_dir\""
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="test -d $install_dir && test -r $install_dir && test -w $install_dir && test -x $install_dir"
    if test $? -ne 0; then
        echo ""
        echo -e "Directory $install_dir \033[1;33mnot exists or no (rwx) permission\033[m, or \033[1;33mcan not login $redis_ip:$ssh_port by $install_user.\033[m"
        echo -e "Exit now.\n"
        exit 1
    fi

    # 清空安装目录
    if test "$clear_install_directory" = "yes"; then
        echo ""
        echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"killall -q -w -u $install_user redis-server\""
        $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="killall -q -w -u $install_user redis-server"

        echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"rm -fr $install_dir/*\""
        $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="rm -fr $install_dir/*"
        if test $? -ne 0; then
            echo -e "Exit now.\n"
            exit 1
        fi
    fi

    # 创建公共目录（create directory）
    echo ""
    echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"cd $install_dir;mkdir -p bin conf log data\""
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="cd $install_dir;mkdir -p bin conf log data"
    if test $? -ne 0; then
        echo -e "Exit now.\n"
        exit 1
    fi

    # 上传公共配置文件（upload configuration files）
    echo ""
    echo "$MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis.conf -d=$install_dir/conf"
    $MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis.conf -d=$install_dir/conf
    if test $? -ne 0; then
        echo -e "Exit now.\n"
        exit 1
    fi

    # 上传公共执行文件（upload executable files）
    echo ""
    echo "$MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-server,redis-cli,redis-check-aof,redis-check-rdb -d=$install_dir/bin"
    $MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-server,redis-cli,redis-check-aof,redis-check-rdb,redis-trib.rb -d=$install_dir/bin
    if test $? -ne 0; then
        echo -e "Exit now.\n"
        exit 1
    fi
}

# 安装节点配置文件
function install_node_conf()
{
    redis_ip="$1"
    redis_port="$2"

    # 生成节点配置文件
    cp redis-PORT.conf redis-$redis_port.conf
    sed -i "s|INSTALLDIR|$install_dir|g;s|REDISPORT|$redis_port|g" redis-$redis_port.conf

    # 创建节点数据目录（create data directory for the given node）
    echo ""
    echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"cd $install_dir;mkdir -p data/$redis_port\""
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="cd $install_dir;mkdir -p data/$redis_port"
    if test $? -ne 0; then
        rm -f redis-$redis_port.conf
        echo -e "Exit now.\n"
        exit 1
    fi

    # 上传节点配置文件（upload configuration files）
    echo ""
    echo "$MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-$redis_port.conf -d=$install_dir/conf"
    $MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-$redis_port.conf -d=$install_dir/conf
    if test $? -ne 0; then
        rm -f redis-$redis_port.conf
        echo -e "Exit now.\n"
        exit 1
    fi

    rm -f redis-$redis_port.conf
}

function start_redis_node()
{
    redis_ip="$1"
    redis_port="$2"

    # 启动redis实例（start redis instance）
    echo ""
    echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"$install_dir/bin/redis-server $install_dir/conf/redis-$redis_port.conf\""
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="nohup $install_dir/bin/redis-server $install_dir/conf/redis-$redis_port.conf > /dev/null 2>&1 &"
    if test $? -ne 0; then
        echo -e "Exit now.\n"
        exit 1
    fi
}

# 询问是否安装公共
echo ""
echo -e "\033[1;33m================================\033[m"
echo -en "Install common (files & directories etc.)? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
read -r -p " " to_install_common
if test "X$to_install_common" = "Xyes"; then
    # 是否先清空安装目录再安装？
    echo -en "Clear install directory? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
    read -r -p " " clear_install_directory

    # 安装公共的，包括可执行程序文件和公共配置文件
    for redis_node_ip in $redis_node_ip_array;
    do
        echo -e "[\033[1;33m$redis_node_ip\033[m] Installing common ..."
        install_common "$redis_node_ip" "$clear_install_directory"
    done
fi

# 安装节点配置文件
echo ""
echo -e "\033[1;33m================================\033[m"
for redis_node in ${redis_node_array[@]};
do
    node_ip=
    node_port=

    eval $(echo "$redis_node" | awk -F[\ \:,\;\t]+ '{ printf("node_ip=%s\nnode_port=%s\n",$1,$2); }')
    if test -z "$node_ip" -o -z "$node_port"; then
        continue
    fi

    echo -e "[\033[1;33m$node_ip:$node_port\033[m] Installing node ..."
    install_node_conf $node_ip $node_port
done

# 确认后再继续
echo ""
echo -e "\033[1;33m================================\033[m"
while true
do
    echo -en "Start redis? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
    read -r -p " " input

    if test "$input" = "no"; then
        echo ""
        exit 1
    elif test "$input" = "yes"; then
        echo "Starting to start redis ..."
        echo ""
        break
    fi
done

# 启动redis实例（start redis instance）
for redis_node in ${redis_node_array[@]};
do
    eval $(echo "$redis_node" | awk -F[\ \:,\;\t]+ '{ printf("node_ip=%s\nnode_port=%s\n",$1,$2); }')
    if test -z "$node_ip" -o -z "$node_port"; then
        continue
    fi

    echo -e "[\033[1;33m$node_ip:$node_port\033[m] Starting node ..."
    start_redis_node $node_ip $node_port
done

echo ""
echo -e "\033[1;33m================================\033[m"
echo "Number of nodes: $num_nodes"
if test $num_nodes -lt 6; then
    echo "Number of nodes less than 6, can not create redis cluster."
    echo -e "Exit now.\n"
    exit 1
else
    redis_nodes_str=`echo "$redis_nodes_str" | tr ',' ' '`

    # 确认后再继续
    echo ""
    while true
    do
        echo -en "Create redis cluster? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
        read -r -p " " input

        if test "$input" = "no"; then
            echo ""
            exit 1
        elif test "$input" = "yes"; then
            echo "Starting to create redis cluster with $redis_nodes_str ... ..."
            echo ""
            break
        fi
    done

    # 创建redis集群（create redis cluster）
    if test $redis_cli_ver -lt 5; then
        # redis-trib.rb create --replicas 1
        echo "$REDIS_TRIB create --replicas 1 $redis_nodes_str"
        $REDIS_TRIB create --replicas 1 $redis_nodes_str
    else
        echo "$REDIS_CLI --cluster create $redis_nodes_str --cluster-replicas 1"
        $REDIS_CLI --cluster create $redis_nodes_str --cluster-replicas 1
    fi
    echo -e "Exit now.\n"
    exit 0
fi
