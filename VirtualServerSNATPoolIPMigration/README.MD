# F5 BIG-IP Virtual Server + SNAT Pool IP Migration

Bash script F5 BIG-IP rendszerekhez Virtual Server és SNAT Pool IP-címek egyidejű módosítására.

A script egy `virtual_servers.txt` bemeneti fájl alapján dolgozik, amely tartalmazza a Virtual Server, destination IP, pool, SNAT pool és SNAT translated IP információkat.

A módosítás alapértelmezés szerint **DRY RUN módban** történik, így a konfiguráció tényleges módosítása előtt ellenőrizhető, hogy milyen változtatásokat hajtana végre a script.

## Funkciók

A script az alábbi feladatokat végzi:

* Virtual Server adatok beolvasása fájlból
* IP-címek validálása
* új Virtual Server destination IP kiszámítása
* új SNAT translated IP kiszámítása
* egyedi IP-cím kivételek kezelése
* Virtual Server létezésének ellenőrzése
* SNAT Pool létezésének ellenőrzése
* SNAT Pool member ellenőrzése
* DRY RUN támogatás
* Virtual Server módosítása
* SNAT Pool member módosítása
* módosítások utáni ellenőrzés
* részletes log készítése
* hibák naplózása

## Követelmények

A script futtatásához szükséges:

* F5 BIG-IP
* Bash
* `tmsh`
* `awk` / shell alapú feldolgozás
* `grep`
* `cut`
* `xargs`

A scriptnek olyan F5 BIG-IP rendszeren kell futnia, ahol a `tmsh` konfigurációs parancsok elérhetők.

## Bemeneti fájl

A script alapértelmezett bemeneti fájlja:

```text id="gk1s0v"
./virtual_servers.txt
```

A fájlnak az alábbi formátumot kell követnie:

```text id="j7b8ol"
VS_NAME | DEST_IP | PORT | POOL | SNAT_POOL | SNAT_TRANSLATED_IP | STATE
```

Példa:

```text id="d1i2j7"
VS_NAME | DEST_IP | PORT | POOL | SNAT_POOL | SNAT_TRANSLATED_IP | STATE
vs_http | 10.10.10.100 | 80 | web_pool | snat_web | 10.20.20.100 | enabled
vs_https | 10.10.10.101 | 443 | https_pool | snat_https | 10.20.20.101 | enabled
```

A script automatikusan kihagyja a fejlécsort.

## Konfiguráció

A script fontosabb konfigurációs változói:

```bash id="cv8y8n"
INPUT_FILE="./virtual_servers.txt"

OFFSET=10

DRY_RUN=1

LOG_FILE="./f5_ip_change_$(date +%Y%m%d_%H%M%S).log"
```

### INPUT_FILE

A feldolgozandó input fájl:

```bash id="2pv0km"
INPUT_FILE="./virtual_servers.txt"
```

Ha más néven vagy más könyvtárban található a fájl, ezt az értéket kell módosítani.

### OFFSET

Alapértelmezett érték:

```bash id="t0e4qv"
OFFSET=10
```

Normál esetben az új IP-cím az eredeti IP utolsó oktettjéhez hozzáadott `OFFSET` érték alapján kerül kiszámításra.

Például:

```text id="q3t8y4"
10.10.10.100
       +
      10
       =
10.10.10.110
```

A script csak az utolsó oktettet módosítja.

## DRY RUN mód

A script egyik legfontosabb biztonsági funkciója a `DRY_RUN`.

Alapértelmezett érték:

```bash id="q9p6q3"
DRY_RUN=1
```

Ebben az esetben a script:

* beolvassa az inputot;
* validálja az IP-címeket;
* kiszámolja az új IP-címeket;
* ellenőrzi a Virtual Servert;
* ellenőrzi a SNAT poolt;
* ellenőrzi a SNAT pool membert;
* kiírja a tervezett változtatásokat;

de **nem módosítja az F5 konfigurációt**.

A tényleges módosításhoz:

```bash id="z3nj0a"
DRY_RUN=0
```

értékre kell állítani.

> **Figyelem:** `DRY_RUN=0` esetén a script ténylegesen módosítja a BIG-IP konfigurációt. Éles rendszeren használat előtt ajánlott először DRY RUN módban ellenőrizni a teljes kimenetet.

## IP-cím kivételek

Bizonyos IP-címeknél eltérő mapping lehet szükséges. Erre szolgál az `EXCEPTIONS` associative array.

Például:

```bash id="0b1cz3"
EXCEPTIONS[191]=250
EXCEPTIONS[192]=251
```

Ez azt jelenti, hogy:

```text id="7tqjmb"
.191 -> .250
.192 -> .251
```

