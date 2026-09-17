#!/bin/bash

INPUT="/tmp/virtual_servers.txt"
OFFSET=22

TMP_IPS="/tmp/ip_check_ips_$$.tmp"
TMP_RESULTS="/tmp/ip_check_results_$$.tmp"
TMP_ARP_BEFORE="/tmp/ip_check_arp_before_$$.tmp"
TMP_ARP_AFTER="/tmp/ip_check_arp_after_$$.tmp"

trap 'rm -f "$TMP_IPS" "$TMP_RESULTS" "$TMP_ARP_BEFORE" "$TMP_ARP_AFTER"' EXIT


echo "IP address check"
echo "Source: $INPUT"
echo "DEST_IP and SNAT_TRANSLATED_IP: -$OFFSET"
echo "=============================================================="

printf "%-18s %-12s %-10s %-12s %-20s\n" \
       "IP" "ARP_BEFORE" "PING" "ARP_AFTER" "RESULT"

echo "--------------------------------------------------------------"


# ==============================================================
# 1. Read DEST_IP and SNAT_TRANSLATED_IP
#    Subtract 22 from both
#    sort -u = check every IP only once
# ==============================================================

awk -F'|' -v offset="$OFFSET" '
NR==1 {
    for (i=1; i<=NF; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i)

        if ($i == "DEST_IP")
            dest_col=i

        if ($i == "SNAT_TRANSLATED_IP")
            snat_col=i
    }
    next
}

{
    # DEST_IP
    ip=$dest_col
    gsub(/^[ \t]+|[ \t]+$/, "", ip)

    if (ip != "" && ip != "none") {
        split(ip,a,".")

        if (a[4] - offset > 0)
            print a[1]"."a[2]"."a[3]"."(a[4]-offset)
    }

    # SNAT_TRANSLATED_IP
    ip=$snat_col
    gsub(/^[ \t]+|[ \t]+$/, "", ip)

    if (ip != "" && ip != "none") {
        split(ip,a,".")

        if (a[4] - offset > 0)
            print a[1]"."a[2]"."a[3]"."(a[4]-offset)
    }
}
' "$INPUT" | sort -u > "$TMP_IPS"


TOTAL_IPS=$(wc -l < "$TMP_IPS")

echo "Unique IP addresses to check: $TOTAL_IPS"
echo "=============================================================="
echo ""


# ==============================================================
# 2. Check every IP
# ==============================================================

while IFS= read -r ip; do

    # ----------------------------------------------------------
    # ARP check BEFORE ping
    # ----------------------------------------------------------

    tmsh show net arp all > "$TMP_ARP_BEFORE"

    arp_before="NO"

    if grep -qw "$ip" "$TMP_ARP_BEFORE"; then

        # Get complete ARP line
        arp_line=$(grep -w "$ip" "$TMP_ARP_BEFORE" | head -1)

        # Check for incomplete state
        if echo "$arp_line" | grep -qi "incomplete"; then
            arp_before="INCOMPLETE"
        else
            arp_before="VALID"
        fi

    fi


    # ----------------------------------------------------------
    # Ping
    # ----------------------------------------------------------

    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
        ping_status="YES"
    else
        ping_status="NO"
    fi


    # ----------------------------------------------------------
    # ARP check AFTER ping
    # ----------------------------------------------------------

    tmsh show net arp all > "$TMP_ARP_AFTER"

    arp_after="NO"

    if grep -qw "$ip" "$TMP_ARP_AFTER"; then

        # Get complete ARP line
        arp_line=$(grep -w "$ip" "$TMP_ARP_AFTER" | head -1)

        # Check for incomplete state
        if echo "$arp_line" | grep -qi "incomplete"; then
            arp_after="INCOMPLETE"
        else
            arp_after="VALID"
        fi

    fi


    # ----------------------------------------------------------
    # Result
    # ----------------------------------------------------------

    if [[ "$arp_before" == "VALID" ]]; then

        result="ARP EXISTS"

    elif [[ "$ping_status" == "YES" ]]; then

        result="PING"

    elif [[ "$arp_after" == "VALID" ]]; then

        result="ARP VALID"

    elif [[ "$arp_after" == "INCOMPLETE" ]]; then

        result="FREE"

    else

        result="FREE"

    fi


    printf "%-18s %-12s %-10s %-12s %-20s\n" \
           "$ip" \
           "$arp_before" \
           "$ping_status" \
           "$arp_after" \
           "$result"

    echo "$ip|$arp_before|$ping_status|$arp_after|$result" \
        >> "$TMP_RESULTS"

done < "$TMP_IPS"


# ==============================================================
# 3. Summary
# ==============================================================

TOTAL=$(wc -l < "$TMP_RESULTS")

ARP_EXISTS=$(grep -Ec '\|ARP EXISTS$' "$TMP_RESULTS" || true)
PING_ONLY=$(grep -Ec '\|PING$' "$TMP_RESULTS" || true)
ARP_VALID=$(grep -Ec '\|ARP VALID$' "$TMP_RESULTS" || true)
FREE=$(grep -Ec '\|FREE$' "$TMP_RESULTS" || true)

echo ""
echo "=============================================================="
echo "SUMMARY"
echo "--------------------------------------------------------------"
echo "Unique IP addresses      : $TOTAL"
echo ""
echo "ARP exists before ping   : $ARP_EXISTS"
echo "PING response            : $PING_ONLY"
echo "Valid ARP after ping     : $ARP_VALID"
echo "FREE                     : $FREE"
echo "=============================================================="


# ==============================================================
# 4. List IPs that need attention
# ==============================================================

if (( ARP_EXISTS > 0 || PING_ONLY > 0 || ARP_VALID > 0 )); then

    echo ""
    echo "!!! WARNING !!!"
    echo "IP addresses that need further investigation:"
    echo ""

    printf "%-18s %-12s %-10s %-12s %-20s\n" \
           "IP" "ARP_BEFORE" "PING" "ARP_AFTER" "RESULT"

    echo "--------------------------------------------------------------"

    awk -F'|' '
    $5 != "FREE" {
        printf "%-18s %-12s %-10s %-12s %-20s\n",
               $1,$2,$3,$4,$5
    }
    ' "$TMP_RESULTS"

    echo ""
    echo "DO NOT USE these IP addresses without further checking."

    exit 1

else

    echo ""
    echo "OK: No checked IP appears to be in use."
    echo "ARP INCOMPLETE entries are treated as FREE."

    exit 0

fi

