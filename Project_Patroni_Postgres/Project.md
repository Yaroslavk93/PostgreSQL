# **Настройка реплицированного кластера Postgresql, тюнинг + мониторинг через Grafana**

## **Цель:**
### - Реализовать свой миникластер на 3 ВМ (мастер, 2 сегмента);
### - Настройка отказоустойчивого кластера, используя HAproxy и Patroni;
### - Оптиимизация СУБД;
### - Настройка и реализация мониторинга через Grafana, используя prometheus;
### - Нагрузочное тестирование кластера PostgreSQL;


------------------
1. В рамках подготовки, разворачиваем 6 ноды с помощью Vagrant (3 postgres, 1 ETCD, 1 HAProxy, 1 Monitoring) 
- *переходим в нужную директорию и создаём конфигурационный файл Vagrant:*
```bash
vagrant init
```
- *настраиваем конфиг для ВМ:*
```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"

  machines = {
    'pg-node1' => '192.168.10.10',
    'pg-node2' => '192.168.10.11',
    'pg-node3' => '192.168.10.12',
    'pg-node4' => '192.168.10.13',
    'pg-node5' => '192.168.10.14',
    'pg-node6' => '192.168.10.15',
  }

  machines.each do |name, ip|
    config.vm.define name do |machine|
      machine.vm.box = "ubuntu/focal64"
      machine.vm.hostname = name
      machine.vm.network :private_network, ip: ip

      machine.vm.provider "virtualbox" do |vb|
        if ['pg-node4', 'pg-node5', 'pg-node6'].include?(name)
          vb.memory = "8192" # 8 GB for these nodes
          vb.cpus = 2
        else
          vb.memory = "16384" # 16 GB for the other nodes
          vb.cpus = 4
        end
      end

      machine.vm.provision "shell", inline: <<-SHELL
        sudo apt-get update
        # ... Установка дополнительных пакетов и зависимостей
      SHELL
    end
  end
end
```
- *запускаем файл:*
```bash
vagrant up
```
---------------------------------------------------------------------

2. Далее разворачиваем на хостах pg-node1 - pg-node3 PostgreSQL
- *Устанавливаем PostgreSQL 15:*
```bash
sudo apt-get install -y wget ca-certificates
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee  /etc/apt/sources.list.d/pgdg.list
sudo apt-get update
sudo apt-get install -y postgresql-15
```
- *Останаливаем кластер для дальнейшей настройки patroni:*
```bash
systemctl stop postgresql
pg_lsclusters

Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 down   postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
```
- *Задаём имя хостов с PostgreSQL:*
```bash
sudo hostnamectl set-hostname pg_node1
sudo hostnamectl set-hostname pg_node2
sudo hostnamectl set-hostname pg_node3
```
- *Устанавливаем необходимые пакеты*
```bash
sudo apt install net-tools
sudo apt -y install python3 python3-pip
sudo -H pip install --upgrade testresources
sudo -H pip install --upgrade setuptools
sudo -H pip install psycopg2
sudo -H pip install patroni
sudo -H pip install python-etcd
```
------------------------------------------------

3. Устанавливаем и настраиваем ETCD
- *Задаём имя хоста:*
```bash
sudo hostnamectl set-hostname etcd_node
``` 
- *Устанавливаем необходимые пакеты:*
```bash
sudo apt install net-tools
sudo apt install -y etcd
```

- *Настраиваем конфигурацию ETCD:*
```bash
sudo nano /etc/default/etcd

ETCD_LISTEN_PEER_URLS="http://192.168.10.13:2380,http://localhost:7001"
ETCD_LISTEN_CLIENT_URLS="http://localhost:2379,http://192.168.10.13:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.10.13:2380"
ETCD_INITIAL_CLUSTER="default=http://192.168.10.13:2380,"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.10.13:2379"
```
- *Рестартуем сервис и проверяем статус:*
```bash
systemctl restart etcd
```
```bash
systemctl status etcd

● etcd.service - etcd - highly-available key value store
     Loaded: loaded (/lib/systemd/system/etcd.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2023-09-29 13:02:31 UTC; 99ms ago
       Docs: https://github.com/coreos/etcd
             man:etcd
   Main PID: 16777 (etcd)
      Tasks: 9 (limit: 9494)
     Memory: 19.7M
     CGroup: /system.slice/etcd.service
             └─16777 /usr/bin/etcd

Sep 29 13:02:31 etcdnode etcd[16777]: 8e9e05c52164694d became candidate at term 3
Sep 29 13:02:31 etcdnode etcd[16777]: 8e9e05c52164694d received MsgVoteResp from 8e9e05c52164694d at term 3
Sep 29 13:02:31 etcdnode etcd[16777]: 8e9e05c52164694d became leader at term 3
Sep 29 13:02:31 etcdnode etcd[16777]: raft.node: 8e9e05c52164694d elected leader 8e9e05c52164694d at term 3
Sep 29 13:02:31 etcdnode etcd[16777]: published {Name:etcdnode ClientURLs:[http://192.168.10.13:2379]} to cluster cdf818194>
Sep 29 13:02:31 etcdnode systemd[1]: Started etcd - highly-available key value store.
Sep 29 13:02:31 etcdnode etcd[16777]: ready to serve client requests
Sep 29 13:02:31 etcdnode etcd[16777]: serving insecure client requests on 192.168.10.13:2379, this is strongly discouraged!
Sep 29 13:02:31 etcdnode etcd[16777]: ready to serve client requests
Sep 29 13:02:31 etcdnode etcd[16777]: serving insecure client requests on 127.0.0.1:2379, this is strongly discouraged!
```

-----------------------------
4. Настраиваем Patroni
- *Создаём конфигурационный файл на каждой ноде с PostgreSQL, меняем name и ip адреса:*

