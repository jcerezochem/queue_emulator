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
    if [ -e $QUEUE_MAN/qdel.man ]; then 
        cat $QUEUE_MAN/qdel.man
    else
        # General help of all tools
        cat $QUEUE_MAN/queue.man
    fi
    exit
fi

# Run over all privided ids
for id in $input; do
    # Allow giving the ID both with qe_ and without
    id=${id##qe_}
    # Grep job info from queue.log
    jobinfo=$(egrep "^qe_${id} " $QUEUE_LOG/queue.log)
    if (( $? !=0 )); then 
        echo "qe_$id is not a running nor queued job"
        continue; 
    fi
    pgid=$(echo "$jobinfo" | awk '{print $2}')
    pgid=${pgid/\(/}; pgid=${pgid/\)/}
    user=$(echo "$jobinfo" | awk '{print $3}')
    if [ "$user" != "$USER" ]; then
        echo "Only owned jobs can be deleted, and qe_$id in owned by $user"
        continue
    fi
    # Check that pgid is alive and associeted to the job_command
    job_command=$(echo $jobinfo | awk '{print $10}')
    job_command=${job_command/\.\//}
    job_pgid=$(ps x -o  "%u %p %r %y %x %c " | egrep "^${user}[\ ]+[0-9]+[\ ]+${pgid} ")
    # And get the status
    stat=$(echo $jobinfo | awk '{print $4}')
    if [ "x$job_pgid" != "x$" ]; then
        # Killing a running or waiting job
        # Check again that the job did not finish, and proceed
        egrep "^qe_${id} " $QUEUE_LOG/queue.log &>/dev/null
        if (( $? ==0 )); then
            if [ "$stat" == "R" ]; then
                echo "Stopping job $id ($pgid)"
            elif [ "$stat" == "Q" ]; then
                echo "Removing job $id ($pgid) from queue"
            fi
            kill -9 -$pgid
            $QUEUE_BIN/finalize_job.sh $id 'K'
        fi
    else
        # Killing a job that is not running nor waiting (should not be there)
        echo "Job $id ($pgid) does not seem to be running"
        echo "Cleaning registers..."
        $QUEUE_BIN/finalize_job.sh $id 'F'
    fi
done
