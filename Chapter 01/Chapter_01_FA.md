---
lang: fa
dir: rtl
title: "فصل 01 — چه کسی می‌تواند رمز را بخواند، و این رمز تا حالا کجاها رفته است؟"
---
&#x202b;


# فصل 01، چه کسی می‌تواند رمز را بخواند، و این رمز تا حالا کجاها رفته است؟

**سیستم، پیش از این فصل.** یک ماشین، `HOST-01 dev01`. روی آن: یک سرویس کوچک HTTP به نام
`APP-01 paymentsvc`، و یک پایگاه‌داده PostgreSQL به نام `SVC-01 paymentsdb`. اپلیکیشن با نقش
`ACC-02 paymentsvc` و با یک رمز عبور، یعنی `SEC-01 paymentsvc-db-password`، وارد پایگاه‌داده
می‌شود؛ رمزی که به‌صورت متن ساده و کاملاً خوانا در خط 4 فایل `/opt/paymentsvc/config.yaml`
نشسته است. شما، یعنی `ACC-01`، هم‌زمان توسعه‌دهنده، اپراتور، DBA، تیم امنیت و ممیز (auditor)
هستید. هیچ رمزنگاری‌ای در هیچ‌کجای این سیستم وجود ندارد، هیچ مؤلفه‌ای تصمیم نمی‌گیرد چه کسی
حق دارد رمز را داشته باشد، و هیچ سابقه‌ای از این‌که چه کسی تا به حال آن را خوانده ثبت نمی‌شود.

**فشار.** `OT-001`. آن رمز عبور در یک فایل خوانا نشسته است. دو سؤال هرگز پرسیده نشده‌اند، و تا
وقتی پرسیده نشوند، هر چیز دیگری که بسازیم چیزی جز حدس‌وگمان نیست:

1. **همین الان چه کسی می‌تواند آن را بخواند؟** نه چه کسی *باید* بتواند، بلکه چه کسی *می‌تواند*.
2. **تا حالا کجاها رفته است؟** رازی که یک‌بار نوشته شود، در یک جا نمی‌ماند. سازوکارهایی آن را
   کپی می‌کنند که هیچ‌کس انتخابشان نکرده، هیچ‌کس پیکربندی‌شان نکرده و هیچ‌کس تماشایشان نمی‌کند.

**تا پایان این فصل چه چیزی را راه‌انداخته‌اید.**

- یک آزمایشگاه پابرجا: `dev01` که مثل یک هاست واقعی Linux با PostgreSQL و `paymentsvc` اجرا
  می‌شود و همه فصل‌های بعدی روی آن بنا می‌شوند.
- هفت نسخه متمایز از `SEC-01` که خودتان پیدایشان کرده‌اید، روی ماشینی که فکر می‌کردید فقط
  یک نسخه دارد.
- یک packet capture از احراز هویت اپلیکیشن‌تان، و یک نتیجه واقعاً غافلگیرکننده درباره این‌که
  چه چیزی روی سیم هست و چه چیزی نیست.
- یک هویت اختصاصی در سطح سیستم‌عامل برای اپلیکیشن، یک فایل پیکربندی قفل‌شده، و یک سرویس
  خراب که خودتان عیب‌یابی و درستش می‌کنید.
- یک نقشه صادقانه از این‌که مجوزهای فایل چه چیزهایی را بستند، به چه چیزهایی اصلاً نمی‌رسند، و
  چرا تنها درمان واقعیِ یک اعتبارنامه (credential) لو رفته کاری است که فعلاً هیچ راهی برای
  انجامش نداریم.

---

## 0. اگر خروجی شما فرق داشت

مقادیر وابسته به ماشین، مثل شناسه پروسه‌ها، برچسب‌های زمانی، شناسه کانتینرها و تعداد بایت‌ها،
به‌صورت جای‌نگهدار (placeholder) مثل `<pid>` نمایش داده می‌شوند.

جز این‌ها، خروجی شما باید با آنچه نشان داده شده یکی باشد. اگر یکی نبود، ارزش یک دقیقه وقت
گذاشتن را دارد، نه شانه بالا انداختن؛ دو علت معمول عبارت‌اند از نسخه اصلی متفاوت PostgreSQL
(با `sudo docker exec dev01 psql --version` بررسی کنید) و درایور ذخیره‌سازی متفاوت Docker.
هر دو در همان‌جاهایی که اهمیت پیدا می‌کنند یادآوری شده‌اند.

---

## 1. برپا کردن `dev01`

فصل 00 به `HOST-01 dev01` یک نام و یک تعهد داد. حالا این ماشین واقعاً به اجرا درمی‌آید.

هر چیزی که لازم دارید همین کنار این فصل، در پوشه `lab/` آن، موجود است. همان‌جا کار کنید؛
همه دستورهای این فصل فرض می‌کنند که دایرکتوری کاری شما همان است:

```bash
cd "Chapter 01/lab"
ls
```

انتظار: `docker-compose.yml` و یک دایرکتوری `dev01/`.

آن پوشه مال شماست تا خرابش کنید. فایل‌هایش را ویرایش می‌کنید، در یک مخزن git که در §4.2
می‌سازید کامیت می‌کنید، و عمداً در آن آشغال به جا می‌گذارید. نسخه‌ای که دانلود کرده‌اید حالت
اولیه دست‌نخورده است؛ اگر روزی خواستید برگردید، فصل را دوباره دانلود کنید.

**کانتینر بعد از این فصل هم می‌ماند.** آزمایشگاه آن پوشه نیست؛ آزمایشگاه همان کانتینر `dev01`
است که آن پوشه می‌سازد. این کانتینر بین فصل‌ها همچنان در حال اجرا می‌ماند و حالت (state) جمع
می‌کند، و هیچ فصل بعدی آن را از نو نمی‌سازد. فصل 02 از پوشه `lab/` *خودش* کار می‌کند و روی
همین کانتینر مستقر می‌شود.

### 1.1 چرا اپلیکیشن و پایگاه‌داده در یک کانتینر مشترک‌اند

دفتر ثبت (ledger) فصل 00 می‌گوید `paymentsvc` و `paymentsdb` هر دو روی `HOST-01` اجرا
می‌شوند. این عمدی است و دقیقاً شکل یک پروژه جانبی واقعی است: یک جعبه، همه‌چیز رویش، و همه‌اش
مورد اعتماد چون همه‌اش *مال خودتان* است. پس `dev01` یک کانتینر است که یک userland کامل
Debian را اجرا می‌کند و PostgreSQL روی آن به شیوه معمولی نصب شده، نه با ایمیج رسمی `postgres`
که به شما یک پایگاه‌داده می‌دهد اما یک *ماشین* نه. ما به یک ماشین نیاز داریم، با کاربران،
پروسه‌ها، جدول پروسه‌ها، فایل‌های لاگ و یک پشته شبکه، چون تمام هدف این فصل این است که داخل
چنین ماشینی راه برویم و چیزها را پیدا کنیم.

**کانتینر** اینجا نقش یک سرور کوچک را بازی می‌کند: یک userland ایزوله لینوکسی با فایل‌سیستم
خودش، جدول پروسه خودش و رابط‌های شبکه خودش، که کرنل لپ‌تاپ را با بقیه شریک است. این یک مرز
امنیتی نیست که به آن تکیه کنیم — چند فصل بعدی دقیقاً درباره راه‌هایی است که این مرز نشت
می‌کند — بلکه راهی ارزان برای داشتن یک ماشین است.

یک حذف عمدی: ما دایرکتوری اپلیکیشن را از لپ‌تاپ‌تان به داخل کانتینر bind-mount **نمی‌کنیم**.
روی macOS، ‏Docker Desktop مالکیت فایل‌ها را هنگام عبور از این مرز بازنویسی می‌کند، و این
بی‌سروصدا همه آزمایش‌های مجوز این فصل را تحریف می‌کرد. هر کاری کانتینر با فایل‌های خودش
می‌کند داخل فایل‌سیستم خودش اتفاق می‌افتد، بنابراین `ls -l` روی هر پلتفرمی حقیقت را می‌گوید.

### 1.2 فایل‌ها

همه فایل‌های زیر از قبل در پوشه `lab/` که در آن ایستاده‌اید موجودند. چیزی برای ساختن نیست، و
چیزی برای دوباره‌تایپ‌کردن هم نیست. با این حال همین‌جا بخوانیدشان: چند جزئیات درونشان موضوع
اصلی این فصل است، و یکی دو تا از آن‌ها تله‌های عمدی‌اند.

فایل `dev01/app/config.yaml` خانه `SEC-01` است، دقیقاً همان‌طور که فصل 00 توصیفش کرد:

```yaml
# /opt/paymentsvc/config.yaml
database:
  host: localhost
  port: 5432
  user: paymentsvc
  password: hunter2-payments-prod          # <-- SEC-01
  name: paymentsdb
server:
  listen: 0.0.0.0:8080
```

فایل `dev01/app/paymentsvc.py`، یعنی خود اپلیکیشن. حدود هشتاد خط: پیکربندی را بخوان، یک
اتصال به پایگاه‌داده باز کن، و دو endpoint را سرو کن.

```python
#!/usr/bin/env python3
"""APP-01 paymentsvc, answers 'what is the status of payment X?'"""

import json
import logging
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import yaml
from psycopg2.extras import RealDictCursor

CONFIG_PATH = os.environ.get("PAYMENTSVC_CONFIG", "/opt/paymentsvc/config.yaml")

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler("/var/log/paymentsvc.log"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("paymentsvc")


def load_config(path):
    log.info("loading configuration from %s", path)
    with open(path) as fh:
        cfg = yaml.safe_load(fh)
    # NOTE (Chapter 01): this one line is deliberate, and it is extremely common
    # in real codebases. Chapter 01 shows you exactly what it costs.
    log.debug("effective configuration: %s", cfg)
    return cfg


cfg = load_config(CONFIG_PATH)
db = cfg["database"]

conn = psycopg2.connect(
    host=db["host"],
    port=db["port"],
    user=db["user"],
    password=db["password"],
    dbname=db["name"],
)
conn.autocommit = True
log.info("connected to %s@%s:%s/%s", db["user"], db["host"], db["port"], db["name"])


class Handler(BaseHTTPRequestHandler):
    server_version = "paymentsvc/0.1"

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            return self._json(200, {"status": "ok"})

        parts = self.path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "payments" and parts[2] == "status":
            try:
                payment_id = int(parts[1])
            except ValueError:
                return self._json(400, {"error": "payment id must be an integer"})
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, reference, amount_cents, currency, status "
                    "FROM payments WHERE id = %s",
                    (payment_id,),
                )
                row = cur.fetchone()
            if row is None:
                return self._json(404, {"error": "no such payment"})
            return self._json(200, dict(row))

        return self._json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        log.info("%s %s", self.address_string(), fmt % args)


if __name__ == "__main__":
    host, _, port = cfg["server"]["listen"].rpartition(":")
    srv = ThreadingHTTPServer((host, int(port)), Handler)
    log.info("listening on %s", cfg["server"]["listen"])
    srv.serve_forever()
```

دو چیز در آن فایل مهم‌تر از آن‌اند که به نظر می‌رسند.

خط `log.debug("effective configuration: %s", cfg)` هر وقت سطح لاگ روی `DEBUG` باشد، کل
پیکربندی پارس‌شده — از جمله `SEC-01` — را لاگ می‌کند. من آن را نگذاشته‌ام که شما را به دام
بیندازم. این خط در تعداد بسیار زیادی از کدهای واقعی وجود دارد، آن هم به دلیلی کاملاً منطقی:
این‌که وقتی سرویسی ساعت 03:00 بدرفتاری می‌کند بشود دید واقعاً چه پیکربندی‌ای بارگذاری کرده
است. در §3.4 نشت‌کردنش را تماشا می‌کنیم.

تابع `psycopg2.connect(...)` رمز عبور را به‌عنوان **آرگومان تابع** می‌گیرد، یعنی رمز هرگز در
خط فرمان پروسه ظاهر نمی‌شود. این روش درست انجام دادن کار است، و §3.3 نشان می‌دهد وقتی یک آدم
خسته راه دیگر را انتخاب می‌کند چه اتفاقی می‌افتد.

فایل `dev01/initdb.sql`، یعنی پایگاه‌داده، نقش آن و سه پرداخت:

```sql
CREATE ROLE paymentsvc LOGIN PASSWORD 'hunter2-payments-prod';
CREATE DATABASE paymentsdb OWNER paymentsvc;

\connect paymentsdb

CREATE TABLE payments (
    id           integer PRIMARY KEY,
    reference    text    NOT NULL,
    amount_cents integer NOT NULL,
    currency     char(3) NOT NULL,
    status       text    NOT NULL
);

INSERT INTO payments (id, reference, amount_cents, currency, status) VALUES
  (1001, 'INV-2026-0001', 249900, 'EUR', 'settled'),
  (1002, 'INV-2026-0002',  18050, 'EUR', 'pending'),
  (1003, 'INV-2026-0003', 990000, 'GBP', 'failed');

ALTER TABLE payments OWNER TO paymentsvc;
```

توجه کنید — فعلاً بدون این‌که کاری درباره‌اش بکنیم — که `SEC-01` حالا در یک فایل **دوم** هم
وجود دارد. چاره‌ای هم نبود: بالاخره چیزی باید به PostgreSQL بگوید رمز چیست. این نسخه شماره
دوست و ما هنوز شروع هم نکرده‌ایم.

فایل `dev01/entrypoint.sh`:

```sh
#!/bin/sh
set -e

pg_ctlcluster 15 main start

# wait for the cluster to accept connections
i=0
while [ $i -lt 30 ]; do
    su postgres -c "psql -tAc 'SELECT 1'" >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done

if [ ! -f /var/lib/postgresql/.initialised ]; then
    su postgres -c "psql -v ON_ERROR_STOP=1 -f /opt/paymentsvc/initdb.sql"
    touch /var/lib/postgresql/.initialised
fi

# the application's log file, with the permissions an application log
# almost always has in the real world
touch /var/log/paymentsvc.log /var/log/paymentsvc.out
chown paymentsvc:paymentsvc /var/log/paymentsvc.log /var/log/paymentsvc.out
chmod 0644 /var/log/paymentsvc.log /var/log/paymentsvc.out

echo "dev01 ready, PostgreSQL is up."
exec sleep infinity
```

دستور `pg_ctlcluster 15 main start` روش Debian برای راه‌اندازی یک cluster پستگرس است. Debian
می‌تواند چند نسخه PostgreSQL را کنار هم اجرا کند، بنابراین هر cluster با نسخه و نام شناخته
می‌شود؛ اینجا نسخه `15` و cluster ‏`main`. پیکربندی‌اش در `/etc/postgresql/15/main/` و
داده‌هایش در `/var/lib/postgresql/15/main/` قرار دارد. بعداً در همین فصل از هر دو مسیر
استفاده خواهید کرد.