```bash
sudo nano /etc/patroni.yml
```
```yaml
scope: postgres
namespace: /db/
name: pg_node1

restapi:
  listen: 192.168.10.10:8008
  connect_address: 192.168.10.10:8008

etcd:
  host: 192.168.10.13:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        logging_collector: "on"
        max_wal_senders: 5
        max_replication_slots: 5

  initdb:
  - encoding: UTF8
  - data-checksums

  pg_hba:
  - host replication replicator 127.0.0.1/32 md5
  - host replication replicator 192.168.10.10/0 md5
  - host replication replicator 192.168.10.11/0 md5
  - host replication replicator 192.168.10.12/0 md5
  - host all all 0.0.0.0/0 md5

  users:
    admin:
      password: admin
      options:
        - createrole
        - createdb


postgresql:
  listen: 192.168.10.10:5432
  connect_address: 192.168.10.10:5432
  data_dir: /data/patroni/
  bin_dir: /usr/lib/postgresql/15/bin/
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: admin
    superuser:
      username: postgres
      password: admin
  parameters:
    unix_socket_directories: '.'

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
```
- *Создаём нужную директорию и назначаем права:*
```bash
sudo mkdir -p /data/patroni
sudo chown postgres:postgres /data/patroni
sudo chmod 700 /data/patroni/
```
- *Создаём сервисный файл для автозапуска:*
```bash
sudo nano /etc/systemd/system/patroni.service
```
```makefile
[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL
After=syslog.target network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no

[Install]
WantedBy=multi-user.target
```
- *Добавляем initdb в переменную PATH:*
```bash
export PATH=$PATH:/usr/lib/postgresql/15/bin/
```

- *Обновляем systemd:*
```bash
sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni
```
- *Проверяем статус Patroni*
```bash
sudo systemctl status patroni

● patroni.service - Runners to orchestrate a high-availability PostgreSQL
     Loaded: loaded (/etc/systemd/system/patroni.service; disabled; vendor preset: enabled)
     Active: active (running) since Fri 2023-09-29 14:54:10 UTC; 17min ago
   Main PID: 13039 (patroni)
      Tasks: 15 (limit: 19155)
     Memory: 151.9M
     CGroup: /system.slice/patroni.service
             ├─13039 /usr/bin/python3 /usr/local/bin/patroni /etc/patroni.yml
             ├─13097 /usr/lib/postgresql/15/bin/postgres -D /data/patroni/ --config-file=/data/patroni/postgresql.conf --li>
             ├─13098 postgres: postgres: logger
             ├─13100 postgres: postgres: checkpointer
             ├─13101 postgres: postgres: background writer
             ├─13104 postgres: postgres: walwriter
             ├─13105 postgres: postgres: autovacuum launcher
             ├─13106 postgres: postgres: logical replication launcher
             ├─13109 postgres: postgres: postgres postgres 192.168.10.10(37430) idle
             ├─13127 postgres: postgres: walsender replicator 192.168.10.11(36088) streaming 0/404B410
             └─13130 postgres: postgres: walsender replicator 192.168.10.12(47212) streaming 0/404B410

Sep 29 15:10:11 pgnode1 patroni[13039]: 2023-09-29 15:10:11,473 INFO: no action. I am (pg_node1), the leader with the lock
Sep 29 15:10:21 pgnode1 patroni[13039]: 2023-09-29 15:10:21,524 INFO: no action. I am (pg_node1), 
```
```bash
patronictl -c /etc/patroni.yml list

+ Cluster: postgres (7284261315432325903) -------+----+-----------+
| Member   | Host          | Role    | State     | TL | Lag in MB |
+----------+---------------+---------+-----------+----+-----------+
| pg_node1 | 192.168.10.10 | Replica | streaming | 11 |         0 |
| pg_node2 | 192.168.10.11 | Replica | running   | 10 |         0 |
| pg_node3 | 192.168.10.12 | Leader  | running   | 11 |           |
+----------+---------------+---------+-----------+----+-----------+
```
- *Если есть необходимость подключиться к базе с хоста, т.к управление базой осуществляет patroni,используем следующую команду:*
```bash
psql -h 192.168.10.10 -U postgres -d postgres
```

# Полезные команды
- *Рестарт одной ноды*
```bash
patronictl -c /etc/patroni.yml restart postgres pg_node1
```
- *Рестарт всего кластера*
```bash
patronictl -c /etc/patroni.yml restart postgres
```
- *Рестарт reload кластера*
```bash
patronictl -c /etc/patroni.yml reload postgres
```
- *Плановое переключение*
```bash
patronictl -c /etc/patroni.yml switchover postgres
```
- *Реинициализации ноды*
```bash
patronictl -c /etc/patroni.yml reinit postgres pg_node1
```

----------------------------------------
5. Устанавливаем и настроиваем HAProxy
- *Задаём имя хоста:*
```bash
sudo hostnamectl set-hostname haproxy_node
```
- *Устанавливаем необходимые пакеты:*
```bash
sudo apt install net-tools
sudo apt install -y haproxy
```
- *Создаём копию и редактируем конфигурационный файл:*
```bash
sudo cp -p /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg-orig
sudo nano /etc/haproxy/haproxy.cfg
```
```makefile
global
    maxconn 100
    log     127.0.0.1 local2

defaults
    log global
    mode tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s
 
listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /
 
listen postgres
    bind *:5000
    option httpchk
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg_node1 192.168.10.10:5432 maxconn 100 check port 8008
    server pg_node2 192.168.10.11:5432 maxconn 100 check port 8008
    server pg_node3 192.168.10.12:5432 maxconn 100 check port 8008
```
- *Перезапускаем HAProxy и проверяем состояние:*
```bash
sudo systemctl restart haproxy
haproxy -c -f /etc/haproxy/haproxy.cfg
Configuration file is valid

root@pg-node5:/home/vagrant# grep 'haproxy' /var/log/syslog | tail -n 50
Sep 29 12:16:57 ubuntu-focal haproxy[16388]: [NOTICE] 271/121657 (16388) : New worker #1 (16405) forked
Sep 29 16:14:13 pg-node5 systemd[1]: haproxy.service: Succeeded.
Sep 29 17:25:56 pg-node5 systemd[1]: haproxy.service: Succeeded.
Sep 29 20:12:44 pg-node5 systemd[1]: haproxy.service: Succeeded.
Sep 30 20:22:11 pg-node5 systemd[1]: haproxy.service: Succeeded.
```
- *Пробрасываем порт 7000 и подключаемся через http:*
```makefile
http://192.168.10.14:7000/
```
![image.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-1.png)

---------------------------------------------------------

