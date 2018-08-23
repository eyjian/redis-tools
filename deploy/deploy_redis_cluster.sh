#!/bin/bash
# Writed by yijian on 2018/8/21
# a tool to deploy a redis cluster
# 自动化部署redis集群工具
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
# 4）执行本工具的机器上安装好了ruby，且版本号不低于2.0.0
# 5）执行本工具的机器上安装好了redis-X.Y.Z.gem，且版本号不低于redis-3.0.0.gem
#
# 6）同目录下存在以下几个可执行文件：
# 6.1）redis-server
# 6.2）redis-cli
# 6.3）redis-check-rdb
# 6.4）redis-check-aof
# 6.5）redis-trib.rb
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
# 创建redis集群工具
REDIS_TRIB=$BASEDIR/redis-trib.rb
# redis-server
REDIS_SERVER=$BASEDIR/redis-server
# redis-cli
REDIS_CLI=$BASEDIR/redis-cli
# redis-check-aof
REDIS_CHECK_AOF=$BASEDIR/redis-check-aof
# redis-check-rdb
REDIS_CHECK_RDB=$BASEDIR/redis-check-rdb

# 用法
function usage()
{
    echo -e "\033[1;33mUsage\033[m: `basename $0` \033[0;32;32mssh-port\033[m install-user \033[0;32;32minstall-user-password\033[m install-dir"
    echo -e "\033[1;33mExample\033[m: `basename $0` \033[0;32;32m22\033[m redis \033[0;32;32mredis@1234\033[m /usr/local/redis-4.0.11"
}

# 需要指定五个参数
if test $# -ne 4; then
    usage
    exit 1
fi

ssh_port="$1"
install_user="$2"
install_user_password="$3"
install_dir="$4"
echo -e "[ssh port] \033[1;33m$ssh_port\033[m"
echo -e "[install user] \033[1;33m$install_user\033[m"
echo -e "[install directory] \033[1;33m$install_dir\033[m"
echo ""

# 检查mooon_ssh是否可用
which "$MOOON_SSH" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $MOOON_SSH OK"
else
    echo -e "$MOOON_SSH \033[0;32;31mnot exists or not executable\033[m"
    echo "There are two versions: C++ and GO:"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_ssh.cpp"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_ssh.go"
    echo ""
    exit 1
fi

# 检查mooon_upload是否可用
which "$MOOON_UPLOAD" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $MOOON_UPLOAD OK"
else
    echo -e "$MOOON_UPLOAD \033[0;32;31mnot exists or not executable\033[m"
    echo "There are two versions: C++ and GO:"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_upload.cpp"
    echo "https://raw.githubusercontent.com/eyjian/libmooon/master/tools/mooon_upload.go"
    echo ""
    exit 1
fi

# 检查redis-trib.rb是否可用
which "$REDIS_TRIB" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_TRIB OK"
else
    echo -e "$REDIS_TRIB \033[0;32;31mnot exists or not executable\033[m"
    echo ""
    exit 1
fi

# 检查redis-server是否可用
which "$REDIS_SERVER" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_SERVER OK"
else
    echo -e "$REDIS_SERVER \033[0;32;31mnot exists or not executable\033[m"
    echo ""
    exit 1
fi

# 检查redis-cli是否可用
which "$REDIS_CLI" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_CLI OK"
else
    echo -e "$REDIS_CLI \033[0;32;31mnot exists or not executable\033[m"
    echo ""
    exit 1
fi

# 检查redis-check-aof是否可用
which "$REDIS_CHECK_AOF" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_CHECK_AOF OK"
else
    echo -e "$REDIS_CHECK_AOF \033[0;32;31mnot exists or not executable\033[m"
    echo ""
    exit 1
fi

# 检查redis-check-rdb是否可用
which "$REDIS_CHECK_RDB" > /dev/null 2>&1
if test $? -eq 0; then
    echo -e "Checking $REDIS_CHECK_RDB OK"
else
    echo -e "$REDIS_CHECK_RDB \033[0;32;31mnot exists or not executable\033[m"
    echo ""
    exit 1
fi

# check redis_cluster.nodes
if test -r $REDIS_CLUSTER_NODES; then
    echo -e "Checking $REDIS_CLUSTER_NODES OK"
else
    echo -e "File $REDIS_CLUSTER_NODES \033[0;32;31mnot exits\033[m"
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
    echo ""
    exit 1
fi

# 确认后再继续
echo ""
while true
do
    echo -en "Are you sure? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
    read -r -p " " input

    if test "$input" = "no"; then
        echo ""
        exit 1
    elif test "$input" = "yes"; then
        echo "Starting to install ..."
        echo ""
        break
    fi
done

