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

# Defauts
help=false
nproc=16

# Read job command
job_command=$@

#READING INPUT DATA FROM COMMAND LINE
while test "x$1" != x ; do
    case $1 in
     -np        ) job_command=${job_command/$1/}; shift; job_command=${job_command/$1/}; nproc="$1"    ;;
     -h         ) job_command=${job_command/$1/}; help=true  ;;
    esac
    shift
done


# Help if requested
if $help; then
    # Specific help (need to be written)
    if [ -e $QUEUE_MAN/qsub.man ]; then 
        cat $QUEUE_MAN/qsub.man
    else
        # General help of all tools
        cat $QUEUE_MAN/queue.man
    fi
    # For the moment add the basic info
    cat <<EOF
USAGE
   qstat job.scritp [options]

EOF
    #PRINT ACTUAL PARAMETERS IN USE
    cat <<EOF
CURRENT OPTIONS
   -np      number of processor          $nproc
            requested
   -h       print help and quit          $help

EOF
    exit
fi

# The current time
NOW=$(date "+%d %b %y %H:%M:%S")

# Send to "queue system"
#-------------------------
# Get ID for this job (JOB_ID) and compared with the currently allowed signal
(( JOB_ID = $(read i <$QUEUE_LOG/id.server; (( i=$i+1 )); echo $i | tee $QUEUE_LOG/id.server) ))

# Prepare queue to start the job
$QUEUE_BIN/start_job.sh $JOB_ID $nproc
if (( $? != 0 )); then
    echo ""
    echo "Error: job was not submitted"
    echo ""
    exit
fi

# Check if the program is callable
prog=$(echo $job_command | awk '{print $1}')
which $prog &>/dev/null
if (( $? != 0 )); then
    # Check if the program is a local script
    if [ ! -e $prog ]; then
        echo ""
        echo "Error: the called program $prog does not exist"
        echo "       Aborting submision to queue"
        echo ""
        exit
    fi
    which ./$prog &>/dev/null
    if (( $? != 0 )); then
        echo ""
        echo "Error: the called program $prog does not have execution"
        echo "       permisions. Make it callable typing:"
        echo ""
        echo "        chmod u+x ./$prog"
        echo ""
        echo "       Then try to submit to the queue again"
        echo ""
        exit
    else
        #Prepend ./ to submit the job
        job_command=${job_command/$prog/\.\/$prog}
    fi
fi

# And submit the job appending instructions for the queue
cat <<EOF | nohup bash 1> job${JOB_ID}.out 2>job${JOB_ID}.err & pid=$!
# Let time to build the log entry
sleep 1

# Check if we got allowed
(( i=0 ))
while [ ! -e $QUEUE_TMP/.running.$nproc.$JOB_ID ]; do
    # 
    # This is comented because it erases the diffence in date between files
    # which is used to set the priority of the waiting jobs
    # 
    # # Touch the file ever 500 s but check if allowed every 10
    # if ! (( \$(( i%50 )) )); then
    #     touch $QUEUE_YMP/.waiting.$nproc.$JOB_ID
    #     (( i=0 ))
    # fi
    sleep 10
    # (( i++ ))
done

# Replace status label
line="\$(egrep "^qe_$JOB_ID " $QUEUE_LOG/queue.log)"
new_line="\$(egrep "^qe_$JOB_ID " $QUEUE_LOG/queue.log | sed "s/ Q / R /")"
sed -i "s|\$line|\$new_line|" $QUEUE_LOG/queue.log

###############################
# This is the user job
#
$job_command
#
##############################

# Launch next job in the queue (if any)
$QUEUE_BIN/finalize_job.sh $JOB_ID 'D'
EOF

# We got the pid of the launching script, but we need to group pid 
# to kill all the child proceses (see https://stackoverflow.com/questions/392022/best-way-to-kill-all-child-processes)
pgid=$(ps x -o  "%u %p %r %y %x %c " | egrep "^$USER[\ ]+$pid " | awk '{print $3}')
if [ "x$pgid" == "x" ]; then
    echo ""
    echo "Error: el proceso de envío no se ha podido completar"
    echo "       (PGID not active)"
    echo ""
    exit
fi

# Add entry to qstat.log
JOB_ID="qe_$JOB_ID ($pgid)"
status=$(ps aux | egrep "^$USER[\ ]+$pid\ " | egrep -v "egrep" | \
         awk '{printf "%-18s %10s     Q      %2s       %17s      %-20s\n", "'"$JOB_ID"'",$1,"'"$nproc"'","'"$NOW"'","'"$job_command"'"}' | \
         tee $QUEUE_LOG/.queue.log.tmp | wc -c)
cat $QUEUE_LOG/.queue.log.tmp >> $QUEUE_LOG/queue.log
rm  $QUEUE_LOG/.queue.log.tmp

if ! (( $status )); then
    echo ""
    echo "Error: el proceso de envío no se ha podido completar"
    echo ""
    exit
else
    echo "Job $JOB_ID submitted"
fi




