# F5 BIG-IP IP Address Usage Checker

Egy Bash script F5 BIG-IP rendszerekhez, amely egy korábban generált Virtual Server listából ellenőrzi, hogy bizonyos IP-címek használatban vannak-e.

A script a `/tmp/virtual_servers.txt` fájlból olvassa ki a `DEST_IP` és `SNAT_TRANSLATED_IP` értékeket, majd az IP-címek utolsó oktettjét **22-vel csökkenti**. Az így kapott egyedi IP-címeket ARP és ICMP ping segítségével ellenőrzi.

## Funkciók

A script:

* beolvassa a Virtual Server adatokat;
* feldolgozza a `DEST_IP` mezőt;
* feldolgozza a `SNAT_TRANSLATED_IP` mezőt;
* az IP-címek utolsó oktettjéből levon 22-t;
* minden IP-címet csak egyszer ellenőriz;
* ellenőrzi az ARP táblát ping előtt;
* pingeli az IP-címet;
* újra ellenőrzi az ARP táblát ping után;
* eredményt ad minden IP-címhez;
* összesítést készít;
* külön listázza a további vizsgálatot igénylő címeket.

## Követelmények

A script futtatásához szükséges:

* F5 BIG-IP rendszer
* Bash
* `tmsh`
* `awk`
* `grep`
* `ping`
* `sort`
* `wc`

A script feltételezi, hogy a `/tmp/virtual_servers.txt` fájl már létezik, és tartalmazza a szükséges `DEST_IP` és `SNAT_TRANSLATED_IP` oszlopokat.

## Használat

Másold a scriptet például `check_new_ip_usage.sh` néven a BIG-IP rendszerre:

```bash
chmod +x check_new_ip_usage.sh
```

Ezután futtasd:

```bash
./check_new_ip_usage.sh
```

## Bemeneti fájl

Alapértelmezett bemeneti fájl:

```text
/tmp/virtual_servers.txt
```

A script az első sor alapján keresi meg a következő oszlopokat:

```text
DEST_IP
SNAT_TRANSLATED_IP
```

Ez lehetővé teszi, hogy az oszlopok sorrendje változzon anélkül, hogy a scriptben fix oszlopindexet kellene használni.

## IP-cím módosítása

A script alapértelmezett offset értéke:

```bash
OFFSET=22
```

Ez azt jelenti, hogy például:

```text
10.10.10.100
```

IP-címből:

```text
10.10.10.78
```

lesz az ellenőrzendő cím.

A módosítás kizárólag az IP-cím utolsó oktettjét érinti. Ha az eredmény nem lenne pozitív, az adott IP nem kerül a vizsgálati listába.

> **Figyelem:** az `OFFSET=22` érték a script működésének része. Csak akkor módosítsd, ha a környezetedben más offset szükséges.

## Duplikált IP-címek

A `DEST_IP` és `SNAT_TRANSLATED_IP` mezőkből előállított címek egy közös listába kerülnek, majd:

```bash
sort -u
```

segítségével a duplikált IP-címek kiszűrésre kerülnek.

Ez biztosítja, hogy egy IP-címet a script csak egyszer ellenőrizzen.

## Ellenőrzési folyamat

Minden IP-cím esetében a script három lépést hajt végre.

### 1. ARP ellenőrzés ping előtt

A script lekéri az aktuális ARP táblát:

```bash
tmsh show net arp all
```

Ezután ellenőrzi, hogy az IP-cím szerepel-e benne.

Lehetséges állapotok:

* `NO`
* `VALID`
* `INCOMPLETE`

### 2. Ping

Ezután egy ICMP ping történik:

```bash
ping -c 1 -W 1 "$ip"
```

A lehetséges eredmény:

```text
YES
NO
```

### 3. ARP ellenőrzés ping után

A ping után a script ismét lekéri az ARP táblát:

```bash
tmsh show net arp all
```

Ez azért hasznos, mert egy korábban nem ismert IP-cím pingelése után új ARP bejegyzés jelenhet meg.

## Eredmények

Az egyes IP-címekhez az alábbi eredmények valamelyike tartozhat:

| RESULT       | Jelentés                                                    |
| ------------ | ----------------------------------------------------------- |
| `ARP EXISTS` | Az IP-címhez már ping előtt érvényes ARP bejegyzés létezett |
| `PING`       | Az IP-cím pingre válaszolt                                  |
| `ARP VALID`  | Ping után érvényes ARP bejegyzés jelent meg                 |
| `FREE`       | A script alapján nem talált használatra utaló jelet         |

A prioritás a következő:

```text
ARP EXISTS
    ↓
PING
    ↓
ARP VALID
    ↓
FREE
```

## Kimenet

A script táblázatos formában jeleníti meg az eredményeket:

```text
IP                 ARP_BEFORE   PING       ARP_AFTER    RESULT
--------------------------------------------------------------
10.10.10.78       NO           NO         INCOMPLETE   FREE
10.10.10.79       VALID        NO         VALID        ARP EXISTS
10.10.10.80       NO           YES        VALID        PING
10.10.10.81       NO           NO         VALID        ARP VALID
```

A fejléc és a formázás közvetlenül a scriptben definiált.

## Összesítés

A script a vizsgálat végén összesíti az eredményeket:

```text
==============================================================
SUMMARY
--------------------------------------------------------------
Unique IP addresses      : 10

ARP exists before ping   : 2
PING response            : 3
Valid ARP after ping     : 1
FREE                     : 4
==============================================================
```

Az egyes kategóriák számlálása a generált eredményfájl alapján történik.

## Figyelmeztetés

Ha legalább egy IP-cím az alábbi kategóriák valamelyikébe kerül:

* `ARP EXISTS`
* `PING`
* `ARP VALID`

akkor a script figyelmeztetést jelenít meg, és kilistázza azokat a címeket, amelyek további vizsgálatot igényelnek.

Példa:

```text
!!! WARNING !!!
IP addresses that need further investigation:

IP                 ARP_BEFORE   PING       ARP_AFTER    RESULT
--------------------------------------------------------------
10.10.10.79       VALID        NO         VALID        ARP EXISTS
10.10.10.80       NO           YES        VALID        PING

DO NOT USE these IP addresses without further checking.
```

Ilyen esetben a script:

```text
exit 1
```

értékkel fejeződik be.

## Szabadnak tekintett IP-címek

Ha egyik ellenőrzött IP-címnél sem található használatra utaló jel, a script:

```text
OK: No checked IP appears to be in use.
ARP INCOMPLETE entries are treated as FREE.
```

üzenetet jelenít meg, és:

```text
exit 0
```

értékkel fejeződik be.

> **Fontos:** a `FREE` eredmény nem jelent abszolút garanciát arra, hogy az IP-cím biztonságosan használható. A script az ARP és ping ellenőrzések alapján nem talált aktív használatra utaló jelet.

## Ideiglenes fájlok

A script egyedi, process ID (`$$`) alapú ideiglenes fájlokat használ:

```text
/tmp/ip_check_ips_<PID>.tmp
/tmp/ip_check_results_<PID>.tmp
/tmp/ip_check_arp_before_<PID>.tmp
/tmp/ip_check_arp_after_<PID>.tmp
```

A script `trap` segítségével kilépéskor automatikusan törli ezeket az ideiglenes fájlokat.

## Exit Codes

A script exit code-ja automatizálásnál is használható:

| Exit code | Jelentés                                                       |
| --------: | -------------------------------------------------------------- |
|       `0` | Egyetlen ellenőrzött IP-nél sem talált használatra utaló jelet |
|       `1` | Legalább egy IP további vizsgálatot igényel                    |

Ez lehetővé teszi, hogy a script például monitoring vagy provisioning folyamat részeként is használható legyen.

## Működési folyamat

```text
             /tmp/virtual_servers.txt
                       │
                       ▼
              DEST_IP + SNAT IP
                       │
                       ▼
              Last octet - 22
                       │
                       ▼
                  sort -u
                       │
                       ▼
              Unique IP addresses
                       │
                       ▼
              ┌────────────────┐
              │ ARP BEFORE     │
              └───────┬────────┘
                      │
                      ▼
              ┌────────────────┐
              │ PING           │
              └───────┬────────┘
                      │
                      ▼
              ┌────────────────┐
              │ ARP AFTER      │
              └───────┬────────┘
                      │
                      ▼
                 RESULT
                      │
              ┌───────┴────────┐
              ▼                ▼
          In use /           FREE
       investigation
```

## Kapcsolódó script

Ez a script a Virtual Server lekérdező script által létrehozott:

```text
/tmp/virtual_servers.txt
```

fájlt használja bemenetként.

A két script együtt használható egy egyszerű workflow-ként:

```text
F5 Virtual Server Query
          │
          ▼
/tmp/virtual_servers.txt
          │
          ▼
Check New IP Usage
          │
          ▼
  ARP / PING check
          │
          ▼
   IP usage result
```

## License

This project is provided as-is. Add your preferred license here if you intend to distribute the script publicly.