Az exception **mind a Virtual Server destination IP-re, mind a SNAT IP-re alkalmazásra kerül**.

### Példa

Ha:

```text id="9gd7se"
DEST_IP = 10.10.10.191
```

akkor a normál `OFFSET=10` szabály helyett:

```text id="s3eyb9"
10.10.10.191 -> 10.10.10.250
```

történik.

Hasonlóan:

```text id="k7u4v2"
SNAT_TRANSLATED_IP = 10.20.20.191
```

esetén:

```text id="u8h1zz"
10.20.20.191 -> 10.20.20.250
```

lesz az eredmény.

Új exception hozzáadásához például:

```bash id="0c2r7m"
EXCEPTIONS[200]=220
EXCEPTIONS[201]=221
```

## IP-validáció

A script a feldolgozás előtt ellenőrzi a `DEST_IP` és `SNAT_TRANSLATED_IP` értékeket.

Az IP-nek IPv4 formátumúnak kell lennie:

```text id="r3l1bd"
x.x.x.x
```

és minden oktettnek `0–255` között kell lennie.

Érvénytelen IP esetén a script hibát logol, majd az adott sort kihagyja.

## Előzetes ellenőrzések

A tényleges konfigurációmódosítás előtt a script több ellenőrzést végez.

### Virtual Server

Ellenőrzi, hogy a megadott Virtual Server létezik-e:

```bash id="2g2rhc"
tmsh list ltm virtual "$VS" one-line
```

### SNAT Pool

Ellenőrzi, hogy a megadott SNAT Pool létezik-e:

```bash id="d7m8x2"
tmsh list ltm snatpool "$SNAT_POOL" one-line
```

### SNAT Pool Member

A script azt is ellenőrzi, hogy a bemeneti fájlban szereplő SNAT IP valóban tagja-e a megadott SNAT Poolnak.

Ha például:

```text id="d0g65j"
SNAT_POOL = snat_web
SNAT_TRANSLATED_IP = 10.20.20.100
```

akkor ellenőrzi, hogy a `10.20.20.100` cím ténylegesen szerepel-e az `snat_web` pool memberjei között.

## Módosítási folyamat

Egy input sor feldolgozása a következőképpen történik:

```text id="f44f6p"
Input line
    │
    ▼
Trim whitespace
    │
    ▼
Skip header / empty lines
    │
    ▼
Validate DEST_IP
    │
    ▼
Validate SNAT_TRANSLATED_IP
    │
    ▼
Calculate new VS IP
    │
    ▼
Calculate new SNAT IP
    │
    ▼
Check Virtual Server
    │
    ▼
Check SNAT Pool
    │
    ▼
Check SNAT Pool Member
    │
    ▼
DRY RUN?
   /   \
 YES    NO
  │      │
  ▼      ▼
 Log   Modify VS
          │
          ▼
       Verify VS
          │
          ▼
       Modify SNAT
          │
          ▼
       Verify SNAT
          │
          ▼
       Completed
```

## Virtual Server módosítása

`DRY_RUN=0` esetén a script a Virtual Server destination címét módosítja:

```bash id="8w0i0f"
tmsh modify ltm virtual "$VS_NAME" \
    destination "${NEW_DEST_IP}:${PORT}"
```

A módosítás után a script újra lekéri a Virtual Server destination értékét, és ellenőrzi, hogy az új IP szerepel-e benne.

## SNAT Pool módosítása

A Virtual Server sikeres módosítása után a script módosítja a SNAT Pool member címét:

```bash id="c7xq4u"
tmsh modify ltm snatpool "$SNAT_POOL" \
    members modify {
        "$SNAT_TRANSLATED_IP" {
            address "$NEW_SNAT_IP"
        }
    }
```

Ezután újra lekéri a SNAT Pool memberjeit, és ellenőrzi, hogy az új IP-cím ténylegesen megjelent-e.

## Fontos: részleges módosítás lehetősége

A Virtual Server és a SNAT Pool módosítása két külön lépés.

Ez azt jelenti, hogy ha a Virtual Server módosítása sikeres, de a SNAT Pool módosítása sikertelen, akkor a Virtual Server már módosítva lehet.

A script ezt külön warningként logolja:

```text id="d0h8h1"
WARNING - VS was already modified!
```

Ezért különösen fontos a **DRY RUN használata a tényleges módosítás előtt**, illetve a log ellenőrzése.

## Logging

A script minden fontos eseményt logol.

Az alapértelmezett log fájlnév timestamp alapján készül:

```text id="9cg9kn"
f5_ip_change_YYYYMMDD_HHMMSS.log
```

A log fájl helyét a `LOG_FILE` változó határozza meg.

