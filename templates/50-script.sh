# Discord Voice & Video Fix (STUN + Discord Media IP Discovery)
# This custom script desyncs both Discord IP Discovery and STUN packets
# Resolves "Infinite RTC Connecting" / "No Route" in Discord voice calls
# Compatible with LuCI "custom.d script #50" and OpenWrt 22, 23, 24+

# Can override in config:
NFQWS_OPT_DESYNC_STUN="${NFQWS_OPT_DESYNC_STUN:---payload=stun --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2}"
NFQWS_OPT_DESYNC_DISCORD_MEDIA="${NFQWS_OPT_DESYNC_DISCORD_MEDIA:---payload=discord_ip_discovery --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2}"
DISCORD_MEDIA_PORT_RANGE="${DISCORD_MEDIA_PORT_RANGE:-50000-65535,19294-19344}"

alloc_dnum DNUM_STUN4ALL
alloc_qnum QNUM_STUN4ALL
alloc_dnum DNUM_DISCORD_MEDIA
alloc_qnum QNUM_DISCORD_MEDIA

zapret_custom_daemons()
{
	# $1 - 1 - add, 0 - stop
	local opt_stun="--qnum=$QNUM_STUN4ALL $NFQWS_OPT_DESYNC_STUN"
	do_nfqws $1 $DNUM_STUN4ALL "$opt_stun"

	local opt_media="--qnum=$QNUM_DISCORD_MEDIA $NFQWS_OPT_DESYNC_DISCORD_MEDIA"
	do_nfqws $1 $DNUM_DISCORD_MEDIA "$opt_media"
}

zapret_custom_firewall()
{
	# $1 - 1 - run, 0 - stop
	local f_stun='-p udp -m u32 --u32'
	fw_nfqws_post $1 "$f_stun 0>>22&0x3C@4>>16=28:65535&&0>>22&0x3C@12=0x2112A442&&0>>22&0x3C@8&0xC0000003=0" "$f_stun 44>>16=28:65535&&52=0x2112A442&&48&0xC0000003=0" $QNUM_STUN4ALL

	local DISABLE_IPV6=1
	local port_range
	port_range=$(replace_char - : "$DISCORD_MEDIA_PORT_RANGE")
	local f_media="-p udp -m multiport --dports $port_range -m u32 --u32"
	fw_nfqws_post $1 "$f_media 0>>22&0x3C@4>>16=0x52&&0>>22&0x3C@8=0x00010046&&0>>22&0x3C@16=0&&0>>22&0x3C@76=0" '' $QNUM_DISCORD_MEDIA
}

zapret_custom_firewall_nft()
{
	# stop logic is not required
	local f_stun="udp length >= 28 @ih,32,32 0x2112A442 @ih,0,2 0 @ih,30,2 0"
	nft_fw_nfqws_post "$f_stun" "$f_stun" $QNUM_STUN4ALL

	local DISABLE_IPV6=1
	local f_media="udp dport {$DISCORD_MEDIA_PORT_RANGE} udp length == 82 @ih,0,32 0x00010046 @ih,64,128 0x00000000000000000000000000000000 @ih,192,128 0x00000000000000000000000000000000 @ih,320,128 0x00000000000000000000000000000000 @ih,448,128 0x00000000000000000000000000000000"
	nft_fw_nfqws_post "$f_media" '' $QNUM_DISCORD_MEDIA
}
