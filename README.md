# Keenetic-Split-DNS

Split-DNS для роутеров **Keenetic** с **Entware**: домены Yandex, VK, Mail.ru, OK и др. резолвятся через выбранный **DNS-over-TLS** upstream (например Yandex `77.88.8.8:853`), остальной трафик — через DNS провайдера / Keenetic.

Веб-интерфейс на русском, порт **3200**, только LAN.

## Быстрая установка

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/Keenetic-Split-DNS/main/install.sh | sh
```

После установки откройте `http://<LAN_IP>:3200` (токен API выводится в консоль).

## Удаление

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/Keenetic-Split-DNS/main/uninstall.sh | sh
```

С удалением пакетов Entware:

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/Keenetic-Split-DNS/main/uninstall.sh | sh -s -- --purge
```

## Требования

| Компонент | Описание |
|-----------|----------|
| Роутер Keenetic | Актуальная прошивка с Entware |
| USB + Entware | `/opt/bin/opkg` |
| Компоненты Keenetic | **Entware** (установка из магазина), при Neo — см. ниже |
| Пакеты Entware | `smartdns`, `lighttpd`, `lighttpd-mod-cgi`, `ca-certificates`, `curl`, `bind-dig` (устанавливает install.sh) |

## Что делает установщик

1. Копирует файлы в `/opt/etc/keenetic-split-dns/` и `/opt/share/keenetic-split-dns/`
2. Создаёт `config.yaml` из примера, подставляет LAN IP (`br0`)
3. Генерирует токен API → `/opt/etc/keenetic-split-dns/token`
4. Собирает `smartdns.conf` из YAML (`compile-config.sh`)
5. Включает init-скрипты `S97ksd-compile`, `S98smartdns`, `S99ksd-web`
6. По возможности: `opkg dns-override enable` (предпочтительно для **HydraRoute Neo**)
7. Иначе: правило `netfilter.d` для перенаправления DNS с `br0`

## Конфигурация

Основной файл:

```text
/opt/etc/keenetic-split-dns/config.yaml
```

Списки доменов:

```text
/opt/etc/keenetic-split-dns/domain-sets/ru-services.txt
```

Пересборка и применение вручную:

```sh
/opt/share/keenetic-split-dns/scripts/apply.sh
```

### Upstream по умолчанию

| ID | Тип | Назначение |
|----|-----|------------|
| `yandex-dot` | DoT | `77.88.8.8:853`, SNI `common.dot.dns.yandex.net` |
| `isp-default` | UDP | `auto` — DNS Keenetic / ISP |

### Предзаполненные домены

`yandex.ru`, `ya.ru`, `yandex.com`, `yandex.net`, `yastatic.net`, `yandex.st`, `mail.ru`, `mail.com`, `imgsmail.ru`, `mycdn.me`, `vk.com`, `vk.me`, `vkuservideo.net`, `vkuseraudio.net`, `userapi.com`, `vk-cdn.net`, `ok.ru`, `odnoklassniki.ru`, `okcdn.ru`

## Веб-интерфейс

| Вкладка | Функции |
|---------|---------|
| Обзор | Статус SmartDNS, счётчики |
| Upstream | Master-detail: профиль → домены группы |
| Домены | Таблица, поиск, экспорт |
| Проверка | `dig` через локальный SmartDNS |
| Настройки | Редактор YAML, токен, «Применить» |

API (CGI): `GET/POST /api/status`, `/api/domains`, `/api/config`, `/api/reload`, `/api/test`

Авторизация: заголовок `Authorization: Bearer <token>` или `X-KSD-Token`.

## ⚠️ Конфликт с DoT в Keenetic

В прошивке Keenetic (**Интернет-фильтры → Настройка DNS**) глобальный **DNS-over-TLS** обрабатывает **все** запросы и **не** умеет привязку «домен → сервер».

**Рекомендация:** отключите глобальный DoT в UI Keenetic и используйте split-DNS этого проекта. Иначе политики SmartDNS могут не применяться к клиентам.

## Совместимость с HydraRoute Neo

[HydraRoute Neo](https://github.com/Ground-Zerro/HydraRoute/tree/main/Neo) маршрутизирует по IP из DNS (NFLOG), а не выбирает upstream DNS.

| Правило | Действие |
|---------|----------|
| DHCP DNS | IP роутера в LAN (`192.168.x.1`) |
| DNS path | Предпочтительно `opkg dns-override` → SmartDNS на Entware |
| Глобальный DoT Keenetic | **Выключить** |
| Порты | HRweb `2000`, Split-DNS UI `3200` — не пересекаются |
| Проверка | После установки — диагностика в HRweb |

Установщик сохраняет состояние `dns-override` в `/opt/etc/keenetic-split-dns/dns-override.state`; `uninstall.sh` пытается восстановить прежний `dns-override.conf`.

## Структура репозитория

```text
install.sh / uninstall.sh
scripts/          detect-lan, compile-config, apply, api
etc/              config.yaml.example, domain-sets, lighttpd, smartdns, ndm
www/              index.html, app.js, style.css
cgi-bin/api.cgi
init.d/           S97ksd-compile, S98smartdns, S99ksd-web
```

## Лицензия

MIT — см. [LICENSE](LICENSE).

## Автор

[andrey271192](https://github.com/andrey271192)
