#!/bin/sh
# https://github.com/eyjian/libmooon/blob/master/shell/process_monitor.sh
# Created by yijian on 2012/7/23
#
# 运行日志：/tmp/process_monitor-USER.log，由于多进程同时写，不一定完整，仅供参考。
# 请放到crontab中运行，如（注意要以后台方式运行，因为脚本是常驻不退出的）：
# * * * * * /usr/local/bin/process_monitor.sh /usr/sbin/rinetd /usr/sbin/rinetd > /dev/null 2>&1 &
#
# 进程监控脚本，当指定进程不存在时，执行重启脚本将它拉起
#
# 特色：
# 1.本监控脚本可重复执行，它会自动做自互斥
# 2.互斥不仅依据监控脚本文件名，而且包含了它的命令行参数，只有整体相同时互斥才生效
# 3.对于被监控的进程，可以只指定进程名，也可以包含命令行参数
# 4.不管是监控脚本还是被监控进程，总是只针对属于当前用户下的进程
#
# 如果本脚本手工运行正常，但在crontab中运行不正常，
# 则可考虑检查下ps等命令是否可在crontab中正常运行。
#
# 假设有一程序或脚本文件/home/zhangsan/test，则有如下两个使用方式：
# 1) /usr/local/bin/process_monitor.sh "/home/zhangsan/test" "/home/zhangsan/test"
# 2) /usr/local/bin/process_monitor.sh "test" "/home/zhangsan/test"
#
# 不建议第2种使用方式，推荐总是使用第1种方式，因为第1种更为严格。
#
# 如果需要运行test的多个实例且分别监控，
# 则要求每个实例的参数必须可区分，否则无法独立监控，如：
# /usr/local/bin/process_monitor.sh "/usr/local/bin/test wangwu" "/usr/local/bin/test --name=wangwu"
# /usr/local/bin/process_monitor.sh "/usr/local/bin/test zhangsan" "/usr/local/bin/test --name=zhangsan"

# crontab技巧：
# 1）公共的定义为变量
# 2）如果包含了特殊字符，比如分号则使用单引用号，而不能用双引号，比如：
# RECEIVERS="tom;mike;jay"
# * * * * * * * * * * /usr/local/bin/process_monitor.sh "/tmp/test" "/tmp/test '$RECEIVERS'"

# 注意事项：
# 不管是监控脚本还是可执行程序，
# 均要求使用绝对路径，即必须以“/”打头的路径。

# 需要指定个数的命令行参数
# 参数1：被监控的进程名（可以包含命令行参数，而且必须包含绝对路径方式）
# 参数2：重启被监控进程的脚本（进程不能以相对路径的方式启动）
if test $# -ne 2; then
    printf "\033[1;33musage: $0 process_cmdline restart_script\033[m\n"
    printf "\033[1;33mexample: /usr/local/bin/process_monitor.sh \"/usr/sbin/rinetd\" \"/usr/sbin/rinetd\"\033[m\n"
    printf "\033[1;33mplease install process_monitor.sh into crontab by \"* * * * *\"\033[m\n"
    exit 1
fi

# 设置ONLY_TEST的值为非1关闭测试模式
# 可设置同名的环境变量ONLY_TEST来控制
ONLY_TEST=${ONLY_TEST:-0}

# 实际中，遇到脚本在crontab中运行时，找不到ls和ps等命令
# 原来是有些环境ls和ps位于/usr/bin目录下，而不是常规的/bin目录
export PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin:$PATH
trap "" SIGPIPE # 忽略SIGPIPE

#
# 前置条件判断，
# 所依赖的命令必须可用
#
which id >/dev/null 2>&1 # 依赖命令id取得当前用户的用户ID
if test $? -ne 0; then
    printf "\033[1;33mcommand 'id' not exists\033[m\n"
    exit 1
fi
which ps >/dev/null 2>&1 # 依赖命令ps求进程数
if test $? -ne 0; then
    printf "\033[1;33mcommand 'ps' not exists\033[m\n"
    exit 1
fi
which awk >/dev/null 2>&1 # 依赖命令awk求进程数
if test $? -ne 0; then
    printf "\033[1;33mcommand 'awk' not exists\033[m\n"
    exit 1
fi
which ls >/dev/null 2>&1 # 依赖命令ls计算日志文件大小
if test $? -ne 0; then
    printf "\033[1;33mcommand 'ls' not exists\033[m\n"
    exit 1
fi
which cut >/dev/null 2>&1 # 依赖命令cut计算日志文件大小
if test $? -ne 0; then
    printf "\033[1;33mcommand 'cut' not exists\033[m\n"
    exit 1
fi
which tee >/dev/null 2>&1 # 依赖命令tee写日志
if test $? -ne 0; then
    printf "\033[1;33mcommand 'tee' not exists\033[m\n"
    exit 1
fi
which mv >/dev/null 2>&1 # 依赖命令mv备份日志文件
if test $? -ne 0; then
    printf "\033[1;33mcommand 'mv' not exists\033[m\n"
    exit 1
