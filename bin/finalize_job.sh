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

# The input provides the current job id and exit flag
(( JOB_ID=$1 ))
STAFLAG=$2 # D (Done), K (Killed), F(Failed)

# Get current date
NOW=$(date "+%d %b %y %H:%M:%S")

# Add calculation info to history log
line="$(egrep "^qe_$JOB_ID " $QUEUE_LOG/queue.log)"
new_line="$(egrep "^qe_$JOB_ID " $QUEUE_LOG/queue.log | sed "s/ R / $STAFLAG /" | sed "s/ Q / $STAFLAG /")"
new_line="$new_line   $NOW"
echo "$new_line" >> $QUEUE_LOG/history.log

# Remove entry from the qstat log
line=$(egrep "^qe_$JOB_ID " $QUEUE_LOG/queue.log)
if [ "x$line" != "x" ]; then
    sed -i "/^qe_$JOB_ID /d" $QUEUE_LOG/queue.log
fi
# Clear job marks (if any)
rm $QUEUE_TMP/.waiting.*.$JOB_ID 2>/dev/null
rm $QUEUE_TMP/.running.*.$JOB_ID 2>/dev/null

# If Flag was F, that means a failure of the queue system and the job was not properly
# allocated, so no next job is tried
if [ "$STAFLAG" == "F" ]; then exit; fi

# Get number of procesors avilable
ls $QUEUE_TMP/.running.* 2>/dev/null 1>$QUEUE_TMP/.running.rest.tmp
(( NP_USED = 0 ))
while read runjob; do 
    runjob=${runjob##*/}
    np_used_job=${runjob/.running./}
    np_used_job=${np_used_job%.*}
    (( NP_USED += $np_used_job ))
done < $QUEUE_TMP/.running.rest.tmp
rm $QUEUE_TMP/.running.rest.tmp
(( NP_AVAIL = QUEUE_NPROC - NP_USED ))

# Only go on if there any proc available
if (( NP_AVAIL <= 0 )); then
    exit
fi

# Now check waiting IDs
# Filtering only jobs that require nproc <= avail
ls_list="$QUEUE_TMP/.waiting.0.*"; 
for (( i=1; i<=$NP_AVAIL; i++ )); do
    ls_list="$ls_list $QUEUE_TMP/.waiting.${i}.*"; 
done
ls -ltr $ls_list --time-style="+%s" >  $QUEUE_TMP/.timing.tmp 2>/dev/null

N=$(wc -l < $QUEUE_TMP/.timing.tmp)
# If $QUEUE_TMP/.timing.tmp is empty, there is not awaiting job
if (( $N == 0 )); then
    rm $QUEUE_TMP/.timing.tmp
    exit
fi
# If job did not update its waiting mark within the last 10 min they are dead
found_next=false
for (( i=1; i<=$N; i++ )); do
    file=$(head -n$i $QUEUE_TMP/.timing.tmp | tail -n1 | awk '{print $7}')
    nextjob=${file##*/}; nextjob=${nextjob##.waiting.}
    NEXT_ID=${nextjob##*.} 
    NPROC=${nextjob%.*}
    t_update=$(head -n$i $QUEUE_TMP/.timing.tmp | tail -n1 | awk '{print $6}')
    t_now=$(date '+%s')
    (( t_elapsed = t_now - t_update ))
    # 
    # This is disabled because it erases the diffence in date between files
    # which is used to set the priority of the waiting jobs
    #
    (( t_elapsed = 0 )) 
    #
    # An equivalent check (even better) can be done checking the pid (TODO)
    # as it is done in qdel
    #
    if (( t_elapsed > 600 )); then
        rm $file
        echo "Job $NEXT_ID is dead and so removed from the queue" >> $QUEUE_LOG/dead.jobs
    else
        found_next=true
        break
    fi
done
rm $QUEUE_TMP/.timing.tmp

# Trun waiting mark into running mark 
if $found_next; then
    mv $QUEUE_TMP/.waiting.$NPROC.$NEXT_ID $QUEUE_TMP/.running.$NPROC.$NEXT_ID
    chmod g+w $QUEUE_TMP/.running.$NPROC.$NEXT_ID
fi

