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
QUEUE_NPROC=4
#######################################################

# The input provides the current job id and requested proc
(( JOB_ID=$1 ))
(( NPROC=$2  ))

# Get current date
NOW=$(date "+%d %b %y %H:%M:%S")

# First check that requested proc is not above node limits
if (( NPROC > QUEUE_NPROC )); then
    >&2 echo "Error: requested procesors above node limits ($NPROC/$QUEUE_NPROC)"
    exit 1
fi
line=$(grep "$USER" $QUEUE_LOG/nproc_limits.dat)
if [ "x$line" != "x" ]; then
    nproc_limit=$(echo $line | awk '{print $2}')
else
    nproc_limit=$QUEUE_NPROC
fi
if (( NPROC > nproc_limit )); then
    >&2 echo "Error: requested procesors above user limits ($NPROC/$nproc_limit)"
    exit 1
fi

# Check if there is any job already running
# Running files have the format:
#  .running.NPROC.JOBID
ls $QUEUE_TMP/.running.* 2>/dev/null 1>$QUEUE_TMP/.running.all.tmp
if (( $? != 0 )); then
    #touch $QUEUE_TMP/.running.$NPROC.$JOB_ID
    cat <<EOF > $QUEUE_TMP/.running.${NPROC}.$JOB_ID
Job ID         : $JOB_ID
Submitter      : $USER
Submmit date   : $NOW
Submit location: ${PWD}
Requested procs: $NPROC
EOF

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
    if (( NP_AVAIL < NPROC )); then
        #touch $QUEUE_TMP/.waiting.${NPROC}.$JOB_ID
        cat <<EOF > $QUEUE_TMP/.waiting.${NPROC}.$JOB_ID
Job ID         : $JOB_ID
Submitter      : $USER
Submmit date   : $NOW
Submit location: ${PWD}
Requested procs: $NPROC
EOF
    else
        # Are the available procs under user limits?
        # Get number of procesors avilable to user
        ls -l $QUEUE_TMP/.running.* 2>/dev/null | grep " $USER " > $QUEUE_TMP/.running.all.tmp2
        (( NP_USED = 0 ))
        while read runjob; do 
            runjob=${runjob##*/}
            np_used_job=${runjob/.running./}
            np_used_job=${np_used_job%.*}
            (( NP_USED += $np_used_job ))
        done < $QUEUE_TMP/.running.all.tmp2
        (( NP_AVAIL_USER = nproc_limit - NP_USED ))
        if (( NP_AVAIL_USER >= NPROC )); then
            #touch $QUEUE_TMP/.running.${NPROC}.$JOB_ID
            # Include basic info about the job in the status file
            cat <<EOF > $QUEUE_TMP/.running.${NPROC}.$JOB_ID
Job ID         : $JOB_ID
Submitter      : $USER
Submmit date   : $NOW
Submit location: ${PWD}
Requested procs: $NPROC
EOF
        else
            #touch $QUEUE_TMP/.waiting.${NPROC}.$JOB_ID
            # Include basic info about the job in the status file
            cat <<EOF > $QUEUE_TMP/.waiting.${NPROC}.$JOB_ID
Job ID         : $JOB_ID
Submitter      : $USER
Submmit date   : $NOW
Submit location: ${PWD}
Requested procs: $NPROC
EOF
        fi
        rm $QUEUE_TMP/.running.all.tmp2
    fi
fi
rm $QUEUE_TMP/.running.all.tmp
