# Keenetic AppStore

Лёгкая веб-панель для Entware. Интерфейс и метаданные каталога хранятся в этом GitHub-репозитории; на роутер скачиваются только файлы интерфейса, небольшие CGI-скрипты и журналы запущенных установок.

## Установка

Войдите по SSH в Entware под `root`. Если `curl` ещё не установлен, выполните:

```sh
opkg update && opkg install curl ca-certificates
```

Затем запустите установщик:

```sh
curl -fsSL https://raw.githubusercontent.com/byDGer/Keenetic-AppStore/main/install.sh | sh
```

Установщик предложит LAN-IP роутера и порт (по умолчанию `8088`), поставит Lighttpd, CGI, `jq`, `curl` и сертификаты, создаст случайный ключ доступа и включит автозапуск. В конце он покажет адрес сайта и ключ. Введите ключ в окне установки внутри AppStore; он хранится только в браузере.

Порт и LAN-IP можно передать без вопросов, например `curl -fsSL https://raw.githubusercontent.com/byDGer/Keenetic-AppStore/main/install.sh | sh -s -- 9090 192.168.1.1`.

Откройте `http://<LAN-IP>:<порт>`. Страница получает каталог через `/cgi-bin/catalog.cgi`; CGI скачивает JSON из этого репозитория, не сохраняя его на диске. Архитектура отображается из результата `uname -m`.

## Установка приложений

Кнопка установки отправляет только ID приложения и ключ локальному CGI. CGI повторно загружает каталог GitHub, проверяет архитектуру и запускает только установщики с `raw.githubusercontent.com/byDGer/` в фоне. Статус и журнал доступны через CGI по ID задания. Для 3X-UI используется установщик [byDGer/3xui-keenetic-aarch64](https://github.com/byDGer/3xui-keenetic-aarch64).

Веб-сервер запускается с правами root, чтобы запускать Entware-установщики. Поэтому оставляйте его доступным только из доверенной LAN, не пробрасывайте порт наружу, не публикуйте ключ доступа. Каталог загружается с GitHub при открытии страницы и при каждом запуске установки; список приложений/описания не кэшируются на роутере.

## Управление

```sh
/opt/etc/init.d/S80keenetic-appstore start|stop|restart|status
```

Конфигурация: `/opt/etc/keenetic-appstore/config`. Сайт: `/opt/share/keenetic-appstore/www`. Журналы заданий: `/opt/var/lib/keenetic-appstore/jobs`.

Удаление: `/opt/etc/init.d/S80keenetic-appstore stop`, затем `opkg remove lighttpd lighttpd-mod-cgi jq curl ca-certificates`; файлы приложения можно удалить из перечисленных каталогов.

