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
if [ "$STAFLAG" == "F" ]; then 
    cat <<EOF >> $QUEUE_LOG/err.log
Failure report for job eq_$JOB_ID
Date: $NOW
Owner: $USER
Raised from: $0
Message:
 Job in the queue was not found among active PIDs (with ps aux)

EOF
fi

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

#--------------------------------------------------
# Look for all jobs that have place in the queue
# (may not such a good idea, as jobs with 8 proc
#  will have more priority in crowded days)
#--------------------------------------------------
while (( NP_AVAIL >= 0 )); do
# Now check waiting IDs
# Filtering only jobs that require nproc <= avail
ls_list="$QUEUE_TMP/.waiting.0.*"; 
for (( i=1; i<=$NP_AVAIL; i++ )); do
    ls_list="$ls_list $QUEUE_TMP/.waiting.${i}.*"; 
done
ls -ltr $ls_list --time-style="+%s" >  $QUEUE_TMP/.timing.tmp 2>/dev/null

# Remove user that have no more procs allowed
if [ -e $QUEUE_TMP/.deny.users.tmp ]; then
while read denied_user; do
    sed -i "/ $denied_user /d" $QUEUE_TMP/.timing.tmp
done < $QUEUE_TMP/.deny.users.tmp
fi

N=$(wc -l < $QUEUE_TMP/.timing.tmp)
# If $QUEUE_TMP/.timing.tmp is empty, there is not awaiting job
if (( $N == 0 )); then
    rm $QUEUE_TMP/.timing.tmp
    if [ -e $QUEUE_TMP/.deny.users.tmp ]; then rm $QUEUE_TMP/.deny.users.tmp; fi
    exit
fi

# Found all jobs that have place in the queue
found_next=false
for (( i=1; i<=$N; i++ )); do
    file=$(head -n$i $QUEUE_TMP/.timing.tmp | tail -n1 | awk '{print $7}')
    nextjob=${file##*/}; nextjob=${nextjob##.waiting.}
    NEXT_ID=${nextjob##*.} 
    NPROC=${nextjob%.*}

    #--------------------
    # Additional checks
    #--------------------
    # Check that pgid is alive and associated to a bash run
    #---------------------------------------------------------
    jobinfo=$(egrep "^qe_${NEXT_ID} " $QUEUE_LOG/queue.log)
    if (( $? !=0 )); then 
        # We should never end up here (but this seems 
        # a safe treatment of this weird situation)
        $QUEUE_BIN/finalize_job.sh ${NEXT_ID} 'F'
        (( NPROC = 0 ))
        continue
    fi
    pgid=$(echo "$jobinfo" | awk '{print $2}')
    pgid=${pgid/\(/}; pgid=${pgid/\)/}
    user=$(echo "$jobinfo" | awk '{print $3}')
    job_pgid=$(ps x -o  "%u %p %r %y %x %c " | egrep "^${user}[\ ]+[0-9]+[\ ]+${pgid} " | grep "bash" | tail -n1 | awk '{print $6}')
    if [ "$job_pgid" != "bash" ]; then
        $QUEUE_BIN/finalize_job.sh ${NEXT_ID} 'F'
        (( NPROC = 0 ))
        continue
    fi
    # Check also if the user has nproc limits
    #---------------------------------------------------------
    user=$(ls -l $QUEUE_TMP/.waiting.$NPROC.$NEXT_ID | awk '{print $3}')
    #  get number of procesors used by the user
    ls -l $QUEUE_TMP/.running.* 2>/dev/null | grep " $user " > $QUEUE_TMP/.running.rest.tmp
    (( nproc_user = 0 ))
    while read runjob; do 
        runjob=${runjob##*/}
        np_used_job=${runjob/.running./}
        np_used_job=${np_used_job%.*}
        (( nproc_user += $np_used_job ))
    done < $QUEUE_TMP/.running.rest.tmp
    rm $QUEUE_TMP/.running.rest.tmp
    #  and get limit for the user if there is any
    line=$(grep "$user" $QUEUE_LOG/nproc_limits.dat)
    if [ "x$line" != "x" ]; then
        nproc_limit=$(echo $line | awk '{print $2}')
    else
        nproc_limit=$QUEUE_NPROC
    fi
    (( np_avail_user = $nproc_limit - nproc_user ))
    if (( np_avail_user >= $NPROC )); then
        found_next=true
        break
    else
        echo "$USER" >> $QUEUE_TMP/.deny.users.tmp
    fi
done
rm $QUEUE_TMP/.timing.tmp

# Allow job if possible
if $found_next; then
    # Turn waiting mark into running mark 
    mv $QUEUE_TMP/.waiting.$NPROC.$NEXT_ID $QUEUE_TMP/.running.$NPROC.$NEXT_ID
    chmod g+w $QUEUE_TMP/.running.$NPROC.$NEXT_ID
    (( NP_AVAIL -= NPROC ))
fi


# Here finishes the do loop utill N_AVAIL>=0
done
if [ -e $QUEUE_TMP/.deny.users.tmp ]; then rm $QUEUE_TMP/.deny.users.tmp; fi
