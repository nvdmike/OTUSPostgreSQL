# Урок 6: Установка и настройка PostgreSQL

## Часть 1: Подготовка ВМ

> **Примечание:** ssh-ключ был создан ещё на предыдущем уроке, поэтому новый не гененрирую

1. Создаю на Яндекс.Облако сеть командой:

```bash
yc vpc network create --name otus-vm-db-pg-net-1 --labels my-label=otus-vm-db-pg-net-1 --description "otus-vm-db-pg-net-1"
```

![рис.1](images/01.png)

2. Создаю на Яндекс.Облако подсеть командой:

```bash
yc vpc subnet create --name otus-vm-db-pg-subnet-1 --zone ru-central1-a --range 10.1.2.0/24 --network-name otus-vm-db-pg-net-1 --description "otus-vm-db-pg-subnet-1"
```

![рис.2](images/02.png)

3. Создаю ВМ на Яндекс.Облако с заданными параметрами и подставляю ssh-ключ в метаданные ВМ (После создания ВМ данные об ip-адресе содержатся блоке `one_to_one_nat`. Так, же информацию о ВМ можно вывести командой: `yc compute instance get otus-pg-on-ubuntu`):

```bash
yc compute instance create otus-pg-on-ubuntu --zone ru-central1-a --network-interface subnet-name=otus-vm-db-pg-subnet-1,nat-ip-version=ipv4 --preemptible --platform standard-v3 --cores 4 --core-fraction 20 --memory 4GB --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts --ssh-key "C:\Users\USER01/.ssh/id_ed25519.pub"
```

![рис.3](images/03.png)

4. Подключаюсь к ВМ по ssh командой:

```bash
ssh yc-user@62.84.119.208
```

![рис.4](images/04.png)

## Часть 2: Установка PostgreSQL 15

1. Устанавливаю PostgreSQL 15 командой:

```bash
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt -y install postgresql-15
```

![рис.5](images/05.png)

2. Проверяю то, что кластер запущен:

```bash
sudo -u postgres pg_lsclusters
```

![рис.6](images/06.png)

3. Захожу из под пользователя `postgres` в psql командой:

```bash
sudo -u postgres psql
```

![рис.7](images/07.png)

4. Создаю таблицу и наполняю её содержимым: 

```sql
postgres=# create table test(c1 text);
postgres=# insert into test values('1');
postgres=# \q
```

![рис.8](images/08.png)

5. Останавливаю PostgreSQL командой:

```bash
sudo -u postgres pg_ctlcluster 15 main stop
```

![рис.9](images/09.png)

## Часть 3: Создание диска и подмонтирование его к системе

1. Создаю новый SSD диск к ВМ объёмом 10GB и наименованием `otus-pg-disk1`

![рис.10](images/10.png)

2. Присоединяю созданный диск к ВМ

![рис.11](images/11.png)

3. Чтобы посмотреть какие диски являются нераспознанныеми в системе (т.е. новыми и не инициализированными), использую команду:

```bash
sudo parted -l | grep Error
```

![рис.12](images/12.png)

4. На всякий случай убеждаюсь, что нераспознанный диск именно тот, который необходим командой (вижу, что это как раз нужный диск, размером 10GB):

```bash
lsblk
```

![рис.13](images/13.png)

5. Задаю формат размещения таблиц разделов GPT командой:

```bash
sudo parted /dev/vdb mklabel gpt
```

![рис.14](images/14.png)

6. После выбора формата можно создать раздел, для всего диска командой:

```bash
sudo parted -a opt /dev/vdb mkpart primary ext4 0% 100%
```

![рис.15](images/15.png)

7. Убеждаюсь, что раздел создан и смотрю его имя:

```bash
lsblk
```

![рис.16](images/16.png)

8. Создаю файловую систему на разделе диска командой:

```bash
sudo mkfs.ext4 -L datapartition /dev/vdb1
```

![рис.17](images/17.png)

9. Смотрю, что на выбранном разделе создана ФС и присвоен `UUID`:

```bash
sudo lsblk --fs
```

![рис.18](images/18.png)

10. Создаю новый каталог `/mnt/data`:

```bash
sudo mkdir -p /mnt/data
```

![рис.19](images/19.png)

11. Чтобы диск автоматически подмонтировался в данный каталог, перехожу в редактор `nano` и редактирую файл `fstab`, который содержит информацию о всех монтируемых к системе дисках:

```bash
sudo nano /etc/fstab
```

![рис.20](images/20.png)

12. Добавляю строчку `LABEL=datapartition /mnt/data ext4 defaults 0 2`