6. Устанавливаем и настраиваем мониторинг черег Grafana
- *Для начала установим Grafana. Ставим необходимые пакеты*
```bash
sudo apt-get install -y apt-transport-https 
```
- *Добавляем ключ в репозиторий:*
```bash
sudo wget -q -O /usr/share/keyrings/grafana.key https://packages.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb beta main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get install -y software-properties-common wget
```
- *Обновляем пакетный менеджер:*
```bash
sudo apt-get update
```
- *Ставим Grafana:*
```bash
apt install grafana
```
- *Задаём права:*
```bash
sudo chown -R grafana:grafana /usr/share/grafana
sudo chown -R grafana:grafana /var/log/grafana
sudo chown -R grafana:grafana /var/lib/grafana
sudo chown -R grafana:grafana /etc/grafana
```
- *Перезагружает демона systemctl:*
```bash
systemctl daemon-reload
```
- *Запускаем grafana и смотрим статус:*
```bash
systemctl start grafana-server
systemctl status grafana-server
root@pg-node6:/home/vagrant# systemctl status grafana-server
● grafana-server.service - Grafana instance
     Loaded: loaded (/lib/systemd/system/grafana-server.service; disabled; vendor preset: enabled)
     Active: active (running) since Sun 2023-10-01 13:29:04 UTC; 3min 19s ago
       Docs: http://docs.grafana.org
   Main PID: 27144 (grafana)
      Tasks: 7 (limit: 9494)
     Memory: 83.1M
     CGroup: /system.slice/grafana-server.service
             └─27144 /usr/share/grafana/bin/grafana server --config=/etc/grafana/grafana.ini --pidfile=/run/grafana/grafana>

Oct 01 13:30:53 pg-node6 grafana[27144]: logger=modules t=2023-10-01T13:30:53.941552377Z level=info msg="All modules health>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=ngalert.state.manager t=2023-10-01T13:30:53.941552377Z level=info msg="Warm>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=ngalert.state.manager t=2023-10-01T13:30:53.941552377Z level=info msg="Stat>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=ngalert.scheduler t=2023-10-01T13:30:53.941552377Z level=info msg="Starting>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=ticker t=2023-10-01T13:30:53.941552377Z level=info msg=starting first_tick=>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=grafanaStorageLogger t=2023-10-01T13:30:53.941552377Z level=info msg="stora>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=ngalert.multiorg.alertmanager t=2023-10-01T13:30:53.941552377Z level=info m>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=grafana.update.checker t=2023-10-01T13:30:53.941552377Z level=info msg="Upd>
Oct 01 13:30:53 pg-node6 grafana[27144]: logger=plugins.update.checker t=2023-10-01T13:30:53.941552377Z level=info msg="Upd>
Oct 01 13:31:50 pg-node6 grafana[27144]: logger=infra.usagestats t=2023-10-01T13:31:50.068925942Z level=info msg="Usage sta>
```
- *Пробрасываем порт 3000 и проверяем с хоста (user: admin, pass: admin по дефолту):*
```makefile
http://192.168.10.15:3000/
```
![image-1.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-2.png)

----------------------------------
7. Устанавливаем и настраиваем Prometheus (на ноду с Grafana)
- *Скачиваем дистрибутив:*
```bash
wget https://github.com/prometheus/prometheus/releases/download/v2.37.1/prometheus-2.37.1.linux-amd64.tar.gz
```
- *Распаковываем архив:*
```bash
tar -xvf prometheus-2.37.1.linux-amd64.tar.gz
```
- *Копируем бинарник в дирректорию:*
```bash
cp prometheus-2.37.1.linux-amd64/prometheus /usr/bin
```
- *Создаём нужные директории:*
```bash
mkdir /etc/prometheus
mkdir /var/lib/prometheus
```
- *Копируем необходимые утилиты для работы в вебинтерфейсе:*
```bash
cp -r /home/vagrant/prometheus-2.37.1.linux-amd64/consoles /etc/prometheus
cp -r /home/vagrant/prometheus-2.37.1.linux-amd64/console_libraries /etc/prometheus
```
- *Создаём конфигурационный файл prometheus:*
```bash
nano /etc/prometheus/prometheus.yml
```
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['192.168.10.10:9100', '192.168.10.11:9100', '192.168.10.12:9100', '192.168.10.13:9100', '192.168.10.14:9100', '192.168.10.15:9100']

  - job_name: 'postgres_exporter'
    static_configs:
      - targets: ['192.168.10.15:9187']
```
- *Создаём необходимых пользователей:*
```bash
sudo useradd --no-create-home --shell /bin/false prometheus
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo useradd --no-create-home --shell /bin/false postgres_exporter
```
- *Задаём нужные права (prometheus владелец):*
```bash
sudo chown prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /usr/bin/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus/consoles
sudo chown -R prometheus:prometheus /etc/prometheus/console_libraries
sudo chown -R prometheus:prometheus /etc/prometheus/prometheus.yml
```
- *Напишем сервис для запуска prometheus:*
```bash
sudo nano /etc/systemd/system/prometheus.service
```
```makefile
[Unit]
Description=Prometheus

