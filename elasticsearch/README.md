# Elasticsearch 6.4

**Installer**

.tar package.

**Environment**

Aliyun ECS Linux.

> Linux ES-master 3.10.0-693.2.2.el7.x86_64 #1 SMP Tue Sep 12 22:26:13 UTC 2017 x86_64 x86_64 x86_64 GNU/Linux

**Architecture**

| Node                     | IP Address     |
| ------------------------ | -------------- |
| Master and Ingest node 1 | 172.17.191.195 |
| Master and Ingest node 2 | 172.17.191.196 |
| Data node 1              | 172.17.191.199 |
| Data node 2              | 172.17.191.198 |



## 1. Install Java

```bash
sudo yum install -y java-1.8.0-openjdk
```



## 2. Tune OS Parameters



### Increase `max file descriptors`

Manually edit `/etc/security/limits.conf`

```conf
root soft nofile 65536
root hard nofile 65536
* soft nofile 65536
* hard nofile 65536
```

Or:

```bash
sudo sed -i 's/nofile 65535/nofile 65536/' /etc/security/limits.conf
```



### Turn on `Memory Lock` (Optional)

Manually edit `/etc/security/limits.conf`

```conf
# Allow all user to memlock
* soft memlock unlimited
* hard memlock unlimited
```

> https://www.elastic.co/guide/en/elasticsearch/reference/current/_memory_lock_check.html



### Increase `vm.max_map_count`

Manually edit `/etc/sysctl.conf`

```conf
# For Elasticsearch 6.4
vm.max_map_count = 262144
```



**Reboot to make changes effective.**



## 3. Install and Configure Elasticsearch

The cluster has 4 nodes, first 2 nodes play both `Master node` and `Ingest node`, another 2 nodes play `Data node`, each role has a backup node.

`Search Remote Connect` is disabled since no intention of cross cluster search.



### 3.1. Method A: by Script

Install Elasticsearch on each node by script.

> Script: git@git.edulaby.com:petro-config/elk-config.git

Parameters:

* `-u deployer` : User name to run Elasticsearch
* `-c logging-dev` : Cluster name
* `-p` : Tell to listen on private IP
* `-l` : Turn on `memory lock`
* `-d -r` : Remove `Data` role and disable `Search Remote Connect`
* `-m -i -r` : Remove `Master`, `Ingest` role and disable `Search Remote Connect`

**On master node and ingest nodes:**

```bash
sudo bash elasticsearch-install.sh -f elasticsearch-6.4.0.tar.gz -u deployer -c logging-dev -p -l -d -r
```

**On data nodes:**

```bash
sudo bash elasticsearch-install.sh -f elasticsearch-6.4.0.tar.gz -u deployer -c logging-dev -p -l -m -i -r
```



### 3.2. Method B: Manually

Skip `section 3.2` if `section 3.1` was taken.



#### 3.2.1. Install Elasticsearch on each node by issuing following commands.

```bash
sudo tar -C /opt -xzvf elasticsearch-6.4.0.tar.gz
sudo chown -R deployer:deployer /opt/elasticsearch*

sudo mkdir /var/lib/elasticsearch /var/log/elasticsearch
sudo chown deployer:deployer /var/lib/elasticsearch /var/log/elasticsearch
```



#### 3.2.2. Configure Elasticsearch



**Manually edit `/opt/elasticsearch-6.4.0/config/elasticsearch.yml`**

On master and ingest node 1:

```yml
cluster.name: logging-dev
node.name: ${HOSTNAME}
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
bootstrap.memory_lock: true
network.host: 172.17.191.195

node.master: true
node.data: false
node.ingest: true
search.remote.connect: false
```

On master and ingest node 2:

```yml
cluster.name: logging-dev
node.name: ${HOSTNAME}
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
bootstrap.memory_lock: true
network.host: 172.17.191.196

node.master: true
node.data: false
node.ingest: true
search.remote.connect: false
```

On data node 1:

```yml
cluster.name: logging-dev
node.name: ${HOSTNAME}
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
bootstrap.memory_lock: true
network.host: 172.17.191.199

node.master: false
node.data: true
node.ingest: false
search.remote.connect: false
```

On data node 2:

```yml
cluster.name: logging-dev
node.name: ${HOSTNAME}
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
bootstrap.memory_lock: true
network.host: 172.17.191.198

node.master: false
node.data: true
node.ingest: false
search.remote.connect: false
```

**Manually edit `/opt/elasticsearch-6.4.0/config/jvm.options`** 

On master and ingest nodes:

```options
-Xms4g
-Xmx4g
```

On all data nodes:

```options
-Xms8g
-Xmx8g
```

> Set Xmx to no more than 50% of your physical RAM, to ensure that there is enough    physical RAM left for kernel file system caches.
> https://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html



### 3.3. Additional Steps have to be done manually

Manaually edit `/opt/elasticsearch/config/elasticsearch.yml`

On all nodes:

```
discovery.zen.ping.unicast.hosts: ["172.17.191.195", "172.17.191.196", "172.17.191.199", "172.17.191.198"]
discovery.zen.minimum_master_nodes: 2
```



## 4. Start Elasticsearch

**For testing:**

```bash
/opt/elasticsearch-6.4.0/bin/elasticsearch
```

**On production:**

```bash
nohup /opt/elasticsearch-6.4.0/bin/elasticsearch &
```

A better way is to use supervisors like `supervisord` to government Elasticsearch service process.



## 5. Verify Service

```bash
curl 172.17.191.195:9200/nodes
```



## 6. Troubleshooting

### 1. ERROR: bootstrap checks failed on starting Elasticsearch service

```log
ERROR: [2] bootstrap checks failed
[1]: max file descriptors [65535] for elasticsearch process is too low, increase to at least 65536: max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

