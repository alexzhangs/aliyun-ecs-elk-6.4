#!/bin/bash

## Install Elasticsearch 6.4 on Linux from .tar file.
## Date: 2018-09-11


# Exit on any error
set -eo pipefail

# Debug
if [[ $DEBUG -gt 0 ]]; then
    set -x
else
    set +x
fi

# Set constant
ES_PATH_DATA=/var/lib/elasticsearch
ES_PATH_LOG=/var/log/elasticsearch

# Set default
cluster_name=es_cluster
host=0.0.0.0
memlock=false
role_master=true
role_data=true
role_ingest=true
role_remote_search=true


function usage () {
    printf "Install Elasticsearch 6.4 on Linux from .tar file.\n"
    printf "${0##*/}\n"
    printf "\t-f FILE\n"
    printf "\t-u USER\n"
    printf "\t[-g GROUP]\n"
    printf "\t[-c CLUSTER_NAME]\n"
    printf "\t[-p]\n"
    printf "\t[-l]\n"
    printf "\t[-m]\n"
    printf "\t[-d]\n"
    printf "\t[-i]\n"
    printf "\t[-r]\n"
    printf "\t[-h]\n"

    printf "OPTIONS\n"
    printf "\t-f FILE\n\n"
    printf "\tInstaller file in .tar.\n\n"

    printf "\t-u USER\n\n"
    printf "\tUser name to run Elasticsearch.\n\n"

    printf "\t[-g GROUP]\n\n"
    printf "\tGroup name for user to run Elasticsearch.\n\n"

    printf "\t[-c CLUSTER_NAME]\n\n"
    printf "\tCluster name of Elasticsearch.\n\n"

    printf "\t[-p]\n\n"
    printf "\tListen on private IP, default is 0.0.0.0.\n\n"

    printf "\t[-l]\n\n"
    printf "\tTurn on Lock Memory, default is off.\n\n"

    printf "\t[-m]\n\n"
    printf "\tTurn off Master role, default is on.\n\n"

    printf "\t[-d]\n\n"
    printf "\tTurn off Data role, default is on.\n\n"

    printf "\t[-i]\n\n"
    printf "\tTurn off Ingest role, default is on.\n\n"

    printf "\t[-r]\n\n"
    printf "\tTurn off Search Remote Connect, default is on.\n\n"

    printf "\t[-h]\n\n"
    printf "\tThis help.\n\n"
    exit 255
}

function get_ecs_private_ip () {
    ifconfig eth0 | awk '/inet / {print $2; exit}'
}

function get_total_memory_size () {
    cat /proc/meminfo | \
        grep MemTotal | \
        awk '{ print $2 }' # In KB
}

function calc_es_heap_size () {
    local mem=$(get_total_memory_size)
    echo $((mem / 1024 / 2))m # In MB
}

function is_mac () {
    uname | grep -iq 'darwin'
}

function sed_regx () {
    is_mac && sed -E "$@" || sed -r "$@"
}

function sed_inplace () {
    is_mac && sed -i '' "$@" || sed -i "$@"
}

function sed_regx_inplace () {
    is_mac && sed -E -i '' "$@" || sed -r -i "$@"
}

## Inject lines into file.
## Tested under linux amd macos.
function inject () {
    local opt
    local OPTARG OPTIND
    local file content
    local replace before after start end

    while getopts f:c:r:b:a:se opt; do
        case $opt in
            f)
                file=${OPTARG}
                ;;
            c)
                content=${OPTARG}
                ;;
            r)
                replace=${OPTARG}
                ;;
            b)
                before=${OPTARG}
                ;;
            a)
                after=${OPTARG}
                ;;
            s)
                start=1
                ;;
            e)
                end=1
                ;;
        esac
    done

    if [[ -n $replace ]]; then
        if [[ -n $(sed_regx -n "/${replace:?}/p" "${file:?}") ]]; then
            printf "%s\n" "${content}" | sed_regx_inplace "/${replace:?}/{
r /dev/stdin
d
}" "${file:?}"
            return
        fi
    fi

    if [[ -n $before ]]; then
        if [[ -n $(sed_regx -n "/${before:?}/p" "${file:?}") ]]; then
            printf "%s\n" "${content}" | sed_regx_inplace "/${before:?}/{