# 是否先清空安装目录再安装？
clear_install_directory=
while true
do
    echo -en "Clear install directory? [\033[1;33myes\033[m/\033[1;33mno\033[m]"
    read -r -p " " clear_install_directory

    if test "$clear_install_directory" = "no"; then
        echo ""
        break
    elif test "$clear_install_directory" = "yes"; then        
        echo ""
        break
    fi
done

# 安装公共的，包括可执行程序文件和公共配置文件
function install_common()
{
    redis_ip="$1"
    
    # 检查安装目录是否存在，且有读写权限
    echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"test -d $install_dir && test -r $install_dir && test -w $install_dir && test -x $install_dir\""
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="test -d $install_dir && test -r $install_dir && test -w $install_dir && test -x $install_dir"
    if test $? -ne 0; then
        echo ""
        echo -e "Directory $install_dir \033[1;33mnot exists or no (rwx) permission\033[m"
        echo ""
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
            exit 1
        fi
    fi

    # 创建公共目录（create directory）
    echo ""
    echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"cd $install_dir;mkdir -p bin conf log data\""
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="cd $install_dir;mkdir -p bin conf log data"
    if test $? -ne 0; then
        exit 1
    fi

    # 上传公共配置文件（upload configuration files）
    echo ""
    echo "$MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis.conf -d=$install_dir/conf"
    $MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis.conf -d=$install_dir/conf 
    if test $? -ne 0; then
        exit 1
    fi

    # 上传公共执行文件（upload executable files）
    echo ""
    echo "$MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-server,redis-cli,redis-check-aof,redis-check-rdb -d=$install_dir/bin"    
    $MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-server,redis-cli,redis-check-aof,redis-check-rdb,redis-trib.rb -d=$install_dir/bin
    if test $? -ne 0; then
        exit 1
    fi
}

# 安装节点配置文件和启动redis实例
function install_node()
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
        exit 1
    fi

    # 上传节点配置文件（upload configuration files）
    echo ""
    echo "$MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-$redis_port.conf -d=$install_dir/conf"
    $MOOON_UPLOAD -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -s=redis-$redis_port.conf -d=$install_dir/conf    
    if test $? -ne 0; then
        exit 1
    fi

    # 启动redis实例（start redis instance）
    echo ""
    echo "$MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c=\"$install_dir/bin/redis-server $install_dir/conf/redis-$redis_port.conf\""    
    $MOOON_SSH -h=$redis_ip -P=$ssh_port -u=$install_user -p=$install_user_password -c="nohup $install_dir/bin/redis-server $install_dir/conf/redis-$redis_port.conf > /dev/null 2>&1 &"
    if test $? -ne 0; then
        exit 1
    fi
}

# 批量安装redis（batch to install redis）
num_nodes=0
redis_nodes_str=
redis_nodes_ip_str=
while read line
do
    line=`echo "$line" | xargs`
    if test -z "$line" -o "$line" = "#"; then
        continue
    fi

    # 跳过注释
    begin_char=${line:0:1}
    if test "$begin_char" = "#"; then
        continue
    fi

    eval $(echo "$line" | awk -F[\ \:,\;\t]+ '{ printf("ip=%s\nport=%s\n",$1,$2); }')
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

# 得到IP数组redis_node_ip_array
echo -e "\033[1;33m================================\033[m"
redis_node_ip_array=`echo "$redis_nodes_ip_str" | tr ',' '\n' | sort | uniq`
for redis_node_ip in $redis_node_ip_array;
do
    echo -e "[\033[1;33m$redis_node_ip\033[m] Installing common ..."
    install_common $redis_node_ip
done

# 得到节点数组redis_node_array
echo ""
echo -e "\033[1;33m================================\033[m"
redis_node_array=`echo "$redis_nodes_str" | tr ',' '\n' | sort | uniq`
for redis_node in ${redis_node_array[@]};
do
    node_ip=
    node_port=
    num_nodes=$((++num_nodes))

    eval $(echo "$redis_node" | awk -F[\ \:,\;\t]+ '{ printf("node_ip=%s\nnode_port=%s\n",$1,$2); }')
    if test -z "$node_ip" -o -z "$node_port"; then
        continue
    fi
    
    echo -e "[\033[1;33m$node_ip:$node_port\033[m] Installing node ..."
    install_node $node_ip $node_port
done

echo ""
echo -e "\033[1;33m================================\033[m"
echo "Number of nodes: $num_nodes"
if test $num_nodes -lt 6; then
    echo "Number of nodes less than 6, can not create redis cluster"
    echo ""
    exit 1
else
    redis_nodes_str=`echo "$redis_nodes_str" | tr ',' ' '`

    # 创建redis集群（create redis cluster）
    # redis-trib.rb create --replicas 1
    echo "Creating redis cluster with $redis_nodes_str ..."
    $REDIS_TRIB create --replicas 1 $redis_nodes_str
    echo ""
    exit 0
fi