دستور `exec sleep infinity` در انتها همان چیزی است که کانتینر را زنده نگه می‌دارد. یک کانتینر
وقتی پروسه اصلی‌اش تمام شود خارج می‌شود؛ ما ماشینی می‌خواهیم که همان‌جا بنشیند، پس پروسه
اصلی یک sleep است و کارهایمان را با `docker exec` انجام می‌دهیم.

فایل `dev01/Dockerfile`:

```dockerfile
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-15 \
        python3 python3-yaml python3-psycopg2 \
        procps psmisc iproute2 tcpdump curl less nano ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# belt and braces: the Debian package normally creates the main cluster on
# install, but that step relies on an init system we do not have in a build
# container. Create it if it is missing.
RUN pg_lsclusters | grep -q '^15 *main' || pg_createcluster 15 main

# the identity the application will eventually run as. It exists from the
# start because the log file needs an owner; nothing runs as it until §7.
RUN useradd --system --home-dir /opt/paymentsvc --shell /usr/sbin/nologin paymentsvc

COPY app/paymentsvc.py /opt/paymentsvc/paymentsvc.py
COPY app/config.yaml   /opt/paymentsvc/config.yaml
COPY initdb.sql        /opt/paymentsvc/initdb.sql
COPY entrypoint.sh     /usr/local/bin/entrypoint.sh

# COPY reproduces whatever mode the file had on your laptop, and that is
# decided by your umask: 0644 under the common 022, 0664 under 002. Pin it,
# so section 3.1 shows you the same thing it shows everyone else. An image
# whose file modes depend on who built it is a bad image regardless.
RUN chmod 0644 /opt/paymentsvc/paymentsvc.py \
               /opt/paymentsvc/config.yaml \
               /opt/paymentsvc/initdb.sql \
 && chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

هر پکیجی آنجا جای خودش را حق دارد: `postgresql-15` همان پایگاه‌داده است؛ `python3-yaml` و
`python3-psycopg2` دو وابستگی اپلیکیشن‌اند که به‌صورت پکیج Debian نصب شده‌اند تا در زمان اجرا
نه `pip` لازم باشد، نه کامپایلر و نه شبکه؛ `procps` به ما `ps` و `pkill` می‌دهد؛ `tcpdump` و
`iproute2` برای §5 هستند؛ و `curl` برای تست.

فایل `docker-compose.yml`:

```yaml
# The lab substrate: one container per "machine" in the ledger.
#
# Bring each machine up ONCE, in the chapter that introduces it, naming the
# service so you only build that one:
#     Chapter 01:  docker compose up -d --build dev01
#     Chapter 04:  docker compose up -d --build db01
#
# After that, chapters deploy into the running container with `docker cp`.
# Rebuilding is not forbidden, it is a reset: a rebuilt dev01 starts from
# Chapter 01's image again and loses everything the later chapters built
# inside it, which is OS accounts, file modes, database rows and some
# deliberately left log lines. If you do rebuild, you are starting the lab
# over and need to work the chapters forward again.
#
# This file is identical in every chapter's lab/ folder until a chapter
# adds a machine, so `docker compose up -d` from any of them is a no-op on
# a lab that is already running.
#
# Processes inside the containers are still started by hand. That is not an
# oversight: these hosts have no service manager, and giving them one is a
# chapter of its own.

name: lab

