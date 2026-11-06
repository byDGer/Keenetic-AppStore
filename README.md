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

Установщик автоматически определит LAN-IP роутера (сначала проверяет `br0`) и предложит порт (по умолчанию `8088`); если порт уже занят, выберет следующий свободный. Он установит Lighttpd, CGI, `jq`, `curl` и сертификаты, настроит автозапуск и покажет адрес сайта. Ключ доступа не создаётся и при установке приложений не запрашивается.

Порт можно передать без вопроса, например `curl -fsSL https://raw.githubusercontent.com/byDGer/Keenetic-AppStore/main/install.sh | sh -s -- 9090`.

Откройте `http://<LAN-IP>:<порт>`. Страница получает каталог через `/cgi-bin/catalog.cgi`; CGI скачивает JSON из этого репозитория, не сохраняя его на диске. Архитектура отображается из результата `uname -m`.

## Удаление

Чтобы удалить AppStore, выполните отдельную команду:

```sh
curl -fsSL https://raw.githubusercontent.com/byDGer/Keenetic-AppStore/main/uninstall.sh | sh
``` 

Скрипт останавливает службу и удаляет файлы AppStore. Установленные пакеты Entware оставляет, так как они могут использоваться другими программами.

## Установка приложений

Кнопка установки отправляет ID приложения локальному CGI без API-ключа. CGI повторно загружает каталог GitHub, проверяет архитектуру и запускает только установщики с `raw.githubusercontent.com/byDGer/` в фоне. Статус и журнал доступны через CGI по ID задания. Для 3X-UI используется установщик [byDGer/3xui-keenetic-aarch64](https://github.com/byDGer/3xui-keenetic-aarch64).

Веб-сервер запускается с правами root, чтобы запускать Entware-установщики. Поэтому оставляйте его доступным только из доверенной LAN, не пробрасывайте порт наружу. Каталог загружается с GitHub при открытии страницы и при каждом запуске установки; список приложений/описания не кэшируются на роутере.

## Управление

```sh
/opt/etc/init.d/S80keenetic-appstore start|stop|restart|status
```

Конфигурация: `/opt/etc/keenetic-appstore/config`. Сайт: `/opt/share/keenetic-appstore/www`. Журналы заданий: `/opt/var/lib/keenetic-appstore/jobs`.