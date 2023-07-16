# **Нагрузочное тестирование и тюнинг PostgreSQL**

## **Цель:**
### - сделать нагрузочное тестирование PostgreSQL;
### - настроить параметры PostgreSQL для достижения максимальной производительности.

-----------------

1. Развернуть виртуальную машину любым удобным способом. Поставить на неё PostgreSQL 15 любым способом.
- *ВМ разворачивал с помощью Vargrant*
```bash
mkdir Postgres15_VM
cd Postgres15_VM

vagrant init ubuntu/focal64
``````
- *Далее настраивал конфигурацию ВМ в Vagrantfile*
```ruby
Vagrant.configure("2") do |config|

  config.vm.box = "ubuntu/focal64"

  config.vm.provider "virtualbox" do |v|
    v.memory = 4096  # ОЗУ
    v.cpus = 2  # ядра
  end
  
  # Конфигурация диска
  config.vm.disk :disk, size: "10GB", primary: true

  # Скрипт для установки PostgreSQL
  config.vm.provision "shell", inline: <<-SHELL
    sudo apt-get update
    sudo apt-get install -y wget ca-certificates
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee  /etc/apt/sources.list.d/pgdg.list
    sudo apt-get update
    sudo apt-get install -y postgresql-15
  SHELL

end
``````
- *Запускаем машину*
```bash
vagrant up
``````

-------------------

2. Настроить кластер PostgreSQL 15 на максимальную производительность не обращая внимание на возможные проблемы с надежностью в случаеаварийной перезагрузки виртуальной машины.
- *Для начала мы посмотрим текущие настройки параметров СУБД*
```bash
# Вход в PostgreSQL через учетную запись postgres
sudo -u postgres psql -c "
SELECT name AS parameter, setting AS value 
FROM pg_settings 
WHERE name IN (
    'max_connections', 
    'shared_buffers', 
    'effective_cache_size', 
    'maintenance_work_mem', 
    'checkpoint_completion_target', 
    'wal_buffers', 
    'default_statistics_target', 
    'random_page_cost', 
    'effective_io_concurrency', 
    'work_mem', 
    'min_wal_size', 
    'max_wal_size'
);"
``````
- *Получаем следующие параметры:*  
  
| Parameter                   | Value  |
|-----------------------------|--------|
| checkpoint_completion_target| 0.9    |
| default_statistics_target   | 500    |
| effective_cache_size        | 393216 |
| effective_io_concurrency    | 2      |
| maintenance_work_mem        | 524288 |
| max_connections             | 40     |
| max_wal_size                | 16384  |
| min_wal_size                | 4096   |
| random_page_cost            | 4      |
| shared_buffers              | 131072 |
| wal_buffers                 | 2048   |
| work_mem                    | 6553   |


max_connections: Этот параметр определяет максимальное количество параллельных соединений, которые сервер PostgreSQL может обрабатывать одновременно. По умолчанию это число установлено в 100, но в зависимости от нагрузки и ресурсов системы оно может быть увеличено.

shared_buffers: Этот параметр определяет количество памяти, выделенной PostgreSQL для кэширования данных. Увеличение этого параметра может улучшить производительность, поскольку больше данных может быть кэшировано в памяти, что приводит к меньшему количеству дорогостоящих обращений к диску.

effective_cache_size: Этот параметр помогает PostgreSQL оценить, сколько памяти доступно для кэширования операционной системой и PostgreSQL вместе. Это влияет на выбор планировщика запросов между планами запросов, которые могут быть быстрее при наличии большого количества кэша, и планами, которые могут быть быстрее при отсутствии кэша.

maintenance_work_mem: Этот параметр определяет максимальное количество памяти, которое может быть использовано при выполнении операций обслуживания, таких как VACUUM, CREATE INDEX и ALTER TABLE.

checkpoint_completion_target: Этот параметр является коэффициентом, определяющим, какую часть времени между проверками PostgreSQL должен потратить на запись данных на диск. Это помогает сгладить нагрузку на диск, избегая всплесков записи.

wal_buffers: Этот параметр определяет количество памяти, выделенной для буфера журнала записи (Write-Ahead Log, WAL). Буфер WAL используется для временного хранения данных перед их записью на диск.

