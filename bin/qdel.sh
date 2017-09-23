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
job_command=$@

# Defaults
help=false

#READING INPUT DATA FROM COMMAND LINE
while test "x$1" != x ; do
    case $1 in
     -h         ) job_command=${$job_command/$1/}; help=true     ;;
    esac
    shift
done

# Help if requested
if $help; then
    # Specific help (need to be written)
    if [ -e $QUEUE_MAN/qdel.man ]; then 
        cat $QUEUE_MAN/qdel.man
    else
        # General help of all tools
        cat $QUEUE_MAN/queue.man
    fi
    exit
fi

# Run over all privided ids
for id in $job_command; do
    # Allow giving the ID both with qe_ and without
    id=${id##qe_}
    # Grep job info from queue.log
    jobinfo=$(egrep "^qe_${id} " $QUEUE_LOG/queue.log)
    if (( $? !=0 )); then continue; fi
    pid=$(echo "$jobinfo" | awk '{print $2}')
    pid=${pid/\(/}; pid=${pid/\)/}
    user=$(echo "$jobinfo" | awk '{print $3}')
    # Check that pid is alive and associeted to a bash run
    # of the user
    job_pid=$(ps aux | egrep "^${user}[\ ]+${pid} " | awk '{print $11}')
    if [ "$job_pid" == "bash" ]; then
        # Killing a running or waiting job
        # Check that the job did not finish yet, and proceed
        egrep "^qe_${id} " $QUEUE_LOG/queue.log &>/dev/null
        if (( $? ==0 )); then
            echo "Stopping job $id ($pid)"
            $QUEUE_BIN/finalize_job.sh $id 'K'
        fi
    else
        # Killing a job that is not running nor waiting (should not be there)
        echo "Job $id ($pid) does not seem to be running"
        echo "Cleaning registers..."
        $QUEUE_BIN/finalize_job.sh $id 'F'
    fi
done
