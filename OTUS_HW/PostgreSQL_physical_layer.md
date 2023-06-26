# **Установка и настройка PostgreSQL**  

## **Цель:**

### - создавать дополнительный диск для уже существующей виртуальной машины, размечать его и делать на нем файловую систему;
### - переносить содержимое базы данных PostgreSQL на дополнительный диск;
### - переносить содержимое БД PostgreSQL между виртуальными машинами.
------------

1. Создайте виртуальную машину c Ubuntu 20.04/22.04 LTS в GCE/ЯО/Virtual Box/докере
- *Я разворачивал машину через Vargrant Virtual Box*
```bash
mkdir my_vagrant_vm
cd my_vagrant_vm
```
- *Инициализировал новую виртуальную машину*
```bash
vagrant init ubuntu/focal64
```
- *Запуск ВМ*
```bash
vagrant up
```
- *Версия ОС*
```bash
lsb_release -a
No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 20.04.6 LTS
Release:        20.04
Codename:       focal
```
----------

2. Поставьте на нее PostgreSQL, проверьте что кластер запущен через sudo -u postgres pg_lsclusters
- *В моём случае уже был установлен PostgrSQl 12 на данной машине*
##### Установка
```bash
sudo wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &> /dev/null
```

---------

3. Зайдите из под пользователя postgres в psql и сделайте произвольную таблицу с произвольным содержимым
```bash
sudo -i -u postgres psql
```
```sql
CREATE TABLE test(c1 text);
INSERT INTO test values(1);
```

----------------

4. Остановите postgres 
```bash
systemctl stop postgresql
```

-----------

5. Создайте новый диск к ВМ размером 10GB
```ruby
Vagrant.configure("2") do |config|
    config.vm.provider "virtualbox" do |v|
    v.customize ["createhd", "--filename", "./extra_disk.vdi", "--size", 10240] 
    v.customize ['storageattach', :id, '--storagectl', 'SCSI', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', "./extra_disk.vdi"]
  end
```

---------------

6. Добавьте свеже-созданный диск к виртуальной машине - надо зайти в режим ее редактирования и дальше выбрать пункт attach existing disk
```bash
sudo fdisk /dev/sdb
```
-------------------

7. Проинициализируйте диск согласно инструкции и подмонтировать файловую систему, только не забывайте менять имя диска на актуальное, в вашем случае это скорее всего будет /dev/sdb - https://www.digitalocean.com/community/tutorials/how-to-partition-and-format-storage-devices-in-linux
##### Создаём файловую систему на новом разделе:
```bash
sudo mkfs.ext4 /dev/sdb1
```
##### Создаём точку монтирования для нового диска:
```bash
sudo mkdir /mnt/data
```
##### Монтируем раздел:
```bash
sudo mount /dev/sdb1 /mnt/data
```

-------------------

8. Перезагрузите инстанс и убедитесь, что диск остается примонтированным (если не так смотрим в сторону fstab)
##### Убедимся, что диск будет автоматически монтироваться при каждой перезагрузке, добавив его в /etc/fstab. Откроем файл fstab с помощью команды:
```bash
sudo nano /etc/fstab
```
##### И добавим следующую строку:
```bash
/dev/sdb1   /mnt/data   ext4   defaults   0   0
```

-----------------------

9. Сделайте пользователя postgres владельцем /mnt/data - chown -R postgres:postgres /mnt/data/сделайте пользователя postgres владельцем /mnt/data - chown -R postgres:postgres /mnt/data/
```bash
sudo chown -R postgres:postgres /mnt/data/
```

10. Перенесите содержимое /var/lib/postgres/12 в /mnt/data - mv /var/lib/postgresql/12/mnt/data
```bash
sudo mv /var/lib/postgresql/12 /mnt/data
```
-------------------------

11. Попытайтесь запустить кластер - sudo -u postgres pg_ctlcluster 15 main start
```bash
sudo -u postgres pg_ctlcluster 13 main start
```
```bash
Error: /var/lib/postgresql/12/main is not accessible or does not exist
```
##### Напишите получилось или нет и почему
- *Кластер не запустился в связи с тем, что PostgreSQL все еще будет пытаться обратиться к старому местоположению для доступа к своим данным, что приведет к ошибкам.*

##### Задание: найти конфигурационный параметр в файлах раположенных в /etc/postgresql/15/main который надо поменять и поменяйте его
```bash
sudo nano /etc/postgresql/12/main/postgresql.conf
```
```yml
data_directory = '/mnt/data/12'
```

##### Напишите что и почему поменяли
- *Изменил путь для доступа к данным*

----------------------------------

12. Попытайтесь запустить кластер - sudo -u postgres pg_ctlcluster 15 main start
- *Получил ошибку, связанную с тем, что перенеслись не все конфигурационные файлы postgresql.conf, pg_hba.conf, pg_ident.conf*
- *Создал копию, перенес в нужную директорию, и изменил пути к данным файлам в postgresql.conf*
```bash
sudo cp /etc/postgresql/12/main/postgresql.conf /etc/postgresql/12/main/postgresql.conf.bak
sudo cp /etc/postgresql/12/main/pg_hba.conf /etc/postgresql/12/main/pg_hba.conf.bak
sudo cp /etc/postgresql/12/main/pg_ident.conf /etc/postgresql/12/main/pg_ident.conf.bak
```
```bash
sudo mv /etc/postgresql/12/main/postgresql.conf /mnt/data/12/main/postgresql.conf
sudo mv /etc/postgresql/12/main/pg_hba.conf /mnt/data/12/main/pg_hba.conf
sudo mv /etc/postgresql/12/main/pg_ident.conf /mnt/data/12/main/pg_ident.conf
```
```bash
sudo chown postgres:postgres /mnt/data/12/main/postgresql.conf
sudo chown postgres:postgres /mnt/data/12/main/pg_hba.conf
sudo chown postgres:postgres /mnt/data/12/main/pg_ident.conf
```
##### Меняем настройки сервисного файла
```bash
sudo nano /lib/systemd/system/postgresql.service
```
```yml
ExecStart=/usr/lib/postgresql/12/bin/postgres -D /mnt/data/12/main
```
##### Перезагружаем службу systemd, чтобы применить новую конфигурацию:
```bash
sudo systemctl daemon-reload
```

##### Запускаем кластер
```bash
sytemctl start postgresql
```

-----------------

13. Зайдите через через psql и проверьте содержимое ранее созданной таблицы
```bash
sudo -i -u postgres psql
```
```sql
SELECT * FROM test;
```
- *Вывод на экран:*
 c1|
---|
 1 |
(1 row)

--------------------

14. Задание со звездочкой *: не удаляя существующий инстанс ВМ сделайте новый, поставьте на его PostgreSQL, удалите файлы с данными из /var/lib/postgres, перемонтируйте внешний диск который сделали ранее от первой виртуальной машины ко второй и запустите PostgreSQL на второй машине так чтобы он работал с данными на внешнем диске, расскажите как вы это сделали и что в итоге получилось.
- *Для задачи со звездочкой, мы можем повторить шаги 1-7 для новой виртуальной машины, а затем отключить диск от первой машины и подключить его к второй. Затем повторить шаги 8-13 для новой машины, чтобы перемонтировать внешний диск и настроить PostgreSQL на его использование.*