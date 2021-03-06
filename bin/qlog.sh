#!/bin/bash

#######################################################
# Scripts para emular el comportamiento de un
# gestor de colas
#
# J Cerezo, 09/2017
#
#
# Definimos algunas variable de entorno relevantes
QUEUE_PATH=/opt/queue_emulator
QUEUE_BIN=$QUEUE_PATH/bin
QUEUE_LOG=$QUEUE_PATH/log
QUEUE_TMP=$QUEUE_PATH/tmp
QUEUE_MAN=$QUEUE_PATH/man
#######################################################

# Read job command
input=$@

# Defaults
help=false

#READING INPUT DATA FROM COMMAND LINE
while test "x$1" != x ; do
    case $1 in
     -h         ) input=${input/$1/}; help=true     ;;
    esac
    shift
done

# Help if requested
if $help; then
    # Specific help (need to be written)
    if [ -e $QUEUE_MAN/qlog.man ]; then 
        cat $QUEUE_MAN/qlog.man
    else
        # General help of all tools
        cat $QUEUE_MAN/queue.man
    fi
    exit
fi

cat $QUEUE_LOG/history.log

