Redis和Redis集群部署工具

REDIS.crontab crontab监控模板
deploy_redis_cluster.sh 集群部署工具
redis_cluster.nodes 集群所有节点和端口配置文件

注：
本目录下的的redis.conf和redis-PORT.conf取自redis-4.0.11版本，新增了一些配置项，可能不适应于一些低版本。
deploy_redis_cluster.log 为deploy_redis_cluster.sh示例的操作日志和运行日志

依赖两个批量操作工具：mooon_ssh和mooon_upload，这两个批量操作工具有C++和GO两个版本。
mooon-tools-glibc2.4_i386.tar.gz：32位版本的mooon_ssh和mooon_upload，运行依赖C++运行时库
mooon-tools-glibc2.17_x86_64.tar.gz：64位版本的mooon_ssh和mooon_upload，运行依赖C++运行时库
注：GO版本的mooon_ssh和mooon_upload不依赖依赖C++运行时库

在执行deploy_redis_cluster.sh之前，
需要先完成下列前置工作（只需要在任意一台可SSH连接Redis集群的机器上完成）：
1）安装好了ruby，并且版本不低于2.0.0（方法参见Redis集群安装文章）
2）安装好了ruby包管理器RubyGems（方法参见Redis集群安装文章）
3）安装好了redis-X.X.X.gem，并且版本不低于3.0.0（方法参见Redis集群安装文章）
4）准备好了批量命令工具mooon_ssh
5）准备好了批量上传工具mooon_upload
6）准备好了公共的redis配置文件redis.conf
7）准备好了与端口关的redis配置文件模板redis-PORT.conf
8）配置好redis_cluster.nodes，格式请参见redis_cluster.nodes

使用批量操作工具mooon_ssh和mooon_upload完成下列工作（Redis集群每个节点均需）：
1）创建好安装用户，并设置好安装用户密码
2）创建好安装目录，并且设置目录的owner为安装用户
3）系统环境的设置，主要包括（参见Redis集群安装文章）：
3.1）最大可打开文件数（/etc/security/limits.conf）
3.2）TCP监听队列大小（/proc/sys/net/core/somaxconn）
3.3）OOM设置（/proc/sys/vm/overcommit_memory）
3.4）THP设置（/sys/kernel/mm/transparent_hugepage/enabled）

批量操作工具

1）C++版本mooon_ssh和mooon_upload
libmooon包含了mooon_ssh和mooon_upload，这两个工具基于开源的libssh2（http://www.libssh2.org/）实现。

2）GO版本mooon_ssh和mooon_upload

3）编译libssh2
Linux下编译libssh2，需要指定参数“--with-libssl-prefix”：
./configure --prefix=/usr/local/libssh2-1.6.0 --with-libssl-prefix=/usr/local/openssl
make
make install
因此，编译之前需要先安装好openssl

4）编译openssl
./config --prefix=/usr/local/openssl shared threads
make
make install

5）编译libmooon
cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr/local/mooon .
make
make install
编译成功后，在tools目录下可以找到编译好的mooon_ssh和mooon_upload。

GO版本的mooon_ssh和mooon_upload，请直接参见mooon_ssh.go和mooon_upload.go的文件头注释。

Redis集群安装文章：
1）https://blog.csdn.net/Aquester/article/details/50150163
2）http://blog.chinaunix.net/uid-20682147-id-5557566.html

注意ruby和redis-X.X.X.gem的版本并非越高越好，最新版本也可能导致安装失败，
截至到redis-4.0.11版本，ruby 2.X.X配合redis-3.X.X.gem一般没有问题。

以root用户安装rubygems，如果yum可用，只需执行“yum -y install rubygems”即可，否则按以下步骤操作：
1）解压安装包，如：unzip rubygems-2.7.7.zip
2）进入解压目录
3）在解压目录执行：ruby setup.rb
4）等待安装完成

以root用户安装redis-X.X.X.gem，如：gem install -l redis-3.0.0.gem
