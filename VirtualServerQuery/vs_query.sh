{
    echo "VS_NAME | DEST_IP | PORT | POOL | SNAT_POOL | SNAT_TRANSLATED_IP | STATE"

    tmsh list ltm virtual all-properties one-line > /tmp/vs_raw.txt
    tmsh list ltm snatpool all-properties one-line > /tmp/snat_raw.txt

    awk '
    BEGIN {
        # SNAT pool -> translated IP
        while ((getline line < "/tmp/snat_raw.txt") > 0) {

            match(line, /^ltm snatpool ([^ ]+)/, n)
            snatpool=n[1]

            match(line, /members \{([^}]*)\}/, m)
            snatip=m[1]

            gsub(/^[ \t]+|[ \t]+$/, "", snatip)

            if (snatpool != "")
                snat[snatpool]=snatip
        }

        close("/tmp/snat_raw.txt")
    }

    {
        # VS név
        vs=$3

        # DESTINATION
        match($0, /destination ([^ ]+)/, d)
        split(d[1], dest, ":")

        dest_ip=dest[1]
        port=dest[2]

        # POOL
        match($0, / pool ([^ ]+)/, p)
        pool=p[1]

        # SNAT pool
        match($0, /source-address-translation \{ pool ([^ ]+) type snat \}/, s)
        snatpool=s[1]

        # STATE
        match($0, /(enabled|disabled) ephemeral-auth-access-config/, st)
        state=st[1]

        # Eredmény
        print vs " | " \
              dest_ip " | " \
              port " | " \
              pool " | " \
              snatpool " | " \
              snat[snatpool] " | " \
              state

    }' /tmp/vs_raw.txt
} > /tmp/virtual_servers.txt

# Virtual serverek számának meghatározása
VS_COUNT=$(($(wc -l < /tmp/virtual_servers.txt) - 1))

echo ""
echo "=========================================="
echo " Virtual serverek száma: $VS_COUNT"
echo " Kimeneti fájl: /tmp/virtual_servers.txt"
echo "=========================================="
cat /tmp/virtual_servers.txt
