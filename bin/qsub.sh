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
nproc=1

# Read job command
input=$@

#READING INPUT DATA FROM COMMAND LINE
np_opt=""
while test "x$1" != x ; do
    case $1 in
     -np        ) shift; nproc="$1"; np_opt=$(echo $input | egrep "\-np[\ ]+$nproc" -o); input=${input/$np_opt/}  ;;
     -h         ) input=${input/$1/}; help=true  ;;
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
   qsub job.scritp [options]

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

# The input correspond to the job command
job_command=$input
if [ "x${job_command// /}" == "x" ]; then
    echo "Error: no program to submit"
    exit
fi

# The current time
NOW=$(date "+%d %b %y %H:%M:%S")

# Preliminar checks
#-----------------------------------------
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

# Check if number of jobs requested exceed number of jobs allowed to the user
user=$USER
#  get number of procesors used by the user
ls -l $QUEUE_TMP/.running.* 2>/dev/null | grep " $user " > $QUEUE_TMP/.running.subm.tmp
(( nproc_user = 0 ))
while read runjob; do 
    runjob=${runjob##*/}
    np_used_job=${runjob/.running./}
    np_used_job=${np_used_job%.*}
    (( nproc_user += $np_used_job ))
done < $QUEUE_TMP/.running.subm.tmp
rm $QUEUE_TMP/.running.subm.tmp
#  and get limit for the user if there is any
line=$(grep "$user" $QUEUE_LOG/nproc_limits.dat)
if [ "x$line" != "x" ]; then
    nproc_limit=$(echo $line | awk '{print $2}')
else
    nproc_limit=$QUEUE_NPROC
fi

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

# And submit the job appending instructions for the queue
cat <<EOF | nohup bash 1> job${JOB_ID}.out 2>job${JOB_ID}.err & pid=$!
# Let time to build the log entry
sleep 1

# Check if we got allowed
(( i=0 ))
while [ ! -e $QUEUE_TMP/.running.$nproc.$JOB_ID ]; do
    sleep 10
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
         awk '{printf "%-18s %10s     Q      %2s       %17s      %-20s\n", "'"$JOB_ID"'",$1,"'"$nproc"'","'"$NOW"'",substr("'"$job_command"'",0,20)}' | \
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




