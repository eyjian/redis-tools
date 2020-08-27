* **deploy**

  Redis和Redis集群批量部署工具（deploy_redis_cluster.sh）

* **check_redis_cluster.sh**

  检查Redis集群工具，依赖命令SETEX

* **clear_redis_cluster.sh**

  清空Redis集群工具，依赖命令FLUSHALL

* **show_redis_map.sh**

  显示redis集群master和slave间的映射关系，如果同一IP出现两个master或者一对master和slave在同一个IP上，标星的方式提示

* **query_redis_memory**

   查询集群所有节点物理内存工具


* **move_redis_slot.sh**

  迁移slot工具

* **query_key_distribution.sh**

  查询key在节点中的分布工具

* **stop_redis.sh**

  用于停指定端口号 redis-server 进程工具