Wants=network-online.target
After=network-online.targer
[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/bin/prometheus \
--config.file /etc/prometheus/prometheus.yml \
--storage.tsdb.path /var/lib/prometheus/ \
--web.console.templates=/etc/prometheus/consoles \
--web.console.libraries=/etc/prometheus/console_libraries 
[Install]
WantedBy=multi-user.target
```
- *Перезагружает демона systemctl и включаем автозапуск:* 
```bash
systemctl daemon-reload
systemctl enable prometheus
```
*Сервис пока что не запускаем, т.к. необходимо настроить postgres_exporter и node_exporter*

--------------------------------------------

8. Устанавливаем и настраиваем Postgres exporter (на ноду с Grafana)
- *Скачиваем дистрибутив:*
```bash
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.12.0/postgres_exporter-0.12.0.linux-amd64.tar.gz
```
- *Распаковываем архив:*
```bash
tar -xzvf postgres_exporter-0.12.0.linux-amd64.tar.gz
```
- *Копируем бинарник в дирректорию:*
```bash
cp postgres_exporter-0.12.0.linux-amd64/postgres_exporter /usr/bin
```
- *Напишем сервис для запуска postgres_exporter:*
```bash
sudo nano /etc/systemd/system/postgres_exporter.service
```
```makefile
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target

[Service]
Type=simple
Restart=always
User=postgres_exporter
Group=postgres_exporter
Environment=DATA_SOURCE_NAME=postgresql://postgres:admin@192.168.10.14:5000/postgres?sslmode=disable
#Environment=PG_EXPORTER_QUERY_PATH=/etc/prometheus/queries.yaml
ExecStart=/usr/bin/postgres_exporter
[Install]
WantedBy=multi-user.target
```
- *Перезагружает демона systemctl и включаем автозапуск:*
```bash
systemctl daemon-reload
systemctl enable postgres_exporter
```
*#Environment в сервисном файле закоменчен, т.к. планируется в дальнейшем кастомная настройка метрик postgresql*

------------------------------------

9. Далее мы ставим и настраиваем node exporter на каждой ноде
- *Скачиваем дистрибутив:*
```bash
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.0/node_exporter-1.6.0.linux-amd64.tar.gz
```
- *Распаковываем архив:*
```bash
sudo tar xvzf node_exporter-1.6.0.linux-amd64.tar.gz
```
- *Копируем бинарник в дирректорию:*
```bash
cp node_exporter-1.6.0.linux-amd64/node_exporter /usr/bin
```
- *Создаём пользователя:*
```bash
sudo useradd --no-create-home --shell /bin/false node_exporter
```

- *Напишем сервис для запуска postgres_exporter:*
```bash
sudo nano /etc/systemd/system/node_exporter.service
```
```makefile
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/bin/node_exporter
Restart=always
RestartSec=10s
[Install]
WantedBy=multi-user.target
```
- *Перезагружает демона systemctl и включаем автозапуск:*
```bash
systemctl daemon-reload
systemctl enable node_exporter
```
- *Запускаем node_exporter и смотрим статус:*
```bash
systemctl start node_exporter
systemctl status node_exporter
```
```bash
● node_exporter.service - Node Exporter
     Loaded: loaded (/etc/systemd/system/node_exporter.service; enabled; vendor preset: enabled)
     Active: active (running) since Sun 2023-10-01 15:58:57 UTC; 20s ago
   Main PID: 35669 (node_exporter)
      Tasks: 5 (limit: 19155)
     Memory: 2.4M
     CGroup: /system.slice/node_exporter.service
             └─35669 /usr/bin/node_exporter

Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=thermal_zone
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=time
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=timex
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=udp_queues
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=uname
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=vmstat
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=xfs
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.586Z caller=node_exporter.go:117 level=info collector=zfs
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.587Z caller=tls_config.go:274 level=info msg="Listening on" address=[::]:9100
Oct 01 15:58:57 pg-node1 node_exporter[35669]: ts=2023-10-01T15:58:57.587Z caller=tls_config.go:277 level=info msg="TLS is disabled." http2=false address=[::]:9100
```
-------------------------------------

10. Настраиваем метрики для мониторинга в Grafana
- *Запускаем службы postgres_exporter и prometheus*
```bash
systemctl start postgres_exporter
systemctl start prometheus
```
- *Смотрим статус:*
```bash
systemctl status prometheus
```
```bash
● prometheus.service - Prometheus
     Loaded: loaded (/etc/systemd/system/prometheus.service; enabled; vendor preset: enabled)
     Active: active (running) since Sun 2023-10-01 16:03:30 UTC; 37s ago
   Main PID: 29635 (prometheus)
      Tasks: 8 (limit: 9494)
     Memory: 28.3M
     CGroup: /system.slice/prometheus.service
             └─29635 /usr/bin/prometheus --config.file /etc/prometheus/prometheus.yml --storage.tsdb.path /var/lib/promethe>

Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.531Z caller=head.go:536 level=info component=tsdb msg="O>
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.531Z caller=head.go:542 level=info component=tsdb msg="R>
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.532Z caller=head.go:613 level=info component=tsdb msg="W>
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.532Z caller=head.go:619 level=info component=tsdb msg="W>
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.534Z caller=main.go:993 level=info fs_type=EXT4_SUPER_MA>
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.534Z caller=main.go:996 level=info msg="TSDB started"
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.534Z caller=main.go:1177 level=info msg="Loading configu>
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.534Z caller=main.go:1214 level=info msg="Completed loadi>
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.534Z caller=main.go:957 level=info msg="Server is ready >
Oct 01 16:03:30 pg-node6 prometheus[29635]: ts=2023-10-01T16:03:30.535Z caller=manager.go:941 level=info component="rule ma>
```
- *Для проверки метрик экспортёров пробрасываем порты 9100 и 9187 и подключаемся по http:*
```makefile
http://192.168.10.15:9187/
http://192.168.10.15:9100/
```
![image-3.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-3.png)
![image-7.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-7.png)
![image-4.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-4.png)
![image-8.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-8.png)
- *Для просмотра эндпоинтов в prometheus пробрасываем порт 9090 и подключаемся по http:*
```makefile
http://192.168.10.15:9090/
```
![image-9.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-9.png)

- *Настраиваем Data sources и выбираем Prometheus*
![image-10.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-10.png)

- *Далее импортируем готовый дашборд для мониторинга систем, выбираем в качестве источника данных Prometheus. Я выбрал 14513:*
![image-11.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-11.png)
- *На данном дашборде отображается полная информация о нашей системе (все ноды):*

![image-12.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-12.png)

- *Далее настраиваем дашборд для PostgreSQl. Я выбрал в качестве готового варианта id 9628:*
![image-13.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-13.png)

- *Для настройки кастомных метрик от postgres_exporter - создаём файл с метриками:*
```bash
nano /etc/prometheus/queries.yaml
```
```yaml
pg_replication:
  query: "SELECT CASE WHEN NOT pg_is_in_recovery() THEN 0 ELSE GREATEST (0, EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))) END AS lag"
  master: true
  metrics:
    - lag:
        usage: "GAUGE"
        description: "Replication lag behind master in seconds"

pg_postmaster:
  query: "SELECT pg_postmaster_start_time AS start_time_seconds FROM pg_postmaster_start_time()"
  master: true
  metrics:
    - start_time_seconds:
        usage: "GAUGE"
        description: "Time as which postmaster started"

pg_stat_user_tables:
  query: |
   SELECT
     current_database() datname,
     schemaname,
     relname,
     seq_scan,
     seq_tup_read,
     idx_scan,
     idx_tup_fetch,
     n_tup_ins,
     n_tup_upd,
     n_tup_del,
     n_tup_hot_upd,
     n_live_tup,
     n_dead_tup,
     n_mod_since_analyze,
     COALESCE(last_vacuum, '1970-01-01Z') as last_vacuum,
     COALESCE(last_autovacuum, '1970-01-01Z') as last_autovacuum,
     COALESCE(last_analyze, '1970-01-01Z') as last_analyze,
     COALESCE(last_autoanalyze, '1970-01-01Z') as last_autoanalyze,
     vacuum_count,
     autovacuum_count,
     analyze_count,
     autoanalyze_count
   FROM
     pg_stat_user_tables
  metrics:
    - datname:
        usage: "LABEL"
        description: "Name of current database"
    - schemaname:
        usage: "LABEL"
        description: "Name of the schema that this table is in"
    - relname:
        usage: "LABEL"
        description: "Name of this table"
    - seq_scan:
        usage: "COUNTER"
        description: "Number of sequential scans initiated on this table"
    - seq_tup_read:
        usage: "COUNTER"
        description: "Number of live rows fetched by sequential scans"
    - idx_scan:
        usage: "COUNTER"
        description: "Number of index scans initiated on this table"
    - idx_tup_fetch:
        usage: "COUNTER"
        description: "Number of live rows fetched by index scans"
    - n_tup_ins:
        usage: "COUNTER"
        description: "Number of rows inserted"
    - n_tup_upd:
        usage: "COUNTER"
        description: "Number of rows updated"
    - n_tup_del:
        usage: "COUNTER"
        description: "Number of rows deleted"
    - n_tup_hot_upd:
        usage: "COUNTER"
        description: "Number of rows HOT updated (i.e., with no separate index requiered)"
    - n_live_tup:
        usage: "GAUGE"
        description: "Estimated number of live rows"
    - n_dead_tup:
        usage: "GAUGE"
        description: "Estimated number of dead rows"
    - n_mod_since_analyze:
        usage: "GAUGE"
        description: "Estimated numberof rows changed since last analyze"
    - last_vacuum:
        usage: "GAUGE"
        description: "Last time at which this table was manually vacuumed (not counting VACUUM FULL)"
    - last_autovacuum:
        usage: "GAUGE"
        description: "Last time at which this table was vacuumed by the autovacuum daemon"
    - last_analyze:
        usage: "GAUGE"
        description: "Last time at which this table was manually analyzed" 
    - last_autoanalyze:
        usage: "GAUGE"
        description: "Last time at which this table was analyzed by autovacuum daemon"
    - vacuum_count:
        usage: "COUNTER"
        description: "Number of times this table has been manually vacuumed (not counting VACUUM FULL)"
    - autovacuum_count:
        usage: "COUNTER"
        description: "Number of times this table has been vacuumed by the autovacuum daemon"
    - analyze_count:
        usage: "COUNTER"
        description: "Number of times this table has been manually analyzed"
    - autoanalyze_count:
        usage: "COUNTER"
        description: "Number of times this table has been analyzed by the autovacuum daemon"

#current_database() datname: Возвращает имя текущей базы данных.
#schemaname: Название схемы таблицы.
#relname: Название таблицы.
#seq_scan: Количество последовательных (линейных) сканирований таблицы.
#seq_tup_read: Количество строк, прочитанных при последовательном сканировании.
#idx_scan: Количество индексных сканирований таблицы.
#idx_tup_fetch: Количество строк, полученных при помощи индексного сканирования.
#n_tup_ins: Количество вставленных строк.
#n_tup_upd: Количество обновленных строк.
#n_tup_del: Количество удаленных строк.
#n_tup_hot_upd: Количество "горячих" обновлений строк (обновления, которые не приводят к созданию мертвых строк).
#n_live_tup: Количество живых строк в таблице.
#n_dead_tup: Количество мертвых строк в таблице.
#n_mod_since_analyze: Количество изменений строк с момента последнего анализа.
#last_vacuum, last_autovacuum, last_analyze, last_autoanalyze: Время последних операций очистки и анализа, выполненных вручную или автоматически.
#vacuum_count, autovacuum_count, analyze_count, autoanalyze_count: Количество выполненных операций очистки и анализа, выполненных вручную или автоматически.

pg_statio_user_tables:
  query: "SELECT current_database() datname, schemaname, relname, heap_blks_read, heap_blks_hit, idx_blks_read, idx_blks_hit, toast_blks_read, toast_blks_hit, tidx_blks_read, tidx_blks_hit FROM pg_statio_user_tables"
  metrics:
    - datname:
        usage: "LABEL"
        description: "Name of current database"
    - schemaname:
        usage: "LABEL"
        description: "Name of the schema that this table is in"
    - relname:
        usage: "LABEL"
        description: "Name of this table"
    - heap_blks_read:
        usage: "COUNTER"
        description: "Number of disk blocks read from this table"
    - heap_blks_hit:
        usage: "COUNTER"
        description: "Number of buffer hits in this table"
    - idx_blks_read:
        usage: "COUNTER"
        description: "Number of disk blocks read from all indexes on this table"
    - idx_blks_hit:
        usage: "COUNTER"
        description: "Number of buffer hits in all indexes on this table"
    - toast_blks_read:
        usage: "COUNTER"
        description: "Number of disk blocks read from this table's TOAST table (if any)"
    - toast_blks_hit:
        usage: "COUNTER"
        description: "Number of buffer hits in this table's TOAST table (if any)"
    - tidx_blks_read:
        usage: "COUNTER"
        description: "Number of disk blocks read from this table's TOAST table indexes (if any)"
    - tidx_blks_hit:
        usage: "COUNTER"
        description: "Number of buffer hits in this table's TOAST table indexes (if any)"

#current_database() datname: Возвращает имя текущей базы данных.
#schemaname: Название схемы таблицы.
#relname: Название таблицы.
#heap_blks_read: Количество блоков данных, прочитанных из диска.
#heap_blks_hit: Количество блоков данных, прочитанных из кэша (буфера).
#idx_blks_read: Количество блоков индекса, прочитанных из диска.
#idx_blks_hit: Количество блоков индекса, прочитанных из кэша.
#toast_blks_read: Количество блоков TOAST, прочитанных из диска. TOAST — это механизм, который PostgreSQL использует для хранения больших данных.
#toast_blks_hit: Количество блоков TOAST, прочитанных из кэша.
#tidx_blks_read: Количество блоков TOAST-индекса, прочитанных из диска.
#tidx_blks_hit: Количество блоков TOAST-индекса, прочитанных из кэша.


pg_stat_statements:
  query: |
   SELECT
    pg_get_userbyid(userid) as user,
    pg_database.datname,
    pg_stat_statements.queryid,
    pg_stat_statements.calls as calls_total,
    pg_stat_statements.total_time / 1000.0 as seconds_total,
    pg_stat_statements.rows as rows_total,
    pg_stat_statements.blk_read_time / 1000.0 as block_read_seconds_total,
    pg_stat_statements.blk_write_time / 1000.0 as block_write_seconds_total
    FROM pg_stat_statements
    JOIN pg_database
      ON pg_database.oid = pg_stat_statements.dbid
    WHERE
      total_time > (
        SELECT percentile_cont(0.1)
          WITHIN GROUP (ORDER BY total_time)
          FROM pg_stat_statements
      )
    ORDER BY seconds_total DESC
    LIMIT 100
  metrics:
    - user:
        usage: "LABEL"
        description: "The user who executed the statement"
    - datname:
        usage: "LABEL"
        description: "The database in which the statement was executed"
    - queryid:
        usage: "LABEL"
        description: "Internal hash code? computed from the statement's parse tree"
    - calls_total:
        usage: "COUNTER"
        description: "Number of times executed"
    - seconds_total:
        usage: "COUNTER"
        description: "Total time spent in the statement, in seconds"
    - rows_total:
        usage: "COUNTER"
        description: "Total number of rows retrieved or affected by the statement"
    - block_read_seconds_total:
        usage: "COUNTER"
        description: "Total time the statement spent reading blocks, in seconds"
    - block_write_seconds_total:
        usage: "COUNTER"
        description: "Total time the statement spent writing blocks, in seconds"

#pg_get_userbyid(userid) as user: Получение имени пользователя, который выполнил запрос. Идентификатор пользователя (userid) преобразуется в имя пользователя функцией pg_get_userbyid.
#pg_database.datname: Имя базы данных, в которой был выполнен запрос.
#pg_stat_statements.queryid: Идентификатор запроса. Он уникален для каждого уникального текста запроса.
#pg_stat_statements.calls as calls_total: Общее количество вызовов данного SQL-запроса.
#pg_stat_statements.total_time / 1000.0 as seconds_total: Общее время выполнения данного запроса в секундах.
#pg_stat_statements.rows as rows_total: Общее количество строк, возвращенных этим запросом.
#pg_stat_statements.blk_read_time / 1000.0 as block_read_seconds_total: Общее время чтения дисковых блоков этим запросом в секундах.
#pg_stat_statements.blk_write_time / 1000.0 as block_write_seconds_total: Общее время записи на диск этим запросом в секундах.
#percentile_cont(0.1):  выбор 10% самых долго выполняемых запросов.

pg_process_idle:
  query: |
    WITH
      metrics AS (
        SELECT
          application_name,
          SUM(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - state_change))::bigint)::float AS process_idle_seconds_sum,
          COUNT(*) AS process_idle_seconds_count
        FROM pg_stat_activity
        WHERE state = 'idle'
        GROUP BY application_name
      ),
      buckets AS (
        SELECT
          application_name,
          le,
          SUM(
            CASE WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - state_change)) <= le
              THEN 1
              ELSE 0
            END
          )::bigint AS bucket
        FROM
          pg_stat_activity,
          UNNEST(ARRAY[1, 2, 5, 15, 30, 60, 90, 120, 300]) AS le
        GROUP BY application_name, le
        ORDER BY application_name, le
      )
    SELECT
      application_name,
      process_idle_seconds_sum as seconds_sum,
      process_idle_seconds_count as seconds_count,
      ARRAY_AGG(le) AS seconds,
      ARRAY_AGG(bucket) AS seconds_bucket
    FROM metrics JOIN buckets USING (application_name)
    GROUP BY 1, 2, 3
  metrics:
    - application_name:
        usage: "LABEL"
        description: "Application Name"
    - seconds:
        usage: "HISTOGRAM"
        description: "Idle time of server processes"


