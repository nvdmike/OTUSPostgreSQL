# Урок 3: Установка и настройка PostgteSQL в контейнере Docker

## Часть 1: Подготовка

> **Примечание:** Я решил работать не через PuttySSH, а через терминал Visual Studio Code. Для работы с Яндекс.Облако пришлось установить интерфейс командной строки Yandex Cloud (CLI).

1. Для установки CLI выполнил команду:

```bash
iex (New-Object System.Net.WebClient).DownloadString('https://storage.yandexcloud.net/yandexcloud-yc/install.ps1')
```

2. Скрипт установки спроил, нужно ли добавить путь до yc в переменную PATH: ввёл `Y`

3. Получил `OAuth-токен` в сервисе Яндекс.OAuth и скопировал его в буфер обмена

4. Выполните команду `yc init` и вставил полученный токен

5. Выбрал одно из предложенных облаков, к которым имелся доступ: `[1] cloud1`

6. Выбрал каталог по умолчанию: `[1] folder1`

7. Выбрал зону доступности по умолчанию для сервиса Yandex Compute Cloud: `[1] ru-central1-a`

## Часть 2: Выполнение ДЗ

1. Генерирую ssh-ключ командой (нажимаю Enter, чтобы использовать имя по умолчанию):

```bash
ssh-keygen -t ed25519
```

![рис.1](images/01.png)

2. Создаю на Яндекс.Облако сеть командой:

```bash
yc vpc network create --name otus-vm-db-pg-net-1 --labels my-label=otus-vm-db-pg-net-1 --description "otus-vm-db-pg-net-1"
```

![рис.2](images/02.png)

3. Создаю на Яндекс.Облако подсеть командой:

```bash
yc vpc subnet create --name otus-vm-db-pg-subnet-1 --zone ru-central1-a --range 10.1.2.0/24 --network-name otus-vm-db-pg-net-1 --description "otus-vm-db-pg-subnet-1"
```

![рис.3](images/03.png)

4. Создаю новую ВМ на Яндекс.Облако с заданными параметрами и подставляю ssh-ключ в метаданные ВМ (После создания ВМ данные об ip-адресе содержатся блоке `one_to_one_nat`. Так, же информацию о ВМ можно вывести командой: `yc compute instance get otus-pg-on-ubuntu`):

```bash
yc compute instance create otus-pg-on-ubuntu --zone ru-central1-a --network-interface subnet-name=otus-vm-db-pg-subnet-1,nat-ip-version=ipv4 --preemptible --platform standard-v3 --cores 4 --core-fraction 20 --memory 4GB --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts --ssh-key "C:\Users\USER01/.ssh/id_ed25519.pub"
```

![рис.4](images/04.png)

5. Подключаюсь к публичному ip-адресу ВМ по ssh командой (в процессе возникла ошибка, пришлось очистить файл `known_hosts` и снова переподключиться):

```bash
ssh yc-user@158.160.45.167
```

![рис.5](images/05.png)

6. Устанавлию Docker командой:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh && rm get-docker.sh && sudo usermod -aG docker $USER
```

![рис.6](images/06.png)

7. Создаю docker-сеть:

```bash
sudo docker network create pg-net
```

![рис.7](images/07.png)

8. Под супер-пользователем запускаю Docker с именем `pg-serve`r, с использованием ранее созданной docker-сети `pg-net`, пробрасываю из Docker наружу так, чтобы внешний порт соответствовал внутреннему порту Docker, далее создаётся и монтируется к Docker внешний раздел `/var/lib/postgres` и устанавливается Postgres 14 внутри контейнера:

```bash
sudo docker run --name pg-server --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14
```

![рис.8](images/08.png)

9. Запускаю отдельный контейнер с клиентом в общей сети с БД:

```bash
sudo docker run -it --rm --network pg-net --name pg-client postgres:14 psql -h pg-server -U postgres
```

![рис.9](images/09.png)

10. Смотрю какие БД есть в данном экземпляре Postgres командой:

```sql
postgres=# \l
```

![рис.10](images/10.png)

11. Создаю новую БД:

```sql
postgres=# create database test_db;
```

![рис.11](images/11.png)

12. Перехожу в созданную БД:

```sql
postgres=# \c test_db
```

![рис.12](images/12.png)

13. Создаю в этой БД новую таблицу и пару записей в ней:

```sql
test_db=# create table test (i serial, amount int); insert into test(amount) values (100); insert into test(amount) values (500);
```

![рис.13](images/13.png)

14. Выбираю данные из созданной таблицы test в этой БД:

```sql
test_db=# select * from test;
```

![рис.14](images/14.png)

15. Отключаюсь от контейнера с клиентом и устанавливаю клиент Postgres для того, чтобы проверить подключение к контейнеру с машины-хоста:

```bash
sudo apt install postgresql-client-14
```

![рис.15](images/15.png)

16. Подключаюсь к Docker непосредственно с хоста по внешнему ip-адресу:

```bash
psql -p 5432 -U postgres -h 158.160.45.167 -d postgres -W
```

![рис.16](images/16.png)

17. Смотрю какие БД есть в данном экземпляре Postgres и вижу ранее созданную БД `test_db`:

```sql
postgres=# \l
```

![рис.17](images/17.png)

18. Перехожу в созданную БД и выбираю данные из созданной таблицы `test` в этой БД:

```sql
test_db=# select * from test;
```

![рис.18](images/18.png)

19. Отключаюсь от сервера и останавливаю его:

```bash
sudo docker stop pg-server
```

![рис.19](images/19.png)

20. Удаляю контейнер с сервером:

```bash
sudo docker rm pg-server
```

![рис.20](images/20.png)

21. Заново создаю контейнер:

```bash
sudo docker run --name pg-server --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14
```

![рис.21](images/21.png)

22. Снова подключаюсь из контейнера-клиента к серверу:

```bash
sudo docker run -it --rm --network pg-net --name pg-client postgres:14 psql -h pg-server -U postgres
```

![рис.22](images/22.png)

23. Проверяю то, что БД `test_db` осталась:

```sql
postgres=# \l
```

![рис.23](images/23.png)

24. Перехожу в созданную БД и выбираю данные из таблицы `test` в этой БД:

```sql
test_db=# select * from test;
```

![рис.24](images/24.png)