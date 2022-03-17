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
jobid="None"

#READING INPUT DATA FROM COMMAND LINE
while test "x$1" != x ; do
    case $1 in
     -j         ) input=${input/$1/}; shift; input=${input/$1/}; jobid=$1     ;;
     -h         ) input=${input/$1/}; help=true     ;;
    esac
    shift
done

# Help if requested
if $help; then
    # Specific help (need to be written)
    if [ -e $QUEUE_MAN/qstat.man ]; then 
        cat $QUEUE_MAN/qstat.man
    else
        # General help of all tools
        cat $QUEUE_MAN/queue.man
    fi
    exit
fi

if [ "$jobid" == "None" ]; then
    # Default behaviour: show basic info about all jobs
    N=$(wc -l < $QUEUE_LOG/queue.log)
    if (( $N > 2 )); then
        cat $QUEUE_LOG/queue.log
    fi
else
    echo ""
    jobid=${jobid/qe_/}
    # Show specific info about jobid
    iswaiting=$(ls $QUEUE_TMP/.waiting.*.$jobid 2>/dev/null)
    isrunning=$(ls $QUEUE_TMP/.running.*.$jobid 2>/dev/null)
    if   [ "$iswaiting" != "" ]; then
        echo "Job qe_${jobid} is queued"
        echo "-------------------------------"
        cat $QUEUE_TMP/.waiting.*.$jobid
        echo "-------------------------------"
    elif [ "$isrunning" != "" ]; then
        echo "Jos qe_${jobid} is running"
        echo "-------------------------------"
        cat $QUEUE_TMP/.running.*.$jobid
        echo "-------------------------------"
    else
        echo "qe_${jobid} is not an active job"
    fi
    echo ""
fi

