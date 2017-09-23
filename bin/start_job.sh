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
#
# Queue parameters
QUEUE_NPROC=16
#######################################################

# The input provides the current job id and requested proc
(( JOB_ID=$1 ))
(( NPROC=$2  ))

# Get current date
NOW=$(date "+%d %b %y %H:%M:%S")

# First check that requested proc is not avobe node limits
if (( NPROC > QUEUE_NPROC )); then
    >&2 echo "Error: requested procesors avobe node limits ($QUEUE_NPROC)"
    exit
fi

# Check if there is any job already running
# Running files have the format:
#  .running.NPROC.JOBID
ls $QUEUE_TMP/.running.* 2>/dev/null 1>$QUEUE_TMP/.running.all.tmp
if (( $? != 0 )); then
    touch $QUEUE_TMP/.running.$NPROC.$JOB_ID
else
    # Get number of procesors avilable
    (( NP_USED = 0 ))
    while read runjob; do 
        runjob=${runjob##*/}
        np_used_job=${runjob/.running./}
        np_used_job=${np_used_job%.*}
        (( NP_USED += $np_used_job ))
    done < $QUEUE_TMP/.running.all.tmp
    (( NP_AVAIL = QUEUE_NPROC - NP_USED ))
    if (( NP_AVAIL >= NPROC )); then
        touch $QUEUE_TMP/.running.${NPROC}.$JOB_ID
    else
        touch $QUEUE_TMP/.waiting.${NPROC}.$JOB_ID
    fi
fi
rm $QUEUE_TMP/.running.all.tmp