Példa:

```text id="1s7j9g"
2026-09-17 12:00:00 | ============================================================
2026-09-17 12:00:00 | F5 IP migration started
2026-09-17 12:00:00 | ============================================================
2026-09-17 12:00:00 | Input file : ./virtual_servers.txt
2026-09-17 12:00:00 | Offset     : 10
2026-09-17 12:00:00 | Dry run    : 1
2026-09-17 12:00:00 | Log file   : ./f5_ip_change_20260917_120000.log
```

A script az induláskor többek között az input fájlt, offsetet és DRY RUN állapotot is rögzíti.

## Példa DRY RUN kimenetre

Egy feldolgozott Virtual Server esetén a log tartalmazza többek között:

```text id="2j5z0s"
------------------------------------------------------------
Processing line : 2
Virtual Server  : vs_http
DEST IP         : 10.10.10.100
PORT            : 80
SNAT Pool       : snat_web
SNAT IP         : 10.20.20.100
STATE           : enabled

VS IP change    : 10.10.10.100 -> 10.10.10.110
SNAT IP change  : 10.20.20.100 -> 10.20.20.110

DRY RUN - no configuration changes
```

A tényleges értékek természetesen az input fájl tartalmától függenek. A script a feldolgozott mezőket és a kiszámított új IP-címeket is naplózza.

## Hibakezelés

A script több ponton ellenőrzi a hibákat, többek között:

* input fájl hiánya;
* érvénytelen destination IP;
* érvénytelen SNAT IP;
* érvénytelenül kiszámított új IP;
* nem létező Virtual Server;
* nem létező SNAT Pool;
* hiányzó SNAT Pool member;
* sikertelen Virtual Server módosítás;
* sikertelen SNAT Pool módosítás;
* sikertelen konfiguráció-ellenőrzés.

Ha az input fájl nem létezik, a script hibával leáll.

## Telepítés

A script klónozása vagy másolása után:

```bash id="u2e7q4"
chmod +x vs_snatpool_ip_changer.sh
```

Helyezd mellé a bemeneti fájlt:

```text id="h8t5kn"
./
├── vs_snatpool_ip_changer.sh
└── virtual_servers.txt
```

## Ajánlott használat

### 1. Input ellenőrzése

Győződj meg róla, hogy a `virtual_servers.txt` megfelelő formátumú.

### 2. DRY RUN

Első lépésként:

```bash id="y3m2pl"
./vs_snatpool_ip_changer.sh
```

A script alapértelmezés szerint `DRY_RUN=1`, ezért konfigurációmódosítás nélkül megmutatja a tervezett változtatásokat.

### 3. Log ellenőrzése

Ellenőrizd a generált:

```text id="3e4g8k"
f5_ip_change_*.log
```

fájlt.

### 4. Tényleges módosítás

Ha a DRY RUN eredménye megfelelő, módosítsd:

```bash id="n5d8v9"
DRY_RUN=0
```

majd futtasd újra a scriptet.

## Biztonsági megfontolások

> **Ez a script konfigurációt módosít F5 BIG-IP rendszeren.**

Éles környezetben történő használat előtt:

1. készíts konfigurációs mentést;
2. ellenőrizd az input fájlt;
3. futtasd DRY RUN módban;
4. ellenőrizd a tervezett IP-módosításokat;
5. ellenőrizd az exception mappingeket;
6. ellenőrizd, hogy az SNAT IP-k valóban a megfelelő SNAT Poolhoz tartoznak;
7. csak ezután használd `DRY_RUN=0` értékkel.

Különösen fontos, hogy a Virtual Server módosítása és a SNAT Pool módosítása egymást követő műveletek, ezért egy későbbi hiba esetén előfordulhat részleges módosítás.

## Exit Code

A script normál befejezés esetén:

```text id="2u8m8k"
exit 0
```

értékkel fejeződik be.

Input fájl hiánya esetén:

```text id="7k4n3c"
exit 1
```

történik.

## Kapcsolódó workflow

A script jól használható a korábbi két script után.

```text id="g1z5rs"
┌──────────────────────────────┐
│ 1. Virtual Server Query      │
│                              │
│ tmsh → virtual_servers.txt   │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ 2. Check New IP Usage        │
│                              │
│ ARP + PING                   │
│                              │
│ IP availability check        │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ 3. IP Migration              │
│                              │
│ VS destination change        │
│ SNAT pool member change      │
└──────────────────────────────┘
```

A harmadik script inputként ugyanazt a Virtual Server/SNAT információt használja, amelyet a korábbi lekérdező script állít elő.

## License

This project is provided as-is. Add your preferred license here if you intend to distribute the script publicly.