fi
which sleep >/dev/null 2>&1 # 依赖命令sleep
if test $? -ne 0; then
    printf "\033[1;33mcommand 'sleep' not exists\033[m\n"
    exit 1
fi
which sh >/dev/null 2>&1 # 依赖命令sh重启脚本
if test $? -ne 0; then
    printf "\033[1;33mcommand 'sh' not exists\033[m\n"
    exit 1
fi

process_cmdline="$1" # 需要监控的进程名，或完整的命令行，也可以为部分命令行
restart_script="$2"  # 用来重启进程的脚本，要求具有可执行权限
monitor_interval=2   # 定时检测时间间隔，单位为秒
start_seconds=5      # 被监控进程启动需要花费多少秒
cur_user=`whoami`    # 执行本监控脚本的用户名
# 取指定网卡上的IP地址
#eth=1&&netstat -ie|awk -F'[: ]' 'begin{found=0;} { if (match($0,"eth'"$eth"'")) found=1; else if ((1==found) && match($0,"eth")) found=0; if ((1==found) && match($0,"inet addr:") && match($0,"Bcast:")) print $13; }'

uid=`id -u $cur_user` # 当前用户ID
self_name=`basename $0` # 本脚本名
self_cmdline="$0 $*"
self_dirpath=$(dirname "$0") # 脚本所在的目录
self_full_filepath=$self_dirpath/$self_name
process_raw_filepath=`echo "$process_cmdline"|cut -d" " -f1`
process_name=$(basename $process_raw_filepath)
process_dirpath=$(dirname "$process_cmdline")
process_full_filepath=$process_dirpath/$process_name
process_match="${process_cmdline#* }" # 只保留用来匹配的参数部分
process_match=$(echo $process_match) # 去掉前后的空格

# 用来做互斥，
# 以保证只有最先启动的能运行，
# 但若不同参数的彼此不相互影响，
# 这样保证了可同时对不同对象进行监控。
# 因为trap命令对KILL命令无效，所以不能通过创建文件的方式来互斥！
active=0

# 日志文件，可能多个用户都在运行，
# 所以日志文件名需要加上用户名，否则其它用户可能无权限写
log_filepath=/tmp/process_monitor-$cur_user.log
# 日志文件大小（10M）
log_filesize=10485760

# 关闭所有已打开的文件描述符
# 子进程不能继承，否则会导致本脚本自身的日志文件滚动时，被删除的备份不能被释放
close_all_fd()
{
    return
    # 0, 1, 2, 255
    # compgen -G "/proc/$BASHPID/fd/*
    for fd in $(ls /proc/$$/fd); do
        if test $fd -ge 0; then
            # 关闭文件描述符fd
            eval "exec $fd>&-"
            #eval "exec $fd<&-"
        fi
    done
}
# 导出close_all_fd
export -f close_all_fd

# 写日志函数，带1个参数：
# 1) 需要写入的日志
log()
{
    # 创建日志文件，如果不存在的话
    if test ! -f $log_filepath; then
        touch $log_filepath
    fi

    record=$1
    # 得到日志文件大小
    file_size=`ls --time-style=long-iso -l $log_filepath 2>/dev/null|cut -d" " -f5`

    # 处理日志文件过大
    # 日志加上头[$process_cmdline]，用来区分对不同对象的监控
    if test ! -z "$file_size"; then
        LOG_TIME="`date +'%Y-%m-%d %H:%M:%S'`"

        if test $file_size -lt $log_filesize; then
            # 不需要滚动
            if test $ONLY_TEST=1; then
                printf "[$process_cmdline][$LOG_TIME]$record" |tee -a $log_filepath
            else
                printf "[$process_cmdline][$LOG_TIME]$record" >> $log_filepath
            fi
        else
            # 需要滚动
            if test $ONLY_TEST=1; then
                printf "[$process_cmdline][$LOG_TIME]$record" |tee -a $log_filepath
            else
                printf "[$process_cmdline][$LOG_TIME]$record" >> $log_filepath
            fi

            # 滚动备份
            mv $log_filepath $log_filepath.bak

            if test $ONLY_TEST=1; then
                printf "[$process_cmdline][$LOG_TIME]truncated" |tee $log_filepath
                printf "[$process_cmdline][$LOG_TIME]$record" |tee -a $log_filepath
            else
                printf "[$process_cmdline][$LOG_TIME]truncated" > $log_filepath
                printf "[$process_cmdline][$LOG_TIME]$record" >> $log_filepath
            fi
        fi
    fi
}

# 显示调试信息
if test $ONLY_TEST -eq 1; then
    log "self_dirpath: $self_dirpath\n"
    log "self_full_filepath: $self_full_filepath\n"

    log "process_raw_filepath: $process_raw_filepath\n"
    log "process_name: $process_name\n"
    log "process_dirpath: $process_dirpath\n"
    log "process_full_filepath: $process_full_filepath\n"
    log "process_match: $process_match\n"
fi

# 必须使用全路径，即必须以“/”打头
s1=${self_full_filepath:0:1}
p1=${process_full_filepath:0:1}
if test $s1 != "/"; then
    log "illegal, is not an absolute path: $self_cmdline"
    exit 1
