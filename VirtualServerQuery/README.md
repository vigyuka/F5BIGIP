# F5 BIG-IP Virtual Server Query

Egy egyszerű Bash script F5 BIG-IP rendszerekhez, amely lekérdezi a konfigurált **Virtual Servereket**, azokhoz tartozó **destination IP/port**, **pool**, **SNAT pool**, **SNAT translated IP** és **state** információkat.

A script a `tmsh` konfigurációs kimenetét dolgozza fel, majd egy könnyen olvasható táblázatos kimenetet készít.

## Funkciók

A script az alábbi információkat gyűjti össze minden Virtual Serverhez:

| Mező                 | Leírás                                |
| -------------------- | ------------------------------------- |
| `VS_NAME`            | Virtual Server neve                   |
| `DEST_IP`            | Virtual Server destination IP címe    |
| `PORT`               | Virtual Server portja                 |
| `POOL`               | A Virtual Serverhez rendelt pool      |
| `SNAT_POOL`          | A használt SNAT pool neve             |
| `SNAT_TRANSLATED_IP` | Az SNAT poolhoz tartozó translated IP |
| `STATE`              | Virtual Server állapota               |

A kimenet fejlécét a script az alábbi formában hozza létre:

```text
VS_NAME | DEST_IP | PORT | POOL | SNAT_POOL | SNAT_TRANSLATED_IP | STATE
```

## Követelmények

A script futtatásához szükséges:

* F5 BIG-IP rendszer
* `tmsh`
* Bash shell
* `awk`
* `wc`

A scriptet közvetlenül az F5 BIG-IP rendszeren érdemes futtatni, ahol a `tmsh` konfigurációs parancsok elérhetők.

## Használat

Másold a scriptet például `vs_query.sh` néven a BIG-IP rendszerre:

```bash
chmod +x vs_query.sh
```

Majd futtasd:

```bash
./vs_query.sh
```

## Működés

### 1. Virtual Serverek lekérdezése

A script a következő `tmsh` paranccsal gyűjti össze a Virtual Serverek teljes konfigurációját:

```bash
tmsh list ltm virtual all-properties one-line > /tmp/vs_raw.txt
```

### 2. SNAT poolok lekérdezése

Az SNAT poolok konfigurációja külön fájlba kerül:

```bash
tmsh list ltm snatpool all-properties one-line > /tmp/snat_raw.txt
```

A két ideiglenes fájlt a script a `/tmp` könyvtárban hozza létre.

### 3. SNAT pool → translated IP mapping

Az `awk` feldolgozás során a script létrehoz egy mappinget az SNAT pool neve és a hozzá tartozó translated IP között.

A `members` értékből kerül kiolvasásra az SNAT IP:

```awk
match(line, /members \{([^}]*)\}/, m)
snatip=m[1]
```

Majd a mappinget egy `snat[]` tömbben tárolja:

```awk
snat[snatpool]=snatip
```

### 4. Virtual Server adatok feldolgozása

Minden Virtual Server esetében a script kinyeri:

* Virtual Server nevét
* destination IP-t
* portot
* poolt
* SNAT poolt
* state értéket

A destination IP és port a `destination` mezőből kerül feldolgozásra.

A hozzárendelt pool:

```awk
match($0, / pool ([^ ]+)/, p)
pool=p[1]
```

A SNAT pool:

```awk
match($0, /source-address-translation \{ pool ([^ ]+) type snat \}/, s)
snatpool=s[1]
```

A Virtual Server state értéke szintén feldolgozásra kerül:

```awk
match($0, /(enabled|disabled) ephemeral-auth-access-config/, st)
state=st[1]
```

## Kimenet

Az eredmény a következő fájlba kerül:

```text
/tmp/virtual_servers.txt
```

A script a végén kiírja a Virtual Serverek számát és a kimeneti fájl helyét is:

```text
==========================================
 Virtual serverek száma: X
 Kimeneti fájl: /tmp/virtual_servers.txt
==========================================
```

### Példa

```text
VS_NAME | DEST_IP | PORT | POOL | SNAT_POOL | SNAT_TRANSLATED_IP | STATE
vs_http | 10.10.10.10 | 80 | web_pool | snat_web | 192.168.10.10 | enabled
vs_https | 10.10.10.20 | 443 | https_pool | snat_https | 192.168.10.20 | enabled
```

> A fenti adatok csak szemléltető példák.

## Folyamat

A script működése röviden:

```text
                 F5 BIG-IP
                     │
          ┌──────────┴──────────┐
          │                     │
          ▼                     ▼
   tmsh list ltm          tmsh list ltm
      virtual               snatpool
          │                     │
          ▼                     ▼
   /tmp/vs_raw.txt      /tmp/snat_raw.txt
          │                     │
          └──────────┬──────────┘
                     ▼
                    awk
                     │
                     ▼
        /tmp/virtual_servers.txt
                     │
                     ▼
             Összesített lista
```

## Fontos megjegyzések

* A script F5 BIG-IP `tmsh` kimenetre épül.
* A feldolgozás regexekkel történik, ezért a script feltételezi a várt `tmsh` output formátumot.
* Az ideiglenes fájlok a `/tmp` könyvtárba kerülnek.
* A script a Virtual Serverek számát a generált output sorainak számából számolja, a fejlécet levonva.

## License

This project is provided as-is. Add your preferred license here if you intend to distribute the script publicly.