#metrics AS (...): В этом подзапросе выбираются все процессы, которые в данный момент 
#находятся в состоянии 'idle' (ожидание), и для каждого приложения подсчитывается общее время 
#простоя и количество таких процессов.

#buckets AS (...): В этом подзапросе генерируются "бакеты" времени для каждого приложения, 
#каждый из которых представляет собой количество процессов, которые простаивали 
#не более указанного количества секунд. Например, бакет 1 содержит количество процессов, 
#которые простаивали не более 1 секунды, бакет 2 - не более 2 секунд и т.д.

#SELECT application_name, process_idle_seconds_sum as seconds_sum, process_idle_seconds_count as seconds_count, ARRAY_AGG(le) AS seconds, ARRAY_AGG(bucket) AS seconds_bucket FROM metrics JOIN buckets USING (application_name) GROUP BY 1, 2, 3: 
#Здесь мы объединяем результаты из обоих подзапросов по имени приложения, 
#и группируем результаты по имени приложения, общему времени простоя и количеству процессов простоя. 
#Массивы seconds и seconds_bucket формируются из значений le и bucket соответственно.
```
- *Рскомментим сроку для пути к файлу с кастомными метриками:*
```bash
sudo nano /etc/systemd/system/postgres_exporter.service
```
```makefile
Environment=PG_EXPORTER_QUERY_PATH=/etc/prometheus/queries.yaml
```
- *Задаём нужные права на файл:*
```bash
sudo chown postgres_exporter:postgres_exporter /etc/prometheus
sudo chown -R postgres_exporter:postgres_exporter /etc/prometheus/queries.yaml
```
- *Перезапускаем сервис и смотрим статус:*
```bash
systemctl daemon-reload
systemctl restart postgres_exporter
```
- *Для изменения настроек в дабордах Grafana - переходим на необходмуб панель и нажинаем Edit. Находим нужную метрику в postges_exporter и правим. В моём примере прописал process_start_time_seconds{release="$release", instance="$instance"} * 1000. И нажимаем run queries:*
![image-14.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-14.png)

- *Далее я обнаружил, что кастомные метрики не поступают в экспортер и внёс соответствующие изменения в конфигурационный файл:*
```bash
sudo nano /etc/systemd/system/postgres_exporter.service
```
```makefile
ExecStart=/usr/bin/postgres_exporter --extend.query-path=/etc/prometheus/queries.yaml
```
- *Перезапускаем сервис:*
```bash
systemctl daemon-reload
systemctl restart postgres_exporter
```
- *Для проверки метрик используем следующий запрос:*
```bash
curl http://localhost:9187/metrics | grep pg_postmaste
```
```bash
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0# HELP pg_postmaster_start_time_seconds Time a                                                                                                                                                                 s which postmaster started
# TYPE pg_postmaster_start_time_seconds gauge
pg_postmaster_start_time_seconds{server="192.168.10.14:5000"} 1.696190578e+09
100 96060    0 96060    0     0  91.6M      0 --:--:-- --:--:-- --:--:-- 91.6M
```
- *Далее я обнаружил, что не стоит расширение pg_stat_statements. Внеёс соответствующие изменения в файл конфигурации patroni, а также скорректировал некоторые метрики postgresq. Открываем файл конфигурации patroni на нодах с PostgreSQL:*  
**ВАЖНО. ЭТИ ПАРАМЕТРЫ МЕНЯЕМ В postgresql (НЕ bootstrap) РАЗДЕЛЕ, ТК КЛАСТЕР БЫЛ ИНИЦИАЛИЗИРОВАН И ЭТОТ РАЗДЕЛ ДЛЯ ДИНАМИЧЕСКОЙ КОНФИГУРАЦИИ**
```bash
sudo nano /etc/patroni.yml
```
```yaml
parameters:
  unix_socket_directories: '.'
  shared_preload_libraries: 'pg_stat_statements'
  shared_buffers: '1GB'
  maintenance_work_mem: '256MB'
  checkpoint_completion_target: 0.9
  wal_buffers: '16MB'
  default_statistics_target: 100
  random_page_cost: 1.1
  effective_io_concurrency: 300
  work_mem: '32MB'
  min_wal_size: '1GB'
  max_wal_size: '4GB'
