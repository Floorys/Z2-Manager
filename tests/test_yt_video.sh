#!/bin/sh
echo "Fetching YouTube video page..."
page=$(curl -s "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
echo "Page size: ${#page} bytes"
gv=$(echo "${page}" | grep -o 'https://[^"\]*googlevideo\.com[^"\]*' | head -n 1)
echo "Found googlevideo URL: ${gv}"
if [ -n "${gv}" ]; then
    host=$(echo "${gv}" | sed -E 's|https://([^/]+).*|\1|')
    echo "Testing connection to CDN host: ${host}"
    curl -v -k -I --connect-timeout 4 -m 6 "https://${host}" 2>&1 | head -n 25
fi
