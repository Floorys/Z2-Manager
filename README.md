# 🛡️ Zapret2-Manager

**Модульный консольный менеджер и автоскрипт подбора/генерации стратегий для [zapret2-openwrt](https://github.com/1andrevich/zapret2-openwrt) на базе алгоритмов [Asterlike/zapret2UI](https://github.com/Asterlike/zapret2UI).**

[![OpenWrt 23.05+](https://img.shields.io/badge/OpenWrt-23.05%2B%20%7C%2024.10%2B%20%7C%2025.12%2B-blue?style=for-the-badge&logo=openwrt)](https://openwrt.org)
[![Zapret2](https://img.shields.io/badge/Zapret2-1andrevich-success?style=for-the-badge)](https://github.com/1andrevich/zapret2-openwrt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

---

## 📖 О проекте

**Zapret2-Manager** — это автономная утилита для роутеров OpenWrt с установленным пакетом **zapret2** (nfqws2). Она решает главную проблему обхода DPI: **необходимость ручного перебора сотен параметров под каждого конкретного провайдера**.

Мы **не модифицируем сам zapret2** и не собираем сторонние форки — менеджер работает как интеллектуальная надстройка (аналогично [Zapret-Manager от StressOzz](https://github.com/StressOzz/Zapret-Manager)), управляя официальным пакетом от `1andrevich` через стандартные интерфейсы OpenWrt (`uci`, `sync_config.sh`, `init.d`).

### 🧬 Ключевые возможности:
- 🧬 **Двухпроходный генератор стратегий (Two-Pass Generator)**: перенесен прямо из [Asterlike/zapret2UI](https://github.com/Asterlike/zapret2UI). Тестирует сетку из 27+ десинк-бандлов, отдельно ранжирует их для Discord и YouTube, отбирает шортлист с защитой **Gateway-friendly** и подбирает идеальное сочетание.
- ⚡ **Автоподбор из проверенного каталога (Auto-Selector)**: перебор 9 готовых комбо-стратегий (Рекомендуемый, Flowseal ALT10/11, Отечественный VK, Окно wssize, Circular адаптивный) с выбором победителя под вашего провайдера.
- ⏱️ **Расширенный сетевой пробник (набор как в Zapret-Manager)**: проверяет до 10 ключевых доменов (YouTube Web/Video/Preview, Discord Web/Voice/CDN, RuTracker, Twitter, Instagram, VK) с живым выводом статуса за 1-2 секунды без зависаний.
- 🛑 **Безопасное прерывание по Ctrl+C**: нажатие Ctrl+C во время генерации или автоподбора мгновенно откатывает временные настройки и возвращает вас в главное меню, не закрывая сам менеджер.
- 🔄 **Встроенное самообновление в один клик**: как у StressOzz, можно обновить скрипт прямо из меню (пункт 8) или командой `z2m -u` без необходимости заново вводить команды `curl`/`wget`.
- 🔐 **Расширенное меню DNS и DoH**: популярные DNS-over-HTTPS пресеты из коробки — **Google DNS**, **Quad9 DNS**, **Xbox / Comss DNS** (для консолей), **DNS.ru / Yandex DNS**, **Cloudflare**, **AdGuard**.
- 🔍 **Умный поиск установленного zapret2**: если zapret2 уже установлен вручную через opkg/apk или LuCI, скрипт мгновенно находит его и не пытается перезаписывать файлы.
- 📁 **Управление хостлистами и исключениями**: готовые актуальные списки для YouTube, Discord и исключений чувствительных сервисов (Госуслуги, банки, российские CDN).
- 📦 **Поставка фейковых блобов**: включает бинарные блобы ClientHello и QUIC (`tls_vk`, `tls_sber`, `quic_vk` и др.) для работы продвинутых стратегий.

---

## 🚀 Быстрая установка на роутер

Подключитесь к роутеру по SSH и выполните одну команду:

```sh
sh <(curl -fsSL https://raw.githubusercontent.com/Floorys/Z2-Manager/main/install.sh)
```

Или через `wget`:
```sh
sh <(wget -qO- https://raw.githubusercontent.com/Floorys/Z2-Manager/main/install.sh)
```

Инсталлятор автоматически настроит права, создаст команды `/usr/bin/z2m` и `/usr/bin/zsm`, и при необходимости скопирует фейковые блобы и списки доменов.

После установки панель запускается простой командой:
```sh
z2m
```

---

## 🖥️ Использование

### 1. Интерактивное TUI-меню

Запустите команду `z2m` (или `zsm`) без аргументов для входа в главное меню:

```
  ███████╗ █████╗ ██████╗ ██████╗ ███████╗████████╗██████╗     ███╗   ███╗
  ╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝╚════██╗    ████╗ ████║
    ███╔╝ ███████║██████╔╝██████╔╝█████╗     ██║    █████╔╝    ██╔████╔██║
   ███╔╝  ██╔══██║██╔═══╝ ██╔══██╗██╔══╝     ██║   ██╔═══╝     ██║╚██╔╝██║
  ███████╗██║  ██║██║     ██║  ██║███████╗   ██║   ███████╗    ██║ ╚═╝ ██║
  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝    ╚═╝     ╚═╝
  Zapret2 Manager v1.1.0 | Asterlike & 1andrevich Architecture
  ───────────────────────────────────────────────────────────────────

  Устройство : OpenWrt Router (24.10.4, mips_24kc)
  Zapret2    : Запущена (PID: 2315)
  DNS / DoH  : DoH активен (https-dns-proxy)
  ───────────────────────────────────────────────────────────────────

  1. 🛡️ Настройка и служба Zapret2    (статус, запуск, перезапуск, автозапуск)
  2. 🧬 Подбор и генерация стратегий  (генератор Asterlike, автоподбор, тесты)
  3. 🎯 Каталог готовых стратегий     (9 пресетов: General, Flowseal, VK...)
  4. 🔐 Настройка DNS и DoH           (Google, Quad9, Xbox, DNS.ru, Cloudflare)
  5. 📁 Списки доменов и исключений   (YouTube, Discord, Исключения)
  6. 🩺 Диагностика сети и блокировок (проверка DPI RST/Freeze, вердикты)
  7. 📦 Синхронизация файлов и блобов (копирование fake-блобов в /opt/zapret2)
  8. 🔄 Обновить Zapret2-Manager      (автоматическое обновление из GitHub)
  0. Выход
```

### 2. Запуск через аргументы командной строки (для автоматизации)

- `z2m` или `zsm` — интерактивное меню в терминале.
- `z2m -a` или `z2m --autoselect` — автоподбор лучшей стратегии из каталога.
- `z2m -g` или `z2m --generate` — запуск двухпроходного генератора связок Asterlike.
- `z2m -yt` или `z2m --youtube` — тестирование стратегий только для YouTube.
- `z2m -dc` или `z2m --discord` — тестирование стратегий только для Discord.
- `z2m -d` или `z2m --diagnostics` — вывод отчета диагностики доступности.
- `z2m -u` или `z2m --update` — самообновление менеджера до последней версии с GitHub.
- `z2m -r` или `z2m --restart` — перезапуск службы zapret2 с перечитыванием UCI.
- `z2m -s` или `z2m --status` — проверка статуса службы.

---

## 🧠 Как работает генератор (Алгоритм Asterlike)

В отличие от простого перебора, генератор разделяет задачу на **два прохода**:

```mermaid
flowchart TD
    Start["Запуск Генератора"] --> Backup["Бэкап текущего конфига UCI"]
    Backup --> Pass1["Pass 1: Раздельное тестирование 27+ бандлов"]
    Pass1 --> ScoreD["Оценка по Discord<br>(Web + Gateway)"]
    Pass1 --> ScoreY["Оценка по YouTube<br>(Web + Googlevideo)"]
    
    ScoreD --> FilterGW{"Фильтр Gateway-friendly?<br>(fake:ts или hostfakesplit)"}
    FilterGW -- Да --> ShortD["Шортлист Discord"]
    FilterGW -- Нет --> Drop["Отсев (во избежание зависания войса)"]
    
    ScoreY --> ShortY["Шортлист YouTube"]
    
    ShortD --> Pass2["Pass 2: Совместное тестирование пар D × Y"]
    ShortY --> Pass2
    
    Pass2 --> CalcJoint["Расчет min(Score_D, Score_Y)"]
    CalcJoint --> Best["Выбор победителя, защищающего ОБА сервиса"]
    Best --> Apply["Сборка NFQWS2_OPT + коммит в UCI + Рестарт"]
```

1. **Pass 1**: каждый бандл проверяется изолированно с живым выводом прогресса (`⏳ Тест...`).
2. **Фильтр Gateway-friendly**: Discord использует особый размер ClientHello для соединения с голосовыми шлюзами (`gateway.discord.gg`). Непраймированные стратегии с большими смещениями `seqovl` пускают на сайт логина, но намертво вешают голосовой шлюз. Генератор допускает в шортлист только адаптивные бандлы (`hostfakesplit` или праймированные `fake:tcp_ts`).
3. **Pass 2**: пары топ-кандидатов собираются в единое правило через `combo_builder.sh` и тестируются вместе. Выбирается связка, максимизирующая результат слабейшего из сервисов.

---

## 🎯 Каталог готовых стратегий

| Стратегия | Описание | Когда применять |
|---|---|---|
| **1. Комбо (рекомендуемый)** | Discord → `hostfakesplit`, YouTube → `fake:md5+seq multidisorder`, голос → `quic_vk` | Универсальный вариант — начинайте с него |
| **2. Комбо — отечественный (VK)** | Discord → `hostfakesplit vk.com`, YouTube → `fake multidisorder` | Если провайдер режет гугл-фейки |
| **3. Комбо — Flowseal ALT10** | Двойной fake (google + vk) с `tcp_ts=-1000` без сплита | Когда не работают медиа и голосовой шлюз |
| **4. Комбо — Flowseal ALT11** | Fake ts + `multisplit seqovl=681` (google pattern) | Высокая пробиваемость жестких ТСПУ |
| **5. Комбо — Flowseal Multisplit** | Чистый multisplit с перекрытием `seqovl=681` | Альтернатива сплита без фейков |
| **6. Комбо — Flowseal ALT** | Fake с `tcp_ts` + ложная разрезка `fakedsplit` | Если чистый multisplit не работает |
| **7. Комбо — окно (wssize)** | Multisplit + дробление окна ответа сервера (`wsize=1:scale=6`) | Для упрямых блокировок |
| **8. Discord — голос (QUIC-фейк)** | Точечная починка STUN + RTP без затрагивания веб-профилей | Если подключается, но вечный пинг 5000 |
| **9. Discord — адаптивный (circular)** | Ротация стратегий на лету при детекте RST (`fails=2`) | Экспериментальный самоподстраивающийся профиль |

---

## 🔐 Пресеты DNS-over-HTTPS (DoH)

В меню **Настройка DNS и DoH** (пункт 4) доступны предустановленные конфигурации:
1. **Google DNS** (`https://dns.google/dns-query`) — глобальный стабильный DNS.
2. **Quad9 DNS** (`https://dns.quad9.net/dns-query`) — DNS без цензуры со встроенной защитой от малвари.
3. **Xbox DNS (Comss.one)** (`https://dns.comss.one/dns-query`) — решение для снятия сетевых ограничений и ошибок входа на Xbox и PlayStation.
4. **DNS.ru / Yandex DNS** (`https://common.dot.dns.yandex.net/dns-query`) — минимальный пинг для пользователей РФ.
5. **Cloudflare DNS** (`https://cloudflare-dns.com/dns-query`) — быстрый DNS 1.1.1.1.
6. **AdGuard DNS** (`https://dns.adguard.com/dns-query`) — блокировка рекламных трекеров на уровне роутера.
7. **Пользовательский DoH URL** — возможность указать любой собственный адрес резолвера.

---

## 🛠️ Совместимость и требования

- **Роутер**: OpenWrt 23.05, 24.10, 25.12+ (firewall4 / nftables).
- **Пакеты**: установленный [zapret2-openwrt](https://github.com/1andrevich/zapret2-openwrt) (`zapret2` + `luci-app-zapret2`), утилита `curl`.
- **ПК / Клиенты сети**: для корректной работы стратегий с временными метками (`tcp_ts`) на устройствах Windows рекомендуется включить TCP timestamps:
  ```cmd
  netsh int tcp set global timestamps=enabled
  ```

---

## 📄 Лицензия

Проект распространяется под лицензией MIT. Подробнее см. в файле [LICENSE](LICENSE).  
Благодарности авторам:
- **Asterlike** за концепцию и реализацию генератора в [zapret2UI](https://github.com/Asterlike/zapret2UI).
- **1andrevich** за пакет [zapret2-openwrt](https://github.com/1andrevich/zapret2-openwrt).
- **bol-van** за оригинальный [zapret]([https://github.com/bol-van/zapret](https://github.com/bol-van/zapret2)).
- **Flowseal** за сообщество и актуальные наработки по обходу DPI.
- **StressOzz** за концепцию модульного автоскрипта для OpenWrt [Zapret-Manager](https://github.com/StressOzz/Zapret-Manager).