```
- *Перезагружаем patroni:*
```bash
systemctl restart patroni
```
- *Перезапускаем кластер*
```bash
patronictl -c /etc/patroni.yml restart postgres
```
- *Подключаемся к базе:*
```bash
psql -h 192.168.10.10 -U postgres -d postgres
```
- *Проверяем данные параметры:*
```sql
SELECT name, setting 
FROM pg_settings 
WHERE name IN (
    'shared_preload_libraries',
    'shared_buffers',
    'maintenance_work_mem',
    'checkpoint_completion_target',
    'wal_buffers',
    'default_statistics_target',
    'random_page_cost',
    'effective_io_concurrency',
    'work_mem',
    'min_wal_size',
    'max_wal_size'
);
```
```bash
             name             |      setting
------------------------------+--------------------
 checkpoint_completion_target | 0.9
 default_statistics_target    | 100
 effective_io_concurrency     | 300
 maintenance_work_mem         | 262144
 max_wal_size                 | 4096
 min_wal_size                 | 1024
 random_page_cost             | 1.1
 shared_buffers               | 131072
 shared_preload_libraries     | pg_stat_statements
 wal_buffers                  | 2048
 work_mem                     | 32768
(11 rows)
```
- *Теперь переходим в postgres exporter и убедимся, что все метрики отправляются:*
```bash
curl http://localhost:9187/metrics | grep pg_stat_statements
```
```bash
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  3944    0  3944    0     0    255      0 --:--:--  0:00:15 --:--:--   255# HELP pg_settings_pg_stat_statements_max Sets the maximum number of statements tracked by pg_stat_statements.
# TYPE pg_settings_pg_stat_statements_max gauge
pg_settings_pg_stat_statements_max{server="192.168.10.14:5000"} 5000
# HELP pg_settings_pg_stat_statements_save Save pg_stat_statements statistics across server shutdowns.
# TYPE pg_settings_pg_stat_statements_save gauge
pg_settings_pg_stat_statements_save{server="192.168.10.14:5000"} 1
# HELP pg_settings_pg_stat_statements_track_planning Selects whether planning duration is tracked by pg_stat_statements.
# TYPE pg_settings_pg_stat_statements_track_planning gauge
pg_settings_pg_stat_statements_track_planning{server="192.168.10.14:5000"} 0
# HELP pg_settings_pg_stat_statements_track_utility Selects whether utility commands are tracked by pg_stat_statements.
# TYPE pg_settings_pg_stat_statements_track_utility gauge
pg_settings_pg_stat_statements_track_utility{server="192.168.10.14:5000"} 1
100 98488    0 98488    0     0   6375      0 --:--:--  0:00:15 --:--:--  6375
```

---------------------------------------

11. Проверяем работоспособность кластера patroni + postgres  
- *Для того, чтобы убедиться в работоспособности кластера patroni, сымитируем падение ноды:*  
*На тот момент pg_node2 была primary*
![image-15.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-15.png)
```bash
patronictl -c /etc/patroni.yml list
```
```bash
+ Cluster: postgres (7284261315432325903) -------+----+-----------+
| Member   | Host          | Role    | State     | TL | Lag in MB |
+----------+---------------+---------+-----------+----+-----------+
| pg_node1 | 192.168.10.10 | Replica | streaming | 49 |         0 |
| pg_node2 | 192.168.10.11 | Leader  | running   | 49 |           |
| pg_node3 | 192.168.10.12 | Replica | streaming | 49 |         0 |
+----------+---------------+---------+-----------+----+-----------+
```
- *Останавливаем patroni на pg_node2*
```bash
systemctl stop patroni
```
- *Наблюдаем переключение на другую ноду, в моём случае теперь лидером является pg_node1*
![image-16.png](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/img/image-16.png)
```bash
patronictl -c /etc/patroni.yml list
```
```bash
+ Cluster: postgres (7284261315432325903) -------+----+-----------+
| Member   | Host          | Role    | State     | TL | Lag in MB |
+----------+---------------+---------+-----------+----+-----------+
| pg_node1 | 192.168.10.10 | Leader  | running   | 50 |           |
| pg_node3 | 192.168.10.12 | Replica | streaming | 50 |         0 |
+----------+---------------+---------+-----------+----+-----------+
```
- *Восстанавливаем работоспособность patroni на pg_node2*
```bash
systemctl start patroni
```
- *Проверяем*
```bash
patronictl -c /etc/patroni.yml list
```
```bash
+ Cluster: postgres (7284261315432325903) -------+----+-----------+
| Member   | Host          | Role    | State     | TL | Lag in MB |
+----------+---------------+---------+-----------+----+-----------+
| pg_node1 | 192.168.10.10 | Leader  | running   | 50 |           |
| pg_node2 | 192.168.10.11 | Replica | streaming | 50 |         0 |
| pg_node3 | 192.168.10.12 | Replica | streaming | 50 |         0 |
+----------+---------------+---------+-----------+----+-----------+
```

------------------------------------

12. В завершении своей работы я решил сделать нагрузочное тестирование на кластер patroni + postgresql

- *Установим на ноду с HAProxy sysbench:*
```bash
sudo apt-get install sysbench
```
- *Подключаемся к базе с любого хоста, и создаём базу для теста:*
```bash
psql -h 192.168.10.14 -p 5000 -U postgres
```
```sql
CREATE DATABASE testdb;
```
- *Подготавливаем базу данных для теста:*
```bash
sysbench --db-driver=pgsql --table-size=1000000 --tables=24 --threads=1 --pgsql-host=192.168.10.14 --pgsql-port=5000 --pgsql-user=postgres --pgsql-password=admin --pgsql-db=testdb /usr/share/sysbench/oltp_common.lua prepare
```
- *При мониторинге в Gafana также можем наблюдать возросшую активность в момент заливки тестовых данных:*
![Alt text](image-17.png)

- *Далее запускаем тест на сгенерированных тестовых данных:* 
   
**Профиль нагрузки** 
5 запросов чтения (point selects) - 30%.  
5 запросов диапазонного чтения (всего: simple ranges, sum ranges, order ranges, и distinct ranges) - 30%.  
7 запросов записи (2 индексных обновления, 2 неиндексных обновления и 3 операции комбинации удаления и добавления) - 40%.   
  
```bash
sysbench --db-driver=pgsql --tables=24 --table-size=1000000 --threads=10 --time=600 --report-interval=10 --pgsql-host=192.168.10.14 --pgsql-port=5000 --pgsql-user=postgres --pgsql-password=admin --pgsql-db=testdb --rand-type=uniform --point-selects=5 --simple-ranges=1 --sum-ranges=1 --order-ranges=1 --distinct-ranges=1 --index-updates=2 --non-index-updates=2 --delete-inserts=3 /usr/share/sysbench/oltp_read_write.lua run
```
- *В момент нагрузочного тестирования так же наблюдалось плановое переключение ноды в качестве лидера на haproxy:*
![Alt text](image-18.png)
- *В Grafana так же можно увидеть всплеск активности во время тестирования. Можно обратить внимание на transaction (commits / rollbacks):*
![Alt text](image-19.png)

- *Тестирование показало следующие результаты:*
```bash
SQL statistics:
    queries performed:
        read:                            441558
        write:                           490614
        other:                           98124
        total:                           1030296
    transactions:                        49061  (80.80 per sec.)
    queries:                             1030296 (1696.79 per sec.)
    ignored errors:                      1      (0.00 per sec.)
    reconnects:                          0      (0.00 per sec.)