h
r /dev/stdin
g
N
}" "${file:?}"
            return
        fi
    fi

    if [[ -n $after ]]; then
        if [[ -n $(sed_regx -n "/${after:?}/p" "${file:?}") ]]; then
            printf "%s\n" "${content}" | sed_regx_inplace "/${after:?}/ r /dev/stdin" "${file:?}"
            return
        fi
    fi

    if [[ -n $start ]]; then
        printf "%s\n" "${content}" | sed_inplace "1{
h
r /dev/stdin
g
N
}" "${file:?}"
        return
    fi

    if [[ -n $end ]]; then
        printf "%s\n" "${content}" | sed_inplace "$ r /dev/stdin" "${file:?}"
        return
    fi
}


# Main

file=
user=
group=

while getopts f:u:g:c:plmdirh opt; do
    case $opt in
        f)
            file=${OPTARG}
            ;;
        u)
            user=${OPTARG}
            ;;
        g)
            group=${OPTARG}
            ;;
        c)
            cluster_name=${OPTARG}
            ;;
        p)
            private_ip=1
            ;;
        l)
            memlock=true
            ;;
        m)
            role_master=false
            ;;
        d)
            role_data=false
            ;;
        i)
            role_ingest=false
            ;;
        r)
            role_remote_search=false
            ;;
        h|*)
            usage
            ;;
    esac
done

[[ -z $file || -z $user ]] && usage
[[ -z $group ]] && group=$user

# Install ES
/usr/bin/tar -C /opt -xzvf "$file"
chown -R "$user":"$group" /opt/elasticsearch*

mkdir -p "${ES_PATH_DATA:?}" "${ES_PATH_LOG:?}"
chown "$user":"$group" "${ES_PATH_DATA:?}" "${ES_PATH_LOG:?}"

# Configure ES
es_yml_config=$(ls -1 /opt/elasticsearch*/config/elasticsearch.yml)
es_jvm_config=$(ls -1 /opt/elasticsearch*/config/jvm.options)

if [[ $private_ip -eq 1 ]]; then
    host=$(get_ecs_private_ip)
fi

# cluster.name
inject -f "$es_yml_config" -c "cluster.name: ${cluster_name:?}" \
       -r "^cluster.name:" -a "^#cluster.name:" -e

# node.name
inject -f "$es_yml_config" -c "node.name: \${HOSTNAME}" \
       -r "^node.name:" -a "^#node.name:" -e

# path.data
inject -f "$es_yml_config" -c "path.data: ${ES_PATH_DATA:?}" \
       -r "^path.data:" -a "^#path.data:" -e

# path.logs
inject -f "$es_yml_config" -c "path.logs: ${ES_PATH_LOG:?}" \
       -r "^path.logs:" -a "^#path.logs:" -e

# bootstrap.memory_lock
inject -f "$es_yml_config" -c "bootstrap.memory_lock: ${memlock:?}" \
       -r "^bootstrap.memory_lock:" -a "^#bootstrap.memory_lock:" -e

# network.host
inject -f "$es_yml_config" -c "network.host: ${host:?}" \
       -r "^network.host:" -a "^#network.host:" -e

# node.master
inject -f "$es_yml_config" -c "node.master: ${role_master:?}" \
       -r "^node.master:" -a "^#node.master:" -e

# node.data
inject -f "$es_yml_config" -c "node.data: ${role_data:?}" \
       -r "^node.data:" -a "^#node.data:" -e

# node.ingest
inject -f "$es_yml_config" -c "node.ingest: ${role_ingest:?}" \
       -r "^node.ingest:" -a "^#node.ingest:" -e

# search.remote.connect
inject -f "$es_yml_config" -c "search.remote.connect: ${role_remote_search:?}" \
       -r "^search.remote.connect:" -a "^#search.remote.connect:" -e

es_heap_size=$(calc_es_heap_size)

# -Xms
inject -f "$es_jvm_config" -c "-Xms${es_heap_size:?}" \
       -r "^-Xms" -a "^#-Xms" -e

# -Xmx
inject -f "$es_jvm_config" -c "-Xmx${es_heap_size:?}" \
       -r "^-Xmx" -a "^#-Xmx" -e

exit
