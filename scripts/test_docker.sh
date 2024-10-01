#!/usr/bin/env bash
# stats
# average rate = 29762.59 msg/sec count=300000 time=10.0798 (average) msg size=2048 bandwidth=59525.18 kB/sec
# cat /tmp/loggen_stats.txt | awk -F "[ =]" '{printf("%s %s %s %s %s\n", $13, $8, $11, $17, $19)}'
# 10.0798 29762.59 300000 2048 59525.18
set -e
#set -x

LOG=$(mktemp)
TESTS="tcp.logbackends udp.logbackends tcpbackends rings"
SEP="\t"

start_docker_compose() {
  echo hey

}

generate_env_file() {
  local tmpfile=$(mktemp)
  local cfgspec=$1
  local connections=$2
  local logbufsize=$3
  local protoparam=${4:--S}

  cat <<EOF >>${tmpfile}
CFG_SPEC=${cfgspec}
ACTIVE_CONNECTIONS=${connections}
LOGBUFSIZE=${logbufsize}
PROTOCOL_PARAM="${protoparam}"
MSG_SIZE=2048
MSG_RATE=5000
MSG_COUNT=50000
EOF

  echo ${tmpfile}
}

header() {
  printf "%-20s${SEP}%-12s${SEP}%-3s${SEP}%-10s${SEP}%-12s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" test 'duration(s)' conns bufsize count 's1_ms' 's2_ms' 's_tot' lost
}

# -----
#

for test in ${TESTS}; do
  #for test in rings; do
  cfgspec=${test}

  unset protoparam
  if [[ "${test}" =~ "udp" ]]; then
    protoparam="-D"
  fi

  header
  for conn in 1 $(seq 2 4 80); do
    # 4MB per connection
    bufsize=$(($conn * 4 * 1024 * 1024))

    envfile=$(generate_env_file ${cfgspec} ${conn} ${bufsize} ${protoparam})

    # cleanup previous runs
    docker compose --env-file "${envfile}" down --remove-orphans >/dev/null 2>&1

    # start in the background
    docker compose --env-file "${envfile}" --progress=plain up -d >/dev/null 2>&1 || true

    # wait until loggen exits
    while [ -z "$(docker ps -q -f status=exited -f name=syslog-gen-1)" ]; do
      sleep 1
    done

    # loggen stats
    docker compose --env-file "${envfile}" logs syslog-gen | fgrep "average rate" | sed -e 's/,//g' >/tmp/loggen_stats.txt

    read -r duration msgsec count msgsize bw < <(awk -F "[ =]" '{printf("%s %s %s %s %s\n", $13, $8, $11, $17, $19)}' /tmp/loggen_stats.txt)

    # axosyslog stats
    docker exec -it haproxy-logfwd-syslog-server-1-1 syslog-ng-ctl stats | sed 's/\r//' >/tmp/syslog1_stats.txt
    docker exec -it haproxy-logfwd-syslog-server-2-1 syslog-ng-ctl stats | sed 's/\r//' >/tmp/syslog2_stats.txt

    # extract totals
    syslog1_msgs=$(awk -F ';' '/center;;received/ {print $6}' /tmp/syslog1_stats.txt)
    syslog2_msgs=$(awk -F ';' '/center;;received/ {print $6}' /tmp/syslog2_stats.txt)

    rm $envfile

    # results
    #
    s_tot=$((${syslog1_msgs} + ${syslog2_msgs}))
    lost=$((${count} - ${s_tot}))
    printf "%-20s${SEP}%-12s${SEP}%-3s${SEP}%-10s${SEP}%-12s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" ${cfgspec} ${duration} ${conn} ${bufsize} ${count} ${syslog1_msgs} ${syslog2_msgs} ${s_tot} ${lost}
  done
  echo ""
done
# Shutdown
#docker compose down --remove-orphans >/dev/null 2>&1