General statistics:
    total time:                          607.2027s
    total number of events:              49061

Latency (ms):
         min:                                    0.00
         avg:                                  123.74
         max:                                36690.33
         95th percentile:                        0.00
         sum:                              6070600.23

Threads fairness:
    events (avg/stddev):           4906.1000/359.17
    execution time (avg/stddev):   607.0600/0.05

```
Статистика SQL:  
  
queries performed:  
read: 441,558 - общее количество выполненных запросов на чтение.  
write: 490,614 - общее количество выполненных запросов на запись.  
other: 98,124 - общее количество выполненных других запросов (в данном контексте, это может быть связано с транзакциями: начало, завершение).  
total: 1,030,296 - общее количество выполненных запросов.  
transactions: 49,061 - общее количество выполненных транзакций, со средним значением 80.80 транзакций в секунду.  
queries: 1,030,296 - общее количество запросов со средним значением 1,696.79 запросов в секунду.  
ignored errors: 1 - одна ошибка была проигнорирована во время теста.  
reconnects: 0 - количество переподключений к базе данных (здесь 0, что хорошо).  
  
Общая статистика:  
  
total time: 607.2027s - общее время тестирования.  
total number of events: 49,061 - общее количество событий (транзакций) во время тестирования.  
  
Задержка (латентность):  
  
min: минимальная задержка была 0 мс.  
avg: средняя задержка составила 123.74 мс.  
max: максимальная задержка достигла 36,690.33 мс.  
95th percentile: 95% всех запросов имели задержку менее 0 мс. Это выглядит странно, потому что 95-й процентиль не может быть меньше среднего значения. Возможно, здесь какая-то ошибка или неточность в выводе.  
sum: суммарная задержка всех запросов составила 6,070,600.23 мс. 
   
Справедливость потоков:  

events (avg/stddev): в среднем каждый из 10 потоков обработал 4,906.1 событий со стандартным отклонением 359.17.  
execution time (avg/stddev): среднее время выполнения для каждого потока составило 607.06 секунд со стандартным отклонением 0.05 секунды.  
  
Обобщая: база данных справилась с нагрузкой, обработав в среднем 80.80 транзакций и 1,696.79 запросов в секунду со средней задержкой 123.74 мс на транзакцию. Однако максимальное время задержки было довольно высоким - это было обусловленно тем, что ранее наблюдалась задержка в нутри моей сети (при ping отправка первых пакетов шла дольше обычного). Не смотря на это - количество транзакций в секунду увеличилось на 12 по сравнею с предыдущими тестированиями.

-----------------------------------------
Считаю, что цели проекта полностью достигнуты:

1) Кластер в связке patroni + postgresql полностью реализован и настроен (ETCD и HAProxy);
2) Оптимизированы настройки конфигурационных параметров моей СУБД, которые помогли превзойти мои предыдущие результаты;
3) Настроен мониторинг всего кластера (вынесено на отдельную ноду postgres exporter)  и состояния каждой ВМ (node eporter), используя в связке prometheus и Grafana;
4) Произведена проверка отказоустойчивости, которая дала ожидаемые результаты;
5) Произведено нагрузочное тестирование, наблюдение изменений отдельных подсистем во время теста.

---------------------------------------------

Проблемы с, которыми я сталкивался:

1) Ранее я хотел реализовать полноценный кластер ETCD для отказоустойчивости данной подсистемы. Наблюдались следующие проблемы: рассинхрон времени на серверах (проблему решил, NAT), внутренния задержка сети (как указывал ранее - иногда наблюдалась долгая отправка первых пакетов). Возможно проблема заключается в последней версии Vagrant 2.3.7 и VirtualBOX 7.0.10, хотя в документации указывалась поддержка их совместимости.
2) Изначально столкнулся с проблемой - установил postgres, и не поставил сервис на disable. Сверху накатил prometheus и после перезапуска появились проблемы с конфигурационными фалами СУБД. Полностью очищал - начинал работу с чистого листа.
3) После установки HAProxy упала одна нода, углублялся в документацию - помогла реинициализация кластера.
4) Postgres eporter не хотел отправлять кастомные метрики. Проблема решена путём добавления в конфигурационный файл прямого пути до файла с кастомными метриками, изначально путь предполагал предустановку утилит PostgreSQL (не назначенны переменные в PATH).