![рис.21](images/21.png)

13. Перезагружаю инстанс командой:

```bash
sudo reboot
```

![рис.22](images/22.png)

14. Снова  подключаююсь по ssh и проверяю, что диск остался примонтированным после перезагрузки:

```bash
sudo lsblk --fs
```

![рис.23](images/23.png)

## Часть 4: Работа с PostgreSQL

1. Делаю пользователя postgres владельцем /mnt/data командой:

```bash
sudo chown -R postgres:postgres /mnt/data/
```

![рис.24](images/24.png)

2. Переношу содержимое каталога `/var/lib/postgresql/15` в каталог `/mnt/data` командой:

```bash
sudo mv /var/lib/postgresql/15 /mnt/data
```

![рис.25](images/25.png)

3. Пытаюсь запустить кластер:

```bash
sudo -u postgres pg_ctlcluster 15 main start
```

> **Результат:** запустить кластер не удалось, т.к. PostgreSQL не знает расположение данных PostgreSQL

![рис.26](images/26.png)

4. Меняю конфигурационный файл PostgreSQL и выставляю новое расположение:

```bash
sudo nano /etc/postgresql/15/main/postgresql.conf
```

![рис.27](images/27.png)

5. Снова пытаюсь запустить кластер командой:

```bash
sudo -u postgres pg_ctlcluster 15 main start
```

> **Результат:** в этот раз всё получилось, т.к. в конфигурационном файле теперь указано корректное расположение данных PostgreSQL

![рис.28](images/28.png)

6. Захожу через через psql:

```bash
sudo -u postgres psql
```

![рис.29](images/29.png)

7. Проверяю содержимое ранее созданной таблицы:

```sql
postgres=# select * from test;
postgres=# \q
```

![рис.30](images/30.png)

## Часть 5: Задание со звездочкой *

1. Создаю вторую ВМ на Яндекс.Облако с заданными параметрами и подставляю ssh-ключ в метаданные ВМ (После создания ВМ данные об ip-адресе содержатся блоке `one_to_one_nat`. Так, же информацию о ВМ можно вывести командой: `yc compute instance get otus-pg-on-ubuntu-2`):

```bash
yc compute instance create otus-pg-on-ubuntu-2 --zone ru-central1-a --network-interface subnet-name=otus-vm-db-pg-subnet-1,nat-ip-version=ipv4 --preemptible --platform standard-v3 --cores 4 --core-fraction 20 --memory 4GB --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts --ssh-key "C:\Users\USER01/.ssh/id_ed25519.pub"
```

![рис.31](images/31.png)

2. Подключаюсь ко второй ВМ по ssh командой:

```bash
ssh yc-user@51.250.87.143
```

![рис.32](images/32.png)

3. Устанавливаю PostgreSQL 15 на новой ВМ командой:

```bash
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt -y install postgresql-15
```

![рис.33](images/33.png)

4. Останавливаю кластер:

```bash
sudo -u postgres pg_ctlcluster 15 main stop
```

![рис.34](images/34.png)

5. Удаляю содержимое каталога `/var/lib/postgres` командой:

```bash
sudo rm -fr /var/lib/postgresql/
```

![рис.35](images/35.png)

6. Переподключаю в интерфейсе диск от первой ВМ к второй ВМ

![рис.36](images/36.png)

7. Создаю в новой ВМ каталог `/mnt/data`:

```bash
sudo mkdir -p /mnt/data
```

![рис.37](images/37.png)

8. Проверяю разделы командой:

```bash
sudo lsblk
```

![рис.38](images/38.png)

9. Подмонтирую диск в каталог `/mnt/data` (в этот раз я `fstab` не правлю, т.к. смысла нет - монтирую на один раз, для теста):

```bash
sudo mount -o defaults /dev/vdb1 /mnt/data
```

![рис.39](images/39.png)

10. Так же правлю конфигурационный файл PostgreSQL и выставляю новое расположение:

```bash
sudo nano /etc/postgresql/15/main/postgresql.conf
```

![рис.40](images/40.png)

11. Запускаю кластер командой:

```bash
sudo -u postgres pg_ctlcluster 15 main start
```

![рис.41](images/41.png)

12. Захожу через через psql: sudo -u postgres psql

![рис.42](images/42.png)

13. Проверяю содержимое данных и ранее созданной таблицы:

```sql
postgres=# \l
postgres=# select * from test;
```

> **Результат:** как можно заметить, все данные были перенесены и подтянулись к новому инстансу PostgreSQL

![рис.43](images/43.png)