fi
#if test $p1 != "/"; then
#    log "illegal, is not an absolute path: $process_cmdline"
#    exit 1
#fi

# 取得文件类型
# process_filetype取值0表示为可执行脚本文件
# process_filetype取值1表示为可执行程序文件
# process_filetype取值2表示为未知类型文件
if test $p1 != "/"; then
    process_filetype=2
else
    file $process_full_filepath |grep ELF >/dev/null
    if test $? -eq 0; then
        process_filetype=1
    else
        file $process_full_filepath |grep script >/dev/null
        if test $? -eq 0; then
            process_filetype=0
        else
            echo "unknown file type: process_raw_filepath\n"
            exit 1
        fi
    fi
fi

# 命令“ps -C $process_name h -o euid,args”输出示例：
# 1）目标为非脚本时（process_name值为test）：
#    1001 /home/zhangsan/bin/test -a=1 -b=2
# 2）目标为脚本时（process_name值为process_monitor.sh）：
#    1001 /bin/sh /home/zhangsan/process_monitor.sh /home/zhangsan/bin/test -a=1 -b=1

# 以死循环方式，定时检测指定的进程是否存在
# 一个重要原因是crontab最高频率为1分钟，不满足秒级的监控要求
while true; do
    self_count=`ps -C $self_name h -o euid,args| awk 'BEGIN { num=0; } { if (($1==uid) && ($3==self_full_filepath) && match($0, self_cmdline)) {++num;}} END { printf("%d",num); }' uid=$uid self_full_filepath=$self_full_filepath self_cmdline="$self_cmdline"`
    if test $ONLY_TEST -eq 1; then
        log "self_count: $self_count\n"
    fi
    if test ! -z "$self_count"; then
        if test $self_count -gt 2; then
            log "$0 is running[$self_count/active:$active], current user is $cur_user\n"
            # 经测试，正常情况下一般为2，
            # 但运行一段时间后，会出现值为3，因此放在crontab中非常必要
            # 如果监控脚本已经运行，则退出不重复运行
            if test $active -eq 0; then
                exit 1
            fi
        fi
    fi

    # 检查被监控的进程是否存在，如果不存在则重启
    if test -z "$process_match"; then
        if test $process_filetype -eq 0; then # 可执行脚本文件
            process_count=`ps -C $process_name h -o euid,args| awk 'BEGIN { num=0; } { if ($1==uid) && ($3==process_full_filepath)) ++num; } END { printf("%d",num); }' uid=$uid process_full_filepath=$process_full_filepath`
        elif test $process_filetype -eq 1; then # 可执行程序文件
            process_count=`ps -C $process_name h -o euid,args| awk 'BEGIN { num=0; } { if ($1==uid) && ($2==process_full_filepath)) ++num; } END { printf("%d",num); }' uid=$uid process_full_filepath=$process_full_filepath`
        else # 未知类型文件
            process_count=`ps -C $process_name h -o euid,args| awk 'BEGIN { num=0; } { if ($1==uid) ++num; } END { printf("%d",num); }' uid=$uid`
        fi
    else
        if test $process_filetype -eq 0; then # 可执行脚本文件
            process_count=`ps -C $process_name h -o euid,args| awk 'BEGIN { num=0; } { if (($1==uid) && match($0, process_match) && ($3==process_full_filepath)) ++num; } END { printf("%d",num); }' uid=$uid process_full_filepath=$process_full_filepath process_match="$process_match"`
        elif test $process_filetype -eq 1; then # 可执行程序文件
            process_count=`ps -C $process_name h -o euid,args| awk 'BEGIN { num=0; } { if (($1==uid) && match($0, process_match) && ($2==process_full_filepath)) ++num; } END { printf("%d",num); }' uid=$uid process_full_filepath=$process_full_filepath process_match="$process_match"`
        else # 未知类型文件
            process_count=`ps -C $process_name h -o euid,args| awk 'BEGIN { num=0; } { if (($1==uid) && match($0, process_match)) ++num; } END { printf("%d",num); }' uid=$uid process_match="$process_match"`
        fi
    fi

    if test $ONLY_TEST -eq 1; then
        log "process_count: $process_count\n"
    fi
    if test ! -z "$process_count"; then
        if test $process_count -lt 1; then
            # 执行重启脚本，要求这个脚本能够将指定的进程拉起来
            log "restart \"$process_cmdline\"\n"
            #sh -c "$restart_script" 2>&1 >> $log_filepath
            msg=`sh -c "$restart_script" 2>&1`
            if test ! -z "${msg}"; then
                log "${msg}\n"
            fi

            # sleep时间得长一点，原因是启动可能没那么快，以防止启动多个进程
            # 在某些环境遇到sleep无效，正常sleep后“$?”值为0，则异常时变成“141”，
            # 这个是因为收到了信号13，可以使用“trap '' SIGPIPE”忽略SIGPIPE。
            sleep $start_seconds
        else
            sleep $monitor_interval
        fi
    else
        sleep $monitor_interval
    fi

    active=1
done
exit 0