default_statistics_target: Этот параметр определяет количество строк, которые PostgreSQL должен собрать для генерации статистики для планировщика запросов. Более точная статистика может привести к более оптимальным планам запросов, но также требует больше времени для сбора.

random_page_cost: Этот параметр является оценкой стоимости чтения случайной страницы с диска. Он используется планировщиком запросов для выбора наиболее эффективного плана запроса.

effective_io_concurrency: Этот параметр используется для указания планировщику запросов, сколько одновременных операций ввода-вывода может быть выполнено параллельно.

work_mem: Этот параметр определяет количество памяти, которое может быть использовано каждым сортировочным или хеш-операцией во время выполнения запроса.

min_wal_size и max_wal_size: Эти параметры определяют минимальный и максимальный размер дискового пространства, которое PostgreSQL может использовать для хранения WAL-файлов.  
  
  
- *Далее мы инициализируем базу для pgbanch от пользователя postgres, и запускаем тест*
```bash
sudo su - postgres
``````
```bash
pgbench -i postgres

dropping old tables...
NOTICE:  table "pgbench_accounts" does not exist, skipping
NOTICE:  table "pgbench_branches" does not exist, skipping
NOTICE:  table "pgbench_history" does not exist, skipping
NOTICE:  table "pgbench_tellers" does not exist, skipping
creating tables...
generating data (client-side)...
100000 of 100000 tuples (100%) done (elapsed 0.10 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 0.28 s (drop tables 0.00 s, create tables 0.02 s, client-side generate 0.18 s, vacuum 0.04 s, primary keys 0.05 s).
``````
```bash
pgbench -c 10 -t 1000 postgres

pgbench (15.3 (Ubuntu 15.3-1.pgdg20.04+1))
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 10
number of threads: 1
maximum number of tries: 1
number of transactions per client: 1000
number of transactions actually processed: 10000/10000
number of failed transactions: 0 (0.000%)
latency average = 6.564 ms
initial connection time = 57.028 ms
tps = 1523.556004 (without initial connection time)
``````

- *Далее мы настроиваем базу на производительность. Для подбора отимальных параметров я использовал калькулятор https://pgtune.leopard.in.ua*  
*Параметры подбирались с учётом конфигурации машины для 80 активных подключений (max_connections = 80)*
```ruby
max_connections = 80
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 6553kB
min_wal_size = 1GB
max_wal_size = 4GB
``````

- *Применяем данные параметры и перезапускаем кластер*
*Подключаемся к psql*
```bash
sudo -i -u postgres psql
``````
*Меняем параметры*
```sql
ALTER SYSTEM SET max_connections = 80;
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET effective_cache_size = '3GB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET work_mem = '6553kB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET max_wal_size = '4GB';
``````
*Применяем изменения*
```sql
SELECT pg_reload_conf();
``````
*Перезапускаем кластер*
```bash
systemctl restart postgresql
``````
3. *Нагрузить кластер через утилиту через утилиту pgbench (https://postgrespro.ru/docs/postgrespro/14/pgbench).* 
- *Тестируем*
```bash
sudo su - postgres

pgbench -i postgres

dropping old tables...
creating tables...
generating data (client-side)...
100000 of 100000 tuples (100%) done (elapsed 0.05 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 0.19 s (drop tables 0.01 s, create tables 0.00 s, client-side generate 0.11 s, vacuum 0.03 s, primary keys 0.04 s).
``````
```bash
pgbench -c 10 -t 1000 postgres

pgbench (15.3 (Ubuntu 15.3-1.pgdg20.04+1))
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 10
number of threads: 1
maximum number of tries: 1
number of transactions per client: 1000
number of transactions actually processed: 10000/10000
number of failed transactions: 0 (0.000%)
latency average = 5.981 ms
initial connection time = 56.620 ms
tps = 1671.889370 (without initial connection time)
``````
---------------

4. *Написать какого значения tps удалось достичь, показать какие параметры в
какие значения устанавливали и почему* 
- *Сравниваем тесты*  
  
tps во втором тесте выше (1671.889370 против 1523.556004), что указывает на более высокую производительность.  
  
Средняя задержка во втором тесте ниже (5.981 ms против 6.564 ms), что указывает на более быстрое время отклика.  
  
Время инициализации соединения немного меньше во втором тесте (56.620 ms против 57.028 ms), но разница незначительна и скорее всего не будет иметь большого влияния на общую производительность.  
  
Параметры с объяснением, которые я устанавливал, указывал выше.

----------------

5. Задание со *: аналогично протестировать через утилиту https://github.com/Percona-Lab sysbench-tpcc (требует установки https://github.com/akopytov/sysbench)
- *Устанавливаем зависимости:*
```bash
sudo apt-get update
sudo apt-get install make automake libtool pkg-config libaio-dev
``````
- *Скачаем и распакуем исходный код sysbench:*
```bash
wget https://github.com/akopytov/sysbench/archive/master.zip
unzip master.zip
``````
- *Запускаем следующие команды для сборки и установки sysbench:*
```bash
./autogen.sh
./configure
make
sudo make install
``````
*Получил ошибку, установил зависимости следующим образом:*
```bash
sudo apt-get install autoconf automake libtool make libmysqlclient-dev libpq-dev libssl-dev
``````
- *Выполняем предыдущий шаг и проверяем версию*
```bash
sysbench --version

sysbench 1.1.0
``````
*Пытался запустить подготовку к тестированию, также получил ошибку. Пришёл к выводу, что версия не подходит, решил проделать всё заново*
```bash
/home/vagrant/sysbench-tpcc/tpcc.lua --pgsql-host=localhost --pgsql-port=5432 --pgsql-user=postgres --pgsql-password=postgres --pgsql-db=postgres --time=60 --threads=2 --report-interval=1 --tables=2 --scale=100 --use_fk=0 prepare
``````
- *Удаляем текущую установку sysbench:*
```bash
sudo make uninstall
``````
- *Переходим в каталог, в котором мы хотим клонировать репозиторий sysbench*
```bash
cd ~
``````
- *Клонируем репозиторий sysbench из GitHub:*
```bash
git clone https://github.com/akopytov/sysbench.git
```
- *Перейдите в новый каталог sysbench:*
```bash
cd sysbench
``````
- *Запускаем скрипт для генерации конфигурационных файлов:*
```bash
./autogen.sh
``````
- *Сконфигурируем проект. Если мы хотим поддержку PostgreSQL, включаем его при настройке. --prifix это путь до директории*
```bash
./configure --prefix=/usr --with-pgsql
```
- *Собираем проект:*
```bash
make
``````
- *Устанавливаем sysbench:*
```bash
sudo make install
``````
- *Проверяем версию*
```bash
sysbench --version

sysbench 1.1.0-2ca9e3f
``````
- *Подготавливаем данные для тестирования*
```bash
cd /home/vagrant/sysbench-tpcc/
/usr/bin/sysbench ./tpcc.lua --db-driver=pgsql --pgsql-host=localhost --pgsql-port=5432 --pgsql-user=postgres --pgsql-password=postgres --pgsql-db=postgres --time=60 --threads=2 --report-interval=1 --tables=2 --scale=30 --use_fk=0 prepare

sysbench 1.1.0-2ca9e3f (using bundled LuaJIT 2.1.0-beta3)

Initializing worker threads...

DB SCHEMA public
Creating tables: 2

DB SCHEMA public
Creating tables: 1

Adding indexes 1 ...
Waiting on tables 30 sec
Adding indexes 2 ...
Waiting on tables 30 sec

loading tables: 1 for warehouse: 1
loading tables: 1 for warehouse: 2
...
``````
/usr/bin/sysbench: Путь к исполняемому файлу sysbench.  
./tpcc.lua: Путь к файлу скрипта tpcc.lua, который содержит логику теста TPC-C.  
--db-driver=pgsql: Указывает sysbench использовать драйвер для работы с PostgreSQL.  
--pgsql-host=localhost: Указывает хост базы данных PostgreSQL (в данном случае, локальный хост).  
--pgsql-port=5432: Указывает порт, на котором запущен сервер PostgreSQL.  
--pgsql-user=postgres: Указывает имя пользователя для подключения к базе данных PostgreSQL.  
--pgsql-password=postgres: Указывает пароль для подключения к базе данных PostgreSQL.  
--pgsql-db=postgres: Указывает имя базы данных PostgreSQL, на которой будет выполняться тест.  
--time=60: Определяет длительность выполнения теста в секундах (в данном случае, 60 секунд).  
--threads=2: Указывает количество потоков, которые будут использоваться для выполнения теста (в данном случае, 2 потока).  
--report-interval=1: Определяет интервал вывода отчета в секундах (в данном случае, каждую секунду).  
--tables=2: Указывает количество таблиц, которые будут созданы и использованы в тесте (в данном случае, 2 таблицы).  
--scale=100: Определяет масштаб данных, т.е. количество записей в таблицах, которые будут сгенерированы (в данном случае, масштаб 100).  
--use_fk=0: Указывает, будет ли использоваться ограничение внешнего ключа в тесте (в данном случае, отключено).  

- *Запускаем тестирование:*
```bash
/usr/bin/sysbench /home/vagrant/sysbench-tpcc/tpcc.lua --db-driver=pgsql --pgsql-host=localhost --pgsql-port=5432 --pgsql-user=postgres --pgsql-password=postgres --pgsql-db=postgres --time=60 --threads=2 --report-interval=1 --tables=2 --scale=30 --use_fk=0 run

[ 1s ] thds: 2 tps: 33.91 qps: 943.56 (r/w/o: 423.91/445.85/73.81) lat (ms,95%): 248.83 err/s 0.00 reconn/s: 0.00
[ 2s ] thds: 2 tps: 66.00 qps: 1830.97 (r/w/o: 835.99/862.99/132.00) lat (ms,95%): 84.47 err/s 0.00 reconn/s: 0.00
[ 3s ] thds: 2 tps: 65.01 qps: 2135.47 (r/w/o: 987.22/1018.23/130.03) lat (ms,95%): 75.82 err/s 1.00 reconn/s: 0.00
[ 4s ] thds: 2 tps: 76.04 qps: 1918.92 (r/w/o: 879.42/885.42/154.07) lat (ms,95%): 52.89 err/s 1.00 reconn/s: 0.00
...

SQL statistics:
    queries performed:
        read:                            56564
        write:                           58517
        other:                           8768
        total:                           123849
    transactions:                        4370   (72.77 per sec.)
    queries:                             123849 (2062.48 per sec.)
    ignored errors:                      30     (0.50 per sec.)
    reconnects:                          0      (0.00 per sec.)

Throughput:
    events/s (eps):                      72.7743
    time elapsed:                        60.0487s
    total number of events:              4370

Latency (ms):
         min:                                    0.38
         avg:                                   27.47
         max:                                 5088.31
         95th percentile:                       82.96
         sum:                               120030.69

Threads fairness:
    events (avg/stddev):           2185.0000/27.00
    execution time (avg/stddev):   60.0153/0.02
``````

**SQL statistics: Описывает, сколько и каких запросов было выполнено.**  
read: Количество выполненных операций чтения.  
write: Количество выполненных операций записи.  
other: Количество выполненных операций, не являющихся чтением или записью.  
total: Общее количество выполненных операций.  
transactions: Общее количество транзакций. В вашем случае, 72.77 транзакций в секунду.  
ignored errors: Количество ошибок, которые были проигнорированы в процессе тестирования.  
reconnects: Количество повторных подключений к базе данных.  
  
**Throughput: Объем работы, выполненной за единицу времени.**  
events/s (eps): Количество событий в секунду, что в данном контексте эквивалентно количеству транзакций в секунду.  
total number of events: Общее количество событий за весь период испытаний.  
  
**Latency (ms): Задержка выполнения операций.**  
min: Минимальное время ответа.  
avg: Среднее время ответа.  
max: Максимальное время ответа.  
95th percentile: 95% всех запросов были обработаны быстрее указанного времени. Это полезно для понимания "худшего" времени отклика, которое встречается в большинстве случаев.  
sum: Суммарное время выполнения всех операций. 
   
**Threads fairness: Равномерность распределения работы между потоками.**  
events (avg/stddev): Среднее количество событий на поток и стандартное отклонение.  
execution time (avg/stddev): Среднее время выполнения на поток и стандартное отклонение.  
  
Данные тесты показывают, что моя система способна обрабатывать около 73 транзакции в секунду (или около 2062 запроса в секунду), с средним временем отклика около 27 миллисекунд и 95-м процентилем в 83 миллисекунды.

- *Т.к. мы не меняли параметры кластера с предыдущего раза, попробуем протестировать со следующими параметрами:*  
  
max_connections = 100          # Отражает максимальное количество параллельных соединений. Увеличение этого параметра может потребовать больше ресурсов. Начните с 100 и в случае необходимости скорректируйте.

shared_buffers = 1GB           # Это кэш базы данных в памяти. Обычно устанавливается в размере от 15% до 25% от общего объема оперативной памяти.

effective_cache_size = 2.5GB   # Это оценка того, сколько памяти операционная система и дисковый кэш могут предоставить для кэширования БД, обычно устанавливается в размере от 50% до 75% от общего объема оперативной памяти.

maintenance_work_mem = 256MB   # Это максимальное количество памяти для операций обслуживания, таких как VACUUM, CREATE INDEX и другие.

checkpoint_completion_target = 0.9   # Это целевое значение, к которому система старается приблизиться в процессе работы. Увеличение этого значения позволит системе более равномерно распределять нагрузку, но может увеличить время восстановления в случае сбоя.

wal_buffers = 16MB           # Контролирует размер буфера для записи журналов. По умолчанию - 16MB.

default_statistics_target = 100   # Этот параметр определяет, сколько строк будут собраны статистическим анализатором для каждого столбца. Значение по умолчанию обычно подходит для большинства ситуаций.

random_page_cost = 1.1       # Значение по умолчанию обычно 4.0, но для более быстрых дисков, таких как SSD, рекомендуется установить значение ниже, примерно 1.1.

effective_io_concurrency = 300   # Для машин с SSD этот параметр можно увеличить до числа одновременных операций чтения, которые может обработать ваш SSD.

work_mem = 32MB               # Этот параметр контролирует максимальное количество памяти, которое будет использоваться для внутренних операций сортировки и хэширования. Относительно безопасное начальное значение - 32MB.

min_wal_size = 1GB
max_wal_size = 4GB            # min и max wal_size контролируют размер WAL. Большой размер может улучшить производительность больших операций записи, но требует больше дискового пространства.

```sql
ALTER SYSTEM SET max_connections = 100;
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET effective_cache_size = '2.5GB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 300;
ALTER SYSTEM SET work_mem = '32MB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET max_wal_size = '4GB';
``````
*Применяем изменения*
```sql
SELECT pg_reload_conf();
``````
*Перезапускаем кластер*
```bash
systemctl restart postgresql
```
*Повторно тестируем с новыми параметрами*
```bash
cd /home/vagrant/sysbench-tpcc/

/usr/bin/sysbench /home/vagrant/sysbench-tpcc/tpcc.lua --db-driver=pgsql --pgsql-host=localhost --pgsql-port=5432 --pgsql-user=postgres --pgsql-password=postgres --pgsql-db=postgres --time=60 --threads=2 --report-interval=1 --tables=2 --scale=30 --use_fk=0 run

sysbench 1.1.0-2ca9e3f (using bundled LuaJIT 2.1.0-beta3)

Running the test with following options:
Number of threads: 2
Report intermediate results every 1 second(s)
Initializing random number generator from current time


Initializing worker threads...

DB SCHEMA public
DB SCHEMA public
Threads started!

[ 1s ] thds: 2 tps: 85.82 qps: 2266.32 (r/w/o: 1026.88/1061.81/177.63) lat (ms,95%): 70.55 err/s 0.00 reconn/s: 0.00
[ 2s ] thds: 2 tps: 94.03 qps: 2267.65 (r/w/o: 1028.29/1051.30/188.05) lat (ms,95%): 73.13 err/s 0.00 reconn/s: 0.00
[ 3s ] thds: 2 tps: 113.01 qps: 3058.15 (r/w/o: 1391.07/1441.07/226.01) lat (ms,95%): 51.94 err/s 0.00 reconn/s: 0.00
...

SQL statistics:
    queries performed:
        read:                            89670
        write:                           92967
        other:                           13780
        total:                           196417
    transactions:                        6875   (114.52 per sec.)
    queries:                             196417 (3271.81 per sec.)
    ignored errors:                      44     (0.73 per sec.)
    reconnects:                          0      (0.00 per sec.)

Throughput:
    events/s (eps):                      114.5200
    time elapsed:                        60.0332s
    total number of events:              6875

Latency (ms):
         min:                                    0.78
         avg:                                   17.46
         max:                                  259.60
         95th percentile:                       51.94
         sum:                               120008.20

Threads fairness:
    events (avg/stddev):           3437.5000/42.50
    execution time (avg/stddev):   60.0041/0.01
``````

Новые результаты тестирования показывают улучшение производительности по сравнению с предыдущими.  

**SQL statistics:**  
Количество выполненных запросов (чтение с 56564 до 89670, запись  с 58517 до 92967, другие и общее с 8768 до 13780) увеличилось, что указывает на улучшение пропускной способности.  
Количество транзакций в секунду увеличилось с 72.77 до 114.52, что также указывает на увеличение производительности.  
Общее количество запросов возросло с 123849 до 196417, а количество транзакций - с 4370 до 6875.  
Количество игнорированных ошибок незначительно увеличилось с 0.50 до 0.73 в секунду, что может требовать дальнейшего исследования.  
  
**Throughput:**  
Среднее количество событий в секунду увеличилось с 72.77 до 114.52, что подтверждает увеличение производительности.  
  
**Latency (ms):**  
Среднее время ответа снизилось с 27.47 мс до 17.46 мс, что указывает на более быстрый отклик.  
Максимальное время ответа значительно сократилось с 5088.31 мс до 259.60 мс, что является значительным улучшением.  
95-й процентиль также уменьшился с 82.96 мс до 51.94 мс, что говорит о том, что большинство запросов обрабатываются быстрее.  
  
**Threads fairness:**  
Среднее количество событий на поток увеличилось, что указывает на более эффективное распределение работы между потоками.  
  
В целом, эти результаты показывают, что моя система стала более производительной по сравнению с предыдущим тестом. Более быстрое время ответа и большее количество транзакций в секунду говорят о том, что моя система может эффективнее обрабатывать нагрузку. Однако увеличение количества игнорированных ошибок может потребовать дополнительного исследования, чтобы убедиться, что это не влияет на работу системы.

- *Посмотрим логи ошибок для изучения*
```bash
sudo tail -n 100 /var/log/postgresql/postgresql-*.log

2023-07-16 12:25:53.419 UTC [1841] postgres@postgres WARNING:  there is no transaction in progress
2023-07-16 12:25:54.556 UTC [1841] postgres@postgres ERROR:  could not serialize access due to concurrent update
2023-07-16 12:25:54.556 UTC [1841] postgres@postgres STATEMENT:  UPDATE warehouse2
                          SET w_ytd = w_ytd + 1029
                        WHERE w_id = 11
2023-07-16 12:25:54.557 UTC [1841] postgres@postgres WARNING:  there is no transaction in progress
2023-07-16 12:25:55.991 UTC [1841] postgres@postgres ERROR:  could not serialize access due to concurrent update
2023-07-16 12:25:55.991 UTC [1841] postgres@postgres STATEMENT:  SELECT d_next_o_id, d_tax
                                                  FROM district1
                                                 WHERE d_w_id = 1
                                                   AND d_id = 9 FOR UPDATE
2023-07-16 12:25:55.992 UTC [1841] postgres@postgres WARNING:  there is no transaction in progress
2023-07-16 12:25:59.094 UTC [1841] postgres@postgres ERROR:  could not serialize access due to concurrent update
2023-07-16 12:25:59.094 UTC [1841] postgres@postgres STATEMENT:  SELECT d_next_o_id, d_tax
                                                  FROM district2
                                                 WHERE d_w_id = 29
                                                   AND d_id = 7 FOR UPDATE

``````
Эти ошибки связаны с конкурентными обновлениями в вашей базе данных, которые вызывают проблемы с сериализацией доступа. Это обычно происходит, когда два или более процесса пытаются обновить одни и те же данные одновременно.  
  
В общем, когда транзакция пытается модифицировать данные, которые уже изменены другой транзакцией (которая еще не завершилась), она не может гарантировать последовательность, и PostgreSQL отклоняет такую транзакцию, то есть ошибки связаны с уровнем изоляции и не влияют на саму систему.

- *Очищаем базу от сгенерированных данных*
```bash
/usr/bin/sysbench /home/vagrant/sysbench-tpcc/tpcc.lua --db-driver=pgsql --pgsql-host=localhost --pgsql-port=5432 --pgsql-user=postgres --pgsql-password=postgres --pgsql-db=postgres --threads=2 --tables=2 --scale=30 cleanup
``````