services:
  dev01:                                    # HOST-01, where the app and the secret store live
    build:
      context: ./dev01
      dockerfile: Dockerfile
    image: ksm/dev01:chapter01              # named for the chapter that builds it
    container_name: dev01
    hostname: dev01.lab.simurgh.example

    # Published on the laptop's loopback only, never on the network. The
    # difference between 127.0.0.1:8080:8080 and 8080:8080 is the difference
    # between a service your laptop can reach and one the coffee shop can.
    ports:
      - "127.0.0.1:8080:8080"

    # tcpdump needs this to put the loopback interface into the mode it
    # wants. Chapter 01 section 5 uses it.
    cap_add:
      - NET_ADMIN

    # Reap zombies and forward signals. The entrypoint ends in
    # `sleep infinity`, which is not a real init.
    init: true

    # Substrate only: tells you whether PostgreSQL is accepting connections,
    # so `docker compose ps` means something. It deliberately gates nothing,
    # because nothing in this build starts automatically yet.
    healthcheck:
      test: ["CMD", "pg_isready", "-q", "-h", "127.0.0.1", "-p", "5432"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s

    stop_grace_period: 5s
```

استفاده از Compose، به جای یک `docker run` دست‌ساز، رابط ما با آزمایشگاه در کل این ساخت است.
Compose جای خوانایی است برای گفتن این‌که یک ماشین *چیست*، و وقتی فصل‌های بعدی به ماشین دوم
نیاز پیدا کنند، یک سرویس اینجا اضافه می‌کنند به‌جای اختراع یک دستور دیگر برای به‌خاطر سپردن.

چهار خط ارزش یادداشت دارند. خط `ports: "127.0.0.1:8080:8080"` اپلیکیشن را فقط روی رابط
loopback لپ‌تاپ‌تان منتشر می‌کند، نه روی Wi-Fi؛ تفاوت این با `8080:8080` تفاوت سرویسی است که
فقط لپ‌تاپ شما به آن می‌رسد با سرویسی که کافی‌شاپ هم به آن می‌رسد. خط `cap_add: NET_ADMIN` به
`tcpdump` داخل کانتینر اجازه می‌دهد رابط loopback را در حالتی بگذارد که بخش 5 لازم دارد. خط
`init: true` به کانتینر یک init واقعی می‌دهد تا پروسه‌های zombie را جمع کند و سیگنال‌ها را
منتقل کند، چون entrypoint ما به `sleep infinity` ختم می‌شود که init نیست. و `healthcheck` به
شما می‌گوید آیا PostgreSQL اتصال‌ها را می‌پذیرد یا نه، تا `docker compose ps` چیز معناداری
گزارش کند.

توجه کنید که healthcheck عمداً چه کاری **نمی‌کند**: هیچ چیزی را مشروط نمی‌کند. Compose
می‌تواند سرویس‌ها را به ترتیب وابستگی راه بیندازد و وقتی می‌میرند دوباره بالا بیاورد، و این
ساخت از هیچ‌کدام از این دو قابلیت استفاده نمی‌کند، چون هیچ چیزی داخل کانتینر خودکار شروع
نمی‌شود. `HOST-01` هیچ service manager ندارد. این یک شکاف واقعی است، در فصلی بعدی گاز
می‌گیرد، و پوشاندنش اینجا با یک قابلیت Compose فشاری را پنهان می‌کرد که در نهایت آن را به
شکل درست حل می‌کند.

### 1.3 بالا بیاوریدش

از پوشه `lab/` همین فصل، همانی که `docker-compose.yml` را دارد:

```bash
sudo docker compose up -d --build dev01
```

نام‌بردن صریح از سرویس عادتی است که همین حالا — وقتی فقط یکی هست — ارزش ساختن دارد.

اولین بار ساخت چند دقیقه طول می‌کشد، چون دارد Debian و PostgreSQL را دانلود می‌کند. سپس:

```bash
sudo docker compose ps
sudo docker exec dev01 pg_lsclusters
```

انتظار: یک کانتینر به نام `dev01`، و یک cluster که به‌صورت `15 main ... online` گزارش شود.
وضعیت کانتینر ظرف حدود نیم دقیقه از `starting` به `healthy` می‌رود، به‌محض این‌که PostgreSQL
اتصال‌ها را بپذیرد؛ اگر روی `starting` ماند، یعنی cluster بالا نیامده و
`sudo docker compose logs dev01` دلیلش را می‌گوید.

اپلیکیشن را راه بیندازید. دستور `docker exec -d` آن را detached اجرا می‌کند، همان‌طور که یک
سرویس اجرا می‌شود:

```bash
sudo docker exec -d dev01 sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

### 1.4 ثابت کنید کار می‌کند

```bash
curl -s http://127.0.0.1:8080/healthz
curl -s http://127.0.0.1:8080/payments/1001/status
curl -s http://127.0.0.1:8080/payments/9999/status
```

انتظار:

```json
{"status": "ok"}
{"id": 1001, "reference": "INV-2026-0001", "amount_cents": 249900, "currency": "EUR", "status": "settled"}
{"error": "no such payment"}
```

این کل سیستم فصل 00 است که حالا در حال اجراست. شکل 1.1 نشان می‌دهد چه چیزی ساخته‌اید.

```mermaid
flowchart TB
    subgraph LAP["your laptop"]
        direction TB
        subgraph LAB["★ NET-01 lab, HOST-01 dev01 container (trusted entirely by assumption)"]
            direction TB
            CFG{{"SEC-01 in /opt/paymentsvc/config.yaml<br/>mode 0644, owner root:root"}}:::secret
            SQL{{"★ SEC-01 again, in /opt/paymentsvc/initdb.sql<br/>mode 0644, owner root:root"}}:::secret
            APP["APP-01 paymentsvc<br/>python3, running as root<br/>listening 0.0.0.0:8080"]:::app
            DB[("SVC-01 paymentsdb<br/>PostgreSQL 15, 127.0.0.1:5432")]:::store
            LOG[("★ /var/log/paymentsvc.log<br/>mode 0644")]:::store
        end
        U(["ACC-01 you"]):::human
    end

    U -.->|"docker exec, local socket, no protection"| LAB
    CFG -.->|"password bytes, file read at startup, no protection"| APP
    SQL -.->|"password bytes, read once at first boot, no protection"| DB
    APP -.->|"login as ACC-02, PostgreSQL 5432, nothing verifies the server"| DB
    APP -.->|"whatever it decides to write, file append, no protection"| LOG

    style LAP fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4
    style LAB fill:#f8fafc,stroke:#475569,stroke-width:1px

    classDef human fill:#ffffff,stroke:#4b5563,stroke-width:2px,stroke-dasharray:4 3,color:#111827
    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef control fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px,color:#0b1f4b
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef store fill:#e2e8f0,stroke:#475569,stroke-width:1px,color:#0f172a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef best fill:#dcfce7,stroke:#15803d,stroke-width:3px,color:#052e16
    classDef retired fill:#f8fafc,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:2 4,color:#94a3b8
    classDef new stroke-width:3px,stroke-dasharray:6 3
```

**شکل 1.1، `dev01` آن‌طور که واقعاً ساخته شد.** شکل 0.1 فصل 00، این بار در برابر یک ماشین در
حال اجرا. صرفاً به این دلیل که آن را واقعی کردیم دو چیز تغییر کرد، هر دو با ★ علامت خورده‌اند.
اول، حالا **دو** شش‌ضلعی کهربایی داریم نه یکی: `SEC-01` هم در `config.yaml` برای اپلیکیشن است
و هم در `initdb.sql` برای پایگاه‌داده، چون بالاخره چیزی باید به PostgreSQL می‌گفت رمز چیست.
دوم، حالا یک فایل لاگ داریم که هیچ‌کس طراحی‌اش نکرد ولی هر سرویسی یکی دارد. همچنین توجه کنید
که لپ‌تاپ شما حالا به‌عنوان یک **منطقه نامعتمد** (کهربایی خط‌چین) کشیده شده است: کانتینر همان
ماشینی است که درباره‌اش استدلال می‌کنیم، و هر چیزی بیرون آن — دیسک لپ‌تاپ شما، بکاپ‌هایش،
همگام‌سازی ابری‌اش — بیرون مرزی است که وانمود می‌کنیم کنترلش می‌کنیم. همه یال‌ها هنوز
نقطه‌چین‌اند. هیچ چیزی اینجا با هیچ چیزی محافظت نشده است.

---

## 2. دو اصطلاح که پیش از شروع شکار لازم داریم

قرار است درباره این حرف بزنیم که چه کسی می‌تواند یک فایل را بخواند، پس:

**مالکیت و mode.** هر فایل روی یک سیستم Unix یک **کاربر** مالک، یک **گروه** مالک، و یک
**mode** نُه‌بیتی دارد که خواندن/نوشتن/اجرا را جداگانه به مالک، به گروه و به *بقیه همه*
می‌دهد. مقدار `0644` یعنی: مالک می‌تواند بخواند و بنویسد؛ گروه می‌تواند بخواند؛ و بقیه همه
می‌توانند بخوانند. همان بند آخر است که اهمیت دارد. این حالت پیش‌فرض تقریباً هر فایلی است که
هر چیزی می‌سازد، و معنایش این است: «هر حسابی روی این ماشین».

**احراز هویت و محرمانگی دو ویژگی متفاوت‌اند.** احراز هویت (authentication) به این پاسخ می‌دهد
که *آن طرف این اتصال کیست؟* محرمانگی (confidentiality) به این پاسخ می‌دهد که *آیا شخص ثالثی
می‌تواند بخواند ما چه می‌گوییم؟* می‌شود یکی را بدون دیگری داشت. یک سیستم می‌تواند هویت شما را
بی‌نقص اثبات کند و بعد با صدای بلند وسط یک اتاق شلوغ درباره حقوق شما حرف بزند. این تمایز را
نگه دارید؛ §5 روی همین می‌چرخد.

---

## 3. شکار، بخش الف: نسخه‌هایی که همین الان روی این ماشین‌اند

هر چیزی در این بخش را خودتان *نشان خواهید داد*. §6 آن بردارهایی را فهرست می‌کند که واقعی‌اند
اما ما به‌جای اجرا فقط برمی‌شماریمشان، و این را صریح می‌گوید تا همیشه بدانید چه چیزی را اثبات
کرده‌اید و چه چیزی را فقط به شما گفته‌اند.

یک shell روی ماشین بگیرید:

```bash
sudo docker exec -it dev01 bash
```

هر چیزی در §3 داخل همان shell اجرا می‌شود.

### 3.1 نسخه 1 و 2، خودِ فایل‌ها

```bash
ls -l /opt/paymentsvc/
stat -c '%A %U:%G %s %n' /opt/paymentsvc/config.yaml /opt/paymentsvc/initdb.sql
```

انتظار:

```
-rw-r--r-- root:root  196 /opt/paymentsvc/config.yaml
-rw-r--r-- root:root  612 /opt/paymentsvc/initdb.sql
```

الگوی `-rw-r--r--` همان `0644` است: خواندنی برای هر حسابی روی ماشین.

یک نکته درباره این‌که چطور این‌طور شد، چون این نکته حرف ما را تقویت می‌کند نه تضعیف. فایل
Dockerfile این mode‌ها را با یک `chmod` صریح تثبیت می‌کند تا خط بالا هم روی ماشین شما و هم
روی ماشین من یکسان باشد. اگر به حال خود رها می‌شد، `COPY` هر mode‌ای را که فایل روی لپ‌تاپ
شما داشت بازتولید می‌کرد، و آن را **umask** شما تعیین می‌کند: `0644` زیر `022` رایج، و `0664`
زیر `002` که خیلی از راه‌اندازی‌ها استفاده می‌کنند. اگر بدون آن تثبیت دوباره build کنید،
احتمالاً به‌جایش `-rw-rw-r--` می‌بینید، که هم برای همه خواندنی است **و هم** برای گروه نوشتنی.

همین تغییرپذیری خودش درس است، نه یک دردسر. مجوز روی اعتبارنامه production شما را یک پیش‌فرض
shell تعیین کرده که هیچ‌کس در سازمان شما از زمان نصب آن ماشین به آن نگاه نکرده است. نه کسی
`0644` را انتخاب کرد و نه کسی `0664` را. `cp` یکی از این‌ها را تولید می‌کند، ویرایشگر شما یکی
از این‌ها را تولید می‌کند، `git checkout` یکی از این‌ها را تولید می‌کند، و اکثریت قاطع رازهایی
که تا به حال از یک فایل پیکربندی بیرون درز کرده‌اند، از فایلی درز کرده‌اند که mode آن از چیزی
به ارث رسیده بود که هیچ‌کس به آن فکر نمی‌کرد.

کل مسیر را بررسی کنید، چون یک فایل فقط به اندازه دایرکتوری‌های بالای سرش خصوصی است:

```bash
namei -l /opt/paymentsvc/config.yaml
```

انتظار:

```
f: /opt/paymentsvc/config.yaml
 drwxr-xr-x root root /
 drwxr-xr-x root root opt
 drwxr-xr-x root root paymentsvc
 -rw-r--r-- root root config.yaml
```

هر دایرکتوری برای همه `r-x` است، پس هر حسابی می‌تواند تا خود فایل پایین برود، و خود فایل هم
برای همه `r--` است. هیچ دروازه‌ای در هیچ‌کجای این مسیر وجود ندارد.

### 3.2 نسخه 3، اثبات این‌که «بقیه همه» یعنی همه

`nobody` بی‌قدرت‌ترین حسابی است که یک سیستم لینوکس دارد. مالک هیچ چیزی نیست، در هیچ گروه
جالبی نیست، و دقیقاً برای این وجود دارد که چیزهایی که به هیچ اختیاری نیاز ندارند بتوانند بدون
هیچ اختیاری اجرا شوند. اگر `nobody` بتواند `SEC-01` را بخواند، پس هر حسابی روی ماشین می‌تواند.

```bash
su -s /bin/sh nobody -c 'cat /opt/paymentsvc/config.yaml'
```

انتظار: کل فایل پیکربندی، به‌همراه رمز عبور.

دستور `su -s /bin/sh nobody` یک فرمان را به‌عنوان `nobody` اجرا می‌کند و shell معمولاً
غیرفعال آن حساب را دور می‌زند. اینجا نه حقه‌ای در کار است و نه ارتقای سطح دسترسی: این رفتار
عادی و طراحی‌شده یک فایل با mode ‏`0644` است.

بایستید و بگذارید این جا بیفتد. هر پروسه‌ای روی این ماشین — یک agent مانیتورینگ، یک log
shipper، یک crash reporter، یک اسکریپت post-install یک پکیج، یک وابستگی آلوده در سرویسی کاملاً
بی‌ربط، یا یک دستور تک‌خطی دیباگ یک همکار — `SEC-01` را می‌خواند، بدون این‌که به چیز
ممتازی دست بزند و بدون این‌که هیچ ردی در هیچ‌کجا بگذارد.

### 3.3 نسخه 4، جدول پروسه‌ها

تابع `psycopg2.connect()` رمز را به‌عنوان آرگومان می‌گیرد، پس رمز هرگز در خط فرمان اپلیکیشن
ظاهر نمی‌شود. حالا همان کاری را بکنید که یک آدم خسته ساعت 03:00 وقتی می‌خواهد چیزی را مستقیم
چک کند انجام می‌دهد:

```bash
psql "postgresql://paymentsvc:hunter2-payments-prod@127.0.0.1:5432/paymentsdb" \
     -c 'SELECT pg_sleep(120)' &
```

تا وقتی آن در حال اجراست، از *کم‌اختیارترین* حساب روی این جعبه:

```bash
su -s /bin/sh nobody -c 'ps auxww' | grep 'postgresql://'
```

انتظار: کل URI اتصال، با رمز و همه‌چیز، چاپ‌شده توسط حسابی که هیچ اختیاری ندارد.

این کار می‌کند چون روی لینوکس خط فرمان هر پروسه از طریق `/proc/<pid>/cmdline` در دسترس است، و
آن فایل به‌صورت پیش‌فرض برای همه خواندنی است. هر چیزی که در `argv` بگذارید برای هر حسابی روی
ماشین عمومی است، تا هر وقت که پروسه زنده باشد، و هیچ راهی برای پاک کردنش پس از آن وجود ندارد.

مستقیم نگاهش کنید:

```bash
pgrep -f 'postgresql://' | head -1 | xargs -I{} sh -c 'tr "\0" " " < /proc/{}/cmdline; echo'
```

همین درباره **محیط** (environment) یک پروسه هم صادق است: `/proc/<pid>/environ`. آن یکی به‌جای
همه، فقط برای مالک پروسه و root خواندنی است، که متغیرهای محیطی را *بهتر* از آرگومان‌های خط
فرمان می‌کند و باز هم فاصله زیادی با «خوب» دارد. در فصلی بعدی به‌طور جدی به متغیرهای محیطی
برمی‌گردیم، چون رایج‌ترین جایی هستند که رازها در سیستم‌های کانتینری زندگی می‌کنند.

تمیزکاری:

```bash
pkill -f 'postgresql://' || true
```

### 3.4 نسخه 5، لاگ خودِ اپلیکیشن

اپلیکیشن را همان‌طور راه‌اندازی مجدد کنید که هنگام دیباگ‌کردنش می‌کنید:

```bash
exit                                  # leave the container shell
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d -e LOG_LEVEL=debug dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 2
sudo docker exec dev01 grep -n 'effective configuration' /var/log/paymentsvc.log
```

انتظار: یک خط `DEBUG` که کل دیکشنری پیکربندی پارس‌شده را دارد، با
`'password': 'hunter2-payments-prod'` وسطش.

حالا ببینید چه کسی می‌تواند آن لاگ را بخواند:

```bash
sudo docker exec dev01 stat -c '%A %U:%G %n' /var/log/paymentsvc.log
sudo docker exec dev01 su -s /bin/sh nobody -c 'grep -c password /var/log/paymentsvc.log'
```

انتظار: ‏mode برابر `-rw-r--r--`، و `nobody` که با خوشحالی تعداد تطبیق‌ها را می‌شمارد.

این همان برداری است که آدم‌ها را بیچاره می‌کند، و ارزش دارد بفهمیم دقیقاً چرا ریشه‌کن‌کردنش
این‌قدر سخت است. آن خط لاگ *مفید* است. وقتی سرویسی ساعت 03:00 به پایگاه‌داده اشتباهی وصل
می‌شود، «واقعاً چه پیکربندی‌ای بارگذاری کرد؟» اولین سؤال است و این خط سریع‌ترین پاسخ ممکن.
یک آدم بلد آن را نوشته، آن هم به دلیل خوبی. و فقط یک متغیر محیطی لازم بود — متغیری که وسط یک
حادثه، توسط کسی زیر فشار، تنظیم می‌شود و بعد فراموش می‌شود — تا آن خط به یک نسخه دائمی و متن
ساده از اعتبارنامه production شما تبدیل شود، در فایلی که به log aggregator شما فرستاده
می‌شود، ایندکس می‌شود، به دلایل انطباق (compliance) هفت سال نگه داشته می‌شود، و برای همه در
شرکت قابل جستجوست.

تجمیع لاگ (log aggregation) از فایل محلی *بدتر* است: راز از ماشین بیرون می‌رود، به فضای
ذخیره‌سازی‌ای کپی می‌شود که شما پیکربندی‌اش نکرده‌اید، برای دوام تکثیر می‌شود، و قابل جستجو
می‌شود. هیچ `chmod`ی به آن نمی‌رسد.

سطح لاگ را برگردانید:

```bash
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d dev01 sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

با دقت توجه کنید چه کاری را همین الان *نکردید*: آن خط DEBUG هنوز در
`/var/log/paymentsvc.log` هست. بستن شیر، سطل را خالی نمی‌کند.

### 3.5 نسخه 6، چیزی که ابزارهایتان جا می‌گذارند

یک ویرایش بی‌ضرر در پیکربندی انجام دهید — مثلاً فرض کنید یک timeout طولانی‌تر برای اتصال
می‌خواهید — با معمولی‌ترین دستور دنیا:

```bash
sudo docker exec dev01 sed -i.bak 's/^  port: 5432/  port: 5432   # default/' /opt/paymentsvc/config.yaml
sudo docker exec dev01 ls -l /opt/paymentsvc/
```

انتظار: یک فایل جدید به نام `config.yaml.bak`، با mode ‏`0644` و مالک `root:root`، که نسخه
قبلی فایل را با رمز و همه‌چیز در خود دارد.

`sed -i.bak` تنها یک نمونه از خانواده‌ای بسیار بزرگ است. `vim` هنگام ویرایش
`.config.yaml.swp` و هنگام ذخیره `config.yaml~` می‌نویسد. Emacs هم `config.yaml~` و
`#config.yaml#` می‌نویسد. `patch` فایل‌های `.orig` و `.rej` می‌نویسد. ویرایشگرهایی که crash
می‌کنند فایل swap را برای همیشه جا می‌گذارند. mode همه این‌ها `0644` است و هیچ‌کدامشان در
مدل ذهنی هیچ‌کس از «راز کجا زندگی می‌کند» نیستند.

این یکی خیلی فراتر از لپ‌تاپ اهمیت دارد: یک فایل `.bak` یا `.swp` که در document root یک وب
سرور جا مانده باشد، به‌جای اجرا شدن به‌صورت متن ساده سرو می‌شود؛ کلاسی از باگ که بیست‌وپنج
سال است اعتبارنامه‌های پایگاه‌داده را به اینترنت باز نشت می‌دهد و هنوز متوقف نشده است.

فعلاً فایل `.bak` را همان‌جا بگذارید. در §8 به آن برمی‌گردیم.

---

## 4. شکار، بخش ب: نسخه‌هایی که پیشاپیش از ماشین بیرون رفته‌اند

نسخه‌های 1 تا 6 همه روی `dev01` هستند. در اصل می‌توانستید حذفشان کنید. این بخش درباره
نسخه‌هایی است که نمی‌توانید.

### 4.1 نسخه 7، بکاپ

```bash
sudo docker exec dev01 tar czf /tmp/opt-backup.tar.gz /opt
sudo docker exec dev01 sh -c 'zcat /tmp/opt-backup.tar.gz | grep -a -c hunter2'
```

انتظار: یک هشدار `tar: Removing leading '/'`، و بعد یک عدد غیرصفر.

هیچ چیز آن دستور بکاپ اشتباه نیست. این همان کاری است که هر agent بکاپ، هر job بازیابی از
فاجعه (disaster recovery) و هر غریزه «بگذار قبل از دست‌زدن به این یک snapshot بگیرم» انجام
می‌دهد. و بکاپ جای *به‌ویژه* بدی برای یک راز است، چون بکاپ‌ها عمداً طوری مهندسی شده‌اند که
بادوام، تکثیرشده، طولانی‌مدت نگه‌داشته‌شده و قابل بازیابی توسط افرادی غیر از شما باشند. رازی
که به سیستم بکاپ شما برسد، قوی‌ترین تضمین‌های ماندگاری‌ای را گرفته که سازمان شما توان
فراهم‌کردنشان را دارد.

چرخاندن رمز (rotation) بکاپ را تمیز نمی‌کند. حذف فایل بکاپ را تمیز نمی‌کند. آن نسخه تا وقتی
سیاست نگه‌داری منقضی‌اش کند معتبر است، که برای یک کسب‌وکار تحت مقررات با واحد سال اندازه‌گیری
می‌شود.

### 4.2 نسخه 8، کنترل نسخه، و چرا این یکی فرق دارد

هر چیزی تا اینجا را در اصل می‌شد دنبال کرد و حذف کرد. حالا نوبت آن یکی است که نمی‌شود.

روی لپ‌تاپ خودتان، نه داخل کانتینر. پوشه `lab/` این فصل را زیر کنترل نسخه ببرید، دقیقاً
همان‌طور که با هر پروژه‌ای که واقعاً می‌ساختید:

```bash
git init
git config user.email "you@simurgh.example"
git config user.name  "you"
git add .
git commit -m "paymentsvc: initial lab environment"
```

*(اگر این فصل را با clone کردن یک مخزن گرفته‌اید، `git init` اینجا یک مخزن دوم و مستقل داخل
آن می‌سازد. این بی‌ضرر است، مخزن بیرونی نادیده‌اش می‌گیرد، و این نمایشگاه را کاملاً مال خودتان
نگه می‌دارد. اگر ترجیح می‌دهید تودرتو نباشد، اول پوشه `lab/` را جای دیگری کپی کنید و بقیه این
بخش را آنجا اجرا کنید.)*

حالا متوجه اشتباهتان بشوید و درست حلش کنید:

```bash
sed -i.tmp 's/^  password: .*/  password: ${PAYMENTSVC_DB_PASSWORD}/' dev01/app/config.yaml
rm -f dev01/app/config.yaml.tmp
git add -A
git commit -m "paymentsvc: stop committing the database password"
```

فایل فعلی تمیز است. تأییدش کنید:

```bash
grep password dev01/app/config.yaml
```

انتظار: `  password: ${PAYMENTSVC_DB_PASSWORD}`، بدون هیچ رازی.

حالا از git بپرسید:

```bash
git log --oneline
git show HEAD~1:dev01/app/config.yaml | grep password
```

انتظار: همان خط اصلی، با `hunter2-payments-prod` در آن.

و شکل کلی‌اش، که همان روشی است که یک مهاجم با یک clone از مخزن شما واقعاً استفاده می‌کند؛
جستجوی هم‌زمان در هر object در کل تاریخچه:

```bash
git grep -n hunter2 $(git rev-list --all) -- dev01/app/config.yaml
```

انتظار: دست‌کم یک نتیجه، که نام کامیتی را می‌گوید که هنوز رمز را در خود دارد.

**چرا این نسخه از نظر ماهیت متفاوت است.** ‏Git یک فایل‌سیستم با تاریخچه نیست؛ یک انبار object
مبتنی بر محتوا (content-addressed) است که در آن هر نسخه از هر فایل یک object دائمی و
تغییرناپذیر است که با hash محتوایش شناخته می‌شود. «حذف کردن» رمز یک object *جدید* اضافه کرد.
آن قدیمی هنوز آنجاست، از کامیت قدیمی قابل دسترسی است، و کلمه‌به‌کلمه در هر clone‌ای که هر کسی
تا ابد بگیرد کپی می‌شود. اگر این مخزن تا به حال جایی push شده باشد، آنگاه:

- هر clone‌ای که هر کسی گرفته آن را دارد، برای همیشه، آفلاین، خارج از دسترس شما؛
- سرورهای ارائه‌دهنده هاستینگ شما آن را دارند، در بکاپ‌ها و کش‌هایی که نمی‌توانید فهرستشان
  کنید؛
- و اگر مخزن حتی برای چند دقیقه عمومی بوده باشد، اسکرپرهای خودکاری که جریان کامیت‌های عمومی
  را تماشا می‌کنند آن را دارند. صنعتی جاافتاده دقیقاً برای همین کار وجود دارد، و زمان میانه از
  ظاهر شدن یک اعتبارنامه در یک مخزن عمومی تا استفاده شدن از آن با واحد **دقیقه** اندازه‌گیری
  می‌شود، نه روز.

حذف واقعی‌اش یعنی بازنویسی تاریخچه با ابزاری مثل `git filter-repo`، که hash هر کامیت پس از
کامیت آسیب‌دیده را عوض می‌کند، بعد force-push، بعد این‌که همه همکارها دوباره clone کنند، و بعد
درخواست از ارائه‌دهنده هاستینگ برای garbage-collect کردن object‌های بی‌ارجاع و منقضی‌کردن
کش‌هایشان — و حتی آن وقت هم، هر clone‌ای که پیش از شروع این کار گرفته شده هنوز آن را دارد.

و به همین دلیل، پاسخ صادقانه به «ما یک راز را کامیت کردیم» هیچ‌وقت «آن را از مخزن حذف کردیم»
نیست. پاسخ این است: **آن اعتبارنامه لو رفته، عوضش کنید.**

این جمله را نگه دارید. کل این فصل به همین‌جا می‌رود.

---

## 5. شکار، بخش ج: واقعاً چه چیزی روی سیم است

شکل 0.1 فصل 00 یال اپلیکیشن به پایگاه‌داده را «محافظت‌نشده» برچسب زد. بیایید توصیف‌کردنش را
بس کنیم و نگاهش کنیم.

### 5.1 ضبطش کنید

```bash
sudo docker exec -d dev01 sh -c 'tcpdump -U -i lo -s 0 -w /tmp/pg-default.pcap tcp port 5432'
sleep 2
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d -e PGSSLMODE=disable dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 3
curl -s http://127.0.0.1:8080/payments/1001/status
sleep 1
sudo docker exec dev01 pkill tcpdump || true
```

انتظار: رکورد پرداخت 1001 که با همان `curl` چاپ می‌شود.

```json
{"id": 1001, "reference": "INV-2026-0001", "amount_cents": 249900, "currency": "EUR", "status": "settled"}
```

`tcpdump` ابزار ضبط بسته است: ‏`-i lo` روی رابط loopback گوش می‌دهد (اپلیکیشن و پایگاه‌داده
روی یک هاست‌اند، پس ترافیکشان هرگز به یک NIC فیزیکی نمی‌رسد)، `-s 0` بسته‌ها را کامل ضبط
می‌کند به‌جای بریدنشان، و `-w` یک فایل `.pcap` می‌نویسد. سوییچ `-U` هر بسته را به‌محض رسیدن
در فایل می‌نویسد به‌جای بافر کردن، تا کشتن `tcpdump` نتواند چند ثانیه آخر ضبط را از بین ببرد.
اپلیکیشن را وسط کار ری‌استارت می‌کنیم تا یک **ورود تازه** درست وقتی تماشا می‌کنیم اتفاق
بیفتد؛ احراز هویت فقط هنگام برقراری یک اتصال رخ می‌دهد.

آن `curl` تزئینی نیست. اگر یک رکورد پرداخت چاپ کرد، یعنی وقتی ما تماشا می‌کردیم یک کوئری از
روی سیم گذشته، و هر چیزی در بخش بعد درباره ضبطی است که *چیزی* در آن هست.

### 5.2 اول ثابت کنید ضبط خالی نیست

این گام به‌خاطر شکل چیزی که قرار است پیدا کنیم وجود دارد، و رد شدن از آن باعث می‌شود از هیچ،
نتیجه بگیرید:

```bash
sudo docker exec dev01 sh -c 'tcpdump -r /tmp/pg-default.pcap 2>/dev/null | wc -l'
```

انتظار: چند ده بسته. عدد دقیقش فرق می‌کند؛ چیزی که مهم است این است که صفر نباشد.

**اگر صفر بود، همین‌جا بایستید.** هر چیزی پایین‌تر ظاهراً حرف این فصل را تأیید می‌کند در حالی
که در واقع دارد یک فایل خالی را اندازه می‌گیرد. دو چیز باعثش می‌شوند:

- **اپلیکیشن دوباره بالا نیامده**، پس هیچ‌وقت چیزی وصل نشده است. در این حالت `curl` بالا
  به‌جای رکورد پرداخت چیزی چاپ نمی‌کرد. با `docker exec dev01 tail -5
  /var/log/paymentsvc.out` بررسی کنید، هر چه گفت درست کنید، و بخش 5.1 را دوباره اجرا کنید.
- **`tcpdump` هرگز شروع نشده**، معمولاً چون اجرای قبلی هنوز فایل را در دست دارد.
  `sudo docker exec dev01 pkill tcpdump` را بزنید، بعد 5.1 را دوباره اجرا کنید.

### 5.3 نیمه غافلگیرکننده

دنبال رمز بگردید:

```bash
sudo docker exec dev01 grep -a -c 'hunter2-payments-prod' /tmp/pg-default.pcap
```

انتظار: `0`.

این عدد را در کنار تعداد بسته‌هایی که همین الان گرفتید بخوانید. به‌تنهایی، `0` یعنی یا «رمز در
این ضبط نیست» یا «چیزی در این ضبط نیست»، و این دو نتیجه‌گیری کاملاً متضاد از خروجی‌ای یکسان
هستند. یک اندازه‌گیری امنیتی می‌تواند تمیز دربیاید چون خودِ اندازه‌گیری شکست خورده، و شمارش
بخش 5.2 دقیقاً چیزی است که جلوی این اتفاق را می‌گیرد.

رمز آنجا نیست. حالا دنبال چیزی بگردید که کوئری برگرداند:

```bash
sudo docker exec dev01 grep -a -o 'INV-2026-[0-9]*' /tmp/pg-default.pcap | sort -u
sudo docker exec dev01 sh -c "grep -a -o 'SELECT id, reference[^\"]*' /tmp/pg-default.pcap | head -1"
```

انتظار: `INV-2026-0001`، و متن کامل کوئری.

این دو نتیجه را با هم بخوانید، چون این مفیدترین چیز در کل فصل است. **اعتبارنامه روی سیم
محافظت شده بود. داده‌ها نه.**

### 5.4 چرا رمز آنجا نبود

نسخه 14 به بعد PostgreSQL به‌صورت پیش‌فرض از روشی برای احراز هویت به نام `scram-sha-256`
استفاده می‌کند. تأییدش کنید:

```bash
sudo docker exec dev01 grep -v '^#' /etc/postgresql/15/main/pg_hba.conf | grep -v '^$'
sudo docker exec dev01 su postgres -c "psql -tAc \"SELECT rolname, left(rolpassword,14) FROM pg_authid WHERE rolname='paymentsvc'\""
```

انتظار: خط `host ... 127.0.0.1/32 ... scram-sha-256`، و یک مقدار ذخیره‌شده که با
`SCRAM-SHA-256` شروع می‌شود.

کاری که SCRAM می‌کند، بدون این‌که هنوز سراغ ریاضیاتش برویم، این است: به‌جای فرستادن رمز، دو
طرف مقادیر تصادفی رد و بدل می‌کنند و هر کدام با محاسبه مقداری که فقط کسی که رمز را می‌داند
می‌تواند تولید کند، ثابت می‌کند رمز را می‌داند. یک استراق‌سمع‌کننده مقادیر تصادفی و اثبات‌ها
را می‌بیند و نه می‌تواند رمز را از آن‌ها استخراج کند و نه توکنی که بعداً به او اجازه ورود
بدهد. سرور هم رمز را ذخیره نمی‌کند، فقط یک **verifier**، که برای بررسی یک اثبات کافی است و
برای تولید یک اثبات کافی نیست.

این اولین قطعه واقعی رمزنگاری در این ساخت است، و توجه کنید چطور رسید: نه چون ما انتخابش کردیم،
بلکه چون پیش‌فرض بود. پیش‌فرض‌ها در سیستم‌های شما بیش از تصمیم‌های شما دارند کار امنیتی
می‌کنند، و این از هر دو طرف می‌بُرد.

### 5.5 چرا داده‌ها محافظت نشده بودند

چون چیزی این را نخواست. تنظیمی که تصمیم می‌گیرد **`sslmode`** نام دارد، متعلق به کلاینت است، و
`disable` یعنی بدون رمزگذاری. ضبط بخش 5.1 اپلیکیشن را با `PGSSLMODE=disable` در محیطش شروع
کرد، که همان تنظیم است از راهی دیگر، تا این اندازه‌گیری برای شما همان پاسخی را بدهد که به
بقیه می‌دهد، فارغ از این‌که توزیع لینوکس شما چه تصمیمی گرفته باشد.

هیچ چیزی در `config.yaml` اصلاً اسمی از `sslmode` نبرده است، و همین بخش واقع‌گرایانه ماجراست.
تعداد بسیار زیادی از سیستم‌های production هرگز آن خط را ننوشته‌اند، و بنابراین امنیت انتقال
داده‌شان هر چیزی است که پیش‌فرض یک کتابخانه و پیش‌فرض یک پکیج آن هفته بر سرش توافق کنند.

ببینید سرور درباره اتصالی که همین الان ضبط کردید چه فکری می‌کند:

```bash
sudo docker exec dev01 su postgres -c "psql -tAc \"SELECT a.usename, s.ssl \
  FROM pg_stat_ssl s JOIN pg_stat_activity a USING (pid) WHERE a.usename = 'paymentsvc'\""
```

انتظار: `paymentsvc|f`. آن `f` تمام حرف نتیجه دوم بخش 5.3 است.

روشن‌کردنش پایان ماجرا نیست و به همین دلیل این یک اصلاح دو خطی نیست. رمزگذاری بدون راستی‌آزمایی
شما را از کسی که **گوش می‌دهد** محافظت می‌کند و اصلاً از کسی که می‌تواند **پاسخ بدهد** محافظت
نمی‌کند، و تنظیماتی که هر کدام را انجام می‌دهند متفاوت‌اند. فصل 04 این را با یک بدل‌کار
(impostor) واقعی می‌شکافد، وقتی که بین این دو مؤلفه شبکه‌ای وجود داشته باشد که ارزش حمله داشته
باشد.

شکل 1.2 نشان می‌دهد یک استراق‌سمع‌کننده روی آن رابط loopback امروز چه می‌بیند.

```mermaid
sequenceDiagram
    autonumber
    participant App as APP-01 paymentsvc
    participant Tap as tcpdump on lo
    participant DB as SVC-01 paymentsdb

    Note over App,DB: connection setup, sslmode=disable, no TLS is negotiated
    App->>DB: StartupMessage: user=paymentsvc, database=paymentsdb
    Tap-->>Tap: sees the USERNAME in plaintext
    DB-->>App: AuthenticationSASL: mechanism SCRAM-SHA-256
    App->>DB: client-first: nonce
    DB-->>App: server-first: combined nonce, salt, iteration count
    App->>DB: client-final: client proof
    Tap-->>Tap: sees nonces, salt, proof, NOT the password
    DB-->>App: server-final: server signature, AuthenticationOk

    Note over App,DB: session, everything below is plaintext
    App->>DB: Query: SELECT id, reference, amount_cents ... WHERE id = 1001
    Tap-->>Tap: sees the FULL SQL in plaintext
    DB-->>App: DataRow: 1001, INV-2026-0001, 249900, EUR, settled
    Tap-->>Tap: sees the PAYMENT RECORD in plaintext
```

**شکل 1.2، آنچه شنودگر می‌بیند.** زمان رو به پایین جریان دارد. در طول احراز هویت (گام‌های 1 تا
8) استراق‌سمع‌کننده نام کاربری، دو nonce، یک salt، یک شمارنده تکرار و یک اثبات را جمع می‌کند و
از هیچ‌کدام نمی‌تواند رمز را بازسازی کند. از گام 9 به بعد هیچ نوع محافظتی وجود ندارد: متن کامل
هر کوئری و هر سطر از هر نتیجه خواندنی است. از اعتبارنامه دفاع شد؛ رکوردهای پرداخت تحویل داده
شدند. همچنین توجه کنید چه چیزی در کل این تبادل *غایب* است: اپلیکیشن هرگز راستی‌آزمایی نکرد که
چیزی که به آن وصل شده واقعاً پایگاه‌داده‌اش باشد. هیچ چیزی اینجا جلوی چیز دیگری را که روی پورت
5432 پاسخ بدهد نمی‌گیرد.

دو پیامد بلافاصله در پی می‌آیند، و از مسئله رمز عبور مهم‌ترند:

**محرمانگی.** هر رکورد پرداختی که این سرویس تا به حال خوانده، به شکل خوانا از روی آن اتصال
عبور می‌کند. روی loopback مخاطب کوچک است. لحظه‌ای که پایگاه‌داده به ماشین دیگری منتقل شود —
که مرحله 2 است و در راه است — مخاطب می‌شود هر کسی که روی مسیر شبکه باشد.

**احراز هویت سرور.** ‏SCRAM ثابت می‌کند که *کلاینت* رمز را می‌داند. هیچ چیزی در آن تبادل ثابت
نمی‌کند که *سرور* همان پایگاه‌داده واقعی است. هر چیزی که بتواند اول پورت 5432 را اشغال کند، یا
به یک کوئری DNS برای نام میزبان پایگاه‌داده پاسخ بدهد، خودش می‌شود پایگاه‌داده. هر کوئری‌ای به
آن تحویل داده می‌شود، از جمله کوئری‌هایی که داده را افشا می‌کنند، و می‌تواند هر پاسخی که دلش
خواست برگرداند. این همان حفره‌ای است که گواهی‌های سرور TLS برای بستنش وجود دارند، و دقیقاً همان
فشاری است که گواهی‌ها را وارد این ساخت خواهد کرد، چون به آن‌ها *نیاز خواهیم داشت*، نه چون
موضوع بعدی‌اند.

### 5.6 همان سیستم، پیکربندی‌شده به شکلی که خیلی از سیستم‌های واقعی هستند

`scram-sha-256` پیش‌فرض مدرن است. تعداد زیادی از فایل‌های `pg_hba.conf` در production هنوز
`md5` می‌گویند، چون سال‌ها پیش نوشته شده و به جلو کپی شده‌اند، و بعضی‌هایشان `password`
می‌گویند که اعتبارنامه را به‌صورت متن ساده می‌فرستد. این یک مثال ساختگی نیست؛ این چیزی است که
وقتی بروید و نگاه کنید پیدا می‌کنید.

ببینید یک کلمه چه هزینه‌ای دارد:

```bash
# take a byte-for-byte copy first, reverting a regex is how labs end up
# silently running with weakened authentication for the next ten Chapters
sudo docker exec dev01 cp /etc/postgresql/15/main/pg_hba.conf /root/pg_hba.conf.orig

sudo docker exec dev01 sed -i -E 's/^(host[[:space:]].*[[:space:]])scram-sha-256([[:space:]]*)$/\1password\2/' \
    /etc/postgresql/15/main/pg_hba.conf
sudo docker exec dev01 grep -E '^(host|local)' /etc/postgresql/15/main/pg_hba.conf
sudo docker exec dev01 pg_ctlcluster 15 main reload

sudo docker exec -d dev01 sh -c 'tcpdump -U -i lo -s 0 -w /tmp/pg-plain.pcap tcp port 5432'
sleep 2
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d -e PGSSLMODE=disable dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 3
sudo docker exec dev01 pkill tcpdump || true

sudo docker exec dev01 grep -a -c 'hunter2-payments-prod' /tmp/pg-plain.pcap
```

انتظار: یک عدد غیرصفر. اعتبارنامه شما، به‌صورت ASCII، روی سیم.

توجه کنید چه چیزهایی باید درست می‌بود تا این را ببینید. روش احراز هویت باید تضعیف می‌شد **و**
اتصال باید رمزگذاری‌نشده می‌بود. هر کدام به‌تنهایی آن را پنهان می‌کرد، یعنی هر کدام بی‌سروصدا
دارد کمبود دیگری را می‌پوشاند. این وضعیت راحتی است، دقیقاً تا روزی که یکی از آن دو سر جایش
نباشد.

قبل از این‌که فراموش کنید برش گردانید، با بازگرداندن آن کپی، نه با معکوس‌کردن regex:

```bash
sudo docker exec dev01 cp /root/pg_hba.conf.orig /etc/postgresql/15/main/pg_hba.conf
sudo docker exec dev01 pg_ctlcluster 15 main reload
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d dev01 sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

آن دستور آخر اپلیکیشن را **بدون** `PGSSLMODE` شروع می‌کند، پس تنظیم رمزگذاری به پیش‌فرض
کتابخانه برمی‌گردد و آزمایشگاه بعد از یک اندازه‌گیری تضعیف‌شده باقی نمی‌ماند.

حالا راستی‌آزمایی کنید، و **همه** خطوط احراز هویت را راستی‌آزمایی کنید، نه فقط آن‌هایی که دست
زدید:

```bash
sudo docker exec dev01 grep -E '^(host|local)' /etc/postgresql/15/main/pg_hba.conf
```

انتظار: هر خط را با این جدول بسنجید، چون یک `pg_hba.conf` نیمه‌برگردانده‌شده یعنی آزمایشگاهی
که تا آخر این ساخت بی‌سروصدا با احراز هویت تضعیف‌شده کار می‌کند:

| نوع خط | روش درست | معنایش چیست |
|---|---|---|
| `local ...` | `peer` | اتصال‌های Unix-socket با uid سیستم‌عاملی آن سر سوکت احراز هویت می‌شوند. هیچ رمزی در کار نیست. این‌ها را دست نزنید. |
| `host ... 127.0.0.1/32 ...` | `scram-sha-256` | اتصال‌های TCP، از جمله اتصال اپلیکیشن. این همان خطی است که بخش 5.6 عوضش کرد. |
| `host ... ::1/128 ...` | `scram-sha-256` | معادل IPv6 آن. |

به همین دلیل ما فایل را کپی کردیم به‌جای نوشتن یک `sed` معکوسِ زیرکانه. یک جایگزینی سراسری
آسان اعمال می‌شود و سخت دقیقاً برگردانده می‌شود: خطوط `local` و بلوک مستندات کامنت‌شده را هم
بازنویسی می‌کرد، و یک بازگردانی لنگرزده (anchored) خطوطی با فاصله انتهایی را از قلم می‌انداخت.
بازگرداندن یک کپی سالم‌شناخته‌شده نمی‌تواند نیمه‌کاره اعمال شود. برای هر چیزی که سیاست احراز
هویت را تغییر می‌دهد همین شکل از عملیات را ترجیح دهید. این عادتی است که ارزش دارد همین حالا
بسازید، چون تا مرحله 4، اشتباه معادلش یک cluster را از کار می‌اندازد.

---

## 6. شکار، بخش د: برشمرده، نه نشان‌داده

`OT-001` یک برشماری صادقانه می‌خواهد، نه نمایش عملی همه‌چیز. این بردارها واقعی‌اند و هر کدام
برای سازمان‌های واقعی پول واقعی هزینه داشته‌اند. ما اینجا اجرایشان نمی‌کنیم: بعضی‌هایشان به
تنظیمی در کرنل نیاز دارند که از داخل یک کانتینر نمی‌توانیم عوضش کنیم، بعضی بسته به نسخه Docker
فرق می‌کنند، و راه‌اندازی بعضی‌ها بیشتر از ارزش فعلی‌شان طول می‌کشد. هر کدام سازوکار خودش را
نام می‌برد تا بتوانید خودتان روی ماشینی که مالکش هستید راستی‌آزمایی‌اش کنید.

| # | بردار | سازوکار | چه چیزی را شکست می‌دهد |
|---|---|---|---|
| 9 | **حافظه پروسه** | `SEC-01` تا پایان عمر پروسه در heap اپلیکیشن زندگی می‌کند. `/proc/<pid>/mem`، یک دیباگر، یا `gcore` آن را می‌خواند. | هر مجوز فایلی. فایل می‌تواند کاملاً حذف شود و راز هنوز آنجاست. |
| 10 | **Core dump‌ها** | یک crash کل heap را روی دیسک می‌نویسد، در مسیری که `/proc/sys/kernel/core_pattern` در سطح کل هاست تعیین می‌کند، اغلب با mode بازتر از آنچه فایل پیکربندی داشت، و اغلب مستقیم pipe می‌شود به یک سرویس گزارش crash. | مجوزهای فایل، و مرز شبکه شما. |
| 11 | **Swap و hibernation** | زیر فشار حافظه، کرنل صفحات anonymous — از جمله heap حاوی `SEC-01` — را در swap می‌نویسد. ‏Hibernation *کل* RAM را روی دیسک می‌نویسد. هیچ‌کدام رمزگذاری نمی‌شوند مگر خودتان پیکربندی کرده باشید. | مجوزهای فایل، ایزولاسیون پروسه، و طول عمر پروسه — چون از خود پروسه بیشتر عمر می‌کند. |
| 12 | **لایه‌های ایمیج کانتینر** | دستور `COPY app/config.yaml` مقدار `SEC-01` را در یک لایه تغییرناپذیر ایمیج نوشت. حذف فایل در لایه‌ای بعدی فقط یک نشانگر whiteout اضافه می‌کند؛ لایه اصلی هنوز آن بایت‌ها را دارد و همراه ایمیج به هر registry و هر هاستی که آن را pull کند می‌رود. با `docker save` و باز کردن آرشیو لایه‌ها بررسی‌اش کنید؛ چیدمان دقیقش بین انبار ایمیج کلاسیک Docker و containerd فرق می‌کند، و به همین دلیل اینجا اسکریپتش نمی‌کنیم. | حذف. همان مشکل تغییرناپذیری git، با توزیع بدتر. |
| 13 | **لاگ‌های خود PostgreSQL** | با `log_statement = 'all'` یا هنگام خطای اتصال، سرور ممکن است کوئری‌ها و جزئیات اتصال را لاگ کند. به‌ویژه `ALTER ROLE ... PASSWORD` می‌تواند به‌صورت متن ساده در لاگ سرور بنشیند. | بهداشت کاری اپلیکیشن شما — این لاگ *آن طرف* ماجراست. |
| 14 | **مانیتورینگ، APM و log shipper‌ها** | agent‌هایی که آرگومان‌های پروسه، بلوک محیط، فایل‌های پیکربندی یا stack trace‌ها را جمع می‌کنند و به بیرون از هاست، به سیستمی با نگه‌داری و مدل دسترسی خودش، می‌فرستند. | هر مرزی روی ماشین. |
| 15 | **کانال‌های انسانی** | رمز در یک تیکت، یک پیام چت، یک runbook، یک صفحه ویکی، یک اسکرین‌شات، یک اشتراک صفحه، یک تماس تصویری ضبط‌شده، یک ایمیل به یک فروشنده. | همه کنترل‌های فنی، کاملاً. معمولاً بزرگ‌ترین بردار منفرد، و همانی که هیچ‌کس فهرستش نمی‌کند. |
| 16 | **بازمانده فایل‌های حذف‌شده** | `rm` پیوند را قطع می‌کند؛ پاک نمی‌کند. بلوک‌هایی که `config.yaml` قدیمی را نگه داشته‌اند برای هر کسی که دسترسی خام به دستگاه دارد خواندنی می‌مانند تا وقتی دوباره استفاده شوند، و روی فایل‌سیستم‌های copy-on-write و log-structured، و روی SSD‌هایی با wear leveling، «تا وقتی دوباره استفاده شوند» می‌تواند خیلی طولانی باشد. | باز هم حذف. |

بردار 15 ارزش یک لحظه مکث دارد. همانی است که هیچ راه‌حل فنی ندارد، تقریباً همیشه بزرگ‌ترین
است، و دلیل بزرگ بودنش *ساختاری* است: همین حالا، اگر همکاری به `paymentsdb` دسترسی لازم داشته
باشد، تنها چیزی که اصلاً می‌توانید به او بدهید خود رمز عبور است، چون رمز تنها شکلی است که آن
دسترسی در آن وجود دارد. سازوکار، نشت را اجباری می‌کند. هیچ مقدار آموزشی سیستمی را که تنها
ابزار اشتراک‌گذاری‌اش «راز را برایش بفرست» است درست نمی‌کند. این مشاهده بذر بخش بزرگی از چیزی
است که بعداً می‌سازیم.

شکل 1.3 کل این سطح را جمع می‌کند.

```mermaid
flowchart TB
    SEC{{"SEC-01<br/>one password<br/>you thought there was one copy"}}:::secret

    subgraph ONHOST["on dev01, demonstrated in §3"]
        direction TB
        F1["1. config.yaml, mode 0644"]:::app
        F2["2. initdb.sql, mode 0644"]:::app
        F3["3. readable by nobody, i.e. every account"]:::app
        F4["4. process argv, world-readable via /proc"]:::app
        F5["5. app DEBUG log, mode 0644"]:::app
        F6["6. config.yaml.bak from sed -i"]:::app
    end

    subgraph GONE["already off the host, demonstrated in §4"]
        direction TB
        G1["7. backup tarball"]:::app
        G2["8. git history, in every clone, forever"]:::app
    end

    subgraph WIRE["on the wire, demonstrated in §5"]
        direction TB
        W1["password: NOT exposed, SCRAM-SHA-256"]:::best
        W2["payment records: fully exposed, sslmode=disable"]:::app
        W3["server identity: never verified"]:::app
    end

    subgraph ENUM["enumerated in §6, not run here"]
        direction TB
        E1["9-11. process memory, core dumps, swap"]:::app
        E2["12. container image layers"]:::app
        E3["13-14. server logs, monitoring agents"]:::app
        E4["15. tickets, chat, screenshots, email"]:::app
        E5["16. deleted-file remnants on disk"]:::app
    end

    SEC -.-> ONHOST
    SEC -.-> GONE
    SEC -.-> WIRE
    SEC -.-> ENUM

    style ONHOST fill:#f8fafc,stroke:#475569,stroke-width:1px
    style GONE fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4
    style WIRE fill:#f8fafc,stroke:#475569,stroke-width:1px
    style ENUM fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4

    classDef human fill:#ffffff,stroke:#4b5563,stroke-width:2px,stroke-dasharray:4 3,color:#111827
    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef control fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px,color:#0b1f4b
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef store fill:#e2e8f0,stroke:#475569,stroke-width:1px,color:#0f172a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef best fill:#dcfce7,stroke:#15803d,stroke-width:3px,color:#052e16
    classDef retired fill:#f8fafc,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:2 4,color:#94a3b8
    classDef new stroke-width:3px,stroke-dasharray:6 3
```

**شکل 1.3، سطح افشای یک رمز عبور.** یک راز در بالا، و شانزده نسخه یا افشای شناسایی‌شده زیر آن،
دسته‌بندی‌شده بر اساس این‌که آن‌ها را نشان دادیم (جعبه‌های توپر سنگی) یا فقط برشمردیم (کهربایی
خط‌چین). دو گروه کهربایی بیش از همه اهمیت دارند، و یک ویژگی مشترک دارند: آن نسخه‌ها **از ماشین
بیرون رفته‌اند**، پس هیچ کاری که روی ماشین بکنید به آن‌ها نمی‌رسد. تنها جعبه سبز در این شکل،
محافظت SCRAM از رمز روی سیم است — تنها چیزی در کل این سیستم که از قبل درست انجام می‌شد، و ما
انجامش ندادیم.

---

## 7. خرابش کنید، بعد درستش کنید

حالا میزان افشا را می‌دانید. کار بدیهی را درباره آن بخشی از افشا که مجوزهای فایل به آن
می‌رسند انجام دهید: اجازه ندهید هر حسابی روی ماشین فایل پیکربندی را بخواند.

بلافاصله به سؤالی برمی‌خورید که در واقع کل مرحله 2 در مقیاس کوچک است.

**دستور `chmod 600` دسترسی خواندن را به مالک فایل می‌دهد. قرار است مالک چه کسی باشد؟**

فایل متعلق به `root` است. اپلیکیشن به‌عنوان `root` اجرا می‌شود. پس `chmod 600` اصلاً هیچ چیزی
را عوض نمی‌کند، چون root فارغ از mode همه‌چیز را می‌خواند. برای این‌که یک مجوز معنایی داشته
باشد، اپلیکیشن به هویتی از آنِ خودش نیاز دارد، متمایز از هویت شما و متمایز از هویت root.

`ACC-03` برای همین است. کاربر سیستم‌عاملی `paymentsvc` از قبل در ایمیج وجود دارد؛ فقط هنوز
هیچ چیزی به‌عنوان آن اجرا نشده است.

### 7.1 خرابش کنید

قفل‌کردن را به همان ترتیبی انجام دهید که طبیعی به نظر می‌رسد و اشتباه است:

```bash
sudo docker exec dev01 chmod 0600 /opt/paymentsvc/config.yaml
sudo docker exec dev01 ls -l /opt/paymentsvc/config.yaml
```

انتظار: `-rw------- 1 root root ... config.yaml`. خوب است، `nobody` بیرون ماند. تأییدش کنید:

```bash
sudo docker exec dev01 su -s /bin/sh nobody -c 'cat /opt/paymentsvc/config.yaml'
```

انتظار: `cat: /opt/paymentsvc/config.yaml: Permission denied`.

حالا اجرای اپلیکیشن به‌عنوان root را متوقف کنید و آن را با هویت خودش اجرا کنید:

```bash
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -u paymentsvc dev01 python3 /opt/paymentsvc/paymentsvc.py
```

شکست می‌خورد. انتظار داشته باشید که با این خط تمام شود:

```
PermissionError: [Errno 13] Permission denied: '/opt/paymentsvc/config.yaml'
```

توجه کنید که اینجا عمداً آن را در **پیش‌زمینه** (foreground) اجرا کردیم. اگر از `docker exec -d`
استفاده می‌کردیم، اپلیکیشن بی‌صدا می‌مرد و `curl` صرفاً از اتصال سر باز می‌زد، که وضعیت
دیباگ بسیار بدتری است و دقیقاً همان شکلی است که این خرابی در production خودش را نشان می‌دهد.

### 7.2 عیب‌یابی‌اش کنید

حدس نزنید. مسیر واقعی را طی کنید:

```bash
sudo docker exec dev01 id paymentsvc
sudo docker exec dev01 stat -c '%A %U:%G %n' /opt/paymentsvc/config.yaml
sudo docker exec dev01 namei -l /opt/paymentsvc/config.yaml
```

انتظار: `paymentsvc` ‏uid و gid خودش را دارد و در هیچ گروه دیگری نیست؛ فایل `-rw-------` با
مالک `root:root` است؛ و همه دایرکتوری‌های بالای آن قابل عبورند.

این سه واقعیت با هم یک پاسخ کامل می‌سازند. فایل فقط به مالکش اجازه خواندن می‌دهد. مالکش `root`
است. پروسه `paymentsvc` است. `paymentsvc` نه `root` است و نه در گروهی است که چیزی به آن داده
شده باشد. پس: رد شد.

`Errno 13` همان `EACCES` است، و ارزش دارد همسایه‌اش را هم بشناسید: `Errno 2` / `ENOENT` یعنی
«چنین فایلی وجود ندارد». اگر `ENOENT` دیدید مشکل مسیر دارید؛ اگر `EACCES` دیدید مسیر درست است
و هویت اشتباه است. همین یک تمایز در طول یک عمر کاری ساعت‌ها برایتان صرفه‌جویی می‌کند.

### 7.3 درستش کنید

‏mode درست بود. مالکیت اشتباه بود:

```bash
sudo docker exec dev01 chown paymentsvc:paymentsvc /opt/paymentsvc/config.yaml
sudo docker exec dev01 chmod 0400 /opt/paymentsvc/config.yaml
sudo docker exec dev01 ls -l /opt/paymentsvc/config.yaml
```

انتظار: `-r-------- 1 paymentsvc paymentsvc ... config.yaml`.

مقدار `0400` به‌جای `0600`، چون اپلیکیشن این فایل را فقط *می‌خواند*. دسترسی نوشتنی که لازم
ندارد، دسترسی نوشتنی است که مهاجمی که آن را در اختیار بگیرد مجانی به دست می‌آورد. این
**اصل کمترین امتیاز** (principle of least privilege) در کوچک‌ترین شکل ممکنش است: دقیقاً همان
دسترسی لازم را بده، دقیقاً از همان نوع لازم، و نه بیشتر.

حالا که اینجایید، آشغالی را که §3.5 ساخت جمع کنید و آن نسخه دیگر را هم قفل کنید:

```bash
sudo docker exec dev01 rm -f /opt/paymentsvc/config.yaml.bak
sudo docker exec dev01 chmod 0400 /opt/paymentsvc/initdb.sql
sudo docker exec dev01 chown paymentsvc:paymentsvc /opt/paymentsvc/initdb.sql
```

حالا درست راه‌اندازی‌اش کنید:

```bash
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 2
curl -s http://127.0.0.1:8080/payments/1002/status
sudo docker exec dev01 ps -o user,pid,cmd -C python3
```

انتظار: رکورد پرداخت `1002`، و جدول پروسه‌ای که نشان می‌دهد `python3` به‌عنوان **`paymentsvc`**
اجرا می‌شود، نه `root`. همان بررسی دوم است که اهمیت دارد؛ سرویسی که هنوز به‌عنوان root اجرا
می‌شود از هیچ‌کدام از این کارها چیزی به دست نیاورده است.

---

## 8. شکار را دوباره اجرا کنید: چه چیزی بسته شد و چه چیزی نه

این همان بخشی است که آدم‌ها ازش رد می‌شوند، و همان بخشی است که تعیین می‌کند آیا واقعاً چیزی را
بهتر کرده‌اید یا نه.

```bash
# copy 3, every account on the machine
sudo docker exec dev01 su -s /bin/sh nobody -c 'cat /opt/paymentsvc/config.yaml' ; echo "exit=$?"

# copy 6, editor debris
sudo docker exec dev01 ls -l /opt/paymentsvc/

# copy 5, the DEBUG log line from §3.4
sudo docker exec dev01 grep -c 'effective configuration' /var/log/paymentsvc.log

# copy 7, the backup
sudo docker exec dev01 sh -c 'zcat /tmp/opt-backup.tar.gz | grep -a -c hunter2'

# copy 8, version control (run this in the lab folder, not the container)
git grep -c hunter2 $(git rev-list --all) -- dev01/app/config.yaml

# and root
sudo docker exec dev01 cat /opt/paymentsvc/config.yaml | grep password
```

| # | نسخه | قبل | بعد | آیا با `chmod`/`chown` بسته شد؟ |
|---|---|---|---|---|
| 1 | `config.yaml` | 0644 root | 0400 paymentsvc | **بله**، به یک هویت محدود شد |
| 2 | `initdb.sql` | 0644 root | 0400 paymentsvc | **بله** |
| 3 | خواندنی برای هر حساب | بله | خیر | **بله** |
| 4 | argv پروسه | خواندنی برای همه | بدون تغییر | نه، یک انضباط است، نه یک مجوز |
| 5 | خط لاگ DEBUG | موجود، 0644 | **هنوز موجود، هنوز 0644** | نه |
| 6 | `config.yaml.bak` | موجود | حذف شد | بله، *همین یک نمونه*؛ ابزار بعدی یکی دیگر می‌سازد |
| 7 | آرشیو بکاپ | داردش | **هنوز داردش** | نه، از قبل خارج از هاست است |
| 8 | تاریخچه git | داردش | **هنوز داردش، در هر clone** | نه، تغییرناپذیر و توزیع‌شده |
| — | **root** | می‌خواندش | **هنوز می‌خواندش** | **نه، و هرگز هم نمی‌تواند** |
| — | حافظه پروسه (§6) | داردش | هنوز داردش | نه |
| — | لایه ایمیج (§6) | داردش | هنوز داردش | نه |
| — | روی سیم | داده افشا شده | هنوز افشا شده | نه |

سه مورد از شانزده مکان بسته شد؛ دوازده مورد آموزنده‌تر در جدول بالا نشان داده شده‌اند. این هیچ
نیست: بستن «هر حسابی روی این ماشین» یک بهبود واقعی، ارزان و درست است و همیشه باید انجامش دهید.
اما به آنچه باقی مانده نگاه کنید، و توجه کنید که بازماندگان همگی در یکی از دو دسته‌اند:

**نسخه‌هایی که از ماشین بیرون رفته‌اند.** بکاپ‌ها، تاریخچه git، لایه‌های ایمیج، log
aggregator‌ها، تیکت‌ها. مجوزهای فایل ویژگی یک فایل‌سیستم‌اند؛ این نسخه‌ها روی آن نیستند. هیچ
دستوری نیست که روی `dev01` اجرا کنید و به آن‌ها برسد.

**Root.** ‏`chmod` را کرنل اعمال می‌کند و root استثنای کرنل است. هر کسی که روی این جعبه root
باشد — از جمله هر کسی که با سوءاستفاده از *هر* سرویسی روی آن root شود، و از جمله هر کسی که روی
لپ‌تاپ شما دسترسی `docker` دارد، چون `docker exec -u 0` یک shell با دسترسی root است — هر رازی
روی آن را می‌خواند. روی این ماشین آن شخص خود شمایید، پس حس بدی ندارد. اما لحظه‌ای که بیش از یک
نفر در کار باشد این حس از بین می‌رود، و مرحله 3 عمدتاً درباره این است که وقتی «root همه‌چیز را
می‌خواند» دیگر پاسخ قابل قبولی نباشد چه می‌کنید.

و حالا نتیجه‌ای که کل این فصل برای اجباری‌کردنش وجود دارد. شما نمی‌توانید نسخه‌هایی را که
رفته‌اند پس بگیرید. بنابراین باید با آن اعتبارنامه به‌عنوان یک اعتبارنامه لو رفته رفتار کرد.
**تنها درمان واقعی یک اعتبارنامه لو رفته، عوض کردن آن است.**

پس عوضش کنید.

### 8.1 تلاش کنید بچرخانیدش

واقعاً امتحانش کنید، و هزینه‌اش را بشمارید:

```bash
# 1. change it in the database
sudo docker exec dev01 su postgres -c \
    "psql -c \"ALTER ROLE paymentsvc PASSWORD 'a-new-value-you-choose'\""

# 2. the app is now broken. Confirm it.
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -u paymentsvc dev01 python3 /opt/paymentsvc/paymentsvc.py 2>&1 | tail -3
```

انتظار: `psycopg2.OperationalError: ... password authentication failed for user "paymentsvc"`.

برای بازیابی باید `/opt/paymentsvc/config.yaml` را داخل کانتینر دستی ویرایش کنید — فایلی که
همین الان `0400` کردید — پس باید بازش کنید، ویرایشش کنید، دوباره تنگش کنید، و سرویس را
ری‌استارت کنید. بعد باید یادتان بماند `initdb.sql` هم هست. بعد نسخه داخل git. بعد هر نسخه‌ای
در یک تیکت یا یک پیام چت که اصلاً نمی‌توانید فهرستش کنید.

برش گردانید تا آزمایشگاه به کار ادامه دهد:

```bash
sudo docker exec dev01 su postgres -c \
    "psql -c \"ALTER ROLE paymentsvc PASSWORD 'hunter2-payments-prod'\""
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 2
curl -s http://127.0.0.1:8080/healthz
```

هزینه‌اش را بشمارید:

- **قطعی سرویس.** اعتبارنامه در یک جا عوض شد و مصرف‌کننده با خراب شدن از آن باخبر شد.
- **ویرایش دستی یک فایل محافظت‌شده**، که یعنی موقتاً برداشتن محافظت از آن.
- **دو نوشتن که باید با هم بخوانند**، در دو سیستم، بدون هیچ سازوکاری که آن‌ها را سازگار نگه
  دارد.
- **بدون فهرست موجودی.** شما فهرستی از هر چیزی که `SEC-01` را نگه داشته ندارید. این سیستم را
  خودتان ساختید، با شش نسخه، در یک بعدازظهر.
- **بدون راستی‌آزمایی.** هیچ چیزی به شما نمی‌گوید چرخش کامل شده است. هفته‌ها بعد می‌فهمید،
  وقتی چیزی که فراموشش کرده بودید خراب شود.

چرخش (rotation) عملیات بنیادی مدیریت رازهاست: تنها پاسخ به افشا، تنها دفاع در برابر نسخه‌ای که
از وجودش خبر ندارید، و اولین چیزی که هر مقرراتی درباره‌اش می‌پرسد. روی این سیستم، چرخش عملیاتی
دستی، مخرب و راستی‌آزمایی‌نشدنی است، بدون هیچ فهرست موجودی‌ای پشتش.

این فصل 02 است.

---

## 9. چه چیزی در معماری تغییر کرد

شکل 1.4 همان شکل 0.1 فصل 00 است که در برابر آنچه الان درست است دوباره کشیده شده. کنار هم
مقایسه‌شان کنید: تفاوت‌ها کوچک‌اند، و همین کوچکی نکته اصلی است.

```mermaid
flowchart TB
    subgraph LAP["your laptop, untrusted zone (docker access here is root on dev01)"]
        direction TB
        subgraph LAB["NET-01 lab, HOST-01 dev01 (trusted by assumption; root still reads everything)"]
            direction TB
            ROOT(["ACC-01 you, as root"]):::human
            SVCU(["★ ACC-03 paymentsvc, OS user, no shell"]):::human
            CFG{{"SEC-01 in config.yaml<br/>★ mode 0400, owner paymentsvc"}}:::secret
            SQL{{"SEC-01 in initdb.sql<br/>★ mode 0400, owner paymentsvc"}}:::secret
            APP["APP-01 paymentsvc<br/>★ runs as ACC-03, not root"]:::app
            DB[("SVC-01 paymentsdb<br/>PostgreSQL 15, scram-sha-256")]:::store
            LOG[("/var/log/paymentsvc.log<br/>mode 0644, still holds a DEBUG copy")]:::store
        end
    end

    subgraph OUT["copies already beyond reach, nothing on dev01 touches these"]
        direction TB
        BK[("backup tarball")]:::store
        GIT[("git history, every clone")]:::store
        IMG[("container image layer")]:::store
    end

    ROOT -.->|"reads anything, kernel exception to file modes, unstoppable"| CFG
    SVCU -.->|"reads at startup, file read, mode 0400 to one identity"| APP
    CFG -.->|"password bytes, file read, restricted to ACC-03"| APP
    APP -.->|"login as ACC-02, PostgreSQL 5432, SCRAM protects the password, nothing verifies the server"| DB
    APP -.->|"DEBUG copy written earlier, file append, world-readable"| LOG
    CFG -.->|"copied before we locked it, no protection"| OUT

    style LAP fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4
    style LAB fill:#f8fafc,stroke:#475569,stroke-width:1px
    style OUT fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4

    classDef human fill:#ffffff,stroke:#4b5563,stroke-width:2px,stroke-dasharray:4 3,color:#111827
    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef control fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px,color:#0b1f4b
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef store fill:#e2e8f0,stroke:#475569,stroke-width:1px,color:#0f172a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef best fill:#dcfce7,stroke:#15803d,stroke-width:3px,color:#052e16
    classDef retired fill:#f8fafc,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:2 4,color:#94a3b8
    classDef new stroke-width:3px,stroke-dasharray:6 3
```

**شکل 1.4، معماری پس از فصل 01.** سه چیز تازه‌اند (★): هویت سیستم‌عاملی `ACC-03 paymentsvc`،
مالکیت با mode ‏`0400` روی هر دو فایل، و این واقعیت که `APP-01` دیگر به‌عنوان root اجرا
نمی‌شود. یک چیز به‌جای این‌که تازه *درست شده* باشد، تازه *کشیده شده*: گروه کهربایی سمت راست که
نسخه‌های خارج‌شده از ماشین را نگه می‌دارد؛ این‌ها پیش از این فصل هم وجود داشتند و ما صرفاً به
وجودشان اعتراف نکرده بودیم. `ACC-01` هنوز یک یال غیرقابل‌توقف مستقیم به سمت راز دارد، چون root
استثنای کرنل نسبت به مجوزهای فایل است و هیچ `chmod`ی هرگز این را عوض نمی‌کند. همه یال‌های شکل
هنوز نقطه‌چین‌اند. ما محدود کرده‌ایم چه کسی می‌تواند `SEC-01` را روی این یک ماشین بخواند؛ اما
رمزنگاری‌اش نکرده‌ایم، به هیچ چیزی توانایی *تصمیم‌گیری* درباره این‌که آیا یک درخواست برای آن
باید پذیرفته شود نداده‌ایم، و هنوز هیچ سابقه‌ای از هیچ خواندنی نداریم.

---

## 10. تصمیم‌هایی که گرفتیم (و چه چیزی عوضشان می‌کند)

| # | تصمیم | گزینه‌ها | انتخاب‌شده | چرا | چه چیزی برش می‌گرداند |
|---|---|---|---|---|---|
| D-006 | `dev01` یک کانتینر است که یک userland کامل Debian با PostgreSQLِ به‌طور معمولی نصب‌شده اجرا می‌کند | (الف) ایمیج رسمی `postgres` + کانتینر جداگانه برای اپلیکیشن؛ (ب) یک کانتینر Debian با هر دو | (ب) | دفتر ثبت فصل 00 هر دو را روی `HOST-01` می‌گذارد، و این فصل به یک *ماشین* نیاز دارد که در آن راه برود: کاربران، جدول پروسه، لاگ‌ها، پشته شبکه. ایمیج رسمی یک پایگاه‌داده می‌دهد، نه یک هاست. | مرحله 2، وقتی دفتر ثبت واقعاً یک هاست دوم پیدا کند. آن وقت جدا می‌شوند، و همان جدایی خودش فشار است، نه یک مرتب‌کاری. |
| D-007 | هیچ bind mount بین لپ‌تاپ و کانتینر نیست | (الف) ‏bind-mount کردن `./app` برای ویرایش سریع؛ (ب) ‏`COPY` به داخل ایمیج | (ب) | ‏Docker Desktop روی macOS مالکیت را هنگام عبور از bind mount بازنویسی می‌کند، که بی‌سروصدا هر `ls -l` این فصل را تحریف می‌کرد. درستی درس بر راحتی ویرایش می‌چربد. | فصلی که در آن سرعت تکرار روی کد اپلیکیشن مهم‌تر از وفاداری مالکیت فایل باشد. آن وقت bind-mount می‌کنیم و می‌گوییم که کرده‌ایم. |
| D-008 | اپلیکیشن هویت سیستم‌عاملی خودش را می‌گیرد (`ACC-03`) و با آن اجرا می‌شود | (الف) ادامه اجرا به‌عنوان root و تکیه بر مرز کانتینر؛ (ب) یک کاربر بی‌امتیاز اختصاصی | (ب) | یک mode فایل بدون هویتی که به آن اعطا شود بی‌معناست؛ این درس مستقیم §7.1 است. ضمناً شعاع انفجار یک نفوذ به اپلیکیشن را به آنچه همان یک حساب دسترسی دارد محدود می‌کند. | هیچ چیزی. این یک کف است، نه یک ترجیح. فصل‌های بعدی تقویتش می‌کنند (بدون shell، فایل‌سیستم فقط‌خواندنی، حذف capability‌ها)؛ هیچ‌کدام برش نمی‌گردانند. |
| D-009 | `0400`، نه `0600` | (الف) `0600` خواندن‌ونوشتن برای مالک؛ (ب) `0400` فقط‌خواندنی برای مالک | (ب) | اپلیکیشن فقط می‌خواند. دسترسی نوشتنی که لازم ندارد، دسترسی نوشتنی است که مهاجمی که پروسه را به ارث می‌برد مجانی می‌گیرد. | طراحی‌ای که در آن پروسه به‌طور مشروع پیکربندی خودش را بازنویسی می‌کند، که خودش باید زیر سؤال برود. |
| D-010 | `scram-sha-256` را نگه می‌داریم؛ به `md5` یا `password` تغییر نمی‌دهیم | (الف) `md5` برای سازگاری با کلاینت‌های قدیمی؛ (ب) `password`، ساده‌ترین؛ (ج) `scram-sha-256` | (ج)، همان پیش‌فرض | §5 اندازه‌اش گرفت: ‏SCRAM اعتبارنامه را از روی سیم دور نگه می‌دارد و به‌جای یک معادلِ رمز، یک verifier ذخیره می‌کند. `md5` مقداری را ذخیره و منتقل می‌کند که *معادل رمز* است؛ بدزدیدش و می‌توانید احراز هویت کنید. `password` اعتبارنامه را به‌صورت ASCII روی شبکه می‌گذارد. | یک کتابخانه کلاینت آن‌قدر قدیمی که SCRAM بلد نباشد. پاسخ درست ارتقای کلاینت است، نه تنزل سرور؛ و اگر واقعاً ناممکن بود، اتصال باید در TLS پیچیده شود و استثنا با یک مالک و یک تاریخ در ثبت ریسک (risk register) ثبت شود. |

---

## 11. جاهایی که هنوز درد دارد

**چرخش دستی، مخرب و راستی‌آزمایی‌نشدنی است.** عوض کردن `SEC-01` یعنی یک قطعی، یک ویرایش دستی
روی یک فایل محافظت‌شده داخل یک کانتینر، یک ویرایش دوم در جایی دیگر، و هیچ راهی برای اطمینان از
این‌که همه مصرف‌کننده‌ها را پیدا کرده‌اید. این بالای صف است.

**هیچ فهرست موجودی وجود ندارد.** شما نمی‌توانید از هیچ سیستمی جواب «`SEC-01` کجا زندگی
می‌کند؟» را بگیرید. در این فصل با *رفتن و نگاه کردن* جوابش دادید، و روی یک ماشین که خودتان
همین بعدازظهر ساختید شش نسخه پیدا کردید. حالا چهارصد ماشین و یازده سال را تصور کنید.

**Root همه‌چیز را می‌خواند، و دسترسی `docker` همان root است.** هر کسی که روی لپ‌تاپ شما Docker
دارد از طریق `docker exec -u 0` یک shell با دسترسی root روی `dev01` دارد. هیچ مجوز فایلی به
این دست نمی‌زند.

**هیچ چیزی تصمیم نمی‌گیرد، و هیچ چیزی ثبت نمی‌شود.** هنوز هیچ مؤلفه‌ای در هیچ‌کجا نیست که یک
درخواست برای `SEC-01` را بپذیرد یا رد کند، و هیچ سابقه‌ای از این‌که تا به حال خواندنی رخ داده
باشد وجود ندارد. اگر رمز فردا روی یک سایت paste ظاهر شود، حتی نمی‌توانید شروع به محدود کردن
این کنید که از کجا آمده است.

**داده روی سیم لخت است، و سرور هرگز احراز هویت نمی‌شود.** ‏SCRAM از اعتبارنامه محافظت می‌کند و
از هیچ چیز دیگری. `sslmode: disable` یعنی هر رکورد پرداخت به شکل خوانا عبور می‌کند، و اپلیکیشن
هیچ راهی ندارد که پایگاه‌داده واقعی را از هر چیزی که روی پورت 5432 پاسخ می‌دهد تشخیص دهد.
امروز مخاطب loopback است؛ روزی که دو ماشین در کار باشد، مخاطب شبکه است.

**`SEC-01` در حافظه پروسه فناناپذیر است.** تا پایان عمر پروسه در heap می‌نشیند، در دسترس هر
چیزی که بتواند آن حافظه را بخواند، و به core dump‌ها، ‏swap و ایمیج‌های hibernation سرایت
می‌کند. فایل‌ها بخش آسان ماجرا بودند.

**طول عمر راز نامحدود است.** یک‌بار ساخته شد، هرگز عوض نشد، و هیچ انقضایی ندارد. هر شانزده
نسخه تا ابد معتبرند. هیچ چیزی در این سیستم مفهوم اعتبارنامه‌ای را که خودبه‌خود از کار بیفتد
نمی‌فهمد.

---

## 12. جمع‌بندی فصل

- ‏mode یک فایل به‌طور پیش‌فرض `0644` است و هیچ‌کس انتخابش نمی‌کند. `0644` یعنی هر حسابی روی
  ماشین.
- `nobody`، بی‌قدرت‌ترین حساب لینوکس، می‌توانست رمز پایگاه‌داده production شما را بخواند. این
  رفتار عادی و طراحی‌شده `0644` است، نه یک exploit.
- هر چیزی در `argv` یک پروسه از طریق `/proc/<pid>/cmdline` برای همه خواندنی است. هرگز یک راز
  را روی خط فرمان نگذارید. متغیرهای محیطی بهترند و هنوز خوب نیستند.
- یک `LOG_LEVEL=debug` که وسط یک حادثه تنظیم شود، یک خط مفید dump پیکربندی را به یک اعتبارنامه
  دائمی و متن‌ساده تبدیل می‌کند، در فایلی که به log aggregator شما می‌رود و سال‌ها نگه داشته
  می‌شود. بستن شیر سطل را خالی نمی‌کند.
- ویرایشگر شما، `sed -i.bak`، `patch` و یک `vim` که crash کرده، همگی نسخه‌های `0644` از فایل
  قدیمی جا می‌گذارند که در مدل ذهنی هیچ‌کس نیستند.
- بکاپ‌ها و تاریخچه git از نظر ماهیت با بقیه فرق دارند: آن نسخه‌ها **از ماشین بیرون رفته‌اند**،
  انبار object گیت تغییرناپذیر و توزیع‌شده است، و هیچ دستوری که به‌صورت محلی اجرا کنید به
  آن‌ها نمی‌رسد.
- پاسخ صادقانه به «ما یک راز را کامیت کردیم» هرگز «حذفش کردیم» نیست. پاسخ این است: «آن
  اعتبارنامه لو رفته، عوضش کنید.»
- روی سیم، پیش‌فرض `scram-sha-256` پستگرس رمز را از ضبط بیرون نگه داشت، در حالی که هر رکورد
  پرداخت به‌صورت متن ساده عبور کرد. **احراز هویت و محرمانگی دو ویژگی متفاوت‌اند**، و این اتصال
  اولی را دارد و دومی را ندارد.
- `sslmode: disable` همان خطی است که درباره دومی تصمیم می‌گیرد، و تعداد بسیار زیادی از
  سیستم‌های واقعی اثرش را دارند بدون این‌که کسی آن را نوشته باشد.
- هیچ چیزی در آن تبادل *سرور* را احراز هویت نکرد. هر چیزی که روی پورت 5432 پاسخ بدهد
  پایگاه‌داده می‌شود. این همان حفره‌ای است که گواهی‌ها در نهایت می‌بندند، و رمزگذاری به‌تنهایی
  نمی‌بندد: محافظت در برابر کسی که گوش می‌دهد و کسی که پاسخ می‌دهد دو تنظیم متفاوت‌اند.
- دیدن رمز به‌صورت ASCII نیازمند این بود که هم روش احراز هویت تنزل یابد **و هم** اتصال
  رمزگذاری‌نشده باشد. هر کدام بی‌سروصدا کمبود دیگری را می‌پوشاند.
- یک مجوز فایل به هویتی نیاز دارد که به آن آویزان شود. `chmod 600` روی فایلی متعلق به root که
  پروسه‌ای با دسترسی root می‌خواندش هیچ چیزی را عوض نمی‌کند، و به همین دلیل `ACC-03` باید پیش
  از این‌که اصلاح معنایی پیدا کند وجود می‌داشت. `Errno 13` یعنی هویت اشتباه؛ `Errno 2` یعنی
  مسیر اشتباه.
- کمترین امتیاز در کوچک‌ترین شکلش: `0400` نه `0600`، چون اپلیکیشن هرگز نمی‌نویسد.
- سه مورد از شانزده افشای ثبت‌شده بسته شد. هر چه باقی ماند یا خارج از ماشین است یا root است، و
  root برای همیشه استثنای کرنل نسبت به mode‌های فایل است.
- چرخش عملیات بنیادی مدیریت رازهاست، و روی این سیستم دستی است، قطعی ایجاد می‌کند، نیازمند
  برداشتن محافظت از یک فایل محافظت‌شده است، و قابل راستی‌آزمایی نیست.

---

## 13. خودتان امتحان کنید

**پرسش 1. ‏`nobody` هیچ اختیاری ندارد. پس چرا توانست `SEC-01` را بخواند؟ آیا این باگی در
Docker بود، در Debian، یا در PostgreSQL؟**

هیچ‌کدام. این رفتار درست و طراحی‌شده یک فایل با mode ‏`0644` بود، که سه بیت آخرش خواندن را به
«بقیه همه» می‌دهد، و `nobody` هم بخشی از بقیه همه است. هیچ مؤلفه‌ای مقصر نبود و هیچ چیزی به
معنای انحراف از پیش‌فرضش بدپیکربندی نشده بود. دقیقاً همین است که این بردار را این‌قدر بادوام
می‌کند: هیچ پیام خطایی، هیچ هشداری و هیچ یافته ممیزی‌ای وجود ندارد، چون از دید سیستم هیچ چیزی
خراب نشده است. خودِ پیش‌فرض همان آسیب‌پذیری است.

**پرسش 2. ‏`psycopg2.connect(password=...)` رمز را از `argv` بیرون نگه می‌دارد. چرا این بیش از
آنچه به نظر می‌رسد اهمیت دارد، و چرا `PGPASSWORD` در محیط بهتر است اما هنوز خوب نیست؟**

`/proc/<pid>/cmdline` روی لینوکس برای همه خواندنی است، پس هر چیزی در `argv` تا پایان عمر پروسه
برای هر حسابی روی ماشین قابل مشاهده است، و پس از شروع پروسه نمی‌توانید حذفش کنید.
`/proc/<pid>/environ` فقط برای مالک پروسه و root خواندنی است، پس محیط واقعاً مخاطب کوچک‌تری
دارد. با این حال هنوز خوب نیست چون محیط به هر پروسه فرزندی که اپلیکیشن ایجاد می‌کند به ارث
می‌رسد (از جمله فراخوانی یک ابزار که هنگام crash محیطش را لاگ می‌کند)، در بیشتر crash dump‌ها و
در ضبط‌های بسیاری از agent‌های APM ظاهر می‌شود، `docker inspect` متغیرهای محیطی کانتینر را برای
هر کسی که دسترسی Docker دارد چاپ می‌کند، و هر چیزی که از قبل بتواند پروسه را بخواند به‌راحتی
dump‌اش می‌کند. مخاطب کوچک‌تر شد؛ سازوکار بهتر نشد.

**پرسش 3. برگرداندن `LOG_LEVEL` به `INFO` جلوی نشت‌های جدید را گرفت. چرا این یک اصلاح نبود، و
چه چیزی تجمیع لاگ را از فایل محلی بدتر می‌کند؟**

چون آن خط DEBUG که وسط حادثه نوشته شد هنوز در `/var/log/paymentsvc.log` است، هنوز با mode
‏`0644`. متوقف کردن جریان چیزی را که قبلاً جاری شده حذف نمی‌کند. تجمیع لاگ هم‌زمان از سه جهت
بدتر است: راز از هاست بیرون می‌رود، پس هیچ کنترل محلی به آن نمی‌رسد؛ عمداً تکثیر و طولانی‌مدت
نگه‌داری می‌شود، چون کار یک سیستم لاگ همین است؛ و *قابل جستجو* می‌شود برای همه کسانی که به
پلتفرم لاگ دسترسی دارند، که در بیشتر سازمان‌ها گروهی بسیار بزرگ‌تر از کسانی است که می‌توانستند
به سرور وارد شوند. یک راز در یک log aggregator ایندکس، تکثیر و به‌اشتراک‌گذاشته شده است؛ سه
کاری که هرگز آگاهانه با یک اعتبارنامه نمی‌کردید.

**پرسش 4. فایل را `git rm` کنید، کامیت کنید، و از درخت کاری ناپدید می‌شود. چرا واقعاً نرفته
است، و تفاوت این با حذف فایل `.bak` چیست؟**

‏Git یک انبار object مبتنی بر محتواست، نه یک فایل‌سیستم با گزارش undo. هر نسخه از هر فایل یک
object تغییرناپذیر است که با hash محتوایش نام‌گذاری می‌شود، و کامیت‌ها به آن‌ها ارجاع می‌دهند.
حذف رمز یک blob *جدید* ساخت؛ آن قدیمی هنوز از کامیت قدیمی‌تر قابل دسترسی است، در هر clone کپی
می‌شود، و به هر remote ‏push می‌شود. حذف فایل `.bak` واقعاً آن نسخه را از بین برد — یک فایل بود،
روی یک فایل‌سیستم، که شما کنترلش می‌کنید. نسخه git تغییرناپذیر است و *توزیع* شده است. حذفش
نیازمند بازنویسی تاریخچه است، که hash هر کامیت بعدی را عوض می‌کند و همه همکاران را مجبور به
clone دوباره می‌کند، به‌علاوه garbage collection سمت ارائه‌دهنده، و باز هم به clone‌ای که کسی
سه‌شنبه پیش گرفته نمی‌رسد.

**پرسش 5. ضبط شما رکوردهای پرداخت را نشان داد اما رمز را نه. هر دو نیمه را توضیح دهید، و بگویید
باید بیشتر نگران کدام باشید.**

رمز غایب بود چون PostgreSQL نسخه 14 به بعد به‌صورت پیش‌فرض `scram-sha-256` را به کار می‌برد:
کلاینت دانستن رمز را از طریق یک تبادل چالش-پاسخ ثابت می‌کند، پس فقط nonce‌ها، یک salt و یک اثبات
از روی سیم عبور می‌کنند و هیچ‌کدام نه رمز می‌دهند و نه توکنی قابل استفاده مجدد. رکوردها حاضر
بودند چون `sslmode: disable` یعنی اصلاً هیچ رمزگذاری‌ای مذاکره نشد، پس به‌محض کامل شدن احراز
هویت، هر کوئری و هر سطر نتیجه به‌صورت متن ساده سفر کرد. باید بیشتر نگران رکوردها باشید. رمز از
دسترسی به داده محافظت می‌کند؛ داده همان چیزی است که از اول می‌خواستید محافظتش کنید، و دارد
به‌صورت انبوه، هر ثانیه، تا ابد، محافظت‌نشده عبور می‌کند. اشتباهی رایج و پرهزینه است که «رمز
امن است» را به معنای «اتصال امن است» بگیریم.

**پرسش 6. هیچ چیزی در تبادل SCRAM سرور را احراز هویت نکرد. مهاجمی که بتواند روی پورت 5432 پاسخ
بدهد چه می‌تواند بکند، و کدام فصل بعدی این را می‌بندد؟**

او خودش پایگاه‌داده می‌شود. اپلیکیشن وصل می‌شود، بدل‌کار پروتکل PostgreSQL را حرف می‌زند، و چون
اپلیکیشن هیچ راهی برای راستی‌آزمایی طرف مقابل ندارد، ادامه می‌دهد: نام کاربری‌اش را می‌فرستد،
‏SCRAM را کامل می‌کند (بدل‌کار نمی‌تواند اثبات را راستی‌آزمایی کند، اما لازم هم ندارد، فقط
می‌گوید «احراز هویت OK»)، و بعد هر کوئری‌ای را که قرار بود بفرستد می‌فرستد. حالا بدل‌کار
می‌بیند چه پرداخت‌هایی بررسی می‌شوند و می‌تواند هر پاسخی که خواست برگرداند، از جمله پاسخ‌هایی
که باعث می‌شوند اپلیکیشن درباره پول واقعی تصمیم‌های غلط بگیرد. رسیدن به این نقطه نیازمند اشغال
اولیه پورت، مسموم‌کردن DNS، یا قرار گرفتن روی مسیر شبکه است. اصلاحش احراز هویت سرور از طریق TLS
با گواهی‌ای است که کلاینت واقعاً راستی‌آزمایی‌اش کند، و دقیقاً همین فشاری است که گواهی‌ها را در
مرحله 2 معرفی می‌کند، چون دو ماشین که باید روی یک شبکه به هم اعتماد کنند همان مسئله‌ای است که
گواهی‌ها برایش اختراع شدند.

**پرسش 7. چرا `chmod 0600` روی فایل پیکربندی، به‌تنهایی، هیچ چیزی را عوض نکرد؟**

چون فایل متعلق به `root` بود و پروسه هم به‌عنوان `root` اجرا می‌شد. `0600` خواندن و نوشتن را به
*مالک* می‌دهد، پس فایلِ متعلق‌به‌root که با root اجرا می‌شود یعنی root دقیقاً مثل قبل می‌خواندش
— و root به‌هرحال می‌خواندش، چون root استثنای کرنل نسبت به بررسی مجوزهای فایل است. یک بیت مجوز
گزاره‌ای درباره یک هویت است. وقتی فقط یک هویت در تصویر باشد، و آن هویت همانی باشد که قوانین
شاملش نمی‌شوند، گزاره تهی است. این کنترل تنها وقتی واقعی شد که `ACC-03` وجود پیدا کرد و پروسه
واقعاً با آن اجرا شد.

**پرسش 8. شما `PermissionError: [Errno 13]` دیدید. مسیر عیب‌یابی را طی کنید، و بگویید `Errno 2`
چه معنایی می‌داشت.**

سه دستور، سه واقعیت. `id paymentsvc` هویت پروسه و گروه‌هایش را نشان می‌دهد.
`stat -c '%A %U:%G'` نشان می‌دهد فایل چه چیزی و به چه کسی می‌دهد. `namei -l` نشان می‌دهد آیا هر
دایرکتوری روی مسیر قابل عبور است. کنار هم بگذاریدشان: فایل فقط به مالک خواندن می‌دهد، مالک
`root` است، پروسه `paymentsvc` است، و `paymentsvc` در هیچ گروهی نیست که چیزی به آن داده شده
باشد؛ پس رد شد. `Errno 13` (`EACCES`) یعنی مسیر درست حل شد و هویت رد شد. `Errno 2` (`ENOENT`)
یعنی مسیر اصلاً حل نشد: نام فایل اشتباه، دایرکتوری اشتباه، یک mount که سر جایش نیست، یا یک
symlink که به هیچ‌جا اشاره می‌کند. مسئله دسترسی در برابر مسئله مسیر؛ یک ساعت وقت صرف بررسی
مجوزهای فایلی که اصلاً وجود ندارد نکنید.

**پرسش 9. سه مورد از شانزده افشا بسته شد. بازماندگان را در دو دسته بگذارید و بگویید چرا هر دسته
خارج از دسترس `chmod` است.**

**نسخه‌هایی که ماشین را ترک کرده‌اند** — بکاپ‌ها، تاریخچه git و clone‌هایش، لایه‌های ایمیج
کانتینر، ‏log aggregator‌ها، تیکت‌ها و چت. مجوزهای فایل ویژگی یک فایل‌سیستم‌اند که یک کرنل
اعمالشان می‌کند؛ این نسخه‌ها روی سیستم‌های دیگری هستند، زیر کنترل آدم‌های دیگر، با نگه‌داری و
مدل دسترسی خودشان. هیچ دستوری روی `dev01` به آن‌ها نمی‌رسد.
**Root** — چون بررسی mode فایل را کرنل انجام می‌دهد و root استثنای مستندشده آن است. این شامل هر
کسی می‌شود که با سوءاستفاده از هر سرویسی روی این جعبه root شود، و هر کسی که روی لپ‌تاپ شما
دسترسی Docker دارد، چون `docker exec -u 0 dev01 bash` یک shell با دسترسی root است. دسته اول به
یک *معماری* متفاوت نیاز دارد؛ دسته دوم به یک *مدل اعتماد* متفاوت، که در نهایت همان چیزی است که
نگه‌داری کلید با پشتیبانی سخت‌افزار در مرحله 3 درباره‌اش است.

**پرسش 10. چرا چرخش عملیات بنیادی مدیریت رازهاست، و چهار هزینه مشخصی که در §8.1 هنگام امتحان
کردنش اندازه گرفتید را نام ببرید.**

چون تنها پاسخی است به افشا که واقعاً کار می‌کند. شما نمی‌توانید یک نسخه را پس بگیرید؛ فقط
می‌توانید هر نسخه را بی‌ارزش کنید، و عوض کردن مقدار تنها راه انجام این کار است. ضمناً تنها دفاع
در برابر نسخه‌هایی است که از وجودشان خبر ندارید، و همان‌طور که این فصل نشان داد، آن‌ها اکثریت
هستند. چهار هزینه: (1) **قطعی سرویس**، مصرف‌کننده تغییر را با خراب شدن کشف کرد؛ (2) **برداشتن
محافظت از فایل محافظت‌شده**، مجبور شدید `0400` را باز کنید تا ویرایشش کنید و همان افشایی را که
تازه بسته بودید دوباره برقرار کردید؛ (3) **دو نوشتن که باید با هم بخوانند** در پایگاه‌داده و در
پیکربندی، بدون هیچ چیزی که سازگارشان نگه دارد؛ (4) **بدون فهرست موجودی و بدون راستی‌آزمایی**،
هیچ فهرستی از مصرف‌کننده‌ها نداشتید و هیچ چیزی به شما نگفت چرخش کامل شده، پس هفته‌ها بعد
می‌فهمیدید، وقتی چیزی که فراموش کرده بودید خراب شود.

**پرسش 11. شکل 0.1 فصل 00 گفته بود «رمز به‌صورت متن ساده فرستاده می‌شود» و این فصل تغییرش داد.
چرا این فراتر از موشکافی لفظی اهمیت دارد؟**

چون از یک سند معماری برای تصمیم‌گیری درباره محل خرج کردن تلاش استفاده می‌شود. کسی که بخواند
«رمز به‌صورت متن ساده عبور می‌کند» اصلاح مسیر اعتبارنامه را در اولویت می‌گذارد و هیچ چیزی نصیبش
نمی‌شود، چون SCRAM از قبل حلش کرده بود، در حالی که افشای واقعی — عبور هر رکورد پرداخت به‌صورت
متن ساده بدون هیچ احراز هویت سروری — بی‌رسیدگی می‌ماند. بزرگ‌نمایی یک ضعف دقیقاً به همان
اندازه کم‌نمایی آن کار را به بیراهه می‌برد، و ضمناً اعتماد به هر ادعای دیگر آن سند را هم
می‌خورد. به همین دلیل است که با نمودارهای معماری و دفتر ثبت نام‌ها مثل قانون رفتار می‌شود و
به‌صورت علنی اصلاح می‌شوند، نه این‌که بی‌سروصدا ویرایش شوند.

**پرسش 12. این فصل هشت بردار را نشان داد و هشت بردار دیگر را برشمرد. چرا برشماری بدون نمایش
اینجا قابل قبول است، و مرزش کجاست؟**

چون `OT-001` پرسید *چه کسی می‌تواند این را بخواند و کجاها رفته است*، و پاسخ صادقانه و در سطح
سازوکار به این پرسش همان محصول نهایی است؛ یک نقشه کامل بهتر از یک نقشه ناقص با جلوه‌های بهتر
است. مرز این است که هر بردار برشمرده باید **سازوکار مشخص** خودش را نام ببرد (`/proc/<pid>/mem`،
‏`core_pattern`، لایه‌های whiteout در یک ایمیج، صفحات swap)، تا بتوانید هر کدام را خودتان روی
ماشینی که کنترلش می‌کنید راستی‌آزمایی کنید، و فصل باید صریح بگوید کدام کدام است تا همیشه بدانید
چه چیزی را اثبات کرده‌اید و چه چیزی را فقط به شما گفته‌اند. چیزی که *قابل قبول نیست* ارائه خروجی
ساختگی یک دستور اجرانشده به‌عنوان یک نشست واقعی ضبط‌شده است. این تفاوت میان یک ساده‌سازی و یک
جعل است.

---

## 14. آزمایشگاه را پابرجا رها کنید

**رهایش کنید در حال اجرا.** فصل 02 مستقیماً روی این کانتینر بنا می‌شود.

```bash
sudo docker compose ps                 # should show dev01 running
curl -s http://127.0.0.1:8080/healthz
```

اگر ری‌بوت کردید، برش گردانید:

```bash
sudo docker start dev01
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

توجه کنید که اپلیکیشن خودش **دوباره راه نمی‌افتد**. هیچ service manager وجود ندارد، پس یک ری‌بوت
یعنی یک راه‌اندازی دستی. این یک شکاف واقعی است و با یک فشار واقعی درست خواهد شد، نه با مرتب‌کاری.

نظافت اختیاری؛ فایل‌های ضبط داده پرداخت واقعی دارند و یکی از آن‌ها رمز را به‌صورت ASCII دارد:

```bash
sudo docker exec dev01 rm -f /tmp/pg-default.pcap /tmp/pg-plain.pcap /tmp/opt-backup.tar.gz
```

مخزن git را دقیقاً همان‌طور که هست نگه دارید. رمزی که در تاریخچه‌اش هست حالا یک نمایشگاه دائمی
است، و فصل‌های بعدی به آن ارجاع می‌دهند.

**برچیدن کامل**، فقط اگر می‌خواهید این ساخت را رها کنید (این کار پایگاه‌داده و هر چیزی را که
داخل کانتینر انجام دادید نابود می‌کند):

```bash
sudo docker rm -f dev01
sudo docker image rm ksm/dev01:chapter01
